---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Integration testbench of the packetizer: data units through the packetizer, a send port and a
-- receive port of the Packet Service of spp_core and the link looped back to the core; every Space
-- Packet arrives intact at the receive port.
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
entity spp_packetizer_core_tb is
    generic (
        runner_cfg  : string;
        DataWidth_g : positive := 32
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_packetizer_core_tb is

    constant ClkPeriod_c  : time     := 10 ns;
    constant Bytes_c      : positive := DataWidth_g / 8;
    constant ChunkBytes_c : positive := 64;
    constant SecHdr_c     : positive := 3;
    constant Apid_c       : natural  := 16#155#;

    constant ChSrc_c : natural := 0;   -- data units into the packetizer
    constant ChSnk_c : natural := 1;   -- Space Packets out of the receive port
    constant ChExp_c : natural := 2;   -- expected segments; TUser: Sequence Flags (1:0), count (15:2)

    signal Clk : std_logic := '0';
    signal Rst : std_logic := '1';

    signal S_Valid     : std_logic;
    signal S_Ready     : std_logic;
    signal S_Data      : std_logic_vector(DataWidth_g - 1 downto 0);
    signal S_Keep      : std_logic_vector(Bytes_c - 1 downto 0);
    signal S_Last      : std_logic;
    signal S_User      : std_logic_vector(0 downto 0);
    signal Tx_Valid    : std_logic_vector(0 downto 0);
    signal Tx_Ready    : std_logic_vector(0 downto 0);
    signal Tx_Data     : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Tx_Keep     : std_logic_vector(Bytes_c - 1 downto 0);
    signal Tx_Last     : std_logic_vector(0 downto 0);
    signal Tx_User     : std_logic_vector(TxUserWidth_c - 1 downto 0) := (others => '0');
    signal Rx_Valid    : std_logic_vector(0 downto 0);
    signal Rx_Ready    : std_logic_vector(0 downto 0);
    signal Rx_Data     : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Rx_Keep     : std_logic_vector(Bytes_c - 1 downto 0);
    signal Rx_Last     : std_logic_vector(0 downto 0);
    signal Rx_User     : std_logic_vector(RxUserWidth_c - 1 downto 0);
    signal Link_Valid  : std_logic;
    signal Link_Ready  : std_logic;
    signal Link_Data   : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Link_Keep   : std_logic_vector(Bytes_c - 1 downto 0);
    signal Link_Last   : std_logic;
    signal Link_User   : std_logic_vector(LinkUserWidth_c - 1 downto 0);
    signal Cfg_Apid    : std_logic_vector(10 downto 0)                := std_logic_vector(to_unsigned(Apid_c, 11));
    signal SecHdr_Data : std_logic_vector(8 * SecHdr_c - 1 downto 0)  := x"C0FFEE";
    signal Hdr_Sample  : std_logic;
    signal Err_Valid   : std_logic;
    signal Err_Code    : std_logic_vector(4 downto 0);
    signal ErrCount    : natural                                      := 0;

begin

    test_runner_watchdog(runner, 20 ms);

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_c / 2;

    p_main : process is
        variable Rand_v  : t_rand;
        variable Count_v : natural := 0;
        variable Len_v   : natural;
        variable Segs_v  : natural;
        variable Fl_v    : natural;
        variable U_v     : std_logic_vector(15 downto 0);
    begin
        test_runner_setup(runner, runner_cfg);
        Rand_v.set_rand_seeds(11, 13);
        -- The receive port carries APID and indicators in TUser; the packets themselves are compared
        tbSetUserMask(ChSnk_c, "0");

        while test_suite loop
            Rst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            Rst <= '0';
            wait for 20 * ClkPeriod_c;

            if run("test_core_packet_service") then
                tbSetStall(ChSrc_c, 0.3);
                tbSetStall(ChSnk_c, 0.3);

                for i in 0 to 29 loop
                    if i < 6 then
                        Len_v := (i / 2 + 1) * ChunkBytes_c + i mod 2;
                    else
                        Len_v := Rand_v.rand(1, 4 * ChunkBytes_c);
                    end if;
                    tbPush(ChSrc_c, tbPayload(Len_v, i));
                    Segs_v := (Len_v + ChunkBytes_c - 1) / ChunkBytes_c;

                    for k in 0 to Segs_v - 1 loop
                        if Segs_v = 1 then
                            Fl_v := 3;
                        elsif k = 0 then
                            Fl_v := 1;
                        elsif k = Segs_v - 1 then
                            Fl_v := 2;
                        else
                            Fl_v := 0;
                        end if;
                        U_v     := std_logic_vector(to_unsigned(Count_v, 14)) & std_logic_vector(to_unsigned(Fl_v, 2));
                        tbPush(ChExp_c, tbSlice(tbPayload(Len_v, i), k * ChunkBytes_c,
                                                minimum(Len_v, (k + 1) * ChunkBytes_c) - 1), U_v);
                        Count_v := Count_v + 1;
                    end loop;

                end loop;

                tbWaitEmpty(ChSrc_c, 10 ms, "data units in");
                tbWaitEmpty(ChExp_c, 10 ms, "segments sampled");
                tbWaitEmpty(ChSnk_c, 10 ms, "Space Packets at the receive port");
                wait for 50 * ClkPeriod_c;
                tbCheckEmpty(ChExp_c, "expected segments without packet");
                check_value(ErrCount, 0, ERROR, "error events of the core");
            end if;

            wait for 20 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    -- Expected Space Packet of the next segment at every Hdr_Sample of the packetizer
    p_expect : process is
        variable Found_v : boolean;

        procedure pushExpected is
            constant Len_c  : natural  := SppTbStore_v.headLength(ChExp_c);
            constant User_c : TbUser_t := SppTbStore_v.headUser(ChExp_c);
            variable Data_v : TbBytes_t(0 to SecHdr_c + Len_c + 1);
            variable Crc_v  : natural;
        begin

            for i in 0 to SecHdr_c - 1 loop
                Data_v(i) := SecHdr_Data(8 * i + 7 downto 8 * i);
            end loop;

            for i in 0 to Len_c - 1 loop
                Data_v(SecHdr_c + i) := SppTbStore_v.headByte(ChExp_c, i);
            end loop;

            Crc_v                        := tbCrc16(tbSlice(Data_v, SecHdr_c, SecHdr_c + Len_c - 1));
            Data_v(SecHdr_c + Len_c)     := std_logic_vector(to_unsigned(Crc_v / 256, 8));
            Data_v(SecHdr_c + Len_c + 1) := std_logic_vector(to_unsigned(Crc_v mod 256, 8));
            tbPush(ChSnk_c, tbSpacePacket(0, 1, Apid_c, to_integer(unsigned(User_c(1 downto 0))),
                                          to_integer(unsigned(User_c(15 downto 2))), Data_v));
            SppTbStore_v.pop(ChExp_c);
        end procedure;

    -- Expected packets and error events
    begin
        wait until rising_edge(Clk);
        if Rst = '0' and Hdr_Sample = '1' then
            Found_v := SppTbStore_v.count(ChExp_c) > 0;
            if not Found_v then
                alert(ERROR, "Hdr_Sample without an expected segment");
            else
                pushExpected;
            end if;
        end if;
        if Err_Valid = '1' then
            alert(ERROR, "error event of the core, code 0x" & to_hstring(Err_Code));
            ErrCount <= ErrCount + 1;
        end if;
    end process;

    i_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChSrc_c,
            DataWidth_g => DataWidth_g
        )
        port map (
            Clk       => Clk,
            Out_Valid => S_Valid,
            Out_Ready => S_Ready,
            Out_Data  => S_Data,
            Out_Keep  => S_Keep,
            Out_Last  => S_Last,
            Out_User  => S_User
        );

    i_pk : entity work.spp_packetizer
        generic map (
            DataWidth_g   => DataWidth_g,
            ChunkBytes_g  => ChunkBytes_c,
            BufferBytes_g => 2 * ChunkBytes_c,
            SecHdrBytes_g => SecHdr_c,
            Crc_g         => true
        )
        port map (
            Clk         => Clk,
            Rst         => Rst,
            S_Valid     => S_Valid,
            S_Ready     => S_Ready,
            S_Data      => S_Data,
            S_Keep      => S_Keep,
            S_Last      => S_Last,
            S_Error     => S_User(0),
            M_Valid     => Tx_Valid(0),
            M_Ready     => Tx_Ready(0),
            M_Data      => Tx_Data,
            M_Keep      => Tx_Keep,
            M_Last      => Tx_Last(0),
            Cfg_Apid    => Cfg_Apid,
            Cfg_Type    => '0',
            SecHdr_Data => SecHdr_Data,
            Hdr_Sample  => Hdr_Sample,
            Aborted     => open,
            Ecc_Sec     => open,
            Ecc_Ded     => open
        );

    -- Send port 0 and receive port 0 use the Packet Service; the link output loops back to the input
    i_core : entity work.spp_core
        generic map (
            DataWidth_g     => DataWidth_g,
            TxOctetString_g => x"FFFE",
            RxOctetString_g => x"FFFE"
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            S_Tx_Valid        => Tx_Valid,
            S_Tx_Ready        => Tx_Ready,
            S_Tx_Data         => Tx_Data,
            S_Tx_Keep         => Tx_Keep,
            S_Tx_Last         => Tx_Last,
            S_Tx_User         => Tx_User,
            M_Rx_Valid        => Rx_Valid,
            M_Rx_Ready        => Rx_Ready,
            M_Rx_Data         => Rx_Data,
            M_Rx_Keep         => Rx_Keep,
            M_Rx_Last         => Rx_Last,
            M_Rx_User         => Rx_User,
            M_Link_Valid      => Link_Valid,
            M_Link_Ready      => Link_Ready,
            M_Link_Data       => Link_Data,
            M_Link_Keep       => Link_Keep,
            M_Link_Last       => Link_Last,
            M_Link_User       => Link_User,
            S_Link_Valid      => Link_Valid,
            S_Link_Ready      => Link_Ready,
            S_Link_Data       => Link_Data,
            S_Link_Keep       => Link_Keep,
            S_Link_Last       => Link_Last,
            S_Link_User       => Link_User(0 downto 0),
            S_AxiLite_ArAddr  => (others => '0'),
            S_AxiLite_ArValid => '0',
            S_AxiLite_ArReady => open,
            S_AxiLite_AwAddr  => (others => '0'),
            S_AxiLite_AwValid => '0',
            S_AxiLite_AwReady => open,
            S_AxiLite_WData   => (others => '0'),
            S_AxiLite_WStrb   => (others => '0'),
            S_AxiLite_WValid  => '0',
            S_AxiLite_WReady  => open,
            S_AxiLite_BResp   => open,
            S_AxiLite_BValid  => open,
            S_AxiLite_BReady  => '1',
            S_AxiLite_RData   => open,
            S_AxiLite_RResp   => open,
            S_AxiLite_RValid  => open,
            S_AxiLite_RReady  => '1',
            Irq               => open,
            Err_Valid         => Err_Valid,
            Err_Code          => Err_Code,
            Err_Port          => open,
            Err_Apid          => open
        );

    i_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChSnk_c,
            DataWidth_g => DataWidth_g,
            UserWidth_g => RxUserWidth_c,
            Name_g      => "receive port"
        )
        port map (
            Clk      => Clk,
            In_Valid => Rx_Valid(0),
            In_Ready => Rx_Ready(0),
            In_Data  => Rx_Data,
            In_Keep  => Rx_Keep,
            In_Last  => Rx_Last(0),
            In_User  => Rx_User
        );

end architecture;
