---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- OpenSPP core: the CCSDS Space Packet Protocol (CCSDS 133.0-B-2) with the SpaceWire CCSDS Packet
-- Transfer Protocol (ECSS-E-ST-50-53C): sending end, receiving end, transfer layer and register file.
--
-- Documentation: docs/user_guide.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_core is
    generic (
        -- Streams and user ports
        DataWidth_g     : positive range 8 to 128                   := 32;
        NumTx_g         : positive range 1 to MaxPorts_c            := 1;
        NumRx_g         : positive range 1 to MaxPorts_c            := 1;
        TxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0) := (others => '1');
        RxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0) := (others => '1');
        -- Buffers
        TxBufferBytes_g : positive                                  := 4096;
        TxMaxPackets_g  : positive                                  := 8;
        RxBufferBytes_g : positive                                  := 4096;
        RxMaxPackets_g  : positive                                  := 8;
        -- Transfer layer (ECSS-E-ST-50-53C)
        Encapsulation_g : boolean                                   := true;
        NumDest_g       : positive range 1 to MaxDest_c             := 1;
        SpwAddrBytes_g  : natural range 0 to MaxSpwAddrBytes_c      := 4;
        -- Reset values of the managed parameters and of the APID tables
        MaxLength_g     : positive range 7 to 65542                 := 65542;
        RoundRobin_g    : std_logic                                 := '0';
        Tla_g           : std_logic_vector(7 downto 0)              := x"FE";
        TxPathDefault_g : boolean                                   := true;
        RxPathDefault_g : boolean                                   := true;
        -- Clock frequency (scrub pacer of the tables)
        ClkFreqHz_g     : real                                      := 100.0e6
    );
    port (
        -- Control
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        -- Send ports (PACKET.request, OCTET_STRING.request)
        S_Tx_Valid        : in    std_logic_vector(NumTx_g - 1 downto 0);
        S_Tx_Ready        : out   std_logic_vector(NumTx_g - 1 downto 0);
        S_Tx_Data         : in    std_logic_vector(NumTx_g * DataWidth_g - 1 downto 0);
        S_Tx_Keep         : in    std_logic_vector(NumTx_g * DataWidth_g / 8 - 1 downto 0);
        S_Tx_Last         : in    std_logic_vector(NumTx_g - 1 downto 0);
        S_Tx_User         : in    std_logic_vector(NumTx_g * TxUserWidth_c - 1 downto 0);
        -- Receive ports (PACKET.indication, OCTET_STRING.indication)
        M_Rx_Valid        : out   std_logic_vector(NumRx_g - 1 downto 0);
        M_Rx_Ready        : in    std_logic_vector(NumRx_g - 1 downto 0);
        M_Rx_Data         : out   std_logic_vector(NumRx_g * DataWidth_g - 1 downto 0);
        M_Rx_Keep         : out   std_logic_vector(NumRx_g * DataWidth_g / 8 - 1 downto 0);
        M_Rx_Last         : out   std_logic_vector(NumRx_g - 1 downto 0);
        M_Rx_User         : out   std_logic_vector(NumRx_g * RxUserWidth_c - 1 downto 0);
        -- Link: transmitted packets; TUser: error end of packet (bit 0, last beat), destination (4:1)
        M_Link_Valid      : out   std_logic;
        M_Link_Ready      : in    std_logic;
        M_Link_Data       : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Link_Keep       : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Link_Last       : out   std_logic;
        M_Link_User       : out   std_logic_vector(LinkUserWidth_c - 1 downto 0);
        -- Link: received packets; TUser: error end of packet (last beat)
        S_Link_Valid      : in    std_logic;
        S_Link_Ready      : out   std_logic;
        S_Link_Data       : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Link_Keep       : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Link_Last       : in    std_logic;
        S_Link_User       : in    std_logic_vector(0 downto 0);
        -- Register file
        S_AxiLite_ArAddr  : in    std_logic_vector(10 downto 0);
        S_AxiLite_ArValid : in    std_logic;
        S_AxiLite_ArReady : out   std_logic;
        S_AxiLite_AwAddr  : in    std_logic_vector(10 downto 0);
        S_AxiLite_AwValid : in    std_logic;
        S_AxiLite_AwReady : out   std_logic;
        S_AxiLite_WData   : in    std_logic_vector(31 downto 0);
        S_AxiLite_WStrb   : in    std_logic_vector(3 downto 0);
        S_AxiLite_WValid  : in    std_logic;
        S_AxiLite_WReady  : out   std_logic;
        S_AxiLite_BResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_BValid  : out   std_logic;
        S_AxiLite_BReady  : in    std_logic;
        S_AxiLite_RData   : out   std_logic_vector(31 downto 0);
        S_AxiLite_RResp   : out   std_logic_vector(1 downto 0);
        S_AxiLite_RValid  : out   std_logic;
        S_AxiLite_RReady  : in    std_logic;
        Irq               : out   std_logic;
        -- Rejected SDUs and discarded packets (one-cycle event)
        Err_Valid         : out   std_logic;
        Err_Code          : out   std_logic_vector(4 downto 0);
        Err_Port          : out   std_logic_vector(3 downto 0);
        Err_Apid          : out   std_logic_vector(10 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture struct of spp_core is

    constant NumErr_c : positive := NumTx_g + 4;

    function toSl (b : boolean) return std_logic is
    begin
        if b then
            return '1';
        end if;
        return '0';
    end function;

    -- Initial entries of the APID tables: every APID on destination 0 / receive port 0, count 0
    constant TxInit_c : std_logic_vector(TxEntryWidth_c - 1 downto 0) := toSl(TxPathDefault_g) & "0000" & "00000000000000";
    constant RxInit_c : std_logic_vector(RxEntryWidth_c - 1 downto 0) := toSl(RxPathDefault_g) & "0000" & "00" & "00000000000000";

    -- Managed parameters
    signal MaxLength   : std_logic_vector(LengthWidth_c - 1 downto 0);
    signal RoundRobin  : std_logic;
    signal IdleDeliver : std_logic;
    signal TlaCheck    : std_logic;
    signal RxStrip     : std_logic_vector(3 downto 0);
    signal Tla         : std_logic_vector(7 downto 0);
    signal DestAddr    : std_logic_vector(NumDest_g * 8 * maximum(SpwAddrBytes_g, 1) - 1 downto 0);
    signal DestAddrLen : std_logic_vector(NumDest_g * 5 - 1 downto 0);
    signal DestTla     : std_logic_vector(NumDest_g * 8 - 1 downto 0);
    signal DestUa      : std_logic_vector(NumDest_g * 8 - 1 downto 0);
    signal ScrubEna    : std_logic;
    -- Space Packets between the ends and the transfer layer
    signal TxPkt_Valid : std_logic;
    signal TxPkt_Ready : std_logic;
    signal TxPkt_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal TxPkt_Keep  : std_logic_vector(DataWidth_g / 8 - 1 downto 0);
    signal TxPkt_Last  : std_logic;
    signal TxPkt_User  : std_logic_vector(LinkUserWidth_c - 1 downto 0);
    signal RxPkt_Valid : std_logic;
    signal RxPkt_Ready : std_logic;
    signal RxPkt_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal RxPkt_Keep  : std_logic_vector(DataWidth_g / 8 - 1 downto 0);
    signal RxPkt_Last  : std_logic;
    signal RxPkt_User  : std_logic_vector(RxPktUserWidth_c - 1 downto 0);
    -- Tables (client B of the register file)
    signal TxT_Valid   : std_logic;
    signal TxT_Ready   : std_logic;
    signal TxT_Apid    : std_logic_vector(10 downto 0);
    signal TxT_RdValid : std_logic;
    signal TxT_RdData  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
    signal TxT_RdDed   : std_logic;
    signal TxT_WrEna   : std_logic;
    signal TxT_WrData  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
    signal TxT_Release : std_logic;
    signal TxT_Busy    : std_logic;
    signal RxT_Valid   : std_logic;
    signal RxT_Ready   : std_logic;
    signal RxT_Apid    : std_logic_vector(10 downto 0);
    signal RxT_RdValid : std_logic;
    signal RxT_RdData  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
    signal RxT_RdDed   : std_logic;
    signal RxT_WrEna   : std_logic;
    signal RxT_WrData  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
    signal RxT_Release : std_logic;
    signal RxT_Busy    : std_logic;
    -- Events
    signal Err         : ErrEventArray_t(0 to NumErr_c - 1);
    signal Sent        : std_logic;
    signal Delivered   : std_logic_vector(NumRx_g - 1 downto 0);
    signal Loss        : std_logic;
    signal EccSec      : std_logic_vector(7 downto 0);
    signal EccDed      : std_logic_vector(7 downto 0);
    signal InjTx       : std_logic;
    signal InjRx       : std_logic;
    signal InjChannel  : std_logic_vector(5 downto 0);
    signal InjDouble   : std_logic;

begin

    -- Sending end (SE-1 to SE-3, TB-1)
    i_send : entity work.spp_send
        generic map (
            DataWidth_g     => DataWidth_g,
            NumTx_g         => NumTx_g,
            TxOctetString_g => TxOctetString_g,
            BufferBytes_g   => TxBufferBytes_g,
            MaxPackets_g    => TxMaxPackets_g,
            ClkFreqHz_g     => ClkFreqHz_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            S_Tx_Valid     => S_Tx_Valid,
            S_Tx_Ready     => S_Tx_Ready,
            S_Tx_Data      => S_Tx_Data,
            S_Tx_Keep      => S_Tx_Keep,
            S_Tx_Last      => S_Tx_Last,
            S_Tx_User      => S_Tx_User,
            M_Pkt_Valid    => TxPkt_Valid,
            M_Pkt_Ready    => TxPkt_Ready,
            M_Pkt_Data     => TxPkt_Data,
            M_Pkt_Keep     => TxPkt_Keep,
            M_Pkt_Last     => TxPkt_Last,
            M_Pkt_User     => TxPkt_User,
            Cfg_MaxLength  => MaxLength,
            Cfg_RoundRobin => RoundRobin,
            Cfg_TableInit  => TxInit_c,
            Tbl_Valid      => TxT_Valid,
            Tbl_Ready      => TxT_Ready,
            Tbl_Apid       => TxT_Apid,
            Tbl_RdValid    => TxT_RdValid,
            Tbl_RdData     => TxT_RdData,
            Tbl_RdDed      => TxT_RdDed,
            Tbl_WrEna      => TxT_WrEna,
            Tbl_WrData     => TxT_WrData,
            Tbl_Release    => TxT_Release,
            Tbl_Busy       => TxT_Busy,
            Err            => Err(0 to NumTx_g),
            Sent           => Sent,
            Ecc_Sec        => EccSec(3 downto 0),
            Ecc_Ded        => EccDed(3 downto 0),
            ErrInj_Channel => InjChannel,
            ErrInj_Double  => InjDouble,
            ErrInj_Valid   => InjTx,
            Scrub_Enable   => ScrubEna
        );

    -- Transfer layer (EN-1, EN-2)
    g_cptp : if Encapsulation_g generate

        i_encapsulation : entity work.spp_encapsulation
            generic map (
                DataWidth_g    => DataWidth_g,
                NumDest_g      => NumDest_g,
                SpwAddrBytes_g => SpwAddrBytes_g
            )
            port map (
                Clk             => Clk,
                Rst             => Rst,
                S_Pkt_Valid     => TxPkt_Valid,
                S_Pkt_Ready     => TxPkt_Ready,
                S_Pkt_Data      => TxPkt_Data,
                S_Pkt_Keep      => TxPkt_Keep,
                S_Pkt_Last      => TxPkt_Last,
                S_Pkt_User      => TxPkt_User,
                M_Link_Valid    => M_Link_Valid,
                M_Link_Ready    => M_Link_Ready,
                M_Link_Data     => M_Link_Data,
                M_Link_Keep     => M_Link_Keep,
                M_Link_Last     => M_Link_Last,
                M_Link_User     => M_Link_User,
                Cfg_DestAddr    => DestAddr,
                Cfg_DestAddrLen => DestAddrLen,
                Cfg_DestTla     => DestTla,
                Cfg_DestUa      => DestUa
            );

        i_decapsulation : entity work.spp_decapsulation
            generic map (
                DataWidth_g => DataWidth_g
            )
            port map (
                Clk          => Clk,
                Rst          => Rst,
                S_Link_Valid => S_Link_Valid,
                S_Link_Ready => S_Link_Ready,
                S_Link_Data  => S_Link_Data,
                S_Link_Keep  => S_Link_Keep,
                S_Link_Last  => S_Link_Last,
                S_Link_User  => S_Link_User,
                M_Pkt_Valid  => RxPkt_Valid,
                M_Pkt_Ready  => RxPkt_Ready,
                M_Pkt_Data   => RxPkt_Data,
                M_Pkt_Keep   => RxPkt_Keep,
                M_Pkt_Last   => RxPkt_Last,
                M_Pkt_User   => RxPkt_User,
                Cfg_RxStrip  => RxStrip,
                Cfg_TlaCheck => TlaCheck,
                Cfg_Tla      => Tla,
                Err          => Err(NumTx_g + 1)
            );

    end generate;

    g_plain : if not Encapsulation_g generate
        -- Space Packets directly on the link; the destination index in TUser routes them in the subnetwork
        M_Link_Valid <= TxPkt_Valid;
        TxPkt_Ready  <= M_Link_Ready;
        M_Link_Data  <= TxPkt_Data;
        M_Link_Keep  <= TxPkt_Keep;
        M_Link_Last  <= TxPkt_Last;
        M_Link_User  <= TxPkt_User;

        RxPkt_Valid                <= S_Link_Valid;
        S_Link_Ready               <= RxPkt_Ready;
        RxPkt_Data                 <= S_Link_Data;
        RxPkt_Keep                 <= S_Link_Keep;
        RxPkt_Last                 <= S_Link_Last;
        RxPkt_User(RxPktUserEep_c) <= S_Link_User(0);
        RxPkt_User(RxPktUserUa_t)  <= (others => '0');
        Err(NumTx_g + 1)           <= ErrEventNone_c;
    end generate;

    -- Receiving end (RE-1 to RE-3, TB-2)
    i_receive : entity work.spp_receive
        generic map (
            DataWidth_g     => DataWidth_g,
            NumRx_g         => NumRx_g,
            RxOctetString_g => RxOctetString_g,
            BufferBytes_g   => RxBufferBytes_g,
            MaxPackets_g    => RxMaxPackets_g,
            ClkFreqHz_g     => ClkFreqHz_g
        )
        port map (
            Clk             => Clk,
            Rst             => Rst,
            S_Pkt_Valid     => RxPkt_Valid,
            S_Pkt_Ready     => RxPkt_Ready,
            S_Pkt_Data      => RxPkt_Data,
            S_Pkt_Keep      => RxPkt_Keep,
            S_Pkt_Last      => RxPkt_Last,
            S_Pkt_User      => RxPkt_User,
            M_Rx_Valid      => M_Rx_Valid,
            M_Rx_Ready      => M_Rx_Ready,
            M_Rx_Data       => M_Rx_Data,
            M_Rx_Keep       => M_Rx_Keep,
            M_Rx_Last       => M_Rx_Last,
            M_Rx_User       => M_Rx_User,
            Cfg_MaxLength   => MaxLength,
            Cfg_IdleDeliver => IdleDeliver,
            Cfg_TableInit   => RxInit_c,
            Tbl_Valid       => RxT_Valid,
            Tbl_Ready       => RxT_Ready,
            Tbl_Apid        => RxT_Apid,
            Tbl_RdValid     => RxT_RdValid,
            Tbl_RdData      => RxT_RdData,
            Tbl_RdDed       => RxT_RdDed,
            Tbl_WrEna       => RxT_WrEna,
            Tbl_WrData      => RxT_WrData,
            Tbl_Release     => RxT_Release,
            Tbl_Busy        => RxT_Busy,
            Err             => Err(NumTx_g + 2 to NumTx_g + 3),
            Loss            => Loss,
            Delivered       => Delivered,
            Ecc_Sec         => EccSec(7 downto 4),
            Ecc_Ded         => EccDed(7 downto 4),
            ErrInj_Channel  => InjChannel,
            ErrInj_Double   => InjDouble,
            ErrInj_Valid    => InjRx,
            Scrub_Enable    => ScrubEna
        );

    -- Register file (MG-1, MG-2)
    i_mib : entity work.spp_mib
        generic map (
            DataWidth_g     => DataWidth_g,
            NumTx_g         => NumTx_g,
            NumRx_g         => NumRx_g,
            NumDest_g       => NumDest_g,
            SpwAddrBytes_g  => SpwAddrBytes_g,
            Encapsulation_g => Encapsulation_g,
            TxOctetString_g => TxOctetString_g,
            RxOctetString_g => RxOctetString_g,
            TxBufferBytes_g => TxBufferBytes_g,
            RxBufferBytes_g => RxBufferBytes_g,
            MaxLength_g     => MaxLength_g,
            RoundRobin_g    => RoundRobin_g,
            Tla_g           => Tla_g,
            NumErr_g        => NumErr_c
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            S_AxiLite_ArAddr  => S_AxiLite_ArAddr,
            S_AxiLite_ArValid => S_AxiLite_ArValid,
            S_AxiLite_ArReady => S_AxiLite_ArReady,
            S_AxiLite_AwAddr  => S_AxiLite_AwAddr,
            S_AxiLite_AwValid => S_AxiLite_AwValid,
            S_AxiLite_AwReady => S_AxiLite_AwReady,
            S_AxiLite_WData   => S_AxiLite_WData,
            S_AxiLite_WStrb   => S_AxiLite_WStrb,
            S_AxiLite_WValid  => S_AxiLite_WValid,
            S_AxiLite_WReady  => S_AxiLite_WReady,
            S_AxiLite_BResp   => S_AxiLite_BResp,
            S_AxiLite_BValid  => S_AxiLite_BValid,
            S_AxiLite_BReady  => S_AxiLite_BReady,
            S_AxiLite_RData   => S_AxiLite_RData,
            S_AxiLite_RResp   => S_AxiLite_RResp,
            S_AxiLite_RValid  => S_AxiLite_RValid,
            S_AxiLite_RReady  => S_AxiLite_RReady,
            Irq               => Irq,
            Cfg_MaxLength     => MaxLength,
            Cfg_RoundRobin    => RoundRobin,
            Cfg_IdleDeliver   => IdleDeliver,
            Cfg_TlaCheck      => TlaCheck,
            Cfg_RxStrip       => RxStrip,
            Cfg_Tla           => Tla,
            Cfg_DestAddr      => DestAddr,
            Cfg_DestAddrLen   => DestAddrLen,
            Cfg_DestTla       => DestTla,
            Cfg_DestUa        => DestUa,
            Cfg_ScrubEnable   => ScrubEna,
            TxTbl_Valid       => TxT_Valid,
            TxTbl_Ready       => TxT_Ready,
            TxTbl_Apid        => TxT_Apid,
            TxTbl_RdValid     => TxT_RdValid,
            TxTbl_RdData      => TxT_RdData,
            TxTbl_RdDed       => TxT_RdDed,
            TxTbl_WrEna       => TxT_WrEna,
            TxTbl_WrData      => TxT_WrData,
            TxTbl_Release     => TxT_Release,
            TxTbl_Busy        => TxT_Busy,
            RxTbl_Valid       => RxT_Valid,
            RxTbl_Ready       => RxT_Ready,
            RxTbl_Apid        => RxT_Apid,
            RxTbl_RdValid     => RxT_RdValid,
            RxTbl_RdData      => RxT_RdData,
            RxTbl_RdDed       => RxT_RdDed,
            RxTbl_WrEna       => RxT_WrEna,
            RxTbl_WrData      => RxT_WrData,
            RxTbl_Release     => RxT_Release,
            RxTbl_Busy        => RxT_Busy,
            Err               => Err,
            Tx_Sent           => Sent,
            Rx_Delivered      => Delivered,
            Rx_Loss           => Loss,
            Err_Valid         => Err_Valid,
            Err_Code          => Err_Code,
            Err_Port          => Err_Port,
            Err_Apid          => Err_Apid,
            Ecc_Sec           => EccSec,
            Ecc_Ded           => EccDed,
            Inj_TxValid       => InjTx,
            Inj_RxValid       => InjRx,
            Inj_Channel       => InjChannel,
            Inj_Double        => InjDouble
        );

end architecture;
