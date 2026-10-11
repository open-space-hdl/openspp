---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Send buffer (SE-1) of one user port: accepts PACKET.request or OCTET_STRING.request, checks the
-- SDU while it arrives, stores accepted SDUs completely and records their length and parameters in a
-- descriptor; a rejected SDU is dropped and reported.
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
entity spp_send_buffer is
    generic (
        DataWidth_g   : positive := 32;
        OctetString_g : boolean  := true;
        BufferBytes_g : positive := 4096;
        MaxPackets_g  : positive := 8;
        Index_g       : natural  := 0
    );
    port (
        -- Control
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Requests of the user port
        S_Valid        : in    std_logic;
        S_Ready        : out   std_logic;
        S_Data         : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Keep         : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Last         : in    std_logic;
        S_User         : in    std_logic_vector(TxUserWidth_c - 1 downto 0);
        -- Maximum Space Packet length in bytes (7 to 65542)
        Cfg_MaxLength  : in    std_logic_vector(LengthWidth_c - 1 downto 0);
        -- Descriptors of the stored SDUs
        Desc_Valid     : out   std_logic;
        Desc_Ready     : in    std_logic;
        Desc_Data      : out   std_logic_vector(TxDescWidth_c - 1 downto 0);
        Desc_Sec       : out   std_logic;
        Desc_Ded       : out   std_logic;
        -- Stored SDUs
        Data_Valid     : out   std_logic;
        Data_Ready     : in    std_logic;
        Data_Data      : out   std_logic_vector(DataWidth_g - 1 downto 0);
        Data_Last      : out   std_logic;
        Data_Next      : in    std_logic;
        Data_Sec       : out   std_logic;
        Data_Ded       : out   std_logic;
        -- Rejected SDUs
        Err            : out   ErrEvent_t;
        -- Error injection into the next write of the data or the descriptor buffer
        ErrInj_Data    : in    std_logic := '0';
        ErrInj_Desc    : in    std_logic := '0';
        ErrInj_Double  : in    std_logic := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_send_buffer is

    constant Bytes_c : positive := DataWidth_g / 8;
    constant Depth_c : positive := BufferBytes_g / Bytes_c;

    -- Beats that carry the Packet Primary Header
    constant HdrBeats_c : positive := (PrimaryHeaderBytes_c + Bytes_c - 1) / Bytes_c;

    type TwoProcess_r is record
        First    : std_logic;
        Cnt      : unsigned(LengthWidth_c - 1 downto 0);
        Beat     : natural range 0 to HdrBeats_c;
        Hdr      : std_logic_vector(47 downto 0);
        User     : std_logic_vector(TxUserWidth_c - 1 downto 0);
        Oversize : std_logic;
        Err      : ErrEvent_t;
    end record;

    signal r, r_next : TwoProcess_r;

    signal Fifo_InReady : std_logic;
    signal Fifo_InDrop  : std_logic;
    signal Desc_InValid : std_logic;
    signal Desc_InReady : std_logic;
    signal Desc_InData  : std_logic_vector(TxDescWidth_c - 1 downto 0);
    signal InReady      : std_logic;

begin

    assert BufferBytes_g mod Bytes_c = 0 and isPower2(Depth_c)
        report "spp_send_buffer: BufferBytes_g must be a power of two multiple of the beat width"
        severity failure;

    InReady <= Fifo_InReady and Desc_InReady;
    S_Ready <= InReady;

    p_comb : process (all) is
        variable v      : TwoProcess_r;
        variable N_v    : natural range 0 to Bytes_c;
        variable Cnt_v  : unsigned(LengthWidth_c - 1 downto 0);
        variable Hdr_v  : std_logic_vector(47 downto 0);
        variable User_v : std_logic_vector(TxUserWidth_c - 1 downto 0);
        variable Max_v  : unsigned(LengthWidth_c - 1 downto 0);
        variable Over_v : std_logic;
        variable Code_v : ErrCode_t;
        variable Apid_v : std_logic_vector(10 downto 0);
    begin
        -- Hold variables stable
        v      := r;
        v.Err  := ErrEventNone_c;
        Code_v := ErrNone_c;

        -- Byte count of the SDU including this beat (saturating)
        N_v := bytesOfKeep(S_Keep);
        if r.Cnt > LengthMax_c - Bytes_c then
            Cnt_v := to_unsigned(LengthMax_c, LengthWidth_c);
        else
            Cnt_v := r.Cnt + N_v;
        end if;

        -- Request parameters of the first beat (constant during an SDU)
        if r.First = '1' then
            User_v := S_User;
        else
            User_v := r.User;
        end if;

        -- Packet Primary Header of a Space Packet, including the bytes of this beat
        Hdr_v := r.Hdr;

        for k in 0 to PrimaryHeaderBytes_c - 1 loop
            if k / Bytes_c = r.Beat and k mod Bytes_c < N_v then
                Hdr_v(8 * k + 7 downto 8 * k) := S_Data(8 * (k mod Bytes_c) + 7 downto 8 * (k mod Bytes_c));
            end if;
        end loop;

        -- Maximum SDU length: the maximum packet length (less the header of an Octet String), the buffer size
        if OctetString_g then
            Max_v := unsigned(Cfg_MaxLength) - PrimaryHeaderBytes_c;
        else
            Max_v := unsigned(Cfg_MaxLength);
        end if;
        if Max_v > BufferBytes_g then
            Max_v := to_unsigned(BufferBytes_g, LengthWidth_c);
        end if;
        Over_v := r.Oversize;
        if Cnt_v > Max_v then
            Over_v := '1';
        end if;

        -- Checks at the end of the SDU, in a fixed order
        if OctetString_g then
            Apid_v := User_v(TxUserApid_t);
            if Over_v = '1' then
                Code_v := ErrTxOversize_c;                                    -- SPP 3.2.3.1, CPTP 5.5.2c
            elsif Apid_v = IdleApid_c and User_v(TxUserShi_c) = '1' then
                Code_v := ErrTxIdle_c;                                        -- SPP 4.1.3.3.3.4
            elsif User_v(TxUserNameValid_c) = '1' and User_v(TxUserType_c) = '0' then
                Code_v := ErrTxName_c;                                        -- SPP 4.1.3.4.3.2
            end if;
        else
            Apid_v := hdrApid(Hdr_v);
            if Over_v = '1' then
                Code_v := ErrTxOversize_c;                                    -- SPP 3.2.2.1, CPTP 5.5.2c
            elsif Cnt_v < MinPacketBytes_c then
                Code_v := ErrTxShort_c;                                       -- SPP 4.1.2.2
            elsif hdrVersion(Hdr_v) /= PacketVersion_c then
                Code_v := ErrTxVersion_c;                                     -- SPP 4.1.3.2.2
            elsif Cnt_v /= resize(unsigned(hdrPdl(Hdr_v)), LengthWidth_c) + MinPacketBytes_c then
                Code_v := ErrTxLength_c;                                      -- SPP 4.1.3.5
            elsif Apid_v = IdleApid_c and hdrShf(Hdr_v) = '1' then
                Code_v := ErrTxIdle_c;                                        -- SPP 4.1.3.3.3.4
            end if;
        end if;

        -- Defaults of the buffer inputs
        Fifo_InDrop  <= Over_v;
        Desc_InValid <= '0';
        if not OctetString_g then
            -- A Space Packet carries its parameters itself; the descriptor holds its APID
            Desc_InData                                          <= (others => '0');
            Desc_InData(TxDescLen_t)                             <= std_logic_vector(Cnt_v);
            Desc_InData(LengthWidth_c + 10 downto LengthWidth_c) <= Apid_v;
        else
            Desc_InData(TxDescLen_t)  <= std_logic_vector(Cnt_v);
            Desc_InData(TxDescUser_t) <= User_v;
        end if;

        if S_Valid = '1' and InReady = '1' then
            v.First    := '0';
            v.Cnt      := Cnt_v;
            v.Hdr      := Hdr_v;
            v.User     := User_v;
            v.Oversize := Over_v;
            if r.Beat < HdrBeats_c then
                v.Beat := r.Beat + 1;
            end if;
            if S_Last = '1' then
                if Code_v /= ErrNone_c then
                    -- Rejected: dropped from the buffer and reported
                    Fifo_InDrop <= '1';
                    v.Err.Valid := '1';
                    v.Err.Code  := Code_v;
                    v.Err.Index := std_logic_vector(to_unsigned(Index_g, 4));
                    v.Err.Apid  := Apid_v;
                else
                    Desc_InValid <= '1';
                end if;
                v.First    := '1';
                v.Cnt      := (others => '0');
                v.Beat     := 0;
                v.Oversize := '0';
                v.Hdr      := (others => '0');
            end if;
        end if;

        -- Apply to record
        r_next <= v;
    end process;

    Err <= r.Err;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.First     <= '1';
                r.Cnt       <= (others => '0');
                r.Beat      <= 0;
                r.Hdr       <= (others => '0');
                r.Oversize  <= '0';
                r.Err.Valid <= '0';
            end if;
        end if;
    end process;

    -- Complete SDUs
    i_data : entity olo.olo_ft_fifo_packet
        generic map (
            Width_g      => DataWidth_g,
            Depth_g      => Depth_c,
            FeatureSet_g => "DROP_SKIP_ONLY",
            MaxPackets_g => MaxPackets_g
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Valid          => S_Valid,
            In_Ready          => Fifo_InReady,
            In_Data           => S_Data,
            In_Last           => S_Last,
            In_Drop           => Fifo_InDrop,
            In_IsDropped      => open,
            Out_Valid         => Data_Valid,
            Out_Ready         => Data_Ready,
            Out_Data          => Data_Data,
            Out_Size          => open,
            Out_Last          => Data_Last,
            Out_Next          => Data_Next,
            Out_Repeat        => '0',
            Out_EccSec        => Data_Sec,
            Out_EccDed        => Data_Ded,
            PacketLevel       => open,
            FreeWords         => open,
            In_ErrInj_BitFlip => injPattern(eccCodewordWidth(DataWidth_g), ErrInj_Double),
            In_ErrInj_Valid   => ErrInj_Data
        );

    -- Descriptors
    i_desc : entity olo.olo_ft_fifo_sync
        generic map (
            Width_g    => TxDescWidth_c,
            Depth_g    => MaxPackets_g,
            RamStyle_g => "auto"
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            In_Data           => Desc_InData,
            In_Valid          => Desc_InValid,
            In_Ready          => Desc_InReady,
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
            In_ErrInj_BitFlip => injPattern(eccCodewordWidth(TxDescWidth_c), ErrInj_Double),
            In_ErrInj_Valid   => ErrInj_Desc
        );

end architecture;
