---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Delivery to one user port (RE-3): the Packet Extraction Function removes the Packet Primary Header
-- for a port of the Octet String Service (OCTET_STRING.indication); a port of the Packet Service
-- receives the Space Packet intact (PACKET.indication). The output is registered.
--
-- Documentation: hdl/spp_receive/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_receive_extraction is
    generic (
        DataWidth_g   : positive := 32;
        OctetString_g : boolean  := true
    );
    port (
        -- Control
        Clk       : in    std_logic;
        Rst       : in    std_logic;
        -- Space Packets routed to this port
        In_Valid  : in    std_logic;
        In_Ready  : out   std_logic;
        In_Data   : in    std_logic_vector(DataWidth_g - 1 downto 0);
        In_Keep   : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        In_Last   : in    std_logic;
        In_User   : in    std_logic_vector(RxUserWidth_c - 1 downto 0);
        -- Indications of the user port
        M_Valid   : out   std_logic;
        M_Ready   : in    std_logic;
        M_Data    : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Keep    : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Last    : out   std_logic;
        M_User    : out   std_logic_vector(RxUserWidth_c - 1 downto 0);
        -- An SDU was delivered (last beat accepted)
        Delivered : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_receive_extraction is

    -- SPP 4.3.2.2: the Octet String is the Space Packet without its Packet Primary Header
    constant RemoveBytes_c : natural  := choose(OctetString_g, PrimaryHeaderBytes_c, 0);
    constant MaxRemove_c   : positive := choose(OctetString_g, PrimaryHeaderBytes_c, 1);
    -- A name, not an expression, as the actual of the port (docs/conventions.md)
    constant RemoveSlv_c   : std_logic_vector(log2ceil(MaxRemove_c + 1) - 1 downto 0) :=
        std_logic_vector(to_unsigned(RemoveBytes_c, log2ceil(MaxRemove_c + 1)));

    signal M_ValidInt : std_logic;
    signal M_LastInt  : std_logic;
    signal M_UserInt  : std_logic_vector(RxUserWidth_c - 1 downto 0);

begin

    i_remove : entity work.spp_header_remove
        generic map (
            DataWidth_g      => DataWidth_g,
            MaxRemoveBytes_g => MaxRemove_c,
            UserWidth_g      => RxUserWidth_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => In_Valid,
            In_Ready       => In_Ready,
            In_Data        => In_Data,
            In_Keep        => In_Keep,
            In_Last        => In_Last,
            In_User        => In_User,
            In_RemoveBytes => RemoveSlv_c,
            Out_Valid      => M_ValidInt,
            Out_Ready      => M_Ready,
            Out_Data       => M_Data,
            Out_Keep       => M_Keep,
            Out_Last       => M_LastInt,
            Out_User       => M_UserInt,
            Out_Header     => open,
            Out_Empty      => open
        );

    M_Valid <= M_ValidInt;
    -- The error flag is defined with the last beat; a beat that the realignment fills from the last input beat
    -- carries it only when it is the last beat itself
    M_User    <= M_UserInt(RxUserWidth_c - 1 downto RxUserError_c + 1) & (M_UserInt(RxUserError_c) and M_LastInt) &
                 M_UserInt(RxUserError_c - 1 downto 0);
    M_Last    <= M_LastInt;
    Delivered <= M_ValidInt and M_Ready and M_LastInt;

end architecture;
