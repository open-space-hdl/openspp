---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Encapsulation (EN-1) of the SpaceWire CCSDS Packet Transfer Protocol: puts every Space Packet into
-- a CPTP packet with the Target SpaceWire Address, Target Logical Address and User Application value
-- of its destination, the Protocol Identifier 2 and the Reserved field 0.
--
-- Documentation: hdl/spp_encapsulation/docs/architecture.md

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
entity spp_encapsulation is
    generic (
        DataWidth_g    : positive                             := 32;
        NumDest_g      : positive range 1 to MaxDest_c        := 1;
        SpwAddrBytes_g : natural range 0 to MaxSpwAddrBytes_c := 4
    );
    port (
        -- Control
        Clk             : in    std_logic;
        Rst             : in    std_logic;
        -- Space Packets; TUser: error end of packet (bit 0, last beat), destination (4:1)
        S_Pkt_Valid     : in    std_logic;
        S_Pkt_Ready     : out   std_logic;
        S_Pkt_Data      : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Pkt_Keep      : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Pkt_Last      : in    std_logic;
        S_Pkt_User      : in    std_logic_vector(LinkUserWidth_c - 1 downto 0);
        -- CPTP packets; TUser as the input
        M_Link_Valid    : out   std_logic;
        M_Link_Ready    : in    std_logic;
        M_Link_Data     : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Link_Keep     : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Link_Last     : out   std_logic;
        M_Link_User     : out   std_logic_vector(LinkUserWidth_c - 1 downto 0);
        -- Destinations (index d in the bits of index d): Target SpaceWire Address (byte 0 first) and its length,
        -- Target Logical Address, User Application value
        Cfg_DestAddr    : in    std_logic_vector(NumDest_g * 8 * maximum(SpwAddrBytes_g, 1) - 1 downto 0);
        Cfg_DestAddrLen : in    std_logic_vector(NumDest_g * 5 - 1 downto 0);
        Cfg_DestTla     : in    std_logic_vector(NumDest_g * 8 - 1 downto 0);
        Cfg_DestUa      : in    std_logic_vector(NumDest_g * 8 - 1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_encapsulation is

    constant AddrBytes_c : positive := maximum(SpwAddrBytes_g, 1);
    constant MaxHdr_c    : positive := SpwAddrBytes_g + CptpHeaderBytes_c;

    signal Header      : std_logic_vector(8 * MaxHdr_c - 1 downto 0);
    signal HeaderBytes : std_logic_vector(log2ceil(MaxHdr_c + 1) - 1 downto 0);
    signal LinkUser    : std_logic_vector(LinkUserWidth_c - 1 downto 0);
    signal LinkLast    : std_logic;

begin

    -- Header of the destination of the packet (CPTP 5.4.1.1), sampled by the insertion with the first beat
    p_header : process (all) is
        variable Dest_v : natural range 0 to MaxDest_c - 1;
        variable Len_v  : natural range 0 to 31;
        variable Addr_v : std_logic_vector(8 * AddrBytes_c - 1 downto 0);
        variable Hdr_v  : std_logic_vector(8 * MaxHdr_c - 1 downto 0);
        variable Cptp_v : std_logic_vector(31 downto 0);
    begin
        -- A destination index beyond the destinations selects destination 0
        Dest_v := to_integer(unsigned(S_Pkt_User(LinkUserDest_t)));
        if Dest_v >= NumDest_g then
            Dest_v := 0;
        end if;
        Len_v  := 0;
        Addr_v := (others => '0');
        Cptp_v := (others => '0');

        for d in 0 to NumDest_g - 1 loop
            if d = Dest_v then
                Len_v  := to_integer(unsigned(Cfg_DestAddrLen(5 * d + 4 downto 5 * d)));
                Addr_v := Cfg_DestAddr(8 * AddrBytes_c * (d + 1) - 1 downto 8 * AddrBytes_c * d);
                -- Target Logical Address, Protocol Identifier, Reserved, User Application (CPTP 5.3.2 to 5.3.5)
                Cptp_v := Cfg_DestUa(8 * d + 7 downto 8 * d) & CptpReserved_c & CptpProtocolId_c &
                          Cfg_DestTla(8 * d + 7 downto 8 * d);
            end if;
        end loop;

        if Len_v > SpwAddrBytes_g then
            Len_v := SpwAddrBytes_g;
        end if;

        -- Target SpaceWire Address of Len_v bytes (CPTP 5.3.1), then the four CPTP bytes
        Hdr_v := (others => '0');

        for i in 0 to MaxHdr_c - 1 loop
            if i < SpwAddrBytes_g then
                if i < Len_v then
                    Hdr_v(8 * i + 7 downto 8 * i) := Addr_v(8 * i + 7 downto 8 * i);
                end if;
            end if;

            for k in 0 to CptpHeaderBytes_c - 1 loop
                if i = Len_v + k then
                    Hdr_v(8 * i + 7 downto 8 * i) := Cptp_v(8 * k + 7 downto 8 * k);
                end if;
            end loop;

        end loop;

        Header      <= Hdr_v;
        HeaderBytes <= std_logic_vector(to_unsigned(Len_v + CptpHeaderBytes_c, HeaderBytes'length));
    end process;

    i_insert : entity work.spp_header_insert
        generic map (
            DataWidth_g      => DataWidth_g,
            MaxHeaderBytes_g => MaxHdr_c,
            UserWidth_g      => LinkUserWidth_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => S_Pkt_Valid,
            In_Ready       => S_Pkt_Ready,
            In_Data        => S_Pkt_Data,
            In_Keep        => S_Pkt_Keep,
            In_Last        => S_Pkt_Last,
            In_User        => S_Pkt_User,
            In_Header      => Header,
            In_HeaderBytes => HeaderBytes,
            Out_Valid      => M_Link_Valid,
            Out_Ready      => M_Link_Ready,
            Out_Data       => M_Link_Data,
            Out_Keep       => M_Link_Keep,
            Out_Last       => LinkLast,
            Out_User       => LinkUser
        );

    -- The CPTP packet ends with an EOP, or with an EEP when the Space Packet did (CPTP 5.4.1.8); the flag is
    -- defined with the last beat
    M_Link_Last <= LinkLast;
    M_Link_User <= LinkUser(LinkUserDest_t) & (LinkUser(LinkUserEep_c) and LinkLast);

end architecture;
