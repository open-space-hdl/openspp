---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Packetizer (PT-1): cuts data units into segments and sends every segment as a Space Packet for a
-- send port of the Packet Service, with the Sequence Flags of its segment, the Packet Sequence Count
-- of the instance, an optional Packet Secondary Header and an optional CRC.
--
-- Documentation: hdl/spp_packetizer/docs/architecture.md

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
entity spp_packetizer is
    generic (
        DataWidth_g   : positive := 32;
        ChunkBytes_g  : positive := 4096;
        BufferBytes_g : positive := 8192;
        MaxChunks_g   : positive := 8;
        SecHdrBytes_g : natural  := 0;
        Crc_g         : boolean  := false
    );
    port (
        -- Control
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Data units; S_Error with S_Last marks an aborted data unit
        S_Valid       : in    std_logic;
        S_Ready       : out   std_logic;
        S_Data        : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Keep        : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Last        : in    std_logic;
        S_Error       : in    std_logic                                                    := '0';
        -- Space Packets for a send port of the Packet Service
        M_Valid       : out   std_logic;
        M_Ready       : in    std_logic                                                    := '1';
        M_Data        : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Keep        : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Last        : out   std_logic;
        -- Header fields, sampled at the end of the clock cycle in which Hdr_Sample is '1'
        Cfg_Apid      : in    std_logic_vector(10 downto 0);
        Cfg_Type      : in    std_logic                                                    := '0';
        SecHdr_Data   : in    std_logic_vector(8 * maximum(SecHdrBytes_g, 1) - 1 downto 0) := (others => '0');
        Hdr_Sample    : out   std_logic;
        -- Events: aborted data unit, corrected and detected errors (bit 0 buffer, bit 1 descriptors)
        Aborted       : out   std_logic;
        Ecc_Sec       : out   std_logic_vector(1 downto 0);
        Ecc_Ded       : out   std_logic_vector(1 downto 0);
        -- Error injection into the next word written into the buffer or the descriptor FIFO
        ErrInj_Data   : in    std_logic                                                    := '0';
        ErrInj_Desc   : in    std_logic                                                    := '0';
        ErrInj_Double : in    std_logic                                                    := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_packetizer is

    constant Bytes_c       : positive                                                := DataWidth_g / 8;
    constant CrcBytes_c    : natural                                                 := 2 * boolean'pos(Crc_g);
    constant HdrBytes_c    : positive                                                := PrimaryHeaderBytes_c + SecHdrBytes_g;
    constant DescWidth_c   : positive                                                := PkDescWidth_c - 16 * boolean'pos(not Crc_g);
    constant UserWidth_c   : positive                                                := 1 + 15 * boolean'pos(Crc_g);
    constant Shf_c         : std_logic                                               := choose(SecHdrBytes_g > 0, '1', '0');     -- SPP 4.1.3.3.3.2
    constant HdrBytesSlv_c : std_logic_vector(log2ceil(HdrBytes_c + 1) - 1 downto 0) :=
        std_logic_vector(to_unsigned(HdrBytes_c, log2ceil(HdrBytes_c + 1)));

    type State_t is (Idle_s, Data_s);

    type TwoProcess_r is record
        State     : State_t;
        Hdr       : std_logic_vector(8 * HdrBytes_c - 1 downto 0);
        Crc       : std_logic_vector(15 downto 0);
        LastBytes : natural range 1 to Bytes_c;
        Count     : unsigned(13 downto 0);
        EccSec    : std_logic_vector(1 downto 0);
        EccDed    : std_logic_vector(1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- Segmenter to the FIFOs
    signal Seg_Valid   : std_logic;
    signal Seg_Ready   : std_logic;
    signal Seg_Data    : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Seg_Last    : std_logic;
    signal SDesc_Valid : std_logic;
    signal SDesc_Ready : std_logic;
    signal SDesc_Data  : std_logic_vector(PkDescWidth_c - 1 downto 0);

    -- FIFOs to the packet output
    signal Data_Valid : std_logic;
    signal Data_Ready : std_logic;
    signal Data_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Data_Last  : std_logic;
    signal Data_Sec   : std_logic;
    signal Data_Ded   : std_logic;
    signal Desc_Valid : std_logic;
    signal Desc_Ready : std_logic;
    signal Desc_Data  : std_logic_vector(DescWidth_c - 1 downto 0);
    signal Desc_Full  : std_logic_vector(PkDescWidth_c - 1 downto 0);
    signal Desc_Sec   : std_logic;
    signal Desc_Ded   : std_logic;

    -- Error injection patterns: data bits of the codewords
    signal InjData : std_logic_vector(eccCodewordWidth(DataWidth_g) - 1 downto 0);
    signal InjDesc : std_logic_vector(eccCodewordWidth(DescWidth_c) - 1 downto 0);

    -- Header insertion
    signal Ins_Valid : std_logic;
    signal Ins_Ready : std_logic;
    signal Ins_Keep  : std_logic_vector(Bytes_c - 1 downto 0);
    signal Ins_User  : std_logic_vector(UserWidth_c - 1 downto 0);
    signal Pkt_Valid : std_logic;
    signal Pkt_Ready : std_logic;
    signal Pkt_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Pkt_Keep  : std_logic_vector(Bytes_c - 1 downto 0);
    signal Pkt_Last  : std_logic;
    signal Pkt_User  : std_logic_vector(UserWidth_c - 1 downto 0);

begin

    -----------------------------------------------------------------------------------------------
    -- Generic ranges
    -----------------------------------------------------------------------------------------------
    assert DataWidth_g mod 8 = 0 and DataWidth_g >= 8 and DataWidth_g <= 128
        report "spp_packetizer: DataWidth_g must be a multiple of 8 from 8 to 128"
        severity failure;
    assert ChunkBytes_g mod Bytes_c = 0
        report "spp_packetizer: ChunkBytes_g must be a multiple of the beat width DataWidth_g / 8"
        severity failure;
    assert SecHdrBytes_g <= 64
        report "spp_packetizer: SecHdrBytes_g must be at most 64"
        severity failure;
    assert ChunkBytes_g + SecHdrBytes_g + CrcBytes_c <= 65536
        report "spp_packetizer: ChunkBytes_g + SecHdrBytes_g (+ 2 with Crc_g) must be at most 65536, " &
               "the maximum Packet Data Field (SPP 4.1.2.1)"
        severity failure;
    assert BufferBytes_g mod Bytes_c = 0 and isPower2(BufferBytes_g / Bytes_c)
        report "spp_packetizer: BufferBytes_g must be a power of two multiple of the beat width DataWidth_g / 8"
        severity failure;
    assert BufferBytes_g >= ChunkBytes_g
        report "spp_packetizer: BufferBytes_g must be at least ChunkBytes_g"
        severity failure;
    assert MaxChunks_g >= 2 and MaxChunks_g <= 64
        report "spp_packetizer: MaxChunks_g must be from 2 to 64"
        severity failure;

    -----------------------------------------------------------------------------------------------
    -- Input side
    -----------------------------------------------------------------------------------------------
    i_seg : entity work.spp_packetizer_segmenter
        generic map (
            DataWidth_g  => DataWidth_g,
            ChunkBytes_g => ChunkBytes_g,
            Crc_g        => Crc_g
        )
        port map (
            Clk        => Clk,
            Rst        => Rst,
            S_Valid    => S_Valid,
            S_Ready    => S_Ready,
            S_Data     => S_Data,
            S_Keep     => S_Keep,
            S_Last     => S_Last,
            S_Error    => S_Error,
            Seg_Valid  => Seg_Valid,
            Seg_Ready  => Seg_Ready,
            Seg_Data   => Seg_Data,
            Seg_Last   => Seg_Last,
            Desc_Valid => SDesc_Valid,
            Desc_Ready => SDesc_Ready,
            Desc_Data  => SDesc_Data,
            Aborted    => Aborted
        );

    InjData <= injDataPattern(eccCodewordWidth(DataWidth_g), ErrInj_Double);
    InjDesc <= injDataPattern(eccCodewordWidth(DescWidth_c), ErrInj_Double);

    -- Segments, store and forward; the packet boundaries are kept in flip-flops (PT-BF-01)
    i_data : entity olo.olo_ft_fifo_packet
        generic map (
            Width_g      => DataWidth_g,
            Depth_g      => BufferBytes_g / Bytes_c,
            FeatureSet_g => "DROP_SKIP_ONLY",
            MaxPackets_g => maximum(2, MaxChunks_g)
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Valid          => Seg_Valid,
            In_Ready          => Seg_Ready,
            In_Data           => Seg_Data,
            In_Last           => Seg_Last,
            In_Drop           => '0',
            In_IsDropped      => open,
            Out_Valid         => Data_Valid,
            Out_Ready         => Data_Ready,
            Out_Data          => Data_Data,
            Out_Size          => open,
            Out_Last          => Data_Last,
            Out_Next          => '0',
            Out_Repeat        => '0',
            Out_EccSec        => Data_Sec,
            Out_EccDed        => Data_Ded,
            PacketLevel       => open,
            FreeWords         => open,
            In_ErrInj_BitFlip => InjData,
            In_ErrInj_Valid   => ErrInj_Data
        );

    -- Descriptors; a descriptor is read before its segment, so the FIFO has room for every segment
    -- the buffer accepted
    i_desc : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g => DescWidth_c,
            Depth_g => maximum(2, MaxChunks_g)
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Data           => SDesc_Data(DescWidth_c - 1 downto 0),
            In_Valid          => SDesc_Valid,
            In_Ready          => SDesc_Ready,
            In_Level          => open,
            Out_Data          => Desc_Data,
            Out_Valid         => Desc_Valid,
            Out_Ready         => Desc_Ready,
            Out_Level         => open,
            Out_EccSec        => Desc_Sec,
            Out_EccDed        => Desc_Ded,
            Full              => open,
            AlmFull           => open,
            Empty             => open,
            AlmEmpty          => open,
            In_ErrInj_BitFlip => InjDesc,
            In_ErrInj_Valid   => ErrInj_Desc
        );

    -----------------------------------------------------------------------------------------------
    -- Output side: packet control
    -----------------------------------------------------------------------------------------------
    -- Descriptor in the layout of spp_pkg, CRC bits zero without Crc_g
    Desc_Full(DescWidth_c - 1 downto 0)             <= Desc_Data;
    Desc_Full(PkDescWidth_c - 1 downto DescWidth_c) <= (others => '0');

    p_comb : process (all) is
        variable v        : TwoProcess_r;
        variable Sample_v : std_logic;
        variable Len_v    : unsigned(15 downto 0);
        variable Flags_v  : std_logic_vector(1 downto 0);
        variable Pdl_v    : unsigned(15 downto 0);
        variable Pos_v    : natural;
    begin
        -- Hold variables stable
        v        := r;
        v.EccSec := (others => '0');
        v.EccDed := (others => '0');
        Sample_v := '0';

        Desc_Ready <= '0';
        Data_Ready <= '0';
        Ins_Valid  <= '0';

        case r.State is

            when Idle_s =>
                -- A complete segment and its descriptor: build the headers of its packet
                if Desc_Valid = '1' and Data_Valid = '1' then
                    Sample_v   := '1';
                    Desc_Ready <= '1';
                    Len_v      := unsigned(Desc_Full(PkDescLen_t));

                    -- SPP 4.1.3.4.2.2
                    if Desc_Full(PkDescFirst_c) = '1' and Desc_Full(PkDescLast_c) = '1' then
                        Flags_v := "11";
                    elsif Desc_Full(PkDescFirst_c) = '1' then
                        Flags_v := "01";
                    elsif Desc_Full(PkDescLast_c) = '1' then
                        Flags_v := "10";
                    else
                        Flags_v := "00";
                    end if;

                    -- SPP 4.1.3.5: secondary header, segment and CRC, minus one
                    Pdl_v := Len_v + (SecHdrBytes_g + CrcBytes_c);

                    v.Hdr(47 downto 0) := primaryHeader(Cfg_Type, Shf_c, Cfg_Apid, Flags_v,
                                                        std_logic_vector(r.Count), std_logic_vector(Pdl_v));

                    for i in 0 to SecHdrBytes_g - 1 loop
                        Pos_v                                 := PrimaryHeaderBytes_c + i;
                        v.Hdr(8 * Pos_v + 7 downto 8 * Pos_v) := SecHdr_Data(8 * i + 7 downto 8 * i);
                    end loop;

                    v.Crc := Desc_Full(PkDescCrc_t);

                    v.LastBytes := to_integer(Len_v mod Bytes_c) + 1;
                    v.Count     := r.Count + 1;                                -- SPP 4.1.3.4.3.4
                    v.EccSec(1) := Desc_Sec;
                    v.EccDed(1) := Desc_Ded;
                    v.State     := Data_s;
                end if;

            when Data_s =>
                -- The segment into the header insertion
                Ins_Valid  <= Data_Valid;
                Data_Ready <= Ins_Ready;
                if Data_Valid = '1' and Ins_Ready = '1' then
                    v.EccSec(0) := Data_Sec;
                    v.EccDed(0) := Data_Ded;
                    if Data_Last = '1' then
                        v.State := Idle_s;
                    end if;
                end if;

            -- coverage off
            when others =>
                v.State := Idle_s;
            -- coverage on

        end case;

        if Data_Last = '1' then
            Ins_Keep <= keepOfBytes(r.LastBytes, Bytes_c);
        else
            Ins_Keep <= (others => '1');
        end if;

        Hdr_Sample <= Sample_v;

        -- Apply to record
        r_next <= v;
    end process;

    Ins_User <= r.Crc(UserWidth_c - 1 downto 0) when Crc_g else (others => '0');
    Ecc_Sec  <= r.EccSec;
    Ecc_Ded  <= r.EccDed;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State     <= Idle_s;
                r.LastBytes <= Bytes_c;
                r.Count     <= (others => '0');
                r.EccSec    <= (others => '0');
                r.EccDed    <= (others => '0');
            end if;
        end if;
    end process;

    -- Packet Primary Header and Packet Secondary Header in front of the segment
    i_insert : entity work.spp_header_insert
        generic map (
            DataWidth_g      => DataWidth_g,
            MaxHeaderBytes_g => HdrBytes_c,
            UserWidth_g      => UserWidth_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => Ins_Valid,
            In_Ready       => Ins_Ready,
            In_Data        => Data_Data,
            In_Keep        => Ins_Keep,
            In_Last        => Data_Last,
            In_User        => Ins_User,
            In_Header      => r.Hdr,
            In_HeaderBytes => HdrBytesSlv_c,
            Out_Valid      => Pkt_Valid,
            Out_Ready      => Pkt_Ready,
            Out_Data       => Pkt_Data,
            Out_Keep       => Pkt_Keep,
            Out_Last       => Pkt_Last,
            Out_User       => Pkt_User
        );

    -- CRC behind the segment (PT-CR-01)
    g_crc : if Crc_g generate

        i_trailer : entity work.spp_packetizer_trailer
            generic map (
                DataWidth_g => DataWidth_g
            )
            port map (
                Clk       => Clk,
                Rst       => Rst,
                In_Valid  => Pkt_Valid,
                In_Ready  => Pkt_Ready,
                In_Data   => Pkt_Data,
                In_Keep   => Pkt_Keep,
                In_Last   => Pkt_Last,
                In_User   => Pkt_User,
                Out_Valid => M_Valid,
                Out_Ready => M_Ready,
                Out_Data  => M_Data,
                Out_Keep  => M_Keep,
                Out_Last  => M_Last
            );

    else generate

        M_Valid   <= Pkt_Valid;
        Pkt_Ready <= M_Ready;
        M_Data    <= Pkt_Data;
        M_Keep    <= Pkt_Keep;
        M_Last    <= Pkt_Last;

    end generate;

end architecture;
