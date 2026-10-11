---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the encapsulation and the decapsulation: clock, both DUTs, stream sources and
-- sinks, counters of the error events of the decapsulation.
--
-- Documentation: hdl/spp_encapsulation/docs/verification_plan.md

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

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_encapsulation_th is
    generic (
        DataWidth_g    : positive;
        NumDest_g      : positive;
        SpwAddrBytes_g : natural;
        ClkPeriod_g    : time;
        ChEncSrc_g     : natural;
        ChEncSnk_g     : natural;
        ChDecSrc_g     : natural;
        ChDecSnk_g     : natural
    );
    port (
        Clk             : out   std_logic := '0';
        Rst             : in    std_logic;
        Cfg_DestAddr    : in    std_logic_vector(NumDest_g * 8 * maximum(SpwAddrBytes_g, 1) - 1 downto 0);
        Cfg_DestAddrLen : in    std_logic_vector(NumDest_g * 5 - 1 downto 0);
        Cfg_DestTla     : in    std_logic_vector(NumDest_g * 8 - 1 downto 0);
        Cfg_DestUa      : in    std_logic_vector(NumDest_g * 8 - 1 downto 0);
        Cfg_RxStrip     : in    std_logic_vector(3 downto 0);
        Cfg_TlaCheck    : in    std_logic;
        Cfg_Tla         : in    std_logic_vector(7 downto 0);
        ErrCount        : out   integer_vector(0 to 31);
        ErrLast         : out   ErrEvent_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_encapsulation_th is

    constant Bytes_c : positive := DataWidth_g / 8;

    signal EncIn_Valid  : std_logic;
    signal EncIn_Ready  : std_logic;
    signal EncIn_Data   : std_logic_vector(DataWidth_g - 1 downto 0);
    signal EncIn_Keep   : std_logic_vector(Bytes_c - 1 downto 0);
    signal EncIn_Last   : std_logic;
    signal EncIn_User   : std_logic_vector(LinkUserWidth_c - 1 downto 0);
    signal EncOut_Valid : std_logic;
    signal EncOut_Ready : std_logic;
    signal EncOut_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal EncOut_Keep  : std_logic_vector(Bytes_c - 1 downto 0);
    signal EncOut_Last  : std_logic;
    signal EncOut_User  : std_logic_vector(LinkUserWidth_c - 1 downto 0);
    signal DecIn_Valid  : std_logic;
    signal DecIn_Ready  : std_logic;
    signal DecIn_Data   : std_logic_vector(DataWidth_g - 1 downto 0);
    signal DecIn_Keep   : std_logic_vector(Bytes_c - 1 downto 0);
    signal DecIn_Last   : std_logic;
    signal DecIn_User   : std_logic_vector(0 downto 0);
    signal DecOut_Valid : std_logic;
    signal DecOut_Ready : std_logic;
    signal DecOut_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal DecOut_Keep  : std_logic_vector(Bytes_c - 1 downto 0);
    signal DecOut_Last  : std_logic;
    signal DecOut_User  : std_logic_vector(RxPktUserWidth_c - 1 downto 0);
    signal Err          : ErrEvent_t;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    -- The clock is driven on the port, so that testbench and DUT see the same signal (no delta cycle between them)
    Clk <= not Clk after ClkPeriod_g / 2;

    -- Encapsulation
    i_enc_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChEncSrc_g,
            DataWidth_g => DataWidth_g,
            UserWidth_g => LinkUserWidth_c
        )
        port map (
            Clk       => Clk,
            Out_Valid => EncIn_Valid,
            Out_Ready => EncIn_Ready,
            Out_Data  => EncIn_Data,
            Out_Keep  => EncIn_Keep,
            Out_Last  => EncIn_Last,
            Out_User  => EncIn_User
        );

    i_enc : entity work.spp_encapsulation
        generic map (
            DataWidth_g    => DataWidth_g,
            NumDest_g      => NumDest_g,
            SpwAddrBytes_g => SpwAddrBytes_g
        )
        port map (
            Clk             => Clk,
            Rst             => Rst,
            S_Pkt_Valid     => EncIn_Valid,
            S_Pkt_Ready     => EncIn_Ready,
            S_Pkt_Data      => EncIn_Data,
            S_Pkt_Keep      => EncIn_Keep,
            S_Pkt_Last      => EncIn_Last,
            S_Pkt_User      => EncIn_User,
            M_Link_Valid    => EncOut_Valid,
            M_Link_Ready    => EncOut_Ready,
            M_Link_Data     => EncOut_Data,
            M_Link_Keep     => EncOut_Keep,
            M_Link_Last     => EncOut_Last,
            M_Link_User     => EncOut_User,
            Cfg_DestAddr    => Cfg_DestAddr,
            Cfg_DestAddrLen => Cfg_DestAddrLen,
            Cfg_DestTla     => Cfg_DestTla,
            Cfg_DestUa      => Cfg_DestUa
        );

    i_enc_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChEncSnk_g,
            DataWidth_g => DataWidth_g,
            UserWidth_g => LinkUserWidth_c,
            Name_g      => "encapsulation"
        )
        port map (
            Clk      => Clk,
            In_Valid => EncOut_Valid,
            In_Ready => EncOut_Ready,
            In_Data  => EncOut_Data,
            In_Keep  => EncOut_Keep,
            In_Last  => EncOut_Last,
            In_User  => EncOut_User
        );

    -- Decapsulation
    i_dec_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChDecSrc_g,
            DataWidth_g => DataWidth_g,
            UserWidth_g => 1
        )
        port map (
            Clk       => Clk,
            Out_Valid => DecIn_Valid,
            Out_Ready => DecIn_Ready,
            Out_Data  => DecIn_Data,
            Out_Keep  => DecIn_Keep,
            Out_Last  => DecIn_Last,
            Out_User  => DecIn_User
        );

    i_dec : entity work.spp_decapsulation
        generic map (
            DataWidth_g => DataWidth_g
        )
        port map (
            Clk          => Clk,
            Rst          => Rst,
            S_Link_Valid => DecIn_Valid,
            S_Link_Ready => DecIn_Ready,
            S_Link_Data  => DecIn_Data,
            S_Link_Keep  => DecIn_Keep,
            S_Link_Last  => DecIn_Last,
            S_Link_User  => DecIn_User,
            M_Pkt_Valid  => DecOut_Valid,
            M_Pkt_Ready  => DecOut_Ready,
            M_Pkt_Data   => DecOut_Data,
            M_Pkt_Keep   => DecOut_Keep,
            M_Pkt_Last   => DecOut_Last,
            M_Pkt_User   => DecOut_User,
            Cfg_RxStrip  => Cfg_RxStrip,
            Cfg_TlaCheck => Cfg_TlaCheck,
            Cfg_Tla      => Cfg_Tla,
            Err          => Err
        );

    i_dec_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChDecSnk_g,
            DataWidth_g => DataWidth_g,
            UserWidth_g => RxPktUserWidth_c,
            Name_g      => "decapsulation"
        )
        port map (
            Clk      => Clk,
            In_Valid => DecOut_Valid,
            In_Ready => DecOut_Ready,
            In_Data  => DecOut_Data,
            In_Keep  => DecOut_Keep,
            In_Last  => DecOut_Last,
            In_User  => DecOut_User
        );

    -- Error events
    p_count : process (Clk) is
        variable Count_v : integer_vector(0 to 31) := (others => 0);
        variable Last_v  : ErrEvent_t              := ErrEventNone_c;
    begin
        if rising_edge(Clk) then
            if Err.Valid = '1' then
                Count_v(to_integer(unsigned(Err.Code))) := Count_v(to_integer(unsigned(Err.Code))) + 1;
                Last_v                                  := Err;
            end if;
            if Rst = '1' then
                Count_v := (others => 0);
            end if;
            ErrCount <= Count_v;
            ErrLast  <= Last_v;
        end if;
    end process;

end architecture;
