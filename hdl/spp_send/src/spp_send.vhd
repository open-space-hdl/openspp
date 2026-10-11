---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Sending end of the Space Packet Protocol (SE-1 to SE-3, TB-1): send buffers of the user ports, the
-- multiplexer, the packet assembly and the send APID table. Outputs Space Packets with the
-- destination of their managed data path.
--
-- Documentation: hdl/spp_send/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_send is
    generic (
        DataWidth_g     : positive range 8 to 128                   := 32;
        NumTx_g         : positive range 1 to MaxPorts_c            := 1;
        TxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0) := (others => '1');
        BufferBytes_g   : positive                                  := 4096;
        MaxPackets_g    : positive                                  := 8;
        ClkFreqHz_g     : real                                      := 100.0e6
    );
    port (
        -- Control
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Requests of the user ports (PACKET.request, OCTET_STRING.request)
        S_Tx_Valid     : in    std_logic_vector(NumTx_g - 1 downto 0);
        S_Tx_Ready     : out   std_logic_vector(NumTx_g - 1 downto 0);
        S_Tx_Data      : in    std_logic_vector(NumTx_g * DataWidth_g - 1 downto 0);
        S_Tx_Keep      : in    std_logic_vector(NumTx_g * DataWidth_g / 8 - 1 downto 0);
        S_Tx_Last      : in    std_logic_vector(NumTx_g - 1 downto 0);
        S_Tx_User      : in    std_logic_vector(NumTx_g * TxUserWidth_c - 1 downto 0);
        -- Space Packets; TUser: error end of packet (bit 0), destination (bits 4:1)
        M_Pkt_Valid    : out   std_logic;
        M_Pkt_Ready    : in    std_logic;
        M_Pkt_Data     : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Pkt_Keep     : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Pkt_Last     : out   std_logic;
        M_Pkt_User     : out   std_logic_vector(LinkUserWidth_c - 1 downto 0);
        -- Managed parameters
        Cfg_MaxLength  : in    std_logic_vector(LengthWidth_c - 1 downto 0);
        Cfg_RoundRobin : in    std_logic;
        Cfg_TableInit  : in    std_logic_vector(TxEntryWidth_c - 1 downto 0);
        -- Send APID table, access of the register file
        Tbl_Valid      : in    std_logic                                     := '0';
        Tbl_Ready      : out   std_logic;
        Tbl_Apid       : in    std_logic_vector(10 downto 0)                 := (others => '0');
        Tbl_RdValid    : out   std_logic;
        Tbl_RdData     : out   std_logic_vector(TxEntryWidth_c - 1 downto 0);
        Tbl_RdDed      : out   std_logic;
        Tbl_WrEna      : in    std_logic                                     := '0';
        Tbl_WrData     : in    std_logic_vector(TxEntryWidth_c - 1 downto 0) := (others => '0');
        Tbl_Release    : in    std_logic                                     := '0';
        Tbl_Busy       : out   std_logic;
        -- Events: rejected SDUs (index 0 to NumTx_g - 1: send buffers, NumTx_g: assembly), packets sent
        Err            : out   ErrEventArray_t(0 to NumTx_g);
        Sent           : out   std_logic;
        -- ECC events (one-cycle pulses): data buffers, descriptor buffers, table reads, scrubber
        Ecc_Sec        : out   std_logic_vector(3 downto 0);
        Ecc_Ded        : out   std_logic_vector(3 downto 0);
        -- Error injection: channel 2 n data buffer of port n, 2 n + 1 its descriptor buffer, 2 NumTx_g table
        ErrInj_Channel : in    std_logic_vector(5 downto 0)                  := (others => '0');
        ErrInj_Double  : in    std_logic                                     := '0';
        ErrInj_Valid   : in    std_logic                                     := '0';
        Scrub_Enable   : in    std_logic                                     := '1'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture struct of spp_send is

    signal Desc_Valid   : std_logic_vector(NumTx_g - 1 downto 0);
    signal Desc_Ready   : std_logic_vector(NumTx_g - 1 downto 0);
    signal Desc_Data    : std_logic_vector(NumTx_g * TxDescWidth_c - 1 downto 0);
    signal Desc_Sec     : std_logic_vector(NumTx_g - 1 downto 0);
    signal Desc_Ded     : std_logic_vector(NumTx_g - 1 downto 0);
    signal Data_Valid   : std_logic_vector(NumTx_g - 1 downto 0);
    signal Data_Ready   : std_logic_vector(NumTx_g - 1 downto 0);
    signal Data_Data    : std_logic_vector(NumTx_g * DataWidth_g - 1 downto 0);
    signal Data_Last    : std_logic_vector(NumTx_g - 1 downto 0);
    signal Data_Next    : std_logic_vector(NumTx_g - 1 downto 0);
    signal Data_Sec     : std_logic_vector(NumTx_g - 1 downto 0);
    signal Data_Ded     : std_logic_vector(NumTx_g - 1 downto 0);
    signal Grant        : std_logic_vector(NumTx_g - 1 downto 0);
    signal Grant_Valid  : std_logic;
    signal Grant_Ack    : std_logic;
    signal TblA_Valid   : std_logic;
    signal TblA_Ready   : std_logic;
    signal TblA_Apid    : std_logic_vector(10 downto 0);
    signal TblA_RdValid : std_logic;
    signal TblA_RdData  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
    signal TblA_RdDed   : std_logic;
    signal TblA_WrEna   : std_logic;
    signal TblA_WrData  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
    signal TblA_Release : std_logic;
    signal InjTable     : std_logic;

begin

    -- Send buffers (SE-1)
    g_buffer : for i in 0 to NumTx_g - 1 generate
        signal InjData : std_logic;
        signal InjDesc : std_logic;
    begin
        InjData <= ErrInj_Valid when to_integer(unsigned(ErrInj_Channel)) = 2 * i else '0';
        InjDesc <= ErrInj_Valid when to_integer(unsigned(ErrInj_Channel)) = 2 * i + 1 else '0';

        i_buffer : entity work.spp_send_buffer
            generic map (
                DataWidth_g   => DataWidth_g,
                OctetString_g => TxOctetString_g(i) = '1',
                BufferBytes_g => BufferBytes_g,
                MaxPackets_g  => MaxPackets_g,
                Index_g       => i
            )
            port map (
                Clk           => Clk,
                Rst           => Rst,
                S_Valid       => S_Tx_Valid(i),
                S_Ready       => S_Tx_Ready(i),
                S_Data        => S_Tx_Data((i + 1) * DataWidth_g - 1 downto i * DataWidth_g),
                S_Keep        => S_Tx_Keep((i + 1) * DataWidth_g / 8 - 1 downto i * DataWidth_g / 8),
                S_Last        => S_Tx_Last(i),
                S_User        => S_Tx_User((i + 1) * TxUserWidth_c - 1 downto i * TxUserWidth_c),
                Cfg_MaxLength => Cfg_MaxLength,
                Desc_Valid    => Desc_Valid(i),
                Desc_Ready    => Desc_Ready(i),
                Desc_Data     => Desc_Data((i + 1) * TxDescWidth_c - 1 downto i * TxDescWidth_c),
                Desc_Sec      => Desc_Sec(i),
                Desc_Ded      => Desc_Ded(i),
                Data_Valid    => Data_Valid(i),
                Data_Ready    => Data_Ready(i),
                Data_Data     => Data_Data((i + 1) * DataWidth_g - 1 downto i * DataWidth_g),
                Data_Last     => Data_Last(i),
                Data_Next     => Data_Next(i),
                Data_Sec      => Data_Sec(i),
                Data_Ded      => Data_Ded(i),
                Err           => Err(i),
                ErrInj_Data   => InjData,
                ErrInj_Desc   => InjDesc,
                ErrInj_Double => ErrInj_Double
            );

    end generate;

    -- Multiplexer (SE-2)
    i_mux : entity work.spp_send_mux
        generic map (
            NumTx_g => NumTx_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Cfg_RoundRobin => Cfg_RoundRobin,
            Req            => Desc_Valid,
            Grant          => Grant,
            Grant_Valid    => Grant_Valid,
            Grant_Ack      => Grant_Ack
        );

    -- Packet assembly (SE-3)
    i_assembly : entity work.spp_send_assembly
        generic map (
            DataWidth_g     => DataWidth_g,
            NumTx_g         => NumTx_g,
            TxOctetString_g => TxOctetString_g
        )
        port map (
            Clk         => Clk,
            Rst         => Rst,
            Grant       => Grant,
            Grant_Valid => Grant_Valid,
            Grant_Ack   => Grant_Ack,
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
            M_Valid     => M_Pkt_Valid,
            M_Ready     => M_Pkt_Ready,
            M_Data      => M_Pkt_Data,
            M_Keep      => M_Pkt_Keep,
            M_Last      => M_Pkt_Last,
            M_User      => M_Pkt_User,
            Err         => Err(NumTx_g),
            Sent        => Sent,
            Ecc_Sec     => Ecc_Sec(1 downto 0),
            Ecc_Ded     => Ecc_Ded(1 downto 0)
        );

    -- Send APID table (TB-1)
    InjTable <= ErrInj_Valid when to_integer(unsigned(ErrInj_Channel)) = 2 * NumTx_g else '0';

    i_table : entity work.spp_apid_table
        generic map (
            Width_g     => TxEntryWidth_c,
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
            ErrInj_BitFlip => injPattern(eccCodewordWidth(TxEntryWidth_c), ErrInj_Double),
            ErrInj_Valid   => InjTable
        );

end architecture;
