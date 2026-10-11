---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the receiving end: every indication is compared byte by byte with the Octet String or
-- the Space Packet built by the packet model, with its parameters (APID, Secondary Header Indicator,
-- loss indicator, error flag, User Application value); discarded packets are checked through the
-- error events.
--
-- Documentation: hdl/spp_receive/docs/verification_plan.md

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
    use work.spp_receive_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_receive_tb is
    generic (
        runner_cfg    : string;
        DataWidth_g   : positive := 32;
        NumRx_g       : positive := 1;
        PacketPorts_g : natural  := 0;      -- bit p set: port p uses the Packet Service
        BufferBytes_g : positive := 4096
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_receive_tb is

    constant Bytes_c       : positive                                  := DataWidth_g / 8;
    constant OctetString_c : std_logic_vector(MaxPorts_c - 1 downto 0) :=
        not std_logic_vector(to_unsigned(PacketPorts_g, MaxPorts_c));

    signal Clk         : std_logic;
    signal Rst         : std_logic                                     := '1';
    signal MaxLength   : std_logic_vector(LengthWidth_c - 1 downto 0)  := std_logic_vector(to_unsigned(65542, LengthWidth_c));
    signal IdleDeliver : std_logic                                     := '0';
    signal TableInit   : std_logic_vector(RxEntryWidth_c - 1 downto 0) := rxEntry(1, 0);
    signal TblReq      : TblReq_t                                      := TblReqIdle_c;
    signal TblRsp      : TblRsp_t;
    signal Errors      : ErrLog_t;
    signal Delivered   : natural;
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
        variable Seed_v   : natural := 1;
        variable Len_v    : natural;
        variable Apid_v   : natural;
        variable P_v      : natural;
        variable Ua_v     : natural;
        variable Entry_v  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
        variable Ded_v    : std_logic;
        variable Beats_v  : natural;
        variable Cycles_v : natural;
        variable Cnt_v    : natural;
        variable Sent_v   : natural;

        -- Transaction of the register file on the receive APID table
        procedure tblAccess (
            apid         : natural;
            write        : boolean;
            data         : std_logic_vector(RxEntryWidth_c - 1 downto 0);
            variable rd  : out std_logic_vector(RxEntryWidth_c - 1 downto 0);
            variable ded : out std_logic) is
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
            if write then
                TblReq.WrEna  <= '1';
                TblReq.WrData <= data;
            else
                TblReq.Done <= '1';
            end if;
            wait until rising_edge(Clk);
            TblReq.WrEna <= '0';
            TblReq.Done  <= '0';
        end procedure;

        procedure tblWrite (
            apid  : natural;
            entry : std_logic_vector(RxEntryWidth_c - 1 downto 0)) is
            variable Rd_v  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
            variable Ded_v : std_logic;
        begin
            tblAccess(apid, true, entry, Rd_v, Ded_v);
        end procedure;

        procedure waitDone (timeout : time := 2 ms) is
        begin
            tbWaitEmpty(ChSrc_c, timeout, "received packets");

            for p in 0 to NumRx_g - 1 loop
                tbWaitEmpty(ChPort_c + p, timeout, "indications of port " & to_string(p));
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

        -- A correct Space Packet of APID apid with a Packet Data Field of len bytes, delivered to port p
        procedure good (
            p    : natural;
            apid : natural;
            len  : natural;
            seed : natural;
            ua   : natural := 0;
            loss : natural := 0;
            cnt  : natural := 0) is
            constant Pkt_c : TbBytes_t := tbSpacePacket(seed mod 2, (seed / 2) mod 2, apid, 3, cnt, tbPayload(len, seed));
        begin
            receive(Pkt_c, ua);
            expect(p, OctetString_c(p) = '1', Pkt_c, ua, loss);
        end procedure;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        Rand_v.set_rand_seeds(DataWidth_g, NumRx_g);

        while test_suite loop
            Rst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            Rst <= '0';
            wait until rising_edge(Clk);
            if TblRsp.Busy = '1' then
                wait until TblRsp.Busy = '0';
            end if;
            wait until rising_edge(Clk);

            if run("test_octet_delivery") then
                -- Octet Strings of random APIDs, both types, with and without SHF, of 1 to 300 bytes, random User
                -- Application values and stalls
                tbSetStall(ChSrc_c, 0.2);
                tbSetStall(ChPort_c, 0.2);

                for i in 0 to 199 loop
                    if i < 8 then
                        Len_v := i + 1;
                    elsif i < 12 then
                        Len_v := Bytes_c + i - 8;
                    else
                        Len_v := Rand_v.rand(1, 300);
                    end if;
                    good(0, Rand_v.rand(0, 2046), Len_v, Seed_v, Rand_v.rand(0, 255), 0, Rand_v.rand(0, 16383));
                    Seed_v := Seed_v + 1;
                end loop;

                waitDone;
                check_value(Delivered, 200, ERROR, "SDUs delivered");
                check_value(Errors.Total, 0, ERROR, "no error event");
                -- More packets than the buffer holds while the port does not accept them: the reception waits
                tbSetStall(ChSrc_c, 0.0);
                tbSetStall(ChPort_c, 1.0);

                for i in 0 to 19 loop
                    good(0, 5, 1, Seed_v);
                    Seed_v := Seed_v + 1;
                end loop;

                wait for 2 us;
                tbSetStall(ChPort_c, 0.0);
                waitDone;
                check_value(Delivered, 220, ERROR, "SDUs delivered after the stall");

            elsif run("test_packet_delivery") then
                -- Routing by APID to three ports: Octet Strings on ports 0 and 2, Space Packets intact (all Sequence
                -- Flags values) on port 1
                tblWrite(10, rxEntry(1, 0));
                tblWrite(20, rxEntry(1, 1));
                tblWrite(30, rxEntry(1, 2));
                tbSetStall(ChSrc_c, 0.2);

                for p in 0 to NumRx_g - 1 loop
                    tbSetStall(ChPort_c + p, 0.3);
                end loop;

                for i in 0 to 149 loop
                    P_v    := i mod 3;
                    Apid_v := 10 * (P_v + 1);
                    Len_v  := Rand_v.rand(1, 200);
                    if OctetString_c(P_v) = '1' then
                        good(P_v, Apid_v, Len_v, Seed_v, i mod 256);
                    else
                        receive(tbSpacePacket(i mod 2, 0, Apid_v, i mod 4, i, tbPayload(Len_v, Seed_v)), i mod 256);
                        expect(P_v, false, tbSpacePacket(i mod 2, 0, Apid_v, i mod 4, i, tbPayload(Len_v, Seed_v)), i mod 256);
                    end if;
                    Seed_v := Seed_v + 1;
                end loop;

                waitDone;
                check_value(Delivered, 150, ERROR, "SDUs delivered");
                check_value(Errors.Total, 0, ERROR, "no error event");

            elsif run("test_checks") then
                -- Discarded packets, each followed by a correct one
                MaxLength <= std_logic_vector(to_unsigned(100, LengthWidth_c));
                -- Error end of packet: a correct packet and a short one
                receive(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(20, 1)), 7, 1);
                receive(tbPayload(3, 2), 7, 1);
                good(0, 5, 20, 3, 7);
                waitDone;
                checkErrors(ErrRxEep_c, 2, "packets terminated by an EEP discarded");
                -- Shorter than 7 bytes: 1 and 6 bytes
                receive(tbPayload(1, 4));
                receive(tbSlice(tbSpacePacket(0, 0, 5, 3, 0, tbPayload(1, 5)), 0, 5));
                good(0, 5, 1, 6);
                waitDone;
                checkErrors(ErrRxShort_c, 2, "packets shorter than 7 bytes discarded");
                -- Packet Version Number 4
                receive(tbCat(tbPrimaryHeader(4, 0, 0, 5, 3, 0, 9), tbPayload(10, 7)));
                good(0, 5, 10, 8);
                waitDone;
                checkErrors(ErrRxVersion_c, 1, "version 4 discarded");
                checkLast(ErrRxVersion_c, 0, 5);
                -- Length one more and one less than PDL + 7
                receive(tbCat(tbPrimaryHeader(0, 0, 0, 6, 3, 0, 9), tbPayload(11, 9)));
                receive(tbCat(tbPrimaryHeader(0, 0, 0, 6, 3, 0, 9), tbPayload(9, 9)));
                good(0, 6, 10, 10);
                waitDone;
                checkErrors(ErrRxLength_c, 2, "length other than PDL + 7 discarded");
                checkLast(ErrRxLength_c, 0, 6);
                -- Longer than the maximum length of 100 bytes
                receive(tbSpacePacket(0, 0, 7, 3, 0, tbPayload(95, 11)));
                good(0, 7, 94, 12);
                waitDone;
                checkErrors(ErrRxOversize_c, 1, "packet longer than the maximum discarded");
                -- Idle Packets: discarded, delivered when enabled
                receive(tbSpacePacket(0, 0, 2047, 3, 0, tbPayload(10, 13)));
                good(0, 8, 10, 14);
                waitDone;
                checkErrors(ErrRxIdle_c, 1, "Idle Packet discarded");
                checkLast(ErrRxIdle_c, 0, 2047);
                IdleDeliver <= '1';
                good(0, 2047, 10, 15);
                waitDone;
                check_value(Errors.Total, 9, ERROR, "error events");
                check_value(Delivered, 7, ERROR, "SDUs delivered");

            elsif run("test_routing") then
                -- No path (disabled entry, port beyond the ports), Sequence Flags of an Octet String port
                tblWrite(40, rxEntry(0, 0));
                tblWrite(41, rxEntry(1, 5));
                tblWrite(42, rxEntry(1, 0));
                tblWrite(43, rxEntry(1, 1));
                receive(tbSpacePacket(0, 0, 40, 3, 0, tbPayload(10, 1)));
                receive(tbSpacePacket(0, 0, 41, 3, 0, tbPayload(10, 2)));
                good(0, 42, 10, 3);
                waitDone;
                checkErrors(ErrRxNoPath_c, 2, "packets without path discarded");
                checkLast(ErrRxNoPath_c, 5, 41);

                for flags in 0 to 2 loop
                    receive(tbSpacePacket(0, 0, 42, flags, 0, tbPayload(10, 4 + flags)));
                    -- The Packet Service port 1 delivers segments
                    receive(tbSpacePacket(0, 0, 43, flags, 0, tbPayload(10, 4 + flags)));
                    expect(1, false, tbSpacePacket(0, 0, 43, flags, 0, tbPayload(10, 4 + flags)));
                end loop;

                good(0, 42, 12, 9);
                waitDone;
                checkErrors(ErrRxFlags_c, 3, "segments for an Octet String port discarded");
                checkLast(ErrRxFlags_c, 0, 42);
                check_value(Delivered, 5, ERROR, "SDUs delivered");

            elsif run("test_loss") then
                -- Continuity of the Packet Sequence Count of APID 50 (check enabled) and 51 (check disabled)
                tblWrite(50, rxEntry(1, 0, 1, 0, 0));
                tblWrite(51, rxEntry(1, 0, 0, 0, 0));
                good(0, 50, 5, 1, 0, 0, 100);       -- first packet: no loss
                good(0, 50, 5, 2, 0, 0, 101);
                good(0, 50, 5, 3, 0, 1, 103);       -- 102 lost
                good(0, 50, 5, 4, 0, 0, 104);
                good(0, 50, 5, 5, 0, 1, 104);       -- repeated count
                good(0, 51, 5, 6, 0, 0, 7);
                good(0, 51, 5, 7, 0, 0, 3000);      -- no check
                waitDone;
                tblAccess(50, false, rxEntry(0, 0), Entry_v, Ded_v);
                check_value(Entry_v, rxEntry(1, 0, 1, 1, 104), ERROR, "entry of APID 50");
                tblAccess(51, false, rxEntry(0, 0), Entry_v, Ded_v);
                check_value(Entry_v, rxEntry(1, 0, 0, 0, 0), ERROR, "entry of APID 51 unchanged");
                -- Wrap of the count modulo 16384
                tblWrite(50, rxEntry(1, 0, 1, 1, 16382));
                good(0, 50, 5, 8, 0, 0, 16383);
                good(0, 50, 5, 9, 0, 0, 0);
                good(0, 50, 5, 10, 0, 1, 2);
                waitDone;
                check_value(Errors.Total, 0, ERROR, "no error event");

            elsif run("test_max_length") then
                -- A Space Packet of 65542 bytes is delivered
                good(0, 3, 65536, 1);
                waitDone(5 ms);
                check_value(Errors.Total, 0, ERROR, "no error event");
                check_value(Delivered, 1, ERROR, "SDU of 65536 bytes delivered");
                -- A packet longer than the range of the byte count is discarded with the length check: its PDL + 7
                -- (8934) equals the length modulo 2**17, so a count that wrapped instead of saturating would match it
                receive(tbCat(tbPrimaryHeader(0, 0, 0, 3, 3, 0, 8927), tbPayload(140000, 2)));
                good(0, 3, 20, 3);
                waitDone(5 ms);
                checkErrors(ErrRxLength_c, 1, "packet of 140006 bytes discarded (length)");
                check_value(Errors.Total, 1, ERROR, "one error event");
                check_value(Delivered, 2, ERROR, "SDU after the discarded packet delivered");

            elsif run("test_line_rate") then
                -- 100 back-to-back packets of 262 bytes without stall cycles: at most 3 cycles per packet beyond the
                -- beats of the reception
                SppTbStore_v.clearStats(ChPort_c);
                Beats_v := 0;

                for i in 0 to 99 loop
                    good(0, 9, 256, i);
                    Beats_v := Beats_v + (262 + Bytes_c - 1) / Bytes_c;
                end loop;

                waitDone;
                Cycles_v := (SppTbStore_v.lastTime(ChPort_c) - SppTbStore_v.firstTime(ChPort_c)) / ClkPeriod_c + 1;
                log(ID_LOG_HDR, "line rate: " & to_string(Cycles_v) & " cycles for " & to_string(Beats_v) & " received beats of 100 packets");
                check_value(Cycles_v <= Beats_v + 3 * 100, ERROR, "cycles per packet beyond its beats");

            elsif run("test_ecc") then
                ScrubEnable <= '0';
                -- Data buffer: single error corrected; double error flagged with the last beat
                inject(0, '0');
                good(0, 1, 20, 1);
                waitDone;
                check_value(EccSec(0), 1, ERROR, "single error in the data buffer");
                inject(0, '1');
                receive(tbSpacePacket(0, 0, 1, 3, 0, tbPayload(30, 2)));
                expect(0, true, tbSpacePacket(0, 0, 1, 3, 0, tbPayload(30, 2)), 0, 0, 1);
                waitDone;
                check_value(EccDed(0), 1, ERROR, "double error in the data buffer");
                -- Descriptor: double error discards the packet
                inject(1, '1');
                receive(tbSpacePacket(0, 0, 1, 3, 0, tbPayload(30, 3)));
                good(0, 1, 10, 4);
                waitDone;
                checkErrors(ErrRxBuffer_c, 1, "packet with an unreliable descriptor discarded");
                -- Table: single error corrected, double error discards the packet, a write repairs it
                inject(2, '0');
                tblWrite(8, rxEntry(1, 0));
                good(0, 8, 10, 5);
                waitDone;
                check_value(EccSec(2), 1, ERROR, "single error in the table");
                inject(2, '1');
                tblWrite(9, rxEntry(1, 0));
                receive(tbSpacePacket(0, 0, 9, 3, 0, tbPayload(10, 6)));
                waitDone;
                checkErrors(ErrRxBuffer_c, 2, "packet with an unreliable table entry discarded");
                checkLast(ErrRxBuffer_c, 0, 9);
                tblWrite(9, rxEntry(1, 0));
                good(0, 9, 10, 7);
                waitDone;
                check_value(Delivered, 5, ERROR, "SDUs delivered");
                -- Double error in the last word of a packet without an earlier one (one word at 64 bits)
                inject(0, '1');
                receive(tbSpacePacket(0, 0, 1, 3, 0, tbPayload(2, 8)));
                expect(0, true, tbSpacePacket(0, 0, 1, 3, 0, tbPayload(2, 8)), 0, 0, 1);
                waitDone;
                check_value(EccDed(0), 2, ERROR, "double error in the last word");
                check_value(Delivered, 6, ERROR, "SDUs delivered");

            elsif run("test_reset") then
                -- Reset while packets are received and delivered; afterwards normal operation
                tbSetStall(ChPort_c, 0.9);

                for i in 0 to 3 loop
                    good(0, 4, 200, i);
                end loop;

                tbWaitEmpty(ChSrc_c, 1 ms, "packets received");
                wait for 1 us;
                wait until rising_edge(Clk);
                Rst <= '1';
                SppTbStore_v.setAbort(ChPort_c);
                SppTbStore_v.clear(ChPort_c);
                wait until rising_edge(Clk);
                Rst <= '0';
                tbSetStall(ChPort_c, 0.0);
                wait until rising_edge(Clk);
                wait until TblRsp.Busy = '0';
                wait until rising_edge(Clk);

                for i in 0 to 3 loop
                    good(0, 4, 30, 10 + i);
                end loop;

                waitDone;

            elsif run("test_random") then
                -- Random packets to all ports, both services, interleaved with discarded packets, random stalls
                tblWrite(11, rxEntry(1, 0, 1));
                tblWrite(12, rxEntry(1, 1));
                tblWrite(13, rxEntry(1, 2));
                Cnt_v  := 0;
                Sent_v := 0;

                for i in 0 to 299 loop
                    if i mod 50 = 0 then
                        waitDone(5 ms);
                        tbSetStall(ChSrc_c, Rand_v.rand(0.0, 0.5));

                        for p in 0 to NumRx_g - 1 loop
                            tbSetStall(ChPort_c + p, Rand_v.rand(0.0, 0.5));
                        end loop;

                    end if;
                    P_v   := Rand_v.rand(0, NumRx_g - 1);
                    Len_v := Rand_v.rand(1, 400);
                    Ua_v  := Rand_v.rand(0, 255);

                    case Rand_v.rand(0, 9) is
                        when 0 =>
                            receive(tbSpacePacket(0, 0, 11 + P_v, 3, 0, tbPayload(Len_v, Seed_v)), Ua_v, 1);
                        when 1 =>
                            receive(tbCat(tbPrimaryHeader(0, 0, 0, 11 + P_v, 3, 0, Len_v), tbPayload(Len_v, Seed_v)), Ua_v);
                        when others =>
                            if P_v = 0 then
                                -- Continuity checked: consecutive counts
                                good(0, 11, Len_v, Seed_v, Ua_v, 0, Cnt_v);
                                Cnt_v := (Cnt_v + 1) mod 16384;
                            else
                                good(P_v, 11 + P_v, Len_v, Seed_v, Ua_v, 0, Rand_v.rand(0, 16383));
                            end if;
                            Sent_v := Sent_v + 1;
                    end case;

                    Seed_v := Seed_v + 1;
                end loop;

                waitDone(10 ms);
                check_value(Delivered, Sent_v, ERROR, "SDUs delivered");
            end if;

            wait for 20 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    i_th : entity work.spp_receive_th
        generic map (
            DataWidth_g     => DataWidth_g,
            NumRx_g         => NumRx_g,
            RxOctetString_g => OctetString_c,
            BufferBytes_g   => BufferBytes_g
        )
        port map (
            Clk             => Clk,
            Rst             => Rst,
            Cfg_MaxLength   => MaxLength,
            Cfg_IdleDeliver => IdleDeliver,
            Cfg_TableInit   => TableInit,
            Tbl_Req         => TblReq,
            Tbl_Rsp         => TblRsp,
            Errors          => Errors,
            Delivered       => Delivered,
            EccSec          => EccSec,
            EccDed          => EccDed,
            ErrInj_Channel  => InjChannel,
            ErrInj_Double   => InjDouble,
            ErrInj_Valid    => InjValid,
            Scrub_Enable    => ScrubEnable
        );

end architecture;
