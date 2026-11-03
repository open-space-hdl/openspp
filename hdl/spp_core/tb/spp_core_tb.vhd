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
        SpwAddrBytes_g  : natural  := 4;
        NumTx_g         : positive := 3;
        NumRx_g         : positive := 3;
        NumDest_g       : positive := 4;
        BufferBeats_g   : natural  := 0;
        TxMaxPackets_g  : positive := 8;
        RxMaxPackets_g  : positive := 8;
        MaxLength_g     : positive := 65542;
        RoundRobin_g    : boolean  := false;
        Tla_g           : natural  := 16#FE#
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_core_tb is

    constant Bytes_c       : positive := DataWidth_g / 8;
    -- Send and receive buffers: BufferBeats_g beats, by default 4096 up to 32 bits and 1024 above
    constant BufferBeats_c : positive := choose(BufferBeats_g > 0, BufferBeats_g, choose(DataWidth_g > 32, 1024, 4096));
    -- Bytes of the CPTP header of a destination without Target SpaceWire Address
    constant CptpBytes_c   : natural := 4 * boolean'pos(Encapsulation_g);
    -- Lengths of the throughput test: Octet Strings and Space Packets
    constant OctetLen_c    : NatArray_t := (1, 2, 61, 256, 1024);
    constant PacketLen_c   : NatArray_t := (7, 8, 67, 262, 1030);

    signal Clk       : std_logic;
    signal RstA      : std_logic        := '1';
    signal RstB      : std_logic        := '1';
    signal ResetCtrl : ResetCtrlArray_t := (others => ResetCtrlIdle_c);
    signal LinkAB    : LinkCtrl_t       := LinkCtrlIdle_c;
    signal LinkBA    : LinkCtrl_t       := LinkCtrlIdle_c;
    signal StatAB    : LinkStat_t;
    signal StatBA    : LinkStat_t;
    signal Cores     : CoreStatArray_t;
    signal Mon       : MonStatArray_t;
    signal Probe     : ProbeStatArray_t;

    -- Positive control of the post check of test_idle: a vector that is never driven ('U')
    signal IeeeProbeReq  : boolean := false;
    signal IeeeProbeAck  : boolean := false;
    signal IeeeProbeData : unsigned(3 downto 0);

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
        variable Ua_v     : natural;
        variable N_v      : natural;
        variable Strip_v  : natural;
        variable Addr_v   : std_logic_vector(127 downto 0);
        variable Srv_v    : std_logic_vector(31 downto 0);
        variable Rel_v    : natural;
        variable Pkts_v   : natural;
        variable Eeps_v   : natural;
        variable Beat_v   : natural;
        variable Eps_v    : natural;
        variable T_v      : time;
        -- SDU whose bytes 0x55 fail the first check of the receiving end at any offset: as a CPTP header the
        -- Protocol Identifier (0x11), as a Packet Primary Header the Packet Version Number (0x15)
        variable Fill_v   : TbBytes_t(0 to 399) := (others => x"55");

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

        -- Destination d of core c; addr holds the address bytes from bit 0 on, 32 bits per DEST_ADDR register
        procedure dest (
            c    : natural;
            d    : natural;
            tla  : natural;
            ua   : natural;
            len  : natural          := 0;
            addr : std_logic_vector := x"00000000") is
            constant Addr_c : std_logic_vector(addr'length - 1 downto 0) := addr;
        begin
            regWrite(c, RegDestCtrl_c + d * RegDestStride_c, word(len * 2 ** 16 + ua * 2 ** 8 + tla));

            for k in 0 to addr'length / 32 - 1 loop
                regWrite(c, RegDestAddr0_c + d * RegDestStride_c + 4 * k, Addr_c(32 * k + 31 downto 32 * k));
            end loop;

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

            for p in 0 to NumTx_g - 1 loop
                tbWaitEmpty(ChTxA_c + p, timeout, "send port " & to_string(p) & " of core A");
                tbWaitEmpty(ChTxB_c + p, timeout, "send port " & to_string(p) & " of core B");
            end loop;

            for p in 0 to NumRx_g - 1 loop
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

        -- Arms the triggers of core c: DpRst and Rst at beat beat of a packet presented on M_Link, a stall of the
        -- link at beat stallBeat (record ResetCtrl_t)
        procedure arm (
            c           : natural;
            beat        : natural;
            dpCycles    : natural := 1;
            dpDelay     : natural := 0;
            rstCycles   : natural := 0;
            rstDelay    : natural := 0;
            stallBeat   : natural := 0;
            stallCycles : natural := 0) is
            variable Ctrl_v : ResetCtrl_t;
        begin
            Ctrl_v       := ('0',
                             ResetCtrl(c).Arm + 1,
                             beat,
                             dpDelay,
                             dpCycles,
                             rstDelay,
                             rstCycles,
                             stallBeat,
                             stallCycles);
            ResetCtrl(c) <= Ctrl_v;
            wait until rising_edge(Clk);
        end procedure;

        -- DpRst of core c applied by the testbench for n clock cycles
        procedure dpPulse (
            c : natural;
            n : positive) is
        begin
            wait until rising_edge(Clk);
            ResetCtrl(c).DpRst <= '1';

            for i in 1 to n loop
                wait until rising_edge(Clk);
            end loop;

            ResetCtrl(c).DpRst <= '0';
        end procedure;

        -- Waits for the first reset of core c after rel release edges were counted; the sources of its send ports
        -- drop the SDUs they are sending (as sources reset together with the core); then waits for eps release
        -- edges in total and for the initialisation of the tables
        procedure waitRelease (
            c   : natural;
            rel : natural;
            eps : positive := 1) is
            constant Ch_c : natural := choose(c = 0, ChTxA_c, ChTxB_c);
        begin
            if not Probe(c).InReset and Probe(c).Releases = rel then
                wait until Probe(c).InReset for 1 ms;
            end if;
            check_value(Probe(c).InReset or Probe(c).Releases > rel, ERROR, "reset of core " & to_string(c));

            for p in 0 to NumTx_g - 1 loop
                if SppTbStore_v.count(Ch_c + p) > 0 then
                    SppTbStore_v.setAbort(Ch_c + p);
                end if;
            end loop;

            if Probe(c).Releases < rel + eps then
                wait until Probe(c).Releases >= rel + eps for 1 ms;
            end if;
            check_value(Probe(c).Releases, rel + eps, ERROR, "release edges of core " & to_string(c));
            -- A read of a table entry waits for the initialisation of the tables
            regRead(c, RegTxTableEntry_c);
            regRead(c, RegRxTableEntry_c);
            if c = 0 then
                CntA_v := (others => 0);
            else
                CntB_v := (others => 0);
            end if;
        end procedure;

        -- Stream beats of n bytes
        function beats (n : natural) return natural is
        begin
            return (n + Bytes_c - 1) / Bytes_c;
        end function;

        -- Upper bound of the clock cycles per packet of back-to-back packets of n link bytes (user guide, section 7):
        -- one cycle more than the link beats, at least five
        function cyclesBound (n : natural) return natural is
        begin
            return maximum(beats(n) + 1, 5);
        end function;

        -- Cycles from the first to the last beat recorded on a statistics channel
        impure function window (ch : natural) return natural is
        begin
            return (SppTbStore_v.lastTime(ch) - SppTbStore_v.firstTime(ch)) / ClkPeriod_c + 1;
        end function;

        -- Checks the cycles from the first to the last beat of n back-to-back packets of lb link bytes recorded on a
        -- statistics channel against the bound
        procedure checkRate (
            ch  : natural;
            n   : natural;
            lb  : natural;
            msg : string) is
            variable Cycles_v : natural;
        begin
            Cycles_v := window(ch);
            log(ID_LOG_HDR, msg & ": " & to_string(Cycles_v) & " cycles for " & to_string(n) & " packets of " &
                to_string(beats(lb)) & " link beats (bound " & to_string(cyclesBound(lb)) & " cycles per packet)");
            check_value(SppTbStore_v.packets(ch), n, ERROR, msg & ": packets");
            check_value(Cycles_v <= n * cyclesBound(lb), ERROR, msg & ": cycles beyond the bound");
        end procedure;

        -- Sending end of core A: n SDUs of len bytes on send port p are queued while the link is held, then sent
        -- back-to-back into a link that drops them (always ready); lb link bytes per packet. The first seven SDUs fit
        -- into the buffer: the send port takes them at one beat per cycle. The measurement of the link starts after
        -- four packets, because the first ones leave the pipeline registers at once.
        procedure sendRate (
            p    : natural;
            apid : natural;
            len  : natural;
            lb   : natural;
            n    : natural) is
            variable Target_v : natural;
        begin
            SppTbStore_v.clearStats(ChTxIn_c + p);
            LinkAB.Sel <= '1';

            for i in 0 to n - 1 loop
                if Octet_c(p) = '1' then
                    tbPush(ChTxA_c + p, tbPayload(len, i), tbTxUser(apid));
                else
                    tbPush(ChTxA_c + p, tbSpacePacket(0, 0, apid, 3, i, tbPayload(len - 6, i)), tbTxUser(0));
                end if;
                if i = 6 then
                    wait for (7 * beats(len) + 50) * ClkPeriod_c;
                    log(ID_LOG_HDR, "send port " & to_string(p) & " of A, " & to_string(len) & " bytes: " &
                        to_string(SppTbStore_v.packets(ChTxIn_c + p)) & " SDUs taken in " &
                        to_string(window(ChTxIn_c + p)) & " cycles");
                    check_value(SppTbStore_v.packets(ChTxIn_c + p), 7, ERROR, "send port: SDUs taken");
                    check_value(window(ChTxIn_c + p), 7 * beats(len), ERROR, "send port: one beat per cycle");
                end if;
            end loop;

            -- The send buffer fills with TxMaxPackets_g (8) SDUs
            wait for (8 * beats(len) + 100) * ClkPeriod_c;
            Target_v          := StatAB.Dropped + n;
            LinkAB.DropTarget <= Target_v;
            LinkAB.Sel        <= '0';
            wait until StatAB.Dropped = Target_v - n + 4 for 1 ms;
            SppTbStore_v.clearStats(ChLinkOut_c);
            wait until StatAB.Dropped = Target_v for 2 ms;
            tbWaitEmpty(ChTxA_c + p, 1 ms, "send port " & to_string(p) & " of core A");
            checkRate(ChLinkOut_c, n - 4, lb, "link output of A, send port " & to_string(p) & ", " & to_string(len) & " bytes");
        end procedure;

        -- Receiving end of core B: n Space Packets of len bytes (APID apid, routed to receive port q) injected
        -- back-to-back into its link input
        procedure receiveRate (
            q    : natural;
            apid : natural;
            len  : natural;
            n    : natural) is
            constant Ua_c : natural := 16#77# * boolean'pos(Encapsulation_g);
        begin
            SppTbStore_v.clearStats(ChLinkIn_c + 1);
            SppTbStore_v.clearStats(ChRxB_c + q);
            LinkAB.Sel <= '1';

            for i in 0 to n - 1 loop
                inject(tbSpacePacket(0, 0, apid, 3, i, tbPayload(len - 6, i)));
                if Octet_c(q) = '1' then
                    tbPush(ChRxB_c + q, tbPayload(len - 6, i), tbRxUser(apid, 0, 0, 0, Ua_c));
                else
                    tbPush(ChRxB_c + q, tbSpacePacket(0, 0, apid, 3, i, tbPayload(len - 6, i)), tbRxUser(apid, 0, 0, 0, Ua_c));
                end if;
            end loop;

            waitAll;
            LinkAB.Sel <= '0';
            checkRate(ChLinkIn_c + 1, n, len + CptpBytes_c, "link input of B, " & to_string(len) & " bytes");
            checkRate(ChRxB_c + q, n, len + CptpBytes_c, "receive port " & to_string(q) & " of B, " & to_string(len) & " bytes");
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

                for p in 0 to NumTx_g - 1 loop
                    tbSetStall(ChTxA_c + p, 0.2);
                end loop;

                for p in 0 to NumRx_g - 1 loop
                    tbSetStall(ChRxB_c + p, 0.2);
                    tbSetStall(ChRxA_c + p, 0.2);
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
                -- Target SpaceWire Address of the maximum length SpwAddrBytes_g (bytes 1, 2, 3, ...): core B removes
                -- up to 15 bytes (RX_STRIP), the network the others (as a network that delivers the packet)
                Addr_v := (others => '0');

                for b in 0 to SpwAddrBytes_g - 1 loop
                    Addr_v(8 * b + 7 downto 8 * b) := std_logic_vector(to_unsigned(b + 1, 8));
                end loop;

                dest(0, 1, 16#FE#, 16#21#, SpwAddrBytes_g, Addr_v);
                txPath(0, 16#123#, 1);
                Strip_v      := minimum(SpwAddrBytes_g, 15);
                regWrite(1, RegConfig_c, word(16#FE00# + Strip_v * 2 ** 4));
                LinkAB.Strip <= SpwAddrBytes_g - Strip_v;

                for i in 0 to 9 loop
                    octet(0, 0, 0, 16#123#, tbPayload(10 + 37 * i, i), 16#21#);
                end loop;

                waitAll;
                LinkAB.Strip <= 0;
                regCheck(1, RegRxPackets_c, word(10), "SDUs delivered by B");

            elsif run("test_every_port") then
                -- Every send port, destination and receive port, one SDU at a time: SDU i leaves send port
                -- i mod NumTx_g of A through destination i mod NumDest_g and reaches receive port i mod NumRx_g of B
                N_v := 2 * maximum(NumTx_g, maximum(NumRx_g, NumDest_g));

                for d in 0 to NumDest_g - 1 loop
                    dest(0, d, 16#FE#, 16#10# + d);
                end loop;

                for i in 0 to N_v - 1 loop
                    txPath(0, 16#100# + i, i mod NumDest_g);
                    rxPath(1, 16#100# + i, i mod NumRx_g);
                end loop;

                for i in 0 to N_v - 1 loop
                    Len_v := Rand_v.rand(1, 100);
                    Ua_v  := (16#10# + i mod NumDest_g) * boolean'pos(Encapsulation_g);
                    if Octet_c(i mod NumTx_g) = '1' then
                        octet(0, i mod NumTx_g, i mod NumRx_g, 16#100# + i, tbPayload(Len_v, i), Ua_v);
                    else
                        packet(0, i mod NumTx_g, i mod NumRx_g, tbSpacePacket(0, 0, 16#100# + i, 3, 0, tbPayload(Len_v, i)),
                               Ua_v);
                    end if;
                    waitAll;
                end loop;

                regCheck(0, RegTxPackets_c, word(N_v), "packets sent by A");
                regCheck(1, RegRxPackets_c, word(N_v), "SDUs delivered by B");
                check_value(Cores(0).Errors + Cores(1).Errors, 0, ERROR, "no error event");

            elsif run("test_reset_values") then
                -- The registers that show the generics, and the managed parameters at their reset values
                Srv_v                             := (others => '0');
                Srv_v(NumTx_g - 1 downto 0)       := Octet_c(NumTx_g - 1 downto 0);
                Srv_v(16 + NumRx_g - 1 downto 16) := Octet_c(NumRx_g - 1 downto 0);
                regCheck(0, RegGenerics_c, word(NumTx_g + NumRx_g * 2 ** 5 + NumDest_g * 2 ** 10 + SpwAddrBytes_g * 2 ** 15 +
                                                Bytes_c * 2 ** 20 + boolean'pos(Encapsulation_g) * 2 ** 25), "GENERICS");
                regCheck(0, RegServices_c, Srv_v, "SERVICES");
                regCheck(0, RegTxBuffer_c, word(Bytes_c * BufferBeats_c), "TX_BUFFER");
                regCheck(0, RegRxBuffer_c, word(Bytes_c * BufferBeats_c), "RX_BUFFER");
                regCheck(0, RegConfig_c, word(Tla_g * 2 ** 8 + boolean'pos(RoundRobin_g)), "CONFIG");
                regCheck(0, RegMaxLength_c, word(MaxLength_g), "MAX_LENGTH");

            elsif run("test_idle") then
                -- Idle cores after the table initialisation: no metavalue reaches the arithmetic of the data paths.
                -- The VUnit configuration of this test enables the IEEE warnings and fails on a metavalue warning
                -- after the marker below. Positive control: the testbench raises one numeric_std warning itself
                -- between the probe markers, and the post check requires it, so the test fails when the IEEE
                -- warnings are disabled.
                report "SPP_IDLE_PROBE_START";
                IeeeProbeReq <= true;
                wait until IeeeProbeAck;
                report "SPP_IDLE_PROBE_END";
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

            elsif run("test_throughput") then

                -- Sending end: Octet Strings on port 0, also to a destination with a Target SpaceWire Address of 4
                -- bytes, and Space Packets on the Packet Service port 1
                for i in OctetLen_c'range loop
                    sendRate(0, 16#30#, OctetLen_c(i), OctetLen_c(i) + 6 + CptpBytes_c, 16);
                end loop;

                if Encapsulation_g then
                    dest(0, 1, 16#40#, 16#31#, 4, x"04030201");
                    txPath(0, 16#31#, 1);
                    sendRate(0, 16#31#, 61, 61 + 6 + CptpBytes_c + 4, 16);
                end if;

                for i in PacketLen_c'range loop
                    sendRate(1, 16#20#, PacketLen_c(i), PacketLen_c(i) + CptpBytes_c, 16);
                end loop;

                -- Receiving end: Space Packets to the Octet String port 0 and to the Packet Service port 1
                rxPath(1, 16#21#, 1);

                for i in PacketLen_c'range loop
                    receiveRate(0, 16#22#, PacketLen_c(i), 16);
                    receiveRate(1, 16#21#, PacketLen_c(i), 16);
                end loop;

                -- Two send ports with queued SDUs: port 0 fills its buffer first, so that the first two packets are
                -- decided for it, then port 2. Fixed priority sends all SDUs of port 0 before port 2, round robin
                -- alternates the ports from the third packet; both keep the bound
                rxPath(1, 16#42#, 2);

                for scheme in 0 to 1 loop
                    regWrite(0, RegConfig_c, word(16#FE00# + scheme));
                    LinkAB.Sel <= '1';

                    for i in 0 to 11 loop
                        octet(0, 0, 0, 16#40#, tbPayload(61, i));
                    end loop;

                    wait for (8 * beats(61) + 100) * ClkPeriod_c;

                    for i in 0 to 11 loop
                        octet(0, 2, 2, 16#42#, tbPayload(61, 50 + i));
                    end loop;

                    wait for (8 * beats(61) + 100) * ClkPeriod_c;
                    SppTbStore_v.clearStats(ChLinkOut_c);
                    SppTbStore_v.clearStats(ChRxB_c);
                    SppTbStore_v.clearStats(ChRxB_c + 2);
                    LinkAB.Sel <= '0';
                    waitAll;
                    Len_v      := 61 + 6 + CptpBytes_c;
                    checkRate(ChLinkOut_c, 24, Len_v, "link output of A, ports 0 and 2, scheme " & to_string(scheme));
                    if scheme = 0 then
                        check_value(SppTbStore_v.firstTime(ChRxB_c + 2) > SppTbStore_v.lastTime(ChRxB_c), ERROR,
                                    "fixed priority: all SDUs of port 0 first");
                    else
                        check_value(SppTbStore_v.firstTime(ChRxB_c + 2) - SppTbStore_v.firstTime(ChRxB_c) <=
                                    3 * cyclesBound(Len_v) * ClkPeriod_c, ERROR, "round robin: port 2 from the third packet");
                        check_value(abs (SppTbStore_v.lastTime(ChRxB_c + 2) - SppTbStore_v.lastTime(ChRxB_c)) <=
                                    3 * cyclesBound(Len_v) * ClkPeriod_c, ERROR, "round robin: the ports alternate");
                    end if;
                end loop;

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
                -- Rst of A while B sends a packet to A: S_Link_Ready of A in the reset (reset probe), the rest of the
                -- packet is checked after the release as a packet of its own and discarded once
                tbPush(ChTxB_c, Fill_v, tbTxUser(16#41#));
                wait until Probe(0).SlinkBeats >= 3 for 1 ms;
                Rel_v := Probe(0).Releases;
                RstA  <= '1';

                for i in 1 to 3 loop
                    wait until rising_edge(Clk);
                end loop;

                RstA <= '0';
                waitRelease(0, Rel_v);
                octet(1, 0, 0, 16#41#, tbPayload(20, 12));
                waitAll;
                if Encapsulation_g then
                    regCheck(0, RegErrRx1_c, word(2 ** 16), "ERR_RX1: rest of the packet, Protocol Identifier");
                else
                    regCheck(0, RegErrRx3_c, word(2 ** 16), "ERR_RX3: rest of the packet, version");
                end if;
                regCheck(0, RegRxPackets_c, word(1), "SDU delivered by A after its reset");
                check_value(Probe(0).Slink(SlinkInside_c), 1, ERROR, "reset of A inside a received packet");

            elsif run("test_dprst_eep") then
                -- DpRst of A for one cycle at the transfer of the first, the second and the second-to-last beat of a
                -- packet: the packet ends with one EEP beat (checked cycle by cycle by the link output monitor), B
                -- discards it, and A sends again after the release with counts from 0
                Len_v   := 200;
                Beats_v := beats(Len_v + 6 + CptpBytes_c);
                rxPath(1, 16#60#, 0, 1);
                txPath(0, 16#60#, 3);
                octet(0, 0, 0, 16#60#, tbPayload(30, 0));
                waitAll;

                for k in 0 to 2 loop
                    Beat_v := 1 when k = 0 else 2 when k = 1 else Beats_v - 1;
                    Rel_v  := Probe(0).Releases;
                    Pkts_v := Mon(0).Packets;
                    arm(0, Beat_v);
                    tbPush(ChTxA_c, tbPayload(Len_v, 10 + k), tbTxUser(16#60#));
                    waitRelease(0, Rel_v);
                    check_value(Mon(0).Packets, Pkts_v + 1, ERROR, "only the interrupted packet before the release");
                    txPath(0, 16#60#, 3);
                    octet(0, 0, 0, 16#60#, tbPayload(30, 20 + k), 0, 1);
                    octet(0, 0, 0, 16#60#, tbPayload(30, 30 + k));
                    waitAll;
                end loop;

                check_value(Mon(0).Eeps, 3, ERROR, "EEP beats of A");
                -- The beat of the reset edge is transferred at it, or pending through the N-Char adapters
                check_value(Mon(0).Point(PointFirstXfer_c) + Mon(0).Point(PointFirstPend_c), 1, ERROR,
                            "reset edge at a first beat");
                check_value(Mon(0).Point(PointMiddleXfer_c) + Mon(0).Point(PointMiddlePend_c), 2, ERROR,
                            "reset edge at a middle beat");
                check_value(Probe(0).Length(Length1_c), 3, ERROR, "DpRst of one cycle");
                regCheck(1, RegErrRx1_c, word(3), "ERR_RX1: three packets with EEP discarded by B");
                regCheck(1, RegRxPackets_c, word(7), "SDUs delivered by B");
                regCheck(1, RegRxLoss_c, word(3), "discontinuities indicated by B");

            elsif run("test_dprst_no_eep") then
                -- No EEP beat: DpRst of A (a) while A sends nothing, (b) at the transfer of the last beat of a packet,
                -- (c) at the transfer of the last beat while the next packet waits back-to-back (discarded)
                Len_v   := 200;
                Beats_v := beats(Len_v + 6 + CptpBytes_c);
                Rel_v   := Probe(0).Releases;
                Pkts_v  := Mon(0).Packets;
                dpPulse(0, 3);
                waitRelease(0, Rel_v);
                check_value(Mon(0).Packets, Pkts_v, ERROR, "(a) no beat on the link");
                Rel_v   := Probe(0).Releases;
                arm(0, Beats_v, 2);
                octet(0, 0, 0, 16#61#, tbPayload(Len_v, 1));
                waitRelease(0, Rel_v);
                waitAll;
                Rel_v   := Probe(0).Releases;
                arm(0, Beats_v, 2);
                octet(0, 0, 0, 16#61#, tbPayload(Len_v, 2));
                tbPush(ChTxA_c, tbPayload(Len_v, 3), tbTxUser(16#61#));
                waitRelease(0, Rel_v);
                octet(0, 0, 0, 16#61#, tbPayload(30, 4));
                waitAll;
                check_value(Mon(0).Eeps + Mon(0).EepPkts, 0, ERROR, "no EEP beat");
                check_value(Mon(0).Point(PointNone_c), 1, ERROR, "reset edge without an open packet");
                check_value(Mon(0).Point(PointLastXfer_c) + Mon(0).Point(PointLastPend_c), 2, ERROR,
                            "reset edge at a last beat");
                check_value(Cores(1).Errors, 0, ERROR, "no error event at B");
                regCheck(1, RegRxPackets_c, word(3), "SDUs delivered by B");

            elsif run("test_dprst_stall") then
                -- The link stalls for 20 cycles at the beat of the reset edge, DpRst lasts 30 cycles: (a) a middle
                -- beat, (b) a first beat is held and followed by the EEP beat, (c) a pending last beat ends the packet
                -- without EEP beat; (d) DpRst of 4 cycles, a middle beat held for 3000 cycles, beyond the release and
                -- the table initialisation: the SDUs taken after the release follow the EEP beat
                Len_v   := 200;
                Beats_v := beats(Len_v + 6 + CptpBytes_c);

                for k in 0 to 1 loop
                    Beat_v := 3 when k = 0 else 1;
                    Rel_v  := Probe(0).Releases;
                    arm(0, Beat_v, 30, stallBeat => Beat_v, stallCycles => 20);
                    tbPush(ChTxA_c, tbPayload(Len_v, k), tbTxUser(16#62#));
                    waitRelease(0, Rel_v);
                end loop;

                Rel_v  := Probe(0).Releases;
                arm(0, Beats_v, 30, stallBeat => Beats_v, stallCycles => 20);
                octet(0, 0, 0, 16#62#, tbPayload(Len_v, 5));
                waitRelease(0, Rel_v);
                waitAll;
                Rel_v  := Probe(0).Releases;
                arm(0, 3, 4, stallBeat => 3, stallCycles => 3000);
                tbPush(ChTxA_c, tbPayload(Len_v, 6), tbTxUser(16#62#));
                wait until Probe(0).Releases > Rel_v for 1 ms;
                CntA_v := (others => 0);
                octet(0, 0, 0, 16#62#, tbPayload(40, 7));
                octet(0, 0, 0, 16#62#, tbPayload(40, 8));
                waitAll;
                check_value(Mon(0).Eeps, 3, ERROR, "EEP beats of A");
                check_value(Mon(0).Point(PointMiddlePend_c), 2, ERROR, "middle beat pending at the reset edge");
                check_value(Mon(0).Point(PointFirstPend_c), 1, ERROR, "first beat pending at the reset edge");
                check_value(Mon(0).Point(PointLastPend_c), 1, ERROR, "last beat pending at the reset edge");
                check_value(Mon(0).Link(LinkAfterRel_c), 1, ERROR, "end of the packet after the release");
                regCheck(1, RegErrRx1_c, word(3), "ERR_RX1: three packets with EEP discarded by B");
                regCheck(1, RegRxPackets_c, word(3), "SDUs delivered by B");

            elsif run("test_dprst_long") then
                -- DpRst of A for 5000 cycles inside a packet: one EEP beat at once, then no beat up to the release;
                -- a second reset edge of DpRst while the EEP beat is pending on a stalled link: still one EEP beat
                Rel_v := Probe(0).Releases;
                arm(0, 5, 5000);
                tbPush(ChTxA_c, tbPayload(200, 1), tbTxUser(16#63#));
                waitRelease(0, Rel_v);
                check_value(Mon(0).Eeps, 1, ERROR, "one EEP beat during a long DpRst");
                Rel_v := Probe(0).Releases;
                arm(0, 5, 2, stallBeat => 6, stallCycles => 60);
                tbPush(ChTxA_c, tbPayload(200, 2), tbTxUser(16#63#));
                wait until Probe(0).InReset for 1 ms;
                wait for 10 * ClkPeriod_c;
                dpPulse(0, 3);
                waitRelease(0, Rel_v, 2);
                octet(0, 0, 0, 16#63#, tbPayload(40, 3));
                waitAll;
                check_value(Mon(0).Eeps, 2, ERROR, "one EEP beat per interrupted packet");
                check_value(Mon(0).EepPkts, 2, ERROR, "packets ended with an EEP");
                check_value(Probe(0).Length(LengthLong_c), 1, ERROR, "DpRst of more than 2048 cycles");
                check_value(Probe(0).Length(Length16_c), 2, ERROR, "DpRst of 2 to 16 cycles");
                regCheck(1, RegErrRx1_c, word(2), "ERR_RX1: two packets with EEP discarded by B");
                regCheck(1, RegRxPackets_c, word(1), "SDU delivered by B");

            elsif run("test_dprst_state") then

                -- Every register and both APID tables return to their reset values; the tables are initialised again
                for pass in 0 to 1 loop
                    -- Counters, events, last error and ECC counters of A, written table entries
                    if not PathDefault_g then
                        txPath(0, 16#124#, 0);
                        rxPath(1, 16#124#, 0);
                        txPath(1, 16#125#, 0);
                        rxPath(0, 16#125#, 0);
                    end if;
                    octet(0, 0, 0, 16#124#, tbPayload(20, 1));
                    octet(1, 0, 0, 16#125#, tbPayload(20, 2));
                    waitAll;
                    regWrite(0, RegEccInject_c, x"00000100");
                    octet(0, 0, 0, 16#124#, tbPayload(20, 3));
                    waitAll;
                    regWrite(0, RegMaxLength_c, word(100));
                    tbPush(ChTxA_c, tbPayload(200, 4), tbTxUser(16#124#));
                    waitAll;
                    txPath(0, 16#123#, 2, 77);
                    rxPath(0, 16#123#, 1, 1);
                    regWrite(0, RegIrqEn_c, x"0000007F");
                    regWrite(0, RegEccSelect_c, word(3));
                    regWrite(0, RegScrub_c, word(0));
                    regWrite(0, RegConfig_c, x"00004013");

                    for d in 0 to NumDest_g - 1 loop
                        dest(0, d, 16#41#, 16#22#, minimum(SpwAddrBytes_g, 2), x"00000201");
                    end loop;

                    -- The counters clear on a write only: these reads leave them
                    regCheck(0, RegErrTx1_c, word(1), "ERR_TX1 before the reset");
                    regWrite(0, RegEccSelect_c, word(0));
                    regCheck(0, RegEccCount_c, word(1), "ECC_COUNT before the reset");
                    regWrite(0, RegEccSelect_c, word(3));
                    -- DpRst of one cycle, then of 16 cycles
                    Rel_v := Probe(0).Releases;
                    dpPulse(0, 1 + 15 * pass);
                    T_v   := now;
                    regCheck(0, RegTableStatus_c, x"00000003", "tables initialised after the release");
                    wait for T_v + 2064 * ClkPeriod_c - now;
                    regCheck(0, RegTableStatus_c, x"00000000", "tables ready 2048 cycles after the release");
                    waitRelease(0, Rel_v);
                    -- Reset values of the register file
                    regCheck(0, RegConfig_c, word(Tla_g * 2 ** 8 + boolean'pos(RoundRobin_g)), "CONFIG");
                    regCheck(0, RegMaxLength_c, word(MaxLength_g), "MAX_LENGTH");
                    regCheck(0, RegTxTableApid_c, RegTxTableApidReset_c, "TX_TABLE_APID");
                    regCheck(0, RegRxTableApid_c, RegRxTableApidReset_c, "RX_TABLE_APID");
                    regCheck(0, RegLastError_c, word(0), "LAST_ERROR");
                    regCheck(0, RegEvents_c, RegEventsReset_c, "EVENTS");
                    regCheck(0, RegIrqEn_c, RegIrqEnReset_c, "IRQ_EN");
                    regCheck(0, RegIrqStatus_c, word(0), "IRQ_STATUS");
                    regCheck(0, RegEccStatus_c, RegEccStatusReset_c, "ECC_STATUS");
                    regCheck(0, RegEccSelect_c, RegEccSelectReset_c, "ECC_SELECT");
                    regCheck(0, RegEccCount_c, RegEccCountReset_c, "ECC_COUNT");
                    regCheck(0, RegScrub_c, RegScrubReset_c, "SCRUB");
                    regCheck(0, RegTxPackets_c, RegTxPacketsReset_c, "TX_PACKETS");
                    regCheck(0, RegRxPackets_c, RegRxPacketsReset_c, "RX_PACKETS");
                    regCheck(0, RegRxLoss_c, RegRxLossReset_c, "RX_LOSS");

                    for r in 0 to 3 loop
                        regCheck(0, RegErrTx1_c + 4 * r, word(0), "ERR_TX" & to_string(r + 1));
                    end loop;

                    for r in 0 to 5 loop
                        regCheck(0, RegErrRx1_c + 4 * r, word(0), "ERR_RX" & to_string(r + 1));
                    end loop;

                    for d in 0 to NumDest_g - 1 loop
                        regCheck(0, RegDestCtrl_c + d * RegDestStride_c, RegDestCtrlReset_c, "DEST_CTRL");
                        regCheck(0, RegDestAddr0_c + d * RegDestStride_c, RegDestAddr0Reset_c, "DEST_ADDR0");
                    end loop;

                    -- Initial entries of both APID tables
                    regWrite(0, RegTxTableApid_c, word(16#123#));
                    regCheck(0, RegTxTableEntry_c, word(boolean'pos(PathDefault_g) * 2 ** 18), "initial send entry");
                    regWrite(0, RegRxTableApid_c, word(16#123#));
                    regCheck(0, RegRxTableEntry_c, word(boolean'pos(PathDefault_g) * 2 ** 20), "initial receive entry");
                    -- The core works again after the programming sequence
                    if not PathDefault_g then
                        txPath(0, 16#126#, 0);
                        rxPath(1, 16#126#, 0);
                    end if;
                    octet(0, 0, 0, 16#126#, tbPayload(20, 5));
                    waitAll;
                    regCheck(0, RegTxPackets_c, word(1), "packet sent by A after the reset");
                end loop;

                check_value(Probe(0).Length(Length1_c), 1, ERROR, "DpRst of one cycle");
                check_value(Probe(0).Length(Length16_c), 1, ERROR, "DpRst of 16 cycles");

            elsif run("test_dprst_rst") then
                -- Orders of Rst and DpRst of A with a packet open on the link, which drops the packets of A: no EEP beat
                -- follows Rst in any order, the core leaves the reset at the later release
                LinkAB.DropTarget <= 1000;

                for k in 0 to 6 loop
                    Rel_v  := Probe(0).Releases;
                    Eps_v  := 1;
                    Eeps_v := Mon(0).Eeps;

                    case k is

                        when 0 =>
                            -- Rst while the EEP beat is pending on a stalled link: the EEP beat is withdrawn
                            arm(0, 3, 2, 0, 2, 10, 4, 40);
                            Eps_v := 2;

                        when 1 =>
                            -- Both applied at the same edge, released at the same edge
                            arm(0, 3, 3, 0, 3, 0);

                        when 2 =>
                            -- Both applied at the same edge, Rst released first, DpRst one cycle later
                            arm(0, 3, 4, 0, 3, 0);

                        when 3 =>
                            -- Both applied at the same edge, DpRst released first, Rst ten cycles later
                            arm(0, 3, 2, 0, 12, 0);

                        when 4 =>
                            -- DpRst applied while Rst is applied
                            arm(0, 3, 3, 3, 10, 0);

                        when 5 =>
                            -- Rst alone
                            arm(0, 3, 0, 0, 3, 0);

                        when others =>
                            -- Rst applied while DpRst is applied, after the EEP beat: Rst released first
                            arm(0, 3, 10, 0, 3, 3);

                    end case;

                    tbPush(ChTxA_c, tbPayload(200, k), tbTxUser(16#64#));
                    waitRelease(0, Rel_v, Eps_v);
                    check_value(Mon(0).Eeps, Eeps_v + boolean'pos(k = 6), ERROR, "EEP beats of A, case " & to_string(k));
                end loop;

                check_value(Probe(0).Order(OrderDpRst_c) > 0 and Probe(0).Order(OrderRst_c) > 0 and
                            Probe(0).Order(OrderSameEdge_c) > 0 and Probe(0).Order(OrderRstInDp_c) > 0 and
                            Probe(0).Order(OrderDpInRst_c) > 0 and Probe(0).Order(OrderRstFirst_c) > 0 and
                            Probe(0).Order(OrderDpFirst_c) > 0 and Probe(0).Order(OrderSameRel_c) > 0, ERROR,
                            "every order of the two inputs");
                -- The EEP beat of the last case ended the packet in the link model: forward the next packets
                LinkAB.DropTarget <= StatAB.Dropped;
                octet(0, 0, 0, 16#64#, tbPayload(40, 10));
                waitAll;
                regCheck(1, RegRxPackets_c, word(1), "SDU delivered by B");

            elsif run("test_dprst_ports") then
                -- B sends a long SDU to receive port 0 of A, which delivers it slowly
                SppTbStore_v.clearStats(ChRxA_c);
                tbSetStall(ChRxA_c, 0.9);
                octet(1, 0, 0, 16#71#, tbPayload(2000, 1));

                -- The statistics are a shared variable: polled once per cycle
                for i in 1 to 100000 loop
                    exit when SppTbStore_v.bytes(ChRxA_c) > 0;
                    wait until rising_edge(Clk);
                end loop;

                check_value(SppTbStore_v.bytes(ChRxA_c) > 0, ERROR, "A delivers the SDU of B");
                -- A sends a packet of 1000 bytes from send port 0; once it is on the link, a complete SDU waits on
                -- send port 2, and every send port takes part of an SDU
                Pkts_v := Mon(0).Beats;
                tbPush(ChTxA_c, tbPayload(1000, 2), tbTxUser(16#72#));
                wait until Mon(0).Beats > Pkts_v for 1 ms;
                if NumTx_g > 2 then
                    tbPush(ChTxA_c + 2, tbPayload(20, 3), tbTxUser(16#73#));
                end if;

                for p in 0 to NumTx_g - 1 loop
                    if Octet_c(p) = '1' then
                        tbPush(ChTxA_c + p, tbPayload(3000, 10 + p), tbTxUser(16#74#));
                    else
                        tbPush(ChTxA_c + p, tbSpacePacket(0, 0, 16#75#, 3, 0, tbPayload(3000, 10 + p)), tbTxUser(0));
                    end if;
                end loop;

                wait for 100 * ClkPeriod_c;
                -- DpRst of A for 8 cycles: the sink drops the SDU it was receiving (ends without its last beat)
                wait until rising_edge(Clk);
                Rel_v              := Probe(0).Releases;
                Eps_v              := Probe(0).Cycles;
                ResetCtrl(0).DpRst <= '1';
                wait until rising_edge(Clk);
                SppTbStore_v.setAbort(ChRxA_c);
                SppTbStore_v.pop(ChRxA_c);

                for i in 1 to 7 loop
                    wait until rising_edge(Clk);
                end loop;

                ResetCtrl(0).DpRst <= '0';
                waitRelease(0, Rel_v);
                check_value(Probe(0).Cycles - Eps_v, 7, ERROR, "cycles checked by the reset probe");
                check_value(SppTbStore_v.packets(ChRxA_c), 0, ERROR, "SDU in delivery ended without its last beat");
                tbSetStall(ChRxA_c, 0.0);

                -- Every send port sends a new SDU, B delivers exactly these
                for p in 0 to NumTx_g - 1 loop
                    if Octet_c(p) = '1' then
                        octet(0, p, 0, 16#80# + p, tbPayload(40, 20 + p));
                    else
                        packet(0, p, 0, tbSpacePacket(0, 0, 16#80# + p, 3, 0, tbPayload(40, 20 + p)));
                    end if;
                    waitAll;
                end loop;

                octet(1, 0, 0, 16#71#, tbPayload(30, 4));
                waitAll;
                check_value(Mon(0).Eeps, 1, ERROR, "EEP beat of the packet of send port 0");
                regCheck(1, RegErrRx1_c, word(1), "ERR_RX1: packet with EEP discarded by B");
                regCheck(1, RegRxPackets_c, word(NumTx_g), "SDUs delivered by B");
                regCheck(0, RegRxPackets_c, word(1), "SDU delivered by A after the reset");

            elsif run("test_dprst_active_link") then
                -- Both directions with the continuity check; DpRst of A while it sends and receives a packet
                rxPath(1, 16#90#, 0, 1);
                rxPath(0, 16#91#, 0, 1);

                for i in 0 to 4 loop
                    octet(0, 0, 0, 16#90#, tbPayload(50, i));
                    octet(1, 0, 0, 16#91#, tbPayload(50, 10 + i));
                end loop;

                waitAll;
                -- A sends a long packet; once it is on the link B sends a packet that fails the checks of A at any offset
                Pkts_v := Mon(0).Beats;
                tbPush(ChTxA_c, tbPayload(2000, 20), tbTxUser(16#90#));
                wait until Mon(0).Beats > Pkts_v for 1 ms;
                tbPush(ChTxB_c, Fill_v, tbTxUser(16#91#));
                wait until Probe(0).SlinkBeats >= 3 for 1 ms;
                Rel_v  := Probe(0).Releases;
                dpPulse(0, 4);
                waitRelease(0, Rel_v);
                rxPath(0, 16#91#, 0, 1);

                for i in 0 to 2 loop
                    octet(0, 0, 0, 16#90#, tbPayload(50, 30 + i), 0, boolean'pos(i = 0));
                    octet(1, 0, 0, 16#91#, tbPayload(50, 40 + i));
                end loop;

                waitAll;
                check_value(Mon(0).Eeps, 1, ERROR, "EEP beat of A");
                check_value(Probe(0).Slink(SlinkInside_c), 1, ERROR, "DpRst of A inside a received packet");
                regCheck(1, RegErrRx1_c, word(1), "ERR_RX1: packet with EEP discarded by B");
                regCheck(1, RegRxPackets_c, word(8), "SDUs delivered by B");
                regCheck(1, RegRxLoss_c, word(1), "discontinuity of the counts of A at B");
                regCheck(1, RegTxPackets_c, word(9), "packets sent by B");
                if Encapsulation_g then
                    regCheck(0, RegErrRx1_c, word(2 ** 16), "ERR_RX1: rest of the packet, Protocol Identifier");
                else
                    regCheck(0, RegErrRx3_c, word(2 ** 16), "ERR_RX3: rest of the packet, version");
                end if;
                regCheck(0, RegRxPackets_c, word(3), "SDUs delivered by A after the reset");
                regCheck(0, RegRxLoss_c, word(0), "no loss indication at A");
            end if;

            wait for 20 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    -- Positive control of test_idle: to_integer of an undefined vector raises the numeric_std warning
    -- "metavalue detected" when the IEEE warnings are enabled; the result is checked so that it is evaluated
    p_ieee_probe : process is
    begin
        wait until IeeeProbeReq;
        check_value(to_integer(IeeeProbeData), 0, ERROR, "to_integer of an undefined vector");
        IeeeProbeAck <= true;
        wait;
    end process;

    i_th : entity work.spp_core_th
        generic map (
            DataWidth_g     => DataWidth_g,
            Encapsulation_g => Encapsulation_g,
            BufferBeats_g   => BufferBeats_c,
            NChar_g         => NChar_g,
            PathDefault_g   => PathDefault_g,
            SpwAddrBytes_g  => SpwAddrBytes_g,
            NumTx_g         => NumTx_g,
            NumRx_g         => NumRx_g,
            NumDest_g       => NumDest_g,
            TxMaxPackets_g  => TxMaxPackets_g,
            RxMaxPackets_g  => RxMaxPackets_g,
            MaxLength_g     => MaxLength_g,
            RoundRobin_g    => RoundRobin_g,
            Tla_g           => Tla_g
        )
        port map (
            Clk       => Clk,
            RstA      => RstA,
            RstB      => RstB,
            ResetCtrl => ResetCtrl,
            LinkAB    => LinkAB,
            LinkBA    => LinkBA,
            StatAB    => StatAB,
            StatBA    => StatBA,
            Cores     => Cores,
            Mon       => Mon,
            Probe     => Probe
        );

end architecture;
