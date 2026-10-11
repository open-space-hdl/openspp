---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the N-Char adapter: link packets to N-Char packets (data characters and the end of
-- packet marker) and back, compared byte by byte with the packets of the testbench.
--
-- Documentation: hdl/spp_nchar/docs/verification_plan.md

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
entity spp_nchar_tb is
    generic (
        runner_cfg  : string;
        DataWidth_g : positive := 32
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_nchar_tb is

    constant ClkPeriod_c : time     := 10 ns;
    constant Bytes_c     : positive := DataWidth_g / 8;
    constant ChTxSrc_c   : natural  := 0;   -- link packets into the adapter
    constant ChTxSnk_c   : natural  := 1;   -- N-Char packets out of the adapter
    constant ChRxSrc_c   : natural  := 2;   -- N-Char packets into the adapter
    constant ChRxSnk_c   : natural  := 3;   -- link packets out of the adapter

    signal Clk : std_logic := '0';
    signal Rst : std_logic := '1';

    signal LinkIn_Valid  : std_logic;
    signal LinkIn_Ready  : std_logic;
    signal LinkIn_Data   : std_logic_vector(DataWidth_g - 1 downto 0);
    signal LinkIn_Keep   : std_logic_vector(Bytes_c - 1 downto 0);
    signal LinkIn_Last   : std_logic;
    signal LinkIn_User   : std_logic_vector(LinkUserWidth_c - 1 downto 0);
    signal NcOut_Valid   : std_logic;
    signal NcOut_Ready   : std_logic;
    signal NcOut_Data    : std_logic_vector(7 downto 0);
    signal NcOut_Last    : std_logic;
    signal NcIn_Valid    : std_logic;
    signal NcIn_Ready    : std_logic;
    signal NcIn_Data     : std_logic_vector(7 downto 0);
    signal NcIn_Last     : std_logic;
    signal NcIn_Keep     : std_logic_vector(0 downto 0);
    signal NcIn_User     : std_logic_vector(0 downto 0);
    signal LinkOut_Valid : std_logic;
    signal LinkOut_Ready : std_logic;
    signal LinkOut_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal LinkOut_Keep  : std_logic_vector(Bytes_c - 1 downto 0);
    signal LinkOut_Last  : std_logic;
    signal LinkOut_User  : std_logic_vector(0 downto 0);

begin

    test_runner_watchdog(runner, 20 ms);

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_c / 2;

    p_main : process is
        variable Rand_v : t_rand;
        variable Seed_v : natural := 1;
        variable Len_v  : natural;
        variable Eep_v  : natural;

        -- Packet of len bytes through the transmit direction: the N-Char packet is the bytes and the marker
        procedure transmit (
            len  : natural;
            eep  : natural;
            seed : natural) is
            constant Data_c : TbBytes_t := tbPayload(len, seed);
            variable M_v    : TbBytes_t(0 to 0);
        begin
            M_v(0) := std_logic_vector(to_unsigned(eep, 8));
            tbPush(ChTxSrc_c, Data_c, tbLinkUser(0, seed mod 16), tbLinkUser(eep, seed mod 16));
            tbPush(ChTxSnk_c, tbCat(Data_c, M_v), "0");
        end procedure;

        -- N-Char packet of len data characters through the receive direction; a packet without data is discarded
        procedure receive (
            len  : natural;
            eep  : natural;
            seed : natural) is
            constant Data_c : TbBytes_t := tbPayload(len, seed);
            variable M_v    : TbBytes_t(0 to 0);
        begin
            M_v(0) := std_logic_vector(to_unsigned(eep, 8));
            tbPush(ChRxSrc_c, tbCat(Data_c, M_v), "0");
            if len > 0 then
                tbPush(ChRxSnk_c, Data_c, "0", std_logic_vector(to_unsigned(eep, 1)));
            end if;
        end procedure;

        procedure waitAll (timeout : time := 5 ms) is
        begin
            tbWaitEmpty(ChTxSrc_c, timeout, "link packets in");
            tbWaitEmpty(ChTxSnk_c, timeout, "N-Char packets out");
            tbWaitEmpty(ChRxSrc_c, timeout, "N-Char packets in");
            tbWaitEmpty(ChRxSnk_c, timeout, "link packets out");
            wait for 20 * ClkPeriod_c;
        end procedure;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        Rand_v.set_rand_seeds(DataWidth_g, 3);
        -- The N-Char sink ignores TUser
        tbSetUserMask(ChTxSnk_c, "0");

        while test_suite loop
            Rst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            Rst <= '0';
            wait for 5 * ClkPeriod_c;

            if run("test_transmit") then
                -- Packets of 1 byte to three beats and longer, EOP and EEP, stalls on both sides
                tbSetStall(ChTxSrc_c, 0.3);
                tbSetStall(ChTxSnk_c, 0.3);

                for i in 0 to 99 loop
                    Len_v := i + 1;
                    if i >= 3 * Bytes_c then
                        Len_v := Rand_v.rand(1, 200);
                    end if;
                    transmit(Len_v, i mod 3 / 2, Seed_v);
                    Seed_v := Seed_v + 1;
                end loop;

                waitAll;

            elsif run("test_receive") then
                -- Data characters with EOP and EEP, and markers without data characters (discarded)
                tbSetStall(ChRxSrc_c, 0.3);
                tbSetStall(ChRxSnk_c, 0.3);

                for i in 0 to 99 loop
                    Len_v := i;
                    if i >= 3 * Bytes_c then
                        Len_v := Rand_v.rand(0, 200);
                    end if;
                    receive(Len_v, i mod 3 / 2, Seed_v);
                    Seed_v := Seed_v + 1;
                end loop;

                waitAll;

            elsif run("test_back_to_back") then

                -- Both directions at full rate: one character per clock cycle on the N-Char side
                for i in 0 to 49 loop
                    Eep_v  := i mod 5 / 4;
                    transmit(Rand_v.rand(1, 64), Eep_v, Seed_v);
                    receive(Rand_v.rand(1, 64), Eep_v, Seed_v + 1);
                    Seed_v := Seed_v + 2;
                end loop;

                SppTbStore_v.clearStats(ChTxSnk_c);
                waitAll;

            elsif run("test_reset") then
                -- Reset with packets in both directions not accepted by the sinks; afterwards normal operation
                tbSetStall(ChTxSnk_c, 1.0);
                tbSetStall(ChRxSnk_c, 1.0);
                transmit(5 * Bytes_c + 3, 0, 1);
                receive(5 * Bytes_c + 3, 0, 2);
                wait for 1 us;
                wait until rising_edge(Clk);
                Rst <= '1';
                SppTbStore_v.setAbort(ChTxSrc_c);
                SppTbStore_v.setAbort(ChRxSrc_c);
                SppTbStore_v.clear(ChTxSnk_c);
                SppTbStore_v.clear(ChRxSnk_c);
                wait until rising_edge(Clk);
                Rst <= '0';
                tbSetStall(ChTxSnk_c, 0.0);
                tbSetStall(ChRxSnk_c, 0.0);
                wait for 5 * ClkPeriod_c;

                for i in 0 to 9 loop
                    transmit(10 + i, i mod 2, 10 + i);
                    receive(10 + i, i mod 2, 30 + i);
                end loop;

                waitAll;
            end if;

            wait for 20 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    i_link_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChTxSrc_c,
            DataWidth_g => DataWidth_g,
            UserWidth_g => LinkUserWidth_c
        )
        port map (
            Clk       => Clk,
            Out_Valid => LinkIn_Valid,
            Out_Ready => LinkIn_Ready,
            Out_Data  => LinkIn_Data,
            Out_Keep  => LinkIn_Keep,
            Out_Last  => LinkIn_Last,
            Out_User  => LinkIn_User
        );

    i_nchar_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChTxSnk_c,
            DataWidth_g => 8,
            UserWidth_g => 1,
            Name_g      => "N-Char out"
        )
        port map (
            Clk      => Clk,
            In_Valid => NcOut_Valid,
            In_Ready => NcOut_Ready,
            In_Data  => NcOut_Data,
            In_Keep  => "1",
            In_Last  => NcOut_Last,
            In_User  => "0"
        );

    i_nchar_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChRxSrc_c,
            DataWidth_g => 8,
            UserWidth_g => 1
        )
        port map (
            Clk       => Clk,
            Out_Valid => NcIn_Valid,
            Out_Ready => NcIn_Ready,
            Out_Data  => NcIn_Data,
            Out_Keep  => NcIn_Keep,
            Out_Last  => NcIn_Last,
            Out_User  => NcIn_User
        );

    i_link_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChRxSnk_c,
            DataWidth_g => DataWidth_g,
            UserWidth_g => 1,
            Name_g      => "link out"
        )
        port map (
            Clk      => Clk,
            In_Valid => LinkOut_Valid,
            In_Ready => LinkOut_Ready,
            In_Data  => LinkOut_Data,
            In_Keep  => LinkOut_Keep,
            In_Last  => LinkOut_Last,
            In_User  => LinkOut_User
        );

    i_dut : entity work.spp_nchar
        generic map (
            DataWidth_g => DataWidth_g
        )
        port map (
            Clk           => Clk,
            Rst           => Rst,
            S_Link_Valid  => LinkIn_Valid,
            S_Link_Ready  => LinkIn_Ready,
            S_Link_Data   => LinkIn_Data,
            S_Link_Keep   => LinkIn_Keep,
            S_Link_Last   => LinkIn_Last,
            S_Link_User   => LinkIn_User,
            M_NChar_Valid => NcOut_Valid,
            M_NChar_Ready => NcOut_Ready,
            M_NChar_Data  => NcOut_Data,
            M_NChar_Last  => NcOut_Last,
            S_NChar_Valid => NcIn_Valid,
            S_NChar_Ready => NcIn_Ready,
            S_NChar_Data  => NcIn_Data,
            S_NChar_Last  => NcIn_Last,
            M_Link_Valid  => LinkOut_Valid,
            M_Link_Ready  => LinkOut_Ready,
            M_Link_Data   => LinkOut_Data,
            M_Link_Keep   => LinkOut_Keep,
            M_Link_Last   => LinkOut_Last,
            M_Link_User   => LinkOut_User
        );

end architecture;
