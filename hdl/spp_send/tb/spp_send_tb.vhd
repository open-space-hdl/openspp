---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the sending end: every Space Packet is compared byte by byte with the packet built by
-- the packet model from the request (Octet String Service) or with the submitted packet (Packet
-- Service), with the destination of its APID; rejected SDUs are checked through the error events.
--
-- Documentation: hdl/spp_send/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.spp_pkg.all;
    use work.spp_tb_pkg.all;
    use work.spp_tb_stream_pkg.all;
    use work.spp_tb_streamvar_pkg.all;
    use work.spp_tb_packet_pkg.all;
    use work.spp_send_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_send_tb is
    generic (
        runner_cfg     : string;
        DataWidth_g    : positive := 32;
        NumTx_g        : positive := 1;
        PacketPorts_g  : natural  := 0;     -- bit p set: port p uses the Packet Service
        BufferBytes_g  : positive := 4096
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_send_tb is

    constant Bytes_c       : positive                                  := DataWidth_g / 8;
    constant OctetString_c : std_logic_vector(MaxPorts_c - 1 downto 0) :=
        not std_logic_vector(to_unsigned(PacketPorts_g, MaxPorts_c));

    signal Clk         : std_logic;
    signal Rst         : std_logic                                     := '1';
    signal MaxLength   : std_logic_vector(LengthWidth_c - 1 downto 0)  := std_logic_vector(to_unsigned(65542, LengthWidth_c));
    signal RoundRobin  : std_logic                                     := '0';
    signal TableInit   : std_logic_vector(TxEntryWidth_c - 1 downto 0) := txEntry(1, 0, 0);
    signal TblReq      : TblReq_t                                      := TblReqIdle_c;
    signal TblRsp      : TblRsp_t;
    signal Errors      : ErrLog_t;
    signal Sent        : natural;
    signal EccSec      : NatArray_t(0 to 3);
    signal EccDed      : NatArray_t(0 to 3);
    signal InjChannel  : std_logic_vector(5 downto 0)                  := (others => '0');
    signal InjDouble   : std_logic                                     := '0';
    signal InjValid    : std_logic                                     := '0';
    signal ScrubEnable : std_logic                                     := '1';

begin

    test_runner_watchdog(runner, 50 ms);

    p_main : process is
        variable Rand_v   : t_rand;
        variable Cnt_v    : NatArray_t(0 to 2047);
        variable Seed_v   : natural := 1;
        variable Len_v    : natural;
        variable Apid_v   : natural;
        variable Entry_v  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
        variable Ded_v    : std_logic;
        variable Data_v   : TbBytes_t(0 to 39);
        variable P_v      : natural;
        variable Beats_v  : natural;
        variable Cycles_v : natural;
        variable Errs_v   : natural;

        -- Transaction of the register file on the send APID table
        procedure tblAccess (
            apid         : natural;
            write        : boolean;
            data         : std_logic_vector(TxEntryWidth_c - 1 downto 0);
            variable rd  : out std_logic_vector(TxEntryWidth_c - 1 downto 0);
            variable ded : out std_logic;
            hold         : boolean := false) is
        begin
            TblReq.Valid <= '1';
            TblReq.Apid  <= std_logic_vector(to_unsigned(apid, 11));

            loop
                wait until rising_edge(Clk);
                exit when TblRsp.Ready = '1';
            end loop;

            TblReq.Valid <= '0';

            loop
                wait until rising_edge(Clk);
                exit when TblRsp.RdValid = '1';
            end loop;

            rd  := TblRsp.RdData;
            ded := TblRsp.RdDed;
            if not hold then
                if write then
                    TblReq.WrEna  <= '1';
                    TblReq.WrData <= data;
                else
                    TblReq.Done <= '1';
                end if;
                wait until rising_edge(Clk);
                TblReq.WrEna <= '0';
                TblReq.Done  <= '0';
            end if;
        end procedure;

        procedure tblWrite (
            apid  : natural;
            entry : std_logic_vector(TxEntryWidth_c - 1 downto 0)) is
            variable Rd_v  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
            variable Ded_v : std_logic;
        begin
            tblAccess(apid, true, entry, Rd_v, Ded_v);
        end procedure;

        -- Ends a transaction held by tblAccess with hold = true
        procedure tblRelease is
        begin
            TblReq.Done <= '1';
            wait until rising_edge(Clk);
            TblReq.Done <= '0';
        end procedure;

        procedure waitSent (timeout : time := 2 ms) is
        begin

            for p in 0 to NumTx_g - 1 loop
                tbWaitEmpty(p, timeout, "source of port " & to_string(p));
                tbWaitEmpty(ChSink_c + p, timeout, "packets of port " & to_string(p));
            end loop;

            wait for 20 * ClkPeriod_c;
        end procedure;

        procedure checkErrors (
            code  : ErrCode_t;
            count : natural;
            msg   : string) is
        begin
            check_value(Errors.Count(to_integer(unsigned(code))), count, ERROR, msg);
        end procedure;

        procedure checkLast (
            code : ErrCode_t;
            idx  : natural;
            apid : natural) is
        begin
            check_value(Errors.Last.Code, code, ERROR, "code of the last error event");
            check_value(to_integer(unsigned(Errors.Last.Index)), idx, ERROR, "port of the last error event");
            check_value(to_integer(unsigned(Errors.Last.Apid)), apid, ERROR, "APID of the last error event");
        end procedure;

        procedure inject (
            channel : natural;
            double  : std_logic) is
        begin
            InjChannel <= std_logic_vector(to_unsigned(channel, 6));
            InjDouble  <= double;
            InjValid   <= '1';
            wait until rising_edge(Clk);
            InjValid   <= '0';
        end procedure;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        Rand_v.set_rand_seeds(DataWidth_g, NumTx_g);

        while test_suite loop
            -- Reset, table initialisation, match mode of the sink for several ports (bytes 0 and 1: APID)
            Rst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            Rst <= '0';
            wait until rising_edge(Clk);
            if TblRsp.Busy = '1' then
                wait until TblRsp.Busy = '0';
            end if;
            wait until rising_edge(Clk);
            tbSetMatch(ChSink_c, NumTx_g, 0, 2);
            Cnt_v := (others => 0);

            if run("test_octet_string") then
                -- Octet Strings of four APIDs interleaved: header fields, Packet Data Length and one Packet Sequence
                -- Count per APID; APID 100 has destination 5
                tblWrite(100, txEntry(1, 5, 0));
                tbSetStall(0, 0.2);
                tbSetStall(ChSink_c, 0.2);

                for i in 0 to 199 loop

                    case i mod 4 is
                        when 0 => Apid_v := 0;
                        when 1 => Apid_v := 100;
                        when 2 => Apid_v := 2046;
                        when others => Apid_v := 1365;
                    end case;

                    if i < 8 then
                        Len_v := i + 1;
                    elsif i < 12 then
                        Len_v := Bytes_c + i - 8;
                    else
                        Len_v := Rand_v.rand(1, 300);
                    end if;
                    sendOctet(0, Apid_v, tbPayload(Len_v, Seed_v), Cnt_v(Apid_v), 5 * (1 - minimum(1, abs (Apid_v - 100))),
                              i mod 2, (i / 2) mod 2);
                    Cnt_v(Apid_v) := Cnt_v(Apid_v) + 1;
                    Seed_v        := Seed_v + 1;
                end loop;

                waitSent;
                check_value(Sent, 200, ERROR, "packets sent");
                check_value(Errors.Total, 0, ERROR, "no error event");

            elsif run("test_packet_name") then
                -- Telecommand packets with a Packet Name keep the count of the APID; a Packet Name of a telemetry
                -- packet is rejected
                sendOctet(0, 7, tbPayload(10, 1), Cnt_v(7), 0, 0, 1);
                Cnt_v(7) := Cnt_v(7) + 1;
                sendOctet(0, 7, tbPayload(11, 2), 0, 0, 1, 1, 1, 16#2ABC#);
                sendOctet(0, 7, tbPayload(12, 3), 0, 0, 0, 1, 1, 0);
                sendOctet(0, 7, tbPayload(13, 4), Cnt_v(7), 0, 0, 1);
                Cnt_v(7) := Cnt_v(7) + 1;
                waitSent;
                sendRejected(0, tbPayload(14, 5), tbTxUser(7, 0, 0, 1, 5));
                sendOctet(0, 7, tbPayload(15, 6), Cnt_v(7), 0, 0, 0);
                Cnt_v(7) := Cnt_v(7) + 1;
                waitSent;
                checkErrors(ErrTxName_c, 1, "Packet Name of a telemetry packet rejected");
                checkLast(ErrTxName_c, 0, 7);
                check_value(Sent, 5, ERROR, "packets sent");

            elsif run("test_count_wrap") then
                -- The count is continuous modulo 16384; another APID keeps its own count
                tblWrite(42, txEntry(1, 2, 16381));

                for i in 0 to 5 loop
                    sendOctet(0, 42, tbPayload(20, i), (16381 + i) mod 16384, 2);
                    sendOctet(0, 43, tbPayload(21, i), i, 0);
                end loop;

                waitSent;
                tblAccess(42, false, txEntry(0, 0, 0), Entry_v, Ded_v);
                check_value(Entry_v, txEntry(1, 2, 3), ERROR, "entry of APID 42 after six packets");
                tblAccess(43, false, txEntry(0, 0, 0), Entry_v, Ded_v);
                check_value(Entry_v, txEntry(1, 0, 6), ERROR, "entry of APID 43 after six packets");

            elsif run("test_packet_service") then
                -- Space Packets of every Sequence Flags value, both types, with and without secondary header, of
                -- lengths 7 to 200 bytes are transferred intact; their APIDs keep the count 0. Octet Strings on the
                -- other ports at the same time.
                tblWrite(1001, txEntry(1, 9, 0));
                tbSetStall(1, 0.3);
                tbSetStall(ChSink_c, 0.2);

                for i in 0 to 99 loop
                    Len_v := Rand_v.rand(1, 194);
                    if i < 4 then
                        Len_v := i + 1;
                    end if;
                    sendPacket(1, tbSpacePacket(i mod 2, (i / 2) mod 2, 1000 + i mod 3, i mod 4, Rand_v.rand(0, 16383),
                                                tbPayload(Len_v, Seed_v)), 9 * (1 - minimum(1, abs (1000 + i mod 3 - 1001))));
                    Apid_v        := 10 + i mod 5;
                    sendOctet(0, Apid_v, tbPayload(Rand_v.rand(1, 100), Seed_v + 1), Cnt_v(Apid_v));
                    Cnt_v(Apid_v) := Cnt_v(Apid_v) + 1;
                    if NumTx_g > 2 then
                        Apid_v        := 300 + i mod 2;
                        sendOctet(2, Apid_v, tbPayload(Rand_v.rand(1, 100), Seed_v + 2), Cnt_v(Apid_v));
                        Cnt_v(Apid_v) := Cnt_v(Apid_v) + 1;
                    end if;
                    Seed_v := Seed_v + 3;
                end loop;

                waitSent(5 ms);
                check_value(Errors.Total, 0, ERROR, "no error event");

                for a in 1000 to 1002 loop
                    tblAccess(a, false, txEntry(0, 0, 0), Entry_v, Ded_v);
                    check_value(Entry_v(13 downto 0), "00000000000000", ERROR, "count of a Packet Service APID unchanged");
                end loop;

            elsif run("test_packet_checks") then
                -- Rejected Space Packets on the Packet Service port 1, each followed by a correct one
                MaxLength <= std_logic_vector(to_unsigned(100, LengthWidth_c));
                -- Shorter than 7 bytes
                sendRejected(1, tbSlice(tbSpacePacket(0, 0, 1000, 3, 0, tbPayload(1, 1)), 0, 5), tbTxUser(0));
                sendPacket(1, tbSpacePacket(0, 0, 1000, 3, 1, tbPayload(1, 1)));
                waitSent;
                checkErrors(ErrTxShort_c, 1, "short Space Packet rejected");
                checkLast(ErrTxShort_c, 1, 1000);
                -- Packet Version Number 1
                sendRejected(1, tbCat(tbPrimaryHeader(1, 0, 0, 1000, 3, 0, 9), tbPayload(10, 2)), tbTxUser(0));
                sendPacket(1, tbSpacePacket(0, 0, 1000, 3, 2, tbPayload(10, 2)));
                waitSent;
                checkErrors(ErrTxVersion_c, 1, "version 1 rejected");
                -- Packet Data Length one more and one less than the Packet Data Field
                sendRejected(1, tbCat(tbPrimaryHeader(0, 0, 0, 1000, 3, 0, 10), tbPayload(10, 3)), tbTxUser(0));
                sendRejected(1, tbCat(tbPrimaryHeader(0, 0, 0, 1000, 3, 0, 8), tbPayload(10, 3)), tbTxUser(0));
                sendPacket(1, tbSpacePacket(0, 0, 1000, 3, 3, tbPayload(10, 3)));
                waitSent;
                checkErrors(ErrTxLength_c, 2, "length other than PDL + 7 rejected");
                -- Idle Packet with the Secondary Header Flag set; without it the Idle Packet passes
                sendRejected(1, tbSpacePacket(0, 1, 2047, 3, 0, tbPayload(10, 4)), tbTxUser(0));
                sendPacket(1, tbSpacePacket(0, 0, 2047, 3, 0, tbPayload(10, 4)));
                waitSent;
                checkErrors(ErrTxIdle_c, 1, "Idle Packet with SHF rejected");
                checkLast(ErrTxIdle_c, 1, 2047);
                -- Longer than the maximum packet length of 100 bytes
                sendRejected(1, tbSpacePacket(0, 0, 1000, 3, 4, tbPayload(95, 5)), tbTxUser(0));
                sendPacket(1, tbSpacePacket(0, 0, 1000, 3, 5, tbPayload(94, 5)));
                waitSent;
                checkErrors(ErrTxOversize_c, 1, "Space Packet longer than the maximum rejected");
                check_value(Errors.Total, 6, ERROR, "error events");
                check_value(Sent, 5, ERROR, "packets sent");

            elsif run("test_oversize") then
                -- Maximum packet length 100: Octet Strings of up to 94 bytes; the buffer of 4096 bytes limits the
                -- Octet String at the maximum packet length of 65542
                MaxLength <= std_logic_vector(to_unsigned(100, LengthWidth_c));
                wait until rising_edge(Clk);
                sendOctet(0, 1, tbPayload(94, 1), 0);
                sendRejected(0, tbPayload(95, 2), tbTxUser(1));
                sendOctet(0, 1, tbPayload(93, 3), 1);
                waitSent;
                checkErrors(ErrTxOversize_c, 1, "Octet String longer than the maximum rejected");
                checkLast(ErrTxOversize_c, 0, 1);
                MaxLength <= std_logic_vector(to_unsigned(65542, LengthWidth_c));
                wait until rising_edge(Clk);
                sendRejected(0, tbPayload(BufferBytes_g + 1, 4), tbTxUser(1));
                sendOctet(0, 1, tbPayload(BufferBytes_g, 5), 2);
                waitSent;
                checkErrors(ErrTxOversize_c, 2, "Octet String longer than the buffer rejected");
                check_value(Sent, 3, ERROR, "packets sent");

            elsif run("test_max_length") then
                -- Octet String of 65536 bytes: Space Packet of 65542 bytes with the Packet Data Length 65535; one byte
                -- more is rejected
                sendOctet(0, 3, tbPayload(65536, 1), 0);
                waitSent(5 ms);
                sendRejected(0, tbPayload(65537, 2), tbTxUser(3));
                sendOctet(0, 3, tbPayload(17, 3), 1);
                waitSent(5 ms);
                checkErrors(ErrTxOversize_c, 1, "Octet String of 65537 bytes rejected");
                check_value(Sent, 2, ERROR, "packets sent");
                -- An SDU longer than the range of the byte count (saturates) is rejected as well
                sendRejected(0, tbPayload(140000, 5), tbTxUser(3));
                waitSent(5 ms);
                checkErrors(ErrTxOversize_c, 2, "Octet String of 140000 bytes rejected");
                check_value(Sent, 2, ERROR, "packets sent");
                if NumTx_g > 1 then
                    -- Space Packet of 65542 bytes (PDL 65535) on the Packet Service port 1
                    sendPacket(1, tbSpacePacket(1, 1, 1000, 1, 77, tbPayload(65536, 4)));
                    waitSent(5 ms);
                    check_value(Sent, 3, ERROR, "Space Packet of the maximum length sent");
                    check_value(Errors.Total, 2, ERROR, "error events");
                end if;

            elsif run("test_idle") then
                -- Idle APID: accepted without, rejected with the Secondary Header Indicator
                sendRejected(0, tbPayload(9, 1), tbTxUser(2047, 1));
                sendOctet(0, 2047, tbPayload(9, 2), 0, 0, 0);
                waitSent;
                checkErrors(ErrTxIdle_c, 1, "Idle Packet with SHI rejected");
                checkLast(ErrTxIdle_c, 0, 2047);
                check_value(Sent, 1, ERROR, "packets sent");

            elsif run("test_no_path") then
                -- APID without managed data path: rejected and skipped; the destination follows the APID
                tblWrite(300, txEntry(0, 1, 0));
                tblWrite(301, txEntry(1, 3, 0));
                tblWrite(302, txEntry(1, 15, 0));
                sendRejected(0, tbPayload(50, 1), tbTxUser(300));
                sendOctet(0, 301, tbPayload(50, 2), 0, 3);
                sendRejected(0, tbPayload(3, 3), tbTxUser(300));
                sendOctet(0, 302, tbPayload(5, 4), 0, 15);
                waitSent;
                checkErrors(ErrTxNoPath_c, 2, "APID without path rejected");
                checkLast(ErrTxNoPath_c, 0, 300);
                check_value(Sent, 2, ERROR, "packets sent");

            elsif run("test_multiplexing") then

                -- Three SDUs on every port, buffered while the table is held; fixed priority sends port 0 first, round
                -- robin alternates the ports
                for scheme in 0 to 1 loop
                    RoundRobin <= '1' when scheme = 1 else '0';
                    tbSetMatch(ChSink_c, 1, 0, 0);
                    tblAccess(5, false, txEntry(0, 0, 0), Entry_v, Ded_v, true);

                    for k in 0 to 2 loop

                        for p in 0 to NumTx_g - 1 loop
                            Apid_v := 100 * p + k;
                            if OctetString_c(p) = '1' then
                                tbPush(p, tbPayload(Bytes_c, Seed_v), tbTxUser(Apid_v));
                            else
                                tbPush(p, tbSpacePacket(0, 0, Apid_v, 3, k, tbPayload(Bytes_c, Seed_v)), tbTxUser(0));
                            end if;
                            Seed_v := Seed_v + 1;
                        end loop;

                    end loop;

                    -- Expected order
                    Seed_v := Seed_v - 3 * NumTx_g;

                    for n in 0 to 3 * NumTx_g - 1 loop
                        if scheme = 0 then
                            P_v   := n / 3;
                            Len_v := n mod 3;
                        else
                            P_v   := n mod NumTx_g;
                            Len_v := n / NumTx_g;
                        end if;
                        Apid_v := 100 * P_v + Len_v;
                        if OctetString_c(P_v) = '1' then
                            tbPush(ChSink_c, tbSpacePacket(0, 0, Apid_v, 3, Cnt_v(Apid_v), tbPayload(Bytes_c, Seed_v + Len_v * NumTx_g + P_v)),
                                   tbLinkUser(0));
                            Cnt_v(Apid_v) := Cnt_v(Apid_v) + 1;
                        else
                            tbPush(ChSink_c, tbSpacePacket(0, 0, Apid_v, 3, Len_v, tbPayload(Bytes_c, Seed_v + Len_v * NumTx_g + P_v)),
                                   tbLinkUser(0));
                        end if;
                    end loop;

                    Seed_v := Seed_v + 3 * NumTx_g;
                    wait for 100 * ClkPeriod_c;
                    tblRelease;
                    tbWaitEmpty(ChSink_c, 1 ms, "order of the packets");
                end loop;

            elsif run("test_line_rate") then
                -- 100 Octet Strings of 256 bytes back-to-back without stall cycles: at most 3 cycles per packet besides
                -- its beats
                SppTbStore_v.clearStats(ChSink_c);
                Beats_v := 0;

                for i in 0 to 99 loop
                    sendOctet(0, 5, tbPayload(256, i), i);
                    Beats_v := Beats_v + (256 + PrimaryHeaderBytes_c + Bytes_c - 1) / Bytes_c;
                end loop;

                waitSent;
                Cycles_v := (SppTbStore_v.lastTime(ChSink_c) - SppTbStore_v.firstTime(ChSink_c)) / ClkPeriod_c + 1;
                log(ID_LOG_HDR, "line rate: " & to_string(Cycles_v) & " cycles for " & to_string(Beats_v) & " beats of 100 packets");
                check_value(Cycles_v <= Beats_v + 3 * 100, ERROR, "cycles per packet beyond its beats");

            elsif run("test_ecc") then
                -- Data buffer: a single error is corrected; a double error ends the packet with an EEP
                ScrubEnable <= '0';
                inject(0, '0');
                sendOctet(0, 1, tbPayload(20, 1), 0);
                waitSent;
                check_value(EccSec(0), 1, ERROR, "single error in the data buffer");
                inject(0, '1');
                tbPush(0, tbPayload(30, 2), tbTxUser(1));
                tbPush(ChSink_c, tbSpacePacket(0, 0, 1, 3, 1, tbPayload(30, 2)), tbLinkUser(0), tbLinkUser(1));
                waitSent;
                check_value(EccDed(0), 1, ERROR, "double error in the data buffer");
                -- Descriptor: a double error discards the SDU
                inject(1, '1');
                sendRejected(0, tbPayload(30, 3), tbTxUser(1));
                sendOctet(0, 1, tbPayload(10, 4), 2);
                waitSent;
                check_value(EccDed(1), 1, ERROR, "double error in the descriptor buffer");
                checkErrors(ErrTxBuffer_c, 1, "SDU with an unreliable descriptor discarded");
                -- Table: a single error is corrected, a double error discards the SDU
                inject(2, '0');
                tblWrite(8, txEntry(1, 4, 7));
                sendOctet(0, 8, tbPayload(10, 5), 7, 4);
                waitSent;
                check_value(EccSec(2), 1, ERROR, "single error in the table");
                inject(2, '1');
                tblWrite(9, txEntry(1, 4, 7));
                sendRejected(0, tbPayload(10, 6), tbTxUser(9));
                waitSent;
                checkErrors(ErrTxBuffer_c, 2, "SDU with an unreliable table entry discarded");
                checkLast(ErrTxBuffer_c, 0, 9);
                -- The entry is repaired by a write
                tblWrite(9, txEntry(1, 4, 7));
                sendOctet(0, 9, tbPayload(10, 7), 7, 4);
                waitSent;
                check_value(Sent, 5, ERROR, "packets sent");
                -- Double error in the only word of an SDU, which is its last word
                inject(0, '1');
                tbPush(0, tbPayload(3, 8), tbTxUser(1));
                tbPush(ChSink_c, tbSpacePacket(0, 0, 1, 3, 3, tbPayload(3, 8)), tbLinkUser(0), tbLinkUser(1));
                waitSent;
                check_value(EccDed(0), 2, ERROR, "double error in the last word");
                check_value(Sent, 6, ERROR, "packets sent");

            elsif run("test_reset") then
                -- Reset while a packet is sent and further SDUs are buffered: afterwards the table is initialised again
                -- and the counts start at 0
                tbSetStall(ChSink_c, 0.9);
                tblWrite(6, txEntry(1, 0, 500));

                for i in 0 to 3 loop
                    sendOctet(0, 6, tbPayload(200, i), 500 + i);
                end loop;

                tbWaitEmpty(0, 1 ms, "SDUs buffered");
                wait for 1 us;
                wait until rising_edge(Clk);
                Rst <= '1';
                SppTbStore_v.setAbort(ChSink_c);
                SppTbStore_v.clear(ChSink_c);
                wait until rising_edge(Clk);
                Rst <= '0';
                tbSetStall(ChSink_c, 0.0);
                wait until rising_edge(Clk);
                wait until TblRsp.Busy = '0';
                wait until rising_edge(Clk);

                for i in 0 to 3 loop
                    sendOctet(0, 6, tbPayload(30, 10 + i), i);
                end loop;

                waitSent;

            elsif run("test_random") then

                -- Random SDUs on all ports with random stall cycles and lengths, switching the multiplexing scheme
                for i in 0 to 299 loop
                    if i mod 50 = 0 then
                        waitSent(5 ms);
                        RoundRobin <= '1' when (i / 50) mod 2 = 1 else '0';
                        tbSetStall(ChSink_c, Rand_v.rand(0.0, 0.5));

                        for p in 0 to NumTx_g - 1 loop
                            tbSetStall(p, Rand_v.rand(0.0, 0.5));
                        end loop;

                    end if;
                    P_v    := Rand_v.rand(0, NumTx_g - 1);
                    Apid_v := 100 * P_v + Rand_v.rand(0, 9);
                    Len_v  := Rand_v.rand(1, 400);
                    if OctetString_c(P_v) = '1' then
                        sendOctet(P_v, Apid_v, tbPayload(Len_v, Seed_v), Cnt_v(Apid_v), 0, Rand_v.rand(0, 1), Rand_v.rand(0, 1));
                        Cnt_v(Apid_v) := Cnt_v(Apid_v) + 1;
                    else
                        sendPacket(P_v, tbSpacePacket(Rand_v.rand(0, 1), Rand_v.rand(0, 1), Apid_v, Rand_v.rand(0, 3),
                                                      Rand_v.rand(0, 16383), tbPayload(Len_v, Seed_v)));
                    end if;
                    Seed_v := Seed_v + 1;
                end loop;

                waitSent(10 ms);
                check_value(Errors.Total, 0, ERROR, "no error event");
                check_value(Sent, 300, ERROR, "packets sent");
            end if;

            wait for 20 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    i_th : entity work.spp_send_th
        generic map (
            DataWidth_g     => DataWidth_g,
            NumTx_g         => NumTx_g,
            TxOctetString_g => OctetString_c,
            BufferBytes_g   => BufferBytes_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Cfg_MaxLength  => MaxLength,
            Cfg_RoundRobin => RoundRobin,
            Cfg_TableInit  => TableInit,
            Tbl_Req        => TblReq,
            Tbl_Rsp        => TblRsp,
            Errors         => Errors,
            Sent           => Sent,
            EccSec         => EccSec,
            EccDed         => EccDed,
            ErrInj_Channel => InjChannel,
            ErrInj_Double  => InjDouble,
            ErrInj_Valid   => InjValid,
            Scrub_Enable   => ScrubEnable
        );

end architecture;
