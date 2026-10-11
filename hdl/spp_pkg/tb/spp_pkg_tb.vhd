---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the common package: the Packet Primary Header functions and the constants are compared
-- with the packet model of the testbenches, and the stream models of the testbenches prove that they
-- detect wrong packets (self-test of the checker).
--
-- Documentation: hdl/spp_pkg/docs/verification_plan.md

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
entity spp_pkg_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_pkg_tb is

    constant ClkPeriod_c : time    := 10 ns;
    constant Width_c     : natural := 32;
    constant ChSrc_c     : natural := 0;
    constant ChSnk_c     : natural := 1;

    signal Clk        : std_logic := '0';
    signal Loop_Valid : std_logic;
    signal Loop_Ready : std_logic;
    signal Loop_Data  : std_logic_vector(Width_c - 1 downto 0);
    signal Loop_Keep  : std_logic_vector(Width_c / 8 - 1 downto 0);
    signal Loop_Last  : std_logic;
    signal Loop_User  : std_logic_vector(7 downto 0);

begin

    test_runner_watchdog(runner, 10 ms);

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_c / 2;

    p_main : process is
        variable Rand_v  : t_rand;
        variable Typ_v   : natural;
        variable Shf_v   : natural;
        variable Apid_v  : natural;
        variable Flags_v : natural;
        variable Count_v : natural;
        variable Pdl_v   : natural;
        variable Hdr_v   : std_logic_vector(47 downto 0);
        variable Exp_v   : TbBytes_t(0 to 5);
        variable Pkt_v   : TbBytes_t(0 to 19);

        type NatArray6_t is array (0 to 5) of natural;

        function bit01 (n : natural) return std_logic is
        begin
            if n = 1 then
                return '1';
            end if;
            return '0';
        end function;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        Rand_v.set_rand_seeds(17, 4711);

        while test_suite loop

            if run("test_primary_header") then
                -- Encoding against the model, decoding of the encoded fields, boundary and random values

                for i in 0 to 999 loop
                    if i = 0 then
                        -- All fields zero
                        (Typ_v, Shf_v, Apid_v, Flags_v, Count_v, Pdl_v) := NatArray6_t'(0, 0, 0, 0, 0, 0);
                    elsif i = 1 then
                        -- All fields at their maximum
                        (Typ_v, Shf_v, Apid_v, Flags_v, Count_v, Pdl_v) := NatArray6_t'(1, 1, 2047, 3, 16383, 65535);
                    elsif i = 2 then
                        -- Alternating bits 1010...
                        (Typ_v, Shf_v, Apid_v, Flags_v, Count_v, Pdl_v) := NatArray6_t'(1, 0, 1365, 2, 10922, 43690);
                    elsif i = 3 then
                        -- Alternating bits 0101...
                        (Typ_v, Shf_v, Apid_v, Flags_v, Count_v, Pdl_v) := NatArray6_t'(0, 1, 682, 1, 5461, 21845);
                    else
                        Typ_v   := Rand_v.rand(0, 1);
                        Shf_v   := Rand_v.rand(0, 1);
                        Apid_v  := Rand_v.rand(0, 2047);
                        Flags_v := Rand_v.rand(0, 3);
                        Count_v := Rand_v.rand(0, 16383);
                        Pdl_v   := Rand_v.rand(0, 65535);
                    end if;
                    Hdr_v := primaryHeader(bit01(Typ_v), bit01(Shf_v), std_logic_vector(to_unsigned(Apid_v, 11)),
                                           std_logic_vector(to_unsigned(Flags_v, 2)),
                                           std_logic_vector(to_unsigned(Count_v, 14)),
                                           std_logic_vector(to_unsigned(Pdl_v, 16)));
                    Exp_v := tbPrimaryHeader(0, Typ_v, Shf_v, Apid_v, Flags_v, Count_v, Pdl_v);

                    for k in 0 to 5 loop
                        check_value(Hdr_v(8 * k + 7 downto 8 * k), Exp_v(k), ERROR, "header byte " & to_string(k), msg_id => ID_NEVER);
                    end loop;

                    check_value(hdrVersion(Hdr_v), "000", ERROR, "version", msg_id => ID_NEVER);
                    check_value(hdrType(Hdr_v), bit01(Typ_v), ERROR, "type", msg_id => ID_NEVER);
                    check_value(hdrShf(Hdr_v), bit01(Shf_v), ERROR, "SHF", msg_id => ID_NEVER);
                    check_value(to_integer(unsigned(hdrApid(Hdr_v))), Apid_v, ERROR, "APID", msg_id => ID_NEVER);
                    check_value(to_integer(unsigned(hdrFlags(Hdr_v))), Flags_v, ERROR, "flags", msg_id => ID_NEVER);
                    check_value(to_integer(unsigned(hdrCount(Hdr_v))), Count_v, ERROR, "count", msg_id => ID_NEVER);
                    check_value(to_integer(unsigned(hdrPdl(Hdr_v))), Pdl_v, ERROR, "PDL", msg_id => ID_NEVER);
                end loop;

                -- Decoding of a header built by the model with a version other than 0
                Exp_v := tbPrimaryHeader(5, 0, 0, 0, 0, 0, 0);

                for k in 0 to 5 loop
                    Hdr_v(8 * k + 7 downto 8 * k) := Exp_v(k);
                end loop;

                check_value(hdrVersion(Hdr_v), "101", ERROR, "version 5");

            elsif run("test_constants") then
                check_value(MinPacketBytes_c, 7, ERROR, "minimum Space Packet length, SPP 4.1.2.2");
                check_value(MaxPacketBytes_c, 65542, ERROR, "maximum Space Packet length, SPP 4.1.2.2");
                check_value(MaxOctetStringBytes_c, 65536, ERROR, "maximum Octet String length, SPP 3.2.3.1");
                check_value(PrimaryHeaderBytes_c, 6, ERROR, "Packet Primary Header length, SPP 4.1.3.1");
                check_value(PacketVersion_c, "000", ERROR, "Packet Version Number, SPP 4.1.3.2.2");
                check_value(IdleApid_c, "11111111111", ERROR, "APID of Idle Packets, SPP 4.1.3.3.4.4");
                check_value(Unsegmented_c, "11", ERROR, "Sequence Flags of unsegmented User Data, SPP 4.1.3.4.2.2");
                check_value(SeqCountModulo_c, 16384, ERROR, "Packet Sequence Count modulo, SPP 4.1.3.4.3.4");
                check_value(CptpProtocolId_c, x"02", ERROR, "Protocol Identifier, CPTP 5.3.3b");
                check_value(CptpReserved_c, x"00", ERROR, "Reserved field, CPTP 5.3.4a");
                check_value(DefaultLogicalAddr_c, x"FE", ERROR, "default Target Logical Address, CPTP 5.3.2");
                check_value(CptpHeaderBytes_c, 4, ERROR, "CPTP header without the Target SpaceWire Address, CPTP 5.4.1.1");
                check_value(LengthMax_c >= MaxPacketBytes_c, ERROR, "length counters hold the maximum packet length");

            elsif run("test_keep") then

                for w in 1 to 16 loop

                    for n in 0 to w loop
                        check_value(bytesOfKeep(keepOfBytes(n, w)), n, ERROR, "bytes of the byte enables",
                                    msg_id => ID_NEVER);
                        check_value(keepOfBytes(n, w), std_logic_vector(to_unsigned(2 ** n - 1, w)), ERROR,
                                    "byte enables of " & to_string(n) & " bytes", msg_id => ID_NEVER);
                    end loop;

                    check_value(keepOfBytes(w + 3, w), std_logic_vector(to_unsigned(2 ** w - 1, w)), ERROR,
                                "byte enables beyond the width");
                end loop;

            elsif run("test_model_checks") then
                -- Self-test of the stream sink: correct packets pass; a wrong byte, a wrong length, a wrong TUser and
                -- an unexpected packet each raise exactly the expected alerts
                tbSetStall(ChSrc_c, 0.3);
                tbSetStall(ChSnk_c, 0.3);

                for i in 0 to 9 loop
                    tbPush(ChSrc_c, tbPayload(i + 1, i), x"A5");
                    tbPush(ChSnk_c, tbPayload(i + 1, i), x"A5");
                end loop;

                tbWaitEmpty(ChSnk_c, 1 ms);

                -- Wrong byte
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                Pkt_v     := tbPayload(20, 1);
                tbPush(ChSrc_c, Pkt_v, x"11");
                Pkt_v(19) := not Pkt_v(19);
                tbPush(ChSnk_c, Pkt_v, x"11");
                tbWaitEmpty(ChSnk_c, 1 ms);
                -- Wrong length (one byte more than expected): length check and no byte mismatch
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                tbPush(ChSrc_c, tbPayload(21, 2), x"22");
                tbPush(ChSnk_c, tbPayload(20, 2), x"22");
                tbWaitEmpty(ChSnk_c, 1 ms);
                -- Wrong TUser on every one of the three beats, then masked out
                increment_expected_alerts_and_stop_limit(ERROR, 3);
                tbPush(ChSrc_c, tbPayload(9, 3), x"33");
                tbPush(ChSnk_c, tbPayload(9, 3), x"34");
                tbWaitEmpty(ChSnk_c, 1 ms);
                tbSetUserMask(ChSnk_c, x"F0");
                tbPush(ChSrc_c, tbPayload(9, 3), x"33");
                tbPush(ChSnk_c, tbPayload(9, 3), x"34");
                tbWaitEmpty(ChSnk_c, 1 ms);
                -- Unexpected packet
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                tbPush(ChSrc_c, tbPayload(5, 4), x"44");
                tbWaitEmpty(ChSrc_c, 1 ms);
                wait for 20 * ClkPeriod_c;
                -- Missing packet: tbWaitEmpty reports it
                increment_expected_alerts_and_stop_limit(ERROR, 1);
                tbPush(ChSnk_c, tbPayload(5, 5), x"55");
                tbWaitEmpty(ChSnk_c, 2 us);
            end if;

        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    -- Source looped back to a sink
    i_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChSrc_c,
            DataWidth_g => Width_c,
            UserWidth_g => 8
        )
        port map (
            Clk       => Clk,
            Out_Valid => Loop_Valid,
            Out_Ready => Loop_Ready,
            Out_Data  => Loop_Data,
            Out_Keep  => Loop_Keep,
            Out_Last  => Loop_Last,
            Out_User  => Loop_User
        );

    i_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChSnk_c,
            DataWidth_g => Width_c,
            UserWidth_g => 8,
            Name_g      => "loop"
        )
        port map (
            Clk      => Clk,
            In_Valid => Loop_Valid,
            In_Ready => Loop_Ready,
            In_Data  => Loop_Data,
            In_Keep  => Loop_Keep,
            In_Last  => Loop_Last,
            In_User  => Loop_User
        );

end architecture;
