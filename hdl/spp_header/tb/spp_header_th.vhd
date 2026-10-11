---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the header insertion and removal: clock, both DUTs, stream sources and sinks.
-- The per-packet side information (header and header length of the insertion, removal count of the
-- removal) travels in the TUser of the sources; the removed bytes and the empty flag of the removal
-- are compared through the TUser of its sink.
--
-- Documentation: hdl/spp_header/docs/verification_plan.md

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
    use work.spp_header_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_header_th is
    generic (
        DataWidth_g : positive := 32
    );
    port (
        Clk : out   std_logic := '0';
        Rst : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_header_th is

    constant Bytes_c : positive := DataWidth_g / 8;

    -- Insertion
    signal InsIn_Valid  : std_logic;
    signal InsIn_Ready  : std_logic;
    signal InsIn_Data   : std_logic_vector(DataWidth_g - 1 downto 0);
    signal InsIn_Keep   : std_logic_vector(Bytes_c - 1 downto 0);
    signal InsIn_Last   : std_logic;
    signal InsIn_User   : std_logic_vector(InsSrcUserWidth_c - 1 downto 0);
    signal InsOut_Valid : std_logic;
    signal InsOut_Ready : std_logic;
    signal InsOut_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal InsOut_Keep  : std_logic_vector(Bytes_c - 1 downto 0);
    signal InsOut_Last  : std_logic;
    signal InsOut_User  : std_logic_vector(UserBits_c - 1 downto 0);

    -- Removal
    signal RemIn_Valid   : std_logic;
    signal RemIn_Ready   : std_logic;
    signal RemIn_Data    : std_logic_vector(DataWidth_g - 1 downto 0);
    signal RemIn_Keep    : std_logic_vector(Bytes_c - 1 downto 0);
    signal RemIn_Last    : std_logic;
    signal RemIn_User    : std_logic_vector(RemSrcUserWidth_c - 1 downto 0);
    signal RemOut_Valid  : std_logic;
    signal RemOut_Ready  : std_logic;
    signal RemOut_Data   : std_logic_vector(DataWidth_g - 1 downto 0);
    signal RemOut_Keep   : std_logic_vector(Bytes_c - 1 downto 0);
    signal RemOut_Last   : std_logic;
    signal RemOut_User   : std_logic_vector(UserBits_c - 1 downto 0);
    signal RemOut_Header : std_logic_vector(8 * MaxHdr_c - 1 downto 0);
    signal RemOut_Empty  : std_logic;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    -- The clock is driven on the port, so that testbench and DUT see the same signal (no delta cycle between them)
    Clk <= not Clk after ClkPeriod_c / 2;

    -- Insertion
    i_ins_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChInsSrc_c,
            DataWidth_g => DataWidth_g,
            UserWidth_g => InsSrcUserWidth_c
        )
        port map (
            Clk       => Clk,
            Out_Valid => InsIn_Valid,
            Out_Ready => InsIn_Ready,
            Out_Data  => InsIn_Data,
            Out_Keep  => InsIn_Keep,
            Out_Last  => InsIn_Last,
            Out_User  => InsIn_User
        );

    i_insert : entity work.spp_header_insert
        generic map (
            DataWidth_g      => DataWidth_g,
            MaxHeaderBytes_g => MaxHdr_c,
            UserWidth_g      => UserBits_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => InsIn_Valid,
            In_Ready       => InsIn_Ready,
            In_Data        => InsIn_Data,
            In_Keep        => InsIn_Keep,
            In_Last        => InsIn_Last,
            In_User        => InsIn_User(UserBits_c - 1 downto 0),
            In_Header      => InsIn_User(InsSrcUserWidth_c - 1 downto UserBits_c + HdrLenBits_c),
            In_HeaderBytes => InsIn_User(UserBits_c + HdrLenBits_c - 1 downto UserBits_c),
            Out_Valid      => InsOut_Valid,
            Out_Ready      => InsOut_Ready,
            Out_Data       => InsOut_Data,
            Out_Keep       => InsOut_Keep,
            Out_Last       => InsOut_Last,
            Out_User       => InsOut_User
        );

    i_ins_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChInsSnk_c,
            DataWidth_g => DataWidth_g,
            UserWidth_g => UserBits_c,
            Name_g      => "insert"
        )
        port map (
            Clk      => Clk,
            In_Valid => InsOut_Valid,
            In_Ready => InsOut_Ready,
            In_Data  => InsOut_Data,
            In_Keep  => InsOut_Keep,
            In_Last  => InsOut_Last,
            In_User  => InsOut_User
        );

    -- Removal
    i_rem_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChRemSrc_c,
            DataWidth_g => DataWidth_g,
            UserWidth_g => RemSrcUserWidth_c
        )
        port map (
            Clk       => Clk,
            Out_Valid => RemIn_Valid,
            Out_Ready => RemIn_Ready,
            Out_Data  => RemIn_Data,
            Out_Keep  => RemIn_Keep,
            Out_Last  => RemIn_Last,
            Out_User  => RemIn_User
        );

    i_remove : entity work.spp_header_remove
        generic map (
            DataWidth_g      => DataWidth_g,
            MaxRemoveBytes_g => MaxHdr_c,
            UserWidth_g      => UserBits_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => RemIn_Valid,
            In_Ready       => RemIn_Ready,
            In_Data        => RemIn_Data,
            In_Keep        => RemIn_Keep,
            In_Last        => RemIn_Last,
            In_User        => RemIn_User(UserBits_c - 1 downto 0),
            In_RemoveBytes => RemIn_User(UserBits_c + HdrLenBits_c - 1 downto UserBits_c),
            Out_Valid      => RemOut_Valid,
            Out_Ready      => RemOut_Ready,
            Out_Data       => RemOut_Data,
            Out_Keep       => RemOut_Keep,
            Out_Last       => RemOut_Last,
            Out_User       => RemOut_User,
            Out_Header     => RemOut_Header,
            Out_Empty      => RemOut_Empty
        );

    i_rem_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChRemSnk_c,
            DataWidth_g => DataWidth_g,
            UserWidth_g => RemSnkUserWidth_c,
            Name_g      => "remove"
        )
        port map (
            Clk      => Clk,
            In_Valid => RemOut_Valid,
            In_Ready => RemOut_Ready,
            In_Data  => RemOut_Data,
            In_Keep  => RemOut_Keep,
            In_Last  => RemOut_Last,
            In_User  => RemOut_Empty & RemOut_Header & RemOut_User
        );

end architecture;
