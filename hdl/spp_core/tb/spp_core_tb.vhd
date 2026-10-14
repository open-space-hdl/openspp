---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the core: two cores A and B exchange Space Packets and Octet Strings through link
-- models in both directions; every indication is compared byte by byte with the SDU built by the
-- packet model; faults are injected into the links and through the register files.
--
-- Documentation: hdl/spp_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library olo;
    use olo.olo_base_pkg_math.all;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.spp_pkg.all;
    use work.spp_regs_pkg.all;
    use work.spp_tb_pkg.all;
    use work.spp_tb_stream_pkg.all;
    use work.spp_tb_streamvar_pkg.all;
    use work.spp_tb_packet_pkg.all;
    use work.spp_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_core_tb is
    generic (
        runner_cfg      : string;
        DataWidth_g     : positive := 32;
        Encapsulation_g : boolean  := true;
        NChar_g         : boolean  := false;
        PathDefault_g   : boolean  := true;
        SpwAddrBytes_g  : natural  := 4
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_core_tb is

    constant Bytes_c       : positive := DataWidth_g / 8;
    constant BufferBeats_c : positive := choose(DataWidth_g > 32, 1024, 4096);

    signal Clk    : std_logic;
    signal RstA   : std_logic  := '1';
    signal RstB   : std_logic  := '1';
    signal LinkAB : LinkCtrl_t := LinkCtrlIdle_c;
    signal LinkBA : LinkCtrl_t := LinkCtrlIdle_c;
    signal StatAB : LinkStat_t;
    signal StatBA : LinkStat_t;
    signal Cores  : CoreStatArray_t;

begin

    test_runner_watchdog(runner, 100 ms);

    p_main : process is
        variable Rand_v   : t_rand;
        variable Seed_v   : natural := 1;
        variable CntA_v   : NatArray_t(0 to 2047);
        variable CntB_v   : NatArray_t(0 to 2047);
        variable Len_v    : natural;
        variable Apid_v   : natural;
        variable Beats_v  : natural;
        variable Cycles_v : natural;
        variable Ua1_v    : natural;
        variable Ua2_v    : natural;
        variable Ua3_v    : natural;

        -- Register access of core c
        procedure regWrite (
            c    : natural;
            addr : natural;
            data : std_logic_vector(31 downto 0)) is
        begin
            axilite_write(AXILITE_VVCT, c, to_unsigned(addr, 11), data, "core " & to_string(c) & ": write 0x" &
                          to_hstring(to_unsigned(addr, 12)));
            await_completion(AXILITE_VVCT, c, 200 us);
        end procedure;

        procedure regCheck (
            c    : natural;
            addr : natural;
            data : std_logic_vector(31 downto 0);
            msg  : string) is
        begin
            axilite_check(AXILITE_VVCT, c, to_unsigned(addr, 11), data, "core " & to_string(c) & ": " & msg);
            await_completion(AXILITE_VVCT, c, 200 us);
        end procedure;

        procedure regRead (
            c    : natural;
            addr : natural) is
        begin
            axilite_read(AXILITE_VVCT, c, to_unsigned(addr, 11), "core " & to_string(c) & ": read");
            await_completion(AXILITE_VVCT, c, 200 us);
        end procedure;

        function word (n : natural) return std_logic_vector is
        begin
            return std_logic_vector(to_unsigned(n, 32));
        end function;

        -- Entry of the send APID table of core c: path enable, destination, count
        procedure txPath (
            c     : natural;
            apid  : natural;
            dest  : natural;
            count : natural := 0;
            en    : natural := 1) is
        begin
            regWrite(c, RegTxTableApid_c, word(apid));
            regRead(c, RegTxTableEntry_c);
            regWrite(c, RegTxTableEntry_c, word(en * 2 ** 18 + dest * 2 ** 14 + count));
            regRead(c, RegTxTableEntry_c);
        end procedure;

        -- Entry of the receive APID table of core c: path enable, port, continuity check
        procedure rxPath (
            c     : natural;
            apid  : natural;
            p     : natural;
            check : natural := 0;
            en    : natural := 1) is
        begin
            regWrite(c, RegRxTableApid_c, word(apid));
            regRead(c, RegRxTableEntry_c);
            regWrite(c, RegRxTableEntry_c, word(en * 2 ** 20 + p * 2 ** 16 + check * 2 ** 15));
            regRead(c, RegRxTableEntry_c);
        end procedure;

        -- Destination d of core c
        procedure dest (
            c    : natural;
            d    : natural;
            tla  : natural;
            ua   : natural;
            len  : natural                       := 0;
            addr : std_logic_vector(31 downto 0) := x"00000000") is
        begin
            regWrite(c, RegDestCtrl_c + d * RegDestStride_c, word(len * 2 ** 16 + ua * 2 ** 8 + tla));
            regWrite(c, RegDestAddr0_c + d * RegDestStride_c, addr);
        end procedure;

        -- Octet String on send port p of core tx (0 A, 1 B) to receive port q of the other core; the count of the
        -- APID is taken from the model of the sending core
        procedure octet (
            tx      : natural;
            p       : natural;
            q       : natural;
            apid    : natural;
            data    : TbBytes_t;
            ua      : natural := 0;
            loss    : natural := 0;
            shi     : natural := 0;
            pktType : natural := 0) is
            variable Cnt_v : natural;
            variable Rx_v  : natural;
        begin
            if tx = 0 then
                Cnt_v        := CntA_v(apid);
                CntA_v(apid) := (Cnt_v + 1) mod 16384;
                Rx_v         := ChRxB_c;
                tbPush(ChTxA_c + p, data, tbTxUser(apid, shi, pktType));
            else
                Cnt_v        := CntB_v(apid);
                CntB_v(apid) := (Cnt_v + 1) mod 16384;
                Rx_v         := ChRxA_c;
                tbPush(ChTxB_c + p, data, tbTxUser(apid, shi, pktType));
            end if;
            if Octet_c(q) = '1' then
                tbPush(Rx_v + q, data, tbRxUser(apid, shi, loss, 0, ua));
            else
                tbPush(Rx_v + q, tbSpacePacket(pktType, shi, apid, 3, Cnt_v, data), tbRxUser(apid, shi, loss, 0, ua));
            end if;
        end procedure;

        -- Space Packet on the Packet Service send port p of core tx to receive port q of the other core
        procedure packet (
            tx   : natural;
            p    : natural;
            q    : natural;
            pkt  : TbBytes_t;
            ua   : natural := 0;
            loss : natural := 0) is
            constant Apid_c : natural := to_integer(unsigned(std_logic_vector'(pkt(0)(2 downto 0) & pkt(1))));
            constant Shf_c  : natural := to_integer(unsigned(std_logic_vector'('0', pkt(0)(3))));
            variable Rx_v   : natural;
        begin
            if tx = 0 then
                tbPush(ChTxA_c + p, pkt, tbTxUser(0));
                Rx_v := ChRxB_c;
            else
                tbPush(ChTxB_c + p, pkt, tbTxUser(0));
                Rx_v := ChRxA_c;
            end if;
            if Octet_c(q) = '1' then
                tbPush(Rx_v + q, tbSlice(pkt, 6, pkt'length - 1), tbRxUser(Apid_c, Shf_c, loss, 0, ua));
            else
                tbPush(Rx_v + q, pkt, tbRxUser(Apid_c, Shf_c, loss, 0, ua));
            end if;
        end procedure;

        procedure waitAll (timeout : time := 5 ms) is
        begin

            for p in 0 to NumPorts_c - 1 loop
                tbWaitEmpty(ChTxA_c + p, timeout, "send port " & to_string(p) & " of core A");
                tbWaitEmpty(ChTxB_c + p, timeout, "send port " & to_string(p) & " of core B");
                tbWaitEmpty(ChRxA_c + p, timeout, "receive port " & to_string(p) & " of core A");
                tbWaitEmpty(ChRxB_c + p, timeout, "receive port " & to_string(p) & " of core B");
            end loop;

            tbWaitEmpty(ChInjA_c, timeout, "injector into core A");
            tbWaitEmpty(ChInjB_c, timeout, "injector into core B");
            wait for 50 * ClkPeriod_c;
        end procedure;

        -- CPTP packet (or Space Packet without the CPTP layer) injected into the link input of core B
        procedure inject (
            pkt : TbBytes_t;
            eep : natural := 0;
            tla : natural := 16#40#;
            pid : natural := 2;
            res : natural := 0) is
        begin
            if Encapsulation_g then
                tbPush(ChInjB_c, tbCptp(TbNoBytes_c, tla, 16#77#, pkt, pid, res), "0", std_logic_vector(to_unsigned(eep, 1)));
            else
                tbPush(ChInjB_c, pkt, "0", std_logic_vector(to_unsigned(eep, 1)));
            end if;
        end procedure;

        procedure resetCores is
        begin
            RstA <= '1';
            RstB <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            RstA <= '0';
            RstB <= '0';
            -- Initialisation of the tables: a read of an entry waits for it
            regRead(0, RegTxTableEntry_c);
            regRead(1, RegRxTableEntry_c);
            CntA_v := (others => 0);
            CntB_v := (others => 0);
        end procedure;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);

        for c in 0 to NumCores_c - 1 loop
            shared_axilite_vvc_config(c).bfm_config.max_wait_cycles := 10000;
        end loop;

        Rand_v.set_rand_seeds(DataWidth_g, 77);

        while test_suite loop
            resetCores;

            if run("test_end_to_end") then
                -- Both directions at the same time, all ports, symmetric and asymmetric services, destinations
                -- with User Application values, the Target Logical Address filter of core B
                dest(0, 1, 16#40#, 16#31#);
                dest(0, 2, 16#FE#, 16#32#);
                dest(1, 3, 16#FE#, 16#55#);

                for a in 16#100# to 16#103# loop
                    txPath(0, a, 1);
                    rxPath(1, a, 0, 1);
                end loop;

                -- Asymmetric: Space Packets of A port 1 become Octet Strings at B port 2, Octet Strings of A port 2
                -- become Space Packets at B port 1
                txPath(0, 16#200#, 2);
                rxPath(1, 16#200#, 2);
                rxPath(1, 16#300#, 1);
                rxPath(0, 16#400#, 2);
                txPath(1, 16#500#, 3);
                rxPath(0, 16#500#, 0, 1);
                if Encapsulation_g then
                    regWrite(1, RegConfig_c, x"00004004");
                end if;

                for c in 0 to NumPorts_c - 1 loop
                    tbSetStall(ChTxA_c + c, 0.2);
                    tbSetStall(ChRxB_c + c, 0.2);
                    tbSetStall(ChRxA_c + c, 0.2);
                end loop;

                -- User Application values of the destinations 1, 2 and 3 (none without the CPTP layer)
                Ua1_v := 16#31# * boolean'pos(Encapsulation_g);
                Ua2_v := 16#32# * boolean'pos(Encapsulation_g);
                Ua3_v := 16#55# * boolean'pos(Encapsulation_g);

                -- The random lengths are drawn into a variable before the call: an impure function call inside the
                -- actual of an unconstrained array parameter is not evaluated exactly once by every simulator
                for i in 0 to 59 loop
                    Len_v  := Rand_v.rand(1, 300);
                    octet(0, 0, 0, 16#100# + i mod 4, tbPayload(Len_v, Seed_v), Ua1_v, 0, i mod 2, (i / 2) mod 2);
                    Len_v  := Rand_v.rand(1, 200);
                    packet(0, 1, 2, tbSpacePacket(i mod 2, 0, 16#200#, 3, i, tbPayload(Len_v, Seed_v + 1)), Ua2_v);
                    Len_v  := Rand_v.rand(1, 150);
                    octet(0, 2, 1, 16#300#, tbPayload(Len_v, Seed_v + 2));
                    Len_v  := Rand_v.rand(1, 250);
                    octet(1, 2, 2, 16#400#, tbPayload(Len_v, Seed_v + 3));
                    Len_v  := Rand_v.rand(1, 100);
                    packet(1, 1, 0, tbSpacePacket(0, 1, 16#500#, 3, i, tbPayload(Len_v, Seed_v + 4)), Ua3_v);
                    Seed_v := Seed_v + 5;
                end loop;

                waitAll(20 ms);
                regCheck(0, RegTxPackets_c, word(180), "packets sent by A");
                regCheck(1, RegRxPackets_c, word(180), "SDUs delivered by B");
                regCheck(1, RegTxPackets_c, word(120), "packets sent by B");
                regCheck(0, RegRxPackets_c, word(120), "SDUs delivered by A");
                regCheck(0, RegRxLoss_c, word(0), "no loss at A");
                regCheck(1, RegRxLoss_c, word(0), "no loss at B");
                check_value(Cores(0).Errors + Cores(1).Errors, 0, ERROR, "no error event");

            elsif run("test_address_strip") then
                -- Target SpaceWire Address of three bytes, removed by core B (as a network that delivers it)
                dest(0, 1, 16#FE#, 16#21#, 3, x"00030201");
                txPath(0, 16#123#, 1);
                regWrite(1, RegConfig_c, x"0000FE30");

                for i in 0 to 9 loop
                    octet(0, 0, 0, 16#123#, tbPayload(10 + 37 * i, i), 16#21#);
                end loop;

                waitAll;
                regCheck(1, RegRxPackets_c, word(10), "SDUs delivered by B");

            elsif run("test_idle") then
                -- Idle cores after the table initialisation: no metavalue reaches the arithmetic of the data paths.
                -- The VUnit configuration of this test enables the IEEE warnings and fails on a metavalue warning
                -- after the marker below.
                report "SPP_IDLE_CHECK_START";
                wait for 20 us;
                octet(0, 0, 0, 16#123#, tbPayload(20, 1));
                waitAll;
                -- A last beat without bytes from the user ends the SDU; an SDU without any byte is rejected
                tbSetNullTail(ChTxA_c, true);
                octet(0, 0, 0, 16#123#, tbPayload(DataWidth_g / 8, 2));
                tbPush(ChTxA_c, tbPayload(0, 3), tbTxUser(16#123#));
                waitAll;
                tbSetNullTail(ChTxA_c, false);
                regCheck(0, RegErrTx1_c, word(2 ** 16), "ERR_TX1: SDU without bytes");
                -- A last beat without bytes from the link ends the packet
                LinkAB.Sel <= '1';
                tbSetNullTail(ChInjB_c, true);
                inject(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(10, 4)));
                tbPush(ChRxB_c, tbPayload(10, 4), tbRxUser(5, 0, 0, 0, 16#77# * boolean'pos(Encapsulation_g)));
                waitAll;
                tbSetNullTail(ChInjB_c, false);
                LinkAB.Sel <= '0';
                regCheck(1, RegRxPackets_c, word(3), "SDUs delivered by B");

            elsif run("test_link_errors") then
                -- Faulty packets injected into the link input of core B, each followed by a correct one
                regWrite(1, RegConfig_c, x"00004004");
                regWrite(1, RegMaxLength_c, word(200));
                rxPath(1, 16#666#, 0, 0, 0);
                regWrite(1, RegIrqEn_c, x"00000002");
                LinkAB.Sel <= '1';
                inject(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(20, 1)), 1);                          -- EEP
                inject(tbCat(tbPrimaryHeader(2, 0, 0, 5, 3, 0, 9), tbPayload(10, 2)));                -- version
                inject(tbCat(tbPrimaryHeader(0, 0, 0, 5, 3, 0, 20), tbPayload(10, 3)));               -- length
                inject(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(195, 4)));                              -- longer than 200
                inject(tbSpacePacket(0, 0, 2047, 3, 0, tbPayload(10, 5)));                            -- Idle Packet
                inject(tbSpacePacket(0, 0, 16#666#, 3, 0, tbPayload(10, 6)));                         -- no path
                inject(tbSpacePacket(0, 0, 5, 1, 0, tbPayload(10, 7)));                               -- segment to octet port
                inject(tbSlice(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(1, 8)), 0, 4));                 -- 5 bytes
                if Encapsulation_g then
                    inject(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(10, 9)), 0, 16#40#, 1);              -- Protocol Identifier
                    inject(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(10, 10)), 0, 16#40#, 2, 1);         -- Reserved
                    inject(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(10, 11)), 0, 16#41#);               -- address
                end if;
                inject(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(10, 12)));
                tbPush(ChRxB_c, tbPayload(10, 12), tbRxUser(5, 0, 0, 0, 16#77# * boolean'pos(Encapsulation_g)));
                waitAll;
                regCheck(1, RegErrRx1_c, word(1 + 2 ** 16 * boolean'pos(Encapsulation_g)), "ERR_RX1: EEP, Protocol Identifier");
                regCheck(1, RegErrRx2_c, word(boolean'pos(Encapsulation_g) * (1 + 2 ** 16)), "ERR_RX2: Reserved, address");
                regCheck(1, RegErrRx3_c, word(1 + 2 ** 16), "ERR_RX3: short, version");
                regCheck(1, RegErrRx4_c, word(1 + 2 ** 16), "ERR_RX4: length, oversize");
                regCheck(1, RegErrRx5_c, word(1 + 2 ** 16), "ERR_RX5: Idle Packet, no path");
                regCheck(1, RegErrRx6_c, word(1), "ERR_RX6: Sequence Flags");
                regCheck(1, RegRxPackets_c, word(1), "one SDU delivered");
                -- The event output reports one event per cycle; the counters above count all
                check_value(Cores(1).Errors > 0 and Cores(1).Errors <= 8 + 3 * boolean'pos(Encapsulation_g), ERROR,
                            "error events of core B: " & to_string(Cores(1).Errors));
                check_value(Cores(1).Irq, '1', ERROR, "interrupt of core B");
                regCheck(1, RegEvents_c, x"0000000A", "RX_DISCARD and RX_DELIVERED events");
                LinkAB.Sel <= '0';

            elsif run("test_loss") then
                -- A packet lost in the link sets the loss indicator of the next one
                rxPath(1, 16#101#, 0, 1);

                for i in 0 to 1 loop
                    octet(0, 0, 0, 16#101#, tbPayload(30, i), 0);
                end loop;

                waitAll;
                LinkAB.DropTarget <= 1;
                tbPush(ChTxA_c, tbPayload(30, 2), tbTxUser(16#101#));
                CntA_v(16#101#)   := CntA_v(16#101#) + 1;
                wait until StatAB.Dropped = 1 for 1 ms;
                check_value(StatAB.Dropped, 1, ERROR, "packet dropped in the link");
                octet(0, 0, 0, 16#101#, tbPayload(30, 3), 0, 1);
                octet(0, 0, 0, 16#101#, tbPayload(30, 4), 0, 0);
                waitAll;
                regCheck(1, RegRxLoss_c, word(1), "one loss indication");
                regCheck(1, RegEvents_c, x"00000018", "RX_DELIVERED and RX_LOSS events");

            elsif run("test_eep") then
                -- A packet ended by an EEP in the link, and a packet with a double error in the send buffer of core A
                LinkAB.EepTarget <= 1;
                tbPush(ChTxA_c, tbPayload(40, 1), tbTxUser(16#10#));
                CntA_v(16#10#)   := 1;
                wait until StatAB.Eeped = 1 for 1 ms;
                regWrite(0, RegEccInject_c, x"00000200");
                tbPush(ChTxA_c, tbPayload(40, 2), tbTxUser(16#10#));
                CntA_v(16#10#)   := 2;
                octet(0, 0, 0, 16#10#, tbPayload(40, 3));
                waitAll;
                regCheck(1, RegErrRx1_c, word(2), "two packets with EEP discarded by B");
                regCheck(0, RegEccStatus_c, x"00000001", "double error in the send data buffer of A");
                regCheck(1, RegRxPackets_c, word(1), "one SDU delivered");

            elsif run("test_send_errors") then
                -- SDUs rejected by core A: oversize, no path, Idle with SHI, short Space Packet
                regWrite(0, RegMaxLength_c, word(100));
                txPath(0, 16#700#, 0, 0, 0);
                regWrite(0, RegIrqEn_c, x"00000001");
                tbPush(ChTxA_c, tbPayload(95, 1), tbTxUser(16#10#));
                tbPush(ChTxA_c, tbPayload(10, 2), tbTxUser(16#700#));
                tbPush(ChTxA_c + 2, tbPayload(10, 3), tbTxUser(2047, 1));
                tbPush(ChTxA_c + 1, tbPayload(6, 4), tbTxUser(0));
                octet(0, 0, 0, 16#10#, tbPayload(94, 5));
                waitAll;
                regCheck(0, RegErrTx1_c, word(1 + 2 ** 16), "ERR_TX1: oversize, short");
                regCheck(0, RegErrTx3_c, word(1), "ERR_TX3: Idle");
                regCheck(0, RegErrTx4_c, word(1), "ERR_TX4: no path");
                regCheck(0, RegTxPackets_c, word(1), "one packet sent");
                check_value(Cores(0).Errors > 0 and Cores(0).Errors <= 4, ERROR, "error events of core A: " &
                            to_string(Cores(0).Errors));
                check_value(Cores(0).Irq, '1', ERROR, "interrupt of core A");

            elsif run("test_plain") then
                -- Without the CPTP layer: Space Packets directly on the link in both directions
                rxPath(1, 16#20#, 0);
                rxPath(0, 16#21#, 1);

                for i in 0 to 19 loop
                    Len_v := Rand_v.rand(1, 100);
                    octet(0, 0, 0, 16#20#, tbPayload(Len_v, i));
                    Len_v := Rand_v.rand(1, 100);
                    packet(1, 1, 1, tbSpacePacket(1, 1, 16#21#, i mod 4, i, tbPayload(Len_v, i + 50)));
                end loop;

                waitAll;
                regCheck(1, RegGenerics_c, word(3 + 3 * 2 ** 5 + 4 * 2 ** 10 + 4 * 2 ** 15 + Bytes_c * 2 ** 20), "GENERICS without CPTP");

            elsif run("test_default_paths") then
                -- Managed data paths after the reset: with the default every APID reaches destination 0 and receive
                -- port 0 without configuration, without it an APID needs a send and a receive path
                regWrite(0, RegTxTableApid_c, word(16#123#));
                regCheck(0, RegTxTableEntry_c, word(boolean'pos(PathDefault_g) * 2 ** 18), "initial send entry");
                regWrite(1, RegRxTableApid_c, word(16#123#));
                regCheck(1, RegRxTableApid_c, word(16#123#), "RX_TABLE_APID");
                regCheck(1, RegRxTableEntry_c, word(boolean'pos(PathDefault_g) * 2 ** 20), "initial receive entry");
                if not PathDefault_g then
                    -- Rejected by A without a send path (0x07)
                    tbPush(ChTxA_c, tbPayload(20, 1), tbTxUser(16#123#));
                    waitAll;
                    regCheck(0, RegErrTx4_c, word(1), "ERR_TX4: no send path");
                    -- Sent by A, discarded by B without a receive path (0x19)
                    txPath(0, 16#123#, 0);
                    tbPush(ChTxA_c, tbPayload(20, 2), tbTxUser(16#123#));
                    CntA_v(16#123#) := 1;
                    waitAll;
                    wait for 1 us;
                    regCheck(1, RegErrRx5_c, word(2 ** 16), "ERR_RX5: no receive path");
                    rxPath(1, 16#123#, 0);
                end if;
                if SpwAddrBytes_g = 0 then
                    -- Without Target SpaceWire Address bytes a configured address length is limited to 0
                    dest(0, 0, 16#FE#, 0, 3, x"00030201");
                    regCheck(0, RegDestAddr0_c, x"00000000", "no address bytes");
                end if;
                octet(0, 0, 0, 16#123#, tbPayload(20, 3));
                waitAll;
                regCheck(0, RegTxPackets_c, word(1 + boolean'pos(not PathDefault_g)), "packets sent by A");
                regCheck(1, RegRxPackets_c, word(1), "SDUs delivered by B");

            elsif run("test_line_rate") then
                -- 100 Octet Strings of 1024 bytes back-to-back from A to B without stall cycles
                SppTbStore_v.clearStats(ChRxB_c);
                Beats_v := 0;

                for i in 0 to 99 loop
                    octet(0, 0, 0, 16#30#, tbPayload(1024, i));
                    Beats_v := Beats_v + (1024 + 10 + Bytes_c - 1) / Bytes_c;
                end loop;

                waitAll(10 ms);
                Cycles_v := (SppTbStore_v.lastTime(ChRxB_c) - SppTbStore_v.firstTime(ChRxB_c)) / ClkPeriod_c + 1;
                log(ID_LOG_HDR, "line rate: " & to_string(Cycles_v) & " cycles for " & to_string(Beats_v) &
                    " link beats of 100 packets");
                check_value(Cycles_v <= Beats_v + 3 * 100, ERROR, "cycles per packet beyond its link beats");

            elsif run("test_reset") then
                -- Reset of core A: its counts restart at 0, core B reports the discontinuity and keeps working
                rxPath(1, 16#40#, 0, 1);

                for i in 0 to 4 loop
                    octet(0, 0, 0, 16#40#, tbPayload(20, i));
                end loop;

                waitAll;
                RstA   <= '1';
                wait until rising_edge(Clk);
                RstA   <= '0';
                regRead(0, RegTxTableEntry_c);
                CntA_v := (others => 0);
                octet(0, 0, 0, 16#40#, tbPayload(20, 10), 0, 1);
                octet(0, 0, 0, 16#40#, tbPayload(20, 11), 0, 0);
                waitAll;
                regCheck(1, RegRxLoss_c, word(1), "discontinuity after the reset of A");
                regCheck(0, RegTxPackets_c, word(2), "packets sent by A after its reset");
            end if;

            wait for 20 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    i_th : entity work.spp_core_th
        generic map (
            DataWidth_g     => DataWidth_g,
            Encapsulation_g => Encapsulation_g,
            BufferBeats_g   => BufferBeats_c,
            NChar_g         => NChar_g,
            PathDefault_g   => PathDefault_g,
            SpwAddrBytes_g  => SpwAddrBytes_g
        )
        port map (
            Clk    => Clk,
            RstA   => RstA,
            RstB   => RstB,
            LinkAB => LinkAB,
            LinkBA => LinkBA,
            StatAB => StatAB,
            StatBA => StatBA,
            Cores  => Cores
        );

end architecture;
