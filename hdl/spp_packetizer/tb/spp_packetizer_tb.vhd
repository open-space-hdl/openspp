---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the packetizer: data units into the packetizer, every output packet compared byte by
-- byte with the Space Packet that the packet model builds for its segment with the header fields
-- sampled at its Hdr_Sample cycle; monitors of the events and of the timing.
--
-- Documentation: hdl/spp_packetizer/docs/verification_plan.md

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

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.spp_pkg.all;
    use work.spp_tb_pkg.all;
    use work.spp_tb_stream_pkg.all;
    use work.spp_tb_streamvar_pkg.all;
    use work.spp_tb_packet_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_packetizer_tb is
    generic (
        runner_cfg    : string;
        DataWidth_g   : positive := 32;
        ChunkBytes_g  : positive := 32;
        BufferBytes_g : positive := 64;
        MaxChunks_g   : positive := 8;
        SecHdrBytes_g : natural  := 3;
        Crc_g         : boolean  := true
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_packetizer_tb is

    constant ClkPeriod_c  : time     := 10 ns;
    constant Bytes_c      : positive := DataWidth_g / 8;
    constant ChunkBeats_c : positive := ChunkBytes_g / Bytes_c;
    constant CrcBytes_c   : natural  := 2 * boolean'pos(Crc_g);
    constant SecWidth_c   : positive := 8 * maximum(SecHdrBytes_g, 1);
    constant Shf_c        : natural  := boolean'pos(SecHdrBytes_g > 0);
    -- Output beats of the packet of a full segment, input beats of a full segment
    constant OutBeats_c   : positive := (PrimaryHeaderBytes_c + SecHdrBytes_g + ChunkBytes_g + CrcBytes_c +
                                         Bytes_c - 1) / Bytes_c;
    constant TwoChunks_c  : boolean  := BufferBytes_g >= 2 * ChunkBytes_g;

    constant ChSrc_c : natural := 0;   -- data units into the packetizer
    constant ChSnk_c : natural := 1;   -- Space Packets out of the packetizer
    constant ChExp_c : natural := 2;   -- expected segments, in the order of their packets

    -- TUser of an expected segment: Sequence Flags, count, CRC and Packet Data Length when given explicitly
    constant AuxWidth_c : natural := 50;

    function auxUser (
        flags    : natural;
        count    : natural;
        crcGiven : boolean := false;
        crc      : natural := 0;
        pdlGiven : boolean := false;
        pdl      : natural := 0) return std_logic_vector is
        variable U_v : std_logic_vector(AuxWidth_c - 1 downto 0) := (others => '0');
    begin
        U_v(1 downto 0)   := std_logic_vector(to_unsigned(flags, 2));
        U_v(15 downto 2)  := std_logic_vector(to_unsigned(count, 14));
        U_v(16)           := '1' when crcGiven else '0';
        U_v(32 downto 17) := std_logic_vector(to_unsigned(crc, 16));
        U_v(33)           := '1' when pdlGiven else '0';
        U_v(49 downto 34) := std_logic_vector(to_unsigned(pdl, 16));
        return U_v;
    end function;

    signal Clk : std_logic := '0';
    signal Rst : std_logic := '1';

    -- Input stream: stream source or bytes driven by the test
    signal Src_Valid : std_logic;
    signal Src_Ready : std_logic;
    signal Src_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Src_Keep  : std_logic_vector(Bytes_c - 1 downto 0);
    signal Src_Last  : std_logic;
    signal Src_User  : std_logic_vector(0 downto 0);
    signal Manual    : boolean                                    := false;
    signal Man_Valid : std_logic                                  := '0';
    signal Man_Data  : std_logic_vector(DataWidth_g - 1 downto 0) := (others => '0');
    signal Man_Keep  : std_logic_vector(Bytes_c - 1 downto 0)     := (others => '0');
    signal Man_Last  : std_logic                                  := '0';
    signal S_Valid   : std_logic;
    signal S_Ready   : std_logic;
    signal S_Data    : std_logic_vector(DataWidth_g - 1 downto 0);
    signal S_Keep    : std_logic_vector(Bytes_c - 1 downto 0);
    signal S_Last    : std_logic;
    signal S_Error   : std_logic;
    signal M_Valid   : std_logic;
    signal M_Ready   : std_logic;
    signal M_Data    : std_logic_vector(DataWidth_g - 1 downto 0);
    signal M_Keep    : std_logic_vector(Bytes_c - 1 downto 0);
    signal M_Last    : std_logic;

    -- Header fields: fixed values or new values in every clock cycle
    signal CfgChange   : boolean                                   := false;
    signal CfgApidFix  : natural                                   := 16#123#;
    signal CfgTypeFix  : std_logic                                 := '0';
    signal Cfg_Apid    : std_logic_vector(10 downto 0)             := (others => '0');
    signal Cfg_Type    : std_logic                                 := '0';
    signal SecHdr_Data : std_logic_vector(SecWidth_c - 1 downto 0) := (others => '0');
    signal Hdr_Sample  : std_logic;

    -- Events and error injection
    signal Aborted       : std_logic;
    signal Ecc_Sec       : std_logic_vector(1 downto 0);
    signal Ecc_Ded       : std_logic_vector(1 downto 0);
    signal ErrInj_Data   : std_logic := '0';
    signal ErrInj_Desc   : std_logic := '0';
    signal ErrInj_Double : std_logic := '0';

    -- Monitor results
    signal MonMeasure : boolean := false;
    signal MonSamples : natural := 0;
    signal MonPackets : natural := 0;
    signal MonAborted : natural := 0;
    signal MonSec0    : natural := 0;
    signal MonSec1    : natural := 0;
    signal MonDed0    : natural := 0;
    signal MonDed1    : natural := 0;
    signal MonEarly   : natural := 0;
    signal MonMaxGap  : natural := 0;
    signal MonBubbles : natural := 0;
    signal MonInStall : natural := 0;
    signal MonInPkt   : boolean := false;

begin

    test_runner_watchdog(runner, 100 ms);

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_c / 2;

    -----------------------------------------------------------------------------------------------
    -- Test sequencer
    -----------------------------------------------------------------------------------------------
    p_main : process is
        variable Rand_v  : t_rand;
        variable Seed_v  : natural := 1;
        variable Count_v : natural := 0;
        variable Len_v   : natural;
        variable Sec_v   : natural;
        variable Ded_v   : natural;
        variable N_v     : natural;
        variable Seg_v   : TbBytes_t(0 to ChunkBytes_g - 1);

        -- Data unit into the packetizer and its segments into the queue of the expected packets
        procedure sendUnit (
            data    : TbBytes_t;
            aborted : boolean := false) is
            constant N_c    : natural := data'length;
            variable Segs_v : natural;
            variable To_v   : natural;
            variable Fl_v   : natural;
            variable Err_v  : std_logic_vector(0 downto 0);
        begin
            Err_v  := "1" when aborted else "0";
            tbPush(ChSrc_c, data, "0", Err_v);
            Segs_v := (N_c + ChunkBytes_g - 1) / ChunkBytes_g;

            for k in 0 to Segs_v - 1 loop
                To_v := minimum(N_c, (k + 1) * ChunkBytes_g) - 1;
                if Segs_v = 1 then
                    Fl_v := 3;
                elsif k = 0 then
                    Fl_v := 1;
                elsif k = Segs_v - 1 then
                    Fl_v := 2;
                else
                    Fl_v := 0;
                end if;
                tbPush(ChExp_c, tbSlice(data, k * ChunkBytes_g, To_v), auxUser(Fl_v, Count_v));
                Count_v := (Count_v + 1) mod 16384;
            end loop;

        end procedure;

        procedure sendRandom (
            n      : natural;
            maxLen : positive) is
        begin

            for i in 0 to n - 1 loop
                Len_v  := Rand_v.rand(1, maxLen);
                sendUnit(tbPayload(Len_v, Seed_v));
                Seed_v := Seed_v + 1;
            end loop;

        end procedure;

        -- Data unit of a CRC test vector: with the given CRC when it fits into one segment
        procedure crcVector (
            data : TbBytes_t;
            crc  : natural) is
        begin
            if data'length <= ChunkBytes_g then
                tbPush(ChSrc_c, data);
                tbPush(ChExp_c, data, auxUser(3, Count_v, true, crc));
                Count_v := Count_v + 1;
            else
                sendUnit(data);
            end if;
        end procedure;

        procedure waitAll (timeout : time := 20 ms) is
        begin
            tbWaitEmpty(ChSrc_c, timeout, "data units in");
            tbWaitEmpty(ChExp_c, timeout, "segments sampled");
            tbWaitEmpty(ChSnk_c, timeout, "Space Packets out");
            wait for 30 * ClkPeriod_c;
            tbCheckEmpty(ChExp_c, "expected segments without packet");
        end procedure;

        procedure pulse (signal s : out std_logic) is
        begin
            wait until rising_edge(Clk);
            s <= '1';
            wait until rising_edge(Clk);
            s <= '0';
        end procedure;

        -- One beat driven by the test (test_held_segment): the first n bytes of data are valid
        procedure manBeat (
            data : TbBytes_t;
            n    : natural;
            last : std_logic) is
        begin
            Man_Keep <= keepOfBytes(n, Bytes_c);

            for i in 0 to Bytes_c - 1 loop
                if i < n then
                    Man_Data(8 * i + 7 downto 8 * i) <= data(data'low + i);
                else
                    Man_Data(8 * i + 7 downto 8 * i) <= x"5A";
                end if;
            end loop;

            Man_Last  <= last;
            Man_Valid <= '1';

            loop
                wait until rising_edge(Clk);
                exit when S_Ready = '1';
            end loop;

            Man_Valid <= '0';
        end procedure;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        Rand_v.set_rand_seeds(DataWidth_g + ChunkBytes_g, 7 + SecHdrBytes_g);

        while test_suite loop
            Rst     <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            Rst     <= '0';
            wait for 5 * ClkPeriod_c;
            Count_v := 0;

            if run("test_segmentation") then
                -- Lengths around the beat and the segment, random lengths, stalls on both sides, both
                -- Packet Types and two APIDs
                tbSetStall(ChSrc_c, 0.3);
                tbSetStall(ChSnk_c, 0.3);

                for pass in 0 to 1 loop
                    CfgApidFix <= 16#123# when pass = 0 else 16#7FE#;
                    CfgTypeFix <= '0' when pass = 0 else '1';
                    wait until rising_edge(Clk);

                    for i in 0 to 11 loop

                        case i is
                            when 0 => Len_v := 1;
                            when 1 => Len_v := Bytes_c;
                            when 2 => Len_v := Bytes_c + 1;
                            when 3 => Len_v := maximum(ChunkBytes_g - 1, 1);
                            when 4 => Len_v := ChunkBytes_g;
                            when 5 => Len_v := ChunkBytes_g + 1;
                            when 6 => Len_v := 2 * ChunkBytes_g;
                            when 7 => Len_v := 2 * ChunkBytes_g + 1;
                            when 8 => Len_v := 3 * ChunkBytes_g + Bytes_c / 2 + 1;
                            when 9 => Len_v := 3 * ChunkBytes_g - 1;
                            when 10 => Len_v := ChunkBytes_g - Bytes_c + 1;
                            when others => Len_v := 4 * ChunkBytes_g;
                        end case;

                        sendUnit(tbPayload(Len_v, Seed_v));
                        Seed_v := Seed_v + 1;
                    end loop;

                    sendRandom(20, 5 * ChunkBytes_g);
                    waitAll;
                end loop;

            elsif run("test_count_wrap") then

                -- 16390 packets: the count runs to 16383 and continues with 0 (SPP 4.1.3.4.3.4)
                for i in 0 to 16389 loop
                    sendUnit(tbPayload(1, i));
                end loop;

                waitAll(80 ms);
                check_value(MonPackets, 16390, ERROR, "packets");

            elsif run("test_aborted") then
                -- Aborted data units are sent like others; Aborted pulses once per aborted data unit
                tbSetStall(ChSrc_c, 0.2);
                tbSetStall(ChSnk_c, 0.2);
                N_v := 0;

                for i in 0 to 11 loop
                    Len_v  := (i mod 4) * ChunkBytes_g + 1 + Rand_v.rand(0, ChunkBytes_g - 1);
                    sendUnit(tbPayload(Len_v, Seed_v), i mod 2 = 1);
                    N_v    := N_v + i mod 2;
                    Seed_v := Seed_v + 1;
                end loop;

                -- S_Error on the beats before the last one is ignored
                Len_v   := 2 * ChunkBytes_g + 3;
                tbPush(ChSrc_c, tbPayload(Len_v, Seed_v), "1", "0");
                tbPush(ChExp_c, tbSlice(tbPayload(Len_v, Seed_v), 0, ChunkBytes_g - 1), auxUser(1, Count_v));
                tbPush(ChExp_c, tbSlice(tbPayload(Len_v, Seed_v), ChunkBytes_g, 2 * ChunkBytes_g - 1),
                       auxUser(0, Count_v + 1));
                tbPush(ChExp_c, tbSlice(tbPayload(Len_v, Seed_v), 2 * ChunkBytes_g, Len_v - 1),
                       auxUser(2, Count_v + 2));
                Count_v := Count_v + 3;
                waitAll;

                -- Aborted data units that end with a last beat without byte enables, one without any byte
                tbSetNullTail(ChSrc_c, true);

                for i in 0 to 3 loop
                    Len_v  := i * ChunkBytes_g;
                    sendUnit(tbPayload(Len_v, Seed_v), true);
                    N_v    := N_v + 1;
                    Seed_v := Seed_v + 1;
                end loop;

                waitAll;
                check_value(MonAborted, N_v, ERROR, "Aborted pulses");

            elsif run("test_null_last") then
                -- Last beat without byte enables after a partial beat, after a full beat, directly after a
                -- full segment and as the only beat of a data unit
                tbSetNullTail(ChSrc_c, true);
                tbSetStall(ChSrc_c, 0.3);
                tbSetStall(ChSnk_c, 0.3);

                for rep in 0 to 1 loop
                    sendUnit(tbPayload(ChunkBytes_g + 1, Seed_v));
                    sendUnit(tbPayload(minimum(2 * Bytes_c, ChunkBytes_g), Seed_v + 1));
                    sendUnit(tbPayload(ChunkBytes_g, Seed_v + 2));
                    sendUnit(tbPayload(0, Seed_v + 3));
                    sendUnit(tbPayload(2 * ChunkBytes_g, Seed_v + 4));
                    sendUnit(tbPayload(0, Seed_v + 5));
                    sendUnit(tbPayload(Bytes_c, Seed_v + 6));
                    Seed_v := Seed_v + 7;
                end loop;

                waitAll;

            elsif run("test_held_segment") then
                -- A full segment without Last waits for the next beat; a following data beat gives '01',
                -- a following last beat without byte enables gives '11'
                Manual <= true;
                wait until rising_edge(Clk);

                for variant in 0 to 1 loop
                    Len_v := ChunkBytes_g + Bytes_c;
                    if variant = 0 then
                        tbPush(ChExp_c, tbSlice(tbPayload(Len_v, Seed_v), 0, ChunkBytes_g - 1), auxUser(1, Count_v));
                        tbPush(ChExp_c, tbSlice(tbPayload(Len_v, Seed_v), ChunkBytes_g, Len_v - 1),
                               auxUser(2, Count_v + 1));
                        Count_v := Count_v + 2;
                    else
                        tbPush(ChExp_c, tbSlice(tbPayload(Len_v, Seed_v), 0, ChunkBytes_g - 1), auxUser(3, Count_v));
                        Count_v := Count_v + 1;
                    end if;

                    for b in 0 to ChunkBeats_c - 1 loop
                        manBeat(tbSlice(tbPayload(Len_v, Seed_v), b * Bytes_c, b * Bytes_c + Bytes_c - 1), Bytes_c,
                                '0');
                    end loop;

                    -- No packet while the next beat is missing
                    N_v   := MonSamples;
                    Sec_v := 0;

                    for i in 0 to 199 loop
                        wait until rising_edge(Clk);
                        if M_Valid = '1' then
                            Sec_v := Sec_v + 1;
                        end if;
                    end loop;

                    check_value(MonSamples, N_v, ERROR, "no Hdr_Sample while the segment is held");
                    check_value(Sec_v, 0, ERROR, "no output while the segment is held");

                    if variant = 0 then
                        manBeat(tbSlice(tbPayload(Len_v, Seed_v), ChunkBytes_g, Len_v - 1), Bytes_c, '1');
                    else
                        manBeat(tbPayload(1, 0), 0, '1');
                    end if;

                    Seed_v := Seed_v + 1;
                    waitAll;
                end loop;

                Manual <= false;

            elsif run("test_header_sample") then
                -- Header fields that change in every clock cycle: every packet carries the values of the
                -- edge that ends its Hdr_Sample cycle
                CfgChange <= true;
                tbSetStall(ChSrc_c, 0.3);
                tbSetStall(ChSnk_c, 0.5);
                sendRandom(40, 3 * ChunkBytes_g);
                waitAll;
                check_value(MonSamples, MonPackets, ERROR, "one Hdr_Sample per packet");

            elsif run("test_crc_vectors") then
                -- ECSS-E-ST-70-41C Table B-2: the CRC bytes are given explicitly for every block that fits
                -- into one segment; a longer block is segmented and checked with the CRC of the model
                crcVector((x"00", x"00"), 16#1D0F#);
                crcVector((x"00", x"00", x"00"), 16#CC9C#);
                crcVector((x"AB", x"CD", x"EF", x"01"), 16#04A2#);
                crcVector((x"14", x"56", x"F8", x"9A", x"00", x"01"), 16#7FD5#);
                check_value(tbCrc16((x"14", x"56", x"F8", x"9A", x"00", x"01")), 16#7FD5#, ERROR, "CRC model");
                waitAll;

            elsif run("test_ecc_single") then
                -- Single data-bit errors in the buffer and in the descriptors: corrected and reported
                ErrInj_Double <= '0';

                for i in 0 to 3 loop
                    pulse(ErrInj_Data);
                    sendUnit(tbPayload(ChunkBytes_g + i + 1, Seed_v));
                    pulse(ErrInj_Desc);
                    sendUnit(tbPayload(i + 1, Seed_v + 1));
                    Seed_v := Seed_v + 2;
                    waitAll;
                end loop;

                -- Injections during traffic, each one followed by writes before the next one
                tbSetStall(ChSrc_c, 0.3);
                tbSetStall(ChSnk_c, 0.3);
                sendRandom(30, 3 * ChunkBytes_g);

                for i in 0 to 5 loop
                    wait for (4 * ChunkBeats_c + 40) * ClkPeriod_c;
                    if i mod 2 = 0 then
                        pulse(ErrInj_Data);
                    else
                        pulse(ErrInj_Desc);
                    end if;
                end loop;

                sendRandom(10, 3 * ChunkBytes_g);
                waitAll;
                check_value(MonSec0, 7, ERROR, "corrected errors in the buffer");
                check_value(MonSec1, 7, ERROR, "corrected errors in the descriptors");
                check_value(MonDed0 + MonDed1, 0, ERROR, "detected double errors");

            elsif run("test_ecc_double") then
                -- Double data-bit error in the buffer: the first byte of the segment leaves with bits 0 and 1
                -- flipped, the CRC is that of the original segment
                ErrInj_Double <= '1';
                pulse(ErrInj_Data);
                Len_v         := ChunkBytes_g + 1;
                tbPush(ChSrc_c, tbPayload(Len_v, Seed_v));

                Seg_v    := tbSlice(tbPayload(Len_v, Seed_v), 0, ChunkBytes_g - 1);
                Seg_v(0) := Seg_v(0) xor x"03";
                tbPush(ChExp_c, Seg_v, auxUser(1, 0, true, tbCrc16(tbSlice(tbPayload(Len_v, Seed_v), 0,
                                                                            ChunkBytes_g - 1))));

                tbPush(ChExp_c, tbSlice(tbPayload(Len_v, Seed_v), ChunkBytes_g, Len_v - 1), auxUser(2, 1));
                Count_v := 2;
                Seed_v  := Seed_v + 1;
                waitAll;
                check_value(MonDed0, 1, ERROR, "double error in the buffer");

                -- Double data-bit error in a descriptor: bits 0 and 1 of the length flipped; the packet
                -- leaves with that length, the beats of its segment and the CRC of the original segment
                pulse(ErrInj_Desc);
                Len_v   := to_integer(to_unsigned(ChunkBytes_g - 1, 16) xor to_unsigned(3, 16));  -- length - 1
                N_v     := (ChunkBeats_c - 1) * Bytes_c + Len_v mod Bytes_c + 1;
                tbPush(ChSrc_c, tbPayload(ChunkBytes_g, Seed_v));
                tbPush(ChExp_c, tbSlice(tbPayload(ChunkBytes_g, Seed_v), 0, N_v - 1),
                       auxUser(3, 2, true, tbCrc16(tbPayload(ChunkBytes_g, Seed_v)), true,
                               SecHdrBytes_g + Len_v + CrcBytes_c));
                Count_v := 3;
                Seed_v  := Seed_v + 1;
                waitAll;
                check_value(MonDed1, 1, ERROR, "double error in a descriptor");

                -- The packets after both errors are correct
                ErrInj_Double <= '0';
                sendRandom(10, 3 * ChunkBytes_g);
                waitAll;
                check_value(MonSec0 + MonSec1, 0, ERROR, "corrected errors");

            elsif run("test_reset") then
                -- Reset with segments in the buffer, a held beat and a packet half output
                tbSetStall(ChSnk_c, 0.5);
                sendUnit(tbPayload(6 * ChunkBytes_g + 3, Seed_v));
                Seed_v := Seed_v + 1;

                loop
                    wait until rising_edge(Clk);
                    exit when MonPackets >= 1 and M_Valid = '1' and M_Ready = '1' and M_Last = '0';
                end loop;

                tbSetStall(ChSnk_c, 1.0);
                wait until rising_edge(Clk);
                wait until rising_edge(Clk);
                Rst <= '1';
                -- The queues are cleared at the first edge with the reset, when the monitor no longer samples
                wait until rising_edge(Clk);
                SppTbStore_v.setAbort(ChSrc_c);
                SppTbStore_v.setAbort(ChSnk_c);
                SppTbStore_v.clear(ChSnk_c);
                SppTbStore_v.clear(ChExp_c);
                wait until rising_edge(Clk);
                wait until rising_edge(Clk);
                Rst <= '0';
                SppTbStore_v.clearAbort(ChSrc_c);
                tbSetStall(ChSnk_c, 0.3);
                wait for 50 * ClkPeriod_c;
                tbCheckEmpty(ChSnk_c, "no stale packet after the reset");

                -- The count starts at 0 again
                Count_v := 0;
                sendRandom(10, 3 * ChunkBytes_g);
                waitAll;

            elsif run("test_throughput") then
                -- Back-to-back full segments without stalls
                MonMeasure <= true;

                for i in 0 to 19 loop
                    sendUnit(tbPayload(3 * ChunkBytes_g, Seed_v));
                    Seed_v := Seed_v + 1;
                end loop;

                waitAll;
                MonMeasure <= false;
                log(ID_LOG_HDR, "throughput: largest gap between packets " & to_string(MonMaxGap) & " cycles, " &
                    to_string(MonBubbles) & " cycles without data inside packets, " & to_string(MonInStall) &
                    " stall cycles at the input for 60 segments (" & to_string(OutBeats_c) & " output beats, " &
                    to_string(ChunkBeats_c) & " input beats per segment)");
                check_value(MonBubbles, 0, ERROR, "one beat per cycle inside a packet");
                if TwoChunks_c then
                    check_value(MonMaxGap <= 3, ERROR, "at most 3 cycles between packets");
                    check_value(MonInStall <= 60 * (OutBeats_c - ChunkBeats_c + 3), ERROR,
                                "input stalls per segment at most the extra output beats plus 3");
                end if;
            end if;

            check_value(MonEarly, 0, ERROR, "Hdr_Sample at least two cycles before the first beat");
            wait for 20 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Header fields
    -----------------------------------------------------------------------------------------------
    p_cfg : process is
        variable N_v : natural := 0;
    begin
        wait until rising_edge(Clk);
        if CfgChange then
            N_v      := N_v + 1;
            Cfg_Apid <= std_logic_vector(to_unsigned((N_v * 37) mod 2047, 11));
            Cfg_Type <= '1' when N_v mod 3 = 0 else '0';

            for i in 0 to SecWidth_c / 8 - 1 loop
                SecHdr_Data(8 * i + 7 downto 8 * i) <= std_logic_vector(to_unsigned((N_v + 31 * i) mod 256, 8));
            end loop;

        else
            Cfg_Apid <= std_logic_vector(to_unsigned(CfgApidFix, 11));
            Cfg_Type <= CfgTypeFix;

            for i in 0 to SecWidth_c / 8 - 1 loop
                SecHdr_Data(8 * i + 7 downto 8 * i) <= std_logic_vector(to_unsigned((16#A0# + i) mod 256, 8));
            end loop;

        end if;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Monitor: expected packets at Hdr_Sample, events, timing
    -----------------------------------------------------------------------------------------------
    p_mon : process is
        type NatArray_t is array (0 to 1023) of natural;

        variable Cycle_v    : natural := 0;
        variable Smp_v      : NatArray_t;
        variable SmpWr_v    : natural := 0;
        variable SmpRd_v    : natural := 0;
        variable InPkt_v    : boolean := false;
        variable LastEnd_v  : natural := 0;
        variable HaveLast_v : boolean := false;
        variable Measure_v  : boolean := false;
        variable Samples_v  : natural := 0;
        variable Packets_v  : natural := 0;
        variable Aborted_v  : natural := 0;
        variable Sec0_v     : natural := 0;
        variable Sec1_v     : natural := 0;
        variable Ded0_v     : natural := 0;
        variable Ded1_v     : natural := 0;
        variable Early_v    : natural := 0;
        variable MaxGap_v   : natural := 0;
        variable Bubbles_v  : natural := 0;
        variable InStall_v  : natural := 0;

        -- The packet of the next expected segment with the header fields sampled at this edge
        procedure pushExpected is
            constant Len_c  : natural  := SppTbStore_v.headLength(ChExp_c);
            constant User_c : TbUser_t := SppTbStore_v.headUser(ChExp_c);
            variable Data_v : TbBytes_t(0 to SecHdrBytes_g + Len_c + CrcBytes_c - 1);
            variable Crc_v  : natural;
            variable Type_v : natural;
            variable Apid_v : natural;
            variable Fl_v   : natural;
            variable Cnt_v  : natural;
        begin

            for i in 0 to SecHdrBytes_g - 1 loop
                Data_v(i) := SecHdr_Data(8 * i + 7 downto 8 * i);
            end loop;

            for i in 0 to Len_c - 1 loop
                Data_v(SecHdrBytes_g + i) := SppTbStore_v.headByte(ChExp_c, i);
            end loop;

            if Crc_g then
                if User_c(16) = '1' then
                    Crc_v := to_integer(unsigned(User_c(32 downto 17)));
                else
                    Crc_v := tbCrc16(tbSlice(Data_v, SecHdrBytes_g, SecHdrBytes_g + Len_c - 1));
                end if;
                Data_v(SecHdrBytes_g + Len_c)     := std_logic_vector(to_unsigned(Crc_v / 256, 8));
                Data_v(SecHdrBytes_g + Len_c + 1) := std_logic_vector(to_unsigned(Crc_v mod 256, 8));
            end if;
            Type_v := 1 when Cfg_Type = '1' else 0;
            Apid_v := to_integer(unsigned(Cfg_Apid));
            Fl_v   := to_integer(unsigned(User_c(1 downto 0)));
            Cnt_v  := to_integer(unsigned(User_c(15 downto 2)));
            if User_c(33) = '1' then
                tbPush(ChSnk_c, tbCat(tbPrimaryHeader(0, Type_v, Shf_c, Apid_v, Fl_v, Cnt_v,
                                                      to_integer(unsigned(User_c(49 downto 34)))), Data_v));
            else
                tbPush(ChSnk_c, tbSpacePacket(Type_v, Shf_c, Apid_v, Fl_v, Cnt_v, Data_v));
            end if;
            SppTbStore_v.pop(ChExp_c);
        end procedure;

    -- Monitor
    begin
        wait until rising_edge(Clk);
        Cycle_v := Cycle_v + 1;

        if MonMeasure and not Measure_v then
            MaxGap_v   := 0;
            Bubbles_v  := 0;
            InStall_v  := 0;
            HaveLast_v := false;
        end if;
        Measure_v := MonMeasure;

        if Rst = '1' then
            SmpWr_v    := 0;
            SmpRd_v    := 0;
            InPkt_v    := false;
            HaveLast_v := false;
        else
            if Hdr_Sample = '1' then
                Samples_v := Samples_v + 1;
                if SppTbStore_v.count(ChExp_c) = 0 then
                    alert(ERROR, "Hdr_Sample without an expected segment");
                else
                    pushExpected;
                end if;
                Smp_v(SmpWr_v mod 1024) := Cycle_v;
                SmpWr_v                 := SmpWr_v + 1;
            end if;

            if M_Valid = '1' and M_Ready = '1' then
                if not InPkt_v then
                    -- First beat of a packet: at least two cycles after its Hdr_Sample (PT-HD-04)
                    if SmpRd_v < SmpWr_v then
                        if Cycle_v - Smp_v(SmpRd_v mod 1024) < 2 then
                            Early_v := Early_v + 1;
                        end if;
                        SmpRd_v := SmpRd_v + 1;
                    else
                        alert(ERROR, "packet without Hdr_Sample");
                    end if;
                    if Measure_v and HaveLast_v then
                        MaxGap_v := maximum(MaxGap_v, Cycle_v - LastEnd_v - 1);
                    end if;
                    InPkt_v := true;
                end if;
                if M_Last = '1' then
                    InPkt_v    := false;
                    LastEnd_v  := Cycle_v;
                    HaveLast_v := true;
                    Packets_v  := Packets_v + 1;
                end if;
            elsif InPkt_v and M_Valid = '0' and Measure_v then
                Bubbles_v := Bubbles_v + 1;
            end if;

            if S_Valid = '1' and S_Ready = '0' and Measure_v then
                InStall_v := InStall_v + 1;
            end if;

            if Aborted = '1' then
                Aborted_v := Aborted_v + 1;
            end if;
            if Ecc_Sec(0) = '1' then
                Sec0_v := Sec0_v + 1;
            end if;
            if Ecc_Sec(1) = '1' then
                Sec1_v := Sec1_v + 1;
            end if;
            if Ecc_Ded(0) = '1' then
                Ded0_v := Ded0_v + 1;
            end if;
            if Ecc_Ded(1) = '1' then
                Ded1_v := Ded1_v + 1;
            end if;
        end if;

        MonSamples <= Samples_v;
        MonPackets <= Packets_v;
        MonAborted <= Aborted_v;
        MonSec0    <= Sec0_v;
        MonSec1    <= Sec1_v;
        MonDed0    <= Ded0_v;
        MonDed1    <= Ded1_v;
        MonEarly   <= Early_v;
        MonMaxGap  <= MaxGap_v;
        MonBubbles <= Bubbles_v;
        MonInStall <= InStall_v;
        MonInPkt   <= InPkt_v;
    end process;

    -----------------------------------------------------------------------------------------------
    -- Stream models and DUT
    -----------------------------------------------------------------------------------------------
    i_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChSrc_c,
            DataWidth_g => DataWidth_g
        )
        port map (
            Clk       => Clk,
            Out_Valid => Src_Valid,
            Out_Ready => Src_Ready,
            Out_Data  => Src_Data,
            Out_Keep  => Src_Keep,
            Out_Last  => Src_Last,
            Out_User  => Src_User
        );

    S_Valid   <= Man_Valid when Manual else Src_Valid;
    S_Data    <= Man_Data when Manual else Src_Data;
    S_Keep    <= Man_Keep when Manual else Src_Keep;
    S_Last    <= Man_Last when Manual else Src_Last;
    S_Error   <= '0' when Manual else Src_User(0);
    Src_Ready <= '0' when Manual else S_Ready;

    i_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChSnk_c,
            DataWidth_g => DataWidth_g,
            Name_g      => "packets"
        )
        port map (
            Clk      => Clk,
            In_Valid => M_Valid,
            In_Ready => M_Ready,
            In_Data  => M_Data,
            In_Keep  => M_Keep,
            In_Last  => M_Last
        );

    i_dut : entity work.spp_packetizer
        generic map (
            DataWidth_g   => DataWidth_g,
            ChunkBytes_g  => ChunkBytes_g,
            BufferBytes_g => BufferBytes_g,
            MaxChunks_g   => MaxChunks_g,
            SecHdrBytes_g => SecHdrBytes_g,
            Crc_g         => Crc_g
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            S_Valid       => S_Valid,
            S_Ready       => S_Ready,
            S_Data        => S_Data,
            S_Keep        => S_Keep,
            S_Last        => S_Last,
            S_Error       => S_Error,
            M_Valid       => M_Valid,
            M_Ready       => M_Ready,
            M_Data        => M_Data,
            M_Keep        => M_Keep,
            M_Last        => M_Last,
            Cfg_Apid      => Cfg_Apid,
            Cfg_Type      => Cfg_Type,
            SecHdr_Data   => SecHdr_Data,
            Hdr_Sample    => Hdr_Sample,
            Aborted       => Aborted,
            Ecc_Sec       => Ecc_Sec,
            Ecc_Ded       => Ecc_Ded,
            ErrInj_Data   => ErrInj_Data,
            ErrInj_Desc   => ErrInj_Desc,
            ErrInj_Double => ErrInj_Double
        );

end architecture;
