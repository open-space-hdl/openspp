---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Receiving end of the Space Packet Protocol (RE-1 to RE-3, TB-2): reception with the checks of the
-- Space Packets, the demultiplexer by APID with the continuity of the counts, the delivery to the
-- user ports and the receive APID table.
--
-- Documentation: hdl/spp_receive/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_receive is
    generic (
        DataWidth_g     : positive range 8 to 128                   := 32;
        NumRx_g         : positive range 1 to MaxPorts_c            := 1;
        RxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0) := (others => '1');
        BufferBytes_g   : positive                                  := 4096;
        MaxPackets_g    : positive                                  := 8;
        ClkFreqHz_g     : real                                      := 100.0e6
    );
    port (
        -- Control
        Clk             : in    std_logic;
        Rst             : in    std_logic;
        -- Received Space Packets; TUser: error end of packet (bit 0, last beat), User Application value (8:1)
        S_Pkt_Valid     : in    std_logic;
        S_Pkt_Ready     : out   std_logic;
        S_Pkt_Data      : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Pkt_Keep      : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Pkt_Last      : in    std_logic;
        S_Pkt_User      : in    std_logic_vector(RxPktUserWidth_c - 1 downto 0);
        -- Indications of the user ports (PACKET.indication, OCTET_STRING.indication)
        M_Rx_Valid      : out   std_logic_vector(NumRx_g - 1 downto 0);
        M_Rx_Ready      : in    std_logic_vector(NumRx_g - 1 downto 0);
        M_Rx_Data       : out   std_logic_vector(NumRx_g * DataWidth_g - 1 downto 0);
        M_Rx_Keep       : out   std_logic_vector(NumRx_g * DataWidth_g / 8 - 1 downto 0);
        M_Rx_Last       : out   std_logic_vector(NumRx_g - 1 downto 0);
        M_Rx_User       : out   std_logic_vector(NumRx_g * RxUserWidth_c - 1 downto 0);
        -- Managed parameters
        Cfg_MaxLength   : in    std_logic_vector(LengthWidth_c - 1 downto 0);
        Cfg_IdleDeliver : in    std_logic;
        Cfg_TableInit   : in    std_logic_vector(RxEntryWidth_c - 1 downto 0);
        -- Receive APID table, access of the register file
        Tbl_Valid       : in    std_logic                                     := '0';
        Tbl_Ready       : out   std_logic;
        Tbl_Apid        : in    std_logic_vector(10 downto 0)                 := (others => '0');
        Tbl_RdValid     : out   std_logic;
        Tbl_RdData      : out   std_logic_vector(RxEntryWidth_c - 1 downto 0);
        Tbl_RdDed       : out   std_logic;
        Tbl_WrEna       : in    std_logic                                     := '0';
        Tbl_WrData      : in    std_logic_vector(RxEntryWidth_c - 1 downto 0) := (others => '0');
        Tbl_Release     : in    std_logic                                     := '0';
        Tbl_Busy        : out   std_logic;
        -- Events: discarded packets (index 0: reception, 1: demultiplexer), loss indicator set, SDUs delivered per port
        Err             : out   ErrEventArray_t(0 to 1);
        Loss            : out   std_logic;
        Delivered       : out   std_logic_vector(NumRx_g - 1 downto 0);
        -- ECC events (one-cycle pulses): 0 data buffer, 1 descriptor buffer, 2 table reads, 3 scrubber
        Ecc_Sec         : out   std_logic_vector(3 downto 0);
        Ecc_Ded         : out   std_logic_vector(3 downto 0);
        -- Error injection into the next write: channel 0 data buffer, 1 descriptor buffer, 2 table
        ErrInj_Channel  : in    std_logic_vector(5 downto 0)                  := (others => '0');
        ErrInj_Double   : in    std_logic                                     := '0';
        ErrInj_Valid    : in    std_logic                                     := '0';
        Scrub_Enable    : in    std_logic                                     := '1'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture struct of spp_receive is

    signal Desc_Valid   : std_logic;
    signal Desc_Ready   : std_logic;
    signal Desc_Data    : std_logic_vector(RxDescWidth_c - 1 downto 0);
    signal Desc_Sec     : std_logic;
    signal Desc_Ded     : std_logic;
    signal Data_Valid   : std_logic;
    signal Data_Ready   : std_logic;
    signal Data_Data    : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Data_Last    : std_logic;
    signal Data_Next    : std_logic;
    signal Data_Sec     : std_logic;
    signal Data_Ded     : std_logic;
    signal TblA_Valid   : std_logic;
    signal TblA_Ready   : std_logic;
    signal TblA_Apid    : std_logic_vector(10 downto 0);
    signal TblA_RdValid : std_logic;
    signal TblA_RdData  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
    signal TblA_RdDed   : std_logic;
    signal TblA_WrEna   : std_logic;
    signal TblA_WrData  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
    signal TblA_Release : std_logic;
    signal Route_Valid  : std_logic_vector(NumRx_g - 1 downto 0);
    signal Route_Ready  : std_logic_vector(NumRx_g - 1 downto 0);
    signal Route_Data   : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Route_Keep   : std_logic_vector(DataWidth_g / 8 - 1 downto 0);
    signal Route_Last   : std_logic;
    signal Route_User   : std_logic_vector(RxUserWidth_c - 1 downto 0);
    signal InjData      : std_logic;
    signal InjDesc      : std_logic;
    signal InjTable     : std_logic;

begin

    InjData  <= ErrInj_Valid when unsigned(ErrInj_Channel) = 0 else '0';
    InjDesc  <= ErrInj_Valid when unsigned(ErrInj_Channel) = 1 else '0';
    InjTable <= ErrInj_Valid when unsigned(ErrInj_Channel) = 2 else '0';

    -- Reception (RE-1)
    i_buffer : entity work.spp_receive_buffer
        generic map (
            DataWidth_g   => DataWidth_g,
            BufferBytes_g => BufferBytes_g,
            MaxPackets_g  => MaxPackets_g
        )
        port map (
            Clk             => Clk,
            Rst             => Rst,
            S_Valid         => S_Pkt_Valid,
            S_Ready         => S_Pkt_Ready,
            S_Data          => S_Pkt_Data,
            S_Keep          => S_Pkt_Keep,
            S_Last          => S_Pkt_Last,
            S_User          => S_Pkt_User,
            Cfg_MaxLength   => Cfg_MaxLength,
            Cfg_IdleDeliver => Cfg_IdleDeliver,
            Desc_Valid      => Desc_Valid,
            Desc_Ready      => Desc_Ready,
            Desc_Data       => Desc_Data,
            Desc_Sec        => Desc_Sec,
            Desc_Ded        => Desc_Ded,
            Data_Valid      => Data_Valid,
            Data_Ready      => Data_Ready,
            Data_Data       => Data_Data,
            Data_Last       => Data_Last,
            Data_Next       => Data_Next,
            Data_Sec        => Data_Sec,
            Data_Ded        => Data_Ded,
            Err             => Err(0),
            ErrInj_Data     => InjData,
            ErrInj_Desc     => InjDesc,
            ErrInj_Double   => ErrInj_Double
        );

    -- Demultiplexer (RE-2)
    i_demux : entity work.spp_receive_demux
        generic map (
            DataWidth_g     => DataWidth_g,
            NumRx_g         => NumRx_g,
            RxOctetString_g => RxOctetString_g
        )
        port map (
            Clk         => Clk,
            Rst         => Rst,
            Desc_Valid  => Desc_Valid,
            Desc_Ready  => Desc_Ready,
            Desc_Data   => Desc_Data,
            Desc_Sec    => Desc_Sec,
            Desc_Ded    => Desc_Ded,
            Data_Valid  => Data_Valid,
            Data_Ready  => Data_Ready,
            Data_Data   => Data_Data,
            Data_Last   => Data_Last,
            Data_Next   => Data_Next,
            Data_Sec    => Data_Sec,
            Data_Ded    => Data_Ded,
            Tbl_Valid   => TblA_Valid,
            Tbl_Ready   => TblA_Ready,
            Tbl_Apid    => TblA_Apid,
            Tbl_RdValid => TblA_RdValid,
            Tbl_RdData  => TblA_RdData,
            Tbl_RdDed   => TblA_RdDed,
            Tbl_WrEna   => TblA_WrEna,
            Tbl_WrData  => TblA_WrData,
            Tbl_Release => TblA_Release,
            Out_Valid   => Route_Valid,
            Out_Ready   => Route_Ready,
            Out_Data    => Route_Data,
            Out_Keep    => Route_Keep,
            Out_Last    => Route_Last,
            Out_User    => Route_User,
            Err         => Err(1),
            Loss        => Loss,
            Ecc_Sec     => Ecc_Sec(1 downto 0),
            Ecc_Ded     => Ecc_Ded(1 downto 0)
        );

    -- Delivery to the user ports (RE-3)
    g_port : for p in 0 to NumRx_g - 1 generate

        i_extraction : entity work.spp_receive_extraction
            generic map (
                DataWidth_g   => DataWidth_g,
                OctetString_g => RxOctetString_g(p) = '1'
            )
            port map (
                Clk       => Clk,
                Rst       => Rst,
                In_Valid  => Route_Valid(p),
                In_Ready  => Route_Ready(p),
                In_Data   => Route_Data,
                In_Keep   => Route_Keep,
                In_Last   => Route_Last,
                In_User   => Route_User,
                M_Valid   => M_Rx_Valid(p),
                M_Ready   => M_Rx_Ready(p),
                M_Data    => M_Rx_Data((p + 1) * DataWidth_g - 1 downto p * DataWidth_g),
                M_Keep    => M_Rx_Keep((p + 1) * DataWidth_g / 8 - 1 downto p * DataWidth_g / 8),
                M_Last    => M_Rx_Last(p),
                M_User    => M_Rx_User((p + 1) * RxUserWidth_c - 1 downto p * RxUserWidth_c),
                Delivered => Delivered(p)
            );

    end generate;

    -- Receive APID table (TB-2)
    i_table : entity work.spp_apid_table
        generic map (
            Width_g     => RxEntryWidth_c,
            ClkFreqHz_g => ClkFreqHz_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Init_Value     => Cfg_TableInit,
            Init_Busy      => Tbl_Busy,
            A_Valid        => TblA_Valid,
            A_Ready        => TblA_Ready,
            A_Apid         => TblA_Apid,
            A_RdValid      => TblA_RdValid,
            A_RdData       => TblA_RdData,
            A_RdDed        => TblA_RdDed,
            A_WrEna        => TblA_WrEna,
            A_WrData       => TblA_WrData,
            A_Release      => TblA_Release,
            B_Valid        => Tbl_Valid,
            B_Ready        => Tbl_Ready,
            B_Apid         => Tbl_Apid,
            B_RdValid      => Tbl_RdValid,
            B_RdData       => Tbl_RdData,
            B_RdDed        => Tbl_RdDed,
            B_WrEna        => Tbl_WrEna,
            B_WrData       => Tbl_WrData,
            B_Release      => Tbl_Release,
            Ecc_Sec        => Ecc_Sec(2),
            Ecc_Ded        => Ecc_Ded(2),
            Scrub_Sec      => Ecc_Sec(3),
            Scrub_Ded      => Ecc_Ded(3),
            Scrub_Enable   => Scrub_Enable,
            ErrInj_BitFlip => injPattern(eccCodewordWidth(RxEntryWidth_c), ErrInj_Double),
            ErrInj_Valid   => InjTable
        );

end architecture;
