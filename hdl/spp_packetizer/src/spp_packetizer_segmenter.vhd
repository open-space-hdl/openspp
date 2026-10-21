---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Segmenter of the packetizer (PT-1): holds the latest beat of a data unit until the next beat shows
-- how the data unit continues, writes the beats of every segment into the segment buffer and the
-- length, flags and CRC of every segment into the descriptor FIFO.
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

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_packetizer_segmenter is
    generic (
        DataWidth_g  : positive := 32;
        ChunkBytes_g : positive := 4096;
        Crc_g        : boolean  := false
    );
    port (
        -- Control
        Clk        : in    std_logic;
        Rst        : in    std_logic;
        -- Data units
        S_Valid    : in    std_logic;
        S_Ready    : out   std_logic;
        S_Data     : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Keep     : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Last     : in    std_logic;
        S_Error    : in    std_logic;
        -- Beats of the segments into the segment buffer, Seg_Last on the last beat of a segment
        Seg_Valid  : out   std_logic;
        Seg_Ready  : in    std_logic;
        Seg_Data   : out   std_logic_vector(DataWidth_g - 1 downto 0);
        Seg_Last   : out   std_logic;
        -- Descriptors of the segments, one clock cycle after the last beat of their segment
        Desc_Valid : out   std_logic;
        Desc_Ready : in    std_logic;
        Desc_Data  : out   std_logic_vector(PkDescWidth_c - 1 downto 0);
        -- Accepted last beat with S_Error
        Aborted    : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_packetizer_segmenter is

    constant Bytes_c      : positive := DataWidth_g / 8;
    constant ChunkBeats_c : positive := ChunkBytes_g / Bytes_c;

    type TwoProcess_r is record
        -- Hold register: the latest beat of a data unit
        HValid   : std_logic;
        HData    : std_logic_vector(DataWidth_g - 1 downto 0);
        HBytes   : natural range 0 to Bytes_c;
        HLast    : std_logic;
        -- Current segment: beats and bytes already written, first segment of its data unit
        Beat     : natural range 0 to ChunkBeats_c - 1;
        Bytes    : unsigned(16 downto 0);
        First    : std_logic;
        -- Descriptor of the segment ended in the cycle before (its CRC follows one cycle later)
        DValid   : std_logic;
        DLen     : std_logic_vector(15 downto 0);
        DFirst   : std_logic;
        DLast    : std_logic;
        DCrc     : std_logic_vector(15 downto 0);
        DCrcKept : std_logic;
        Aborted  : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal Crc_InValid : std_logic;
    signal Crc_InLast  : std_logic;
    signal Crc_InBe    : std_logic_vector(Bytes_c - 1 downto 0);
    signal Crc_Out     : std_logic_vector(15 downto 0);

begin

    p_comb : process (all) is
        variable v          : TwoProcess_r;
        variable Block_v    : boolean;
        variable Crc_v      : std_logic_vector(15 downto 0);
        variable Null_v     : boolean;
        variable Decides_v  : boolean;
        variable WriteReq_v : boolean;
        variable Write_v    : boolean;
        variable SReady_v   : std_logic;
        variable Acc_v      : boolean;
        variable UnitEnd_v  : boolean;
        variable SegEnd_v   : boolean;
        variable Len_v      : unsigned(16 downto 0);
    begin
        -- Hold variables stable
        v         := r;
        v.Aborted := '0';

        -- Descriptor of the segment ended in the cycle before: the CRC of olo_base_crc is final now and
        -- is kept if the descriptor FIFO does not take the descriptor at once
        if r.DCrcKept = '1' or not Crc_g then
            Crc_v := r.DCrc;
        else
            Crc_v := Crc_Out;
        end if;

        if r.DValid = '1' then
            if Desc_Ready = '1' then
                v.DValid   := '0';
                v.DCrcKept := '0';
            else
                v.DCrc     := Crc_v;
                v.DCrcKept := '1';
            end if;
        end if;

        -- No segment ends while a descriptor waits for the descriptor FIFO
        Block_v := r.DValid = '1' and Desc_Ready = '0';

        -- A beat without bytes ends a data unit with S_Last (D15) and is ignored otherwise
        Null_v    := unsigned(S_Keep) = 0;
        Decides_v := S_Valid = '1' and (S_Last = '1' or not Null_v);

        -- The held beat is written when it ends its data unit or when the next beat shows how the data
        -- unit continues; the next beat is accepted in the same cycle (PT-SG-04)
        WriteReq_v := r.HValid = '1' and (r.HLast = '1' or Decides_v) and not Block_v;
        Write_v    := WriteReq_v and Seg_Ready = '1';

        if not Block_v and (r.HValid = '0' or Seg_Ready = '1') then
            SReady_v := '1';
        else
            SReady_v := '0';
        end if;
        Acc_v := S_Valid = '1' and SReady_v = '1';

        -- The held beat ends its data unit with its own S_Last or with a following beat without bytes
        UnitEnd_v := r.HLast = '1' or (S_Valid = '1' and S_Last = '1' and Null_v);
        SegEnd_v  := r.Beat = ChunkBeats_c - 1 or UnitEnd_v;
        Len_v     := r.Bytes + r.HBytes - 1;

        if Write_v then
            v.HValid := '0';
            if SegEnd_v then
                -- Segment complete: its descriptor follows in the next cycle with the CRC
                v.DValid   := '1';
                v.DLen     := std_logic_vector(Len_v(15 downto 0));
                v.DFirst   := r.First;
                v.DLast    := '1' when UnitEnd_v else '0';
                v.DCrcKept := '0';
                v.Beat     := 0;
                v.Bytes    := (others => '0');
                v.First    := '1' when UnitEnd_v else '0';
            else
                v.Beat  := r.Beat + 1;
                v.Bytes := r.Bytes + r.HBytes;
            end if;
        end if;

        -- Accepted beat: into the hold register unless it has no bytes
        if Acc_v then
            if S_Last = '1' and S_Error = '1' then
                v.Aborted := '1';                                             -- PT-SG-03
            end if;
            if not Null_v then
                v.HValid := '1';
                v.HData  := S_Data;
                v.HLast  := S_Last;
                -- A beat before a last beat without byte enables can be partial as well (D15)
                v.HBytes := bytesOfKeep(S_Keep);
            end if;
        end if;

        -- Outputs
        S_Ready    <= SReady_v;
        Seg_Valid  <= '1' when WriteReq_v else '0';
        Seg_Data   <= r.HData;
        Seg_Last   <= '1' when SegEnd_v else '0';
        Desc_Valid <= r.DValid;

        Desc_Data                <= (others => '0');
        Desc_Data(PkDescLen_t)   <= r.DLen;
        Desc_Data(PkDescFirst_c) <= r.DFirst;
        Desc_Data(PkDescLast_c)  <= r.DLast;
        Desc_Data(PkDescCrc_t)   <= Crc_v;

        -- CRC of every written beat, the last beat of a segment with its byte enables (olo_base_crc
        -- evaluates In_Last and In_Be also without In_Valid, so both are set only for a write)
        Crc_InValid <= '1' when Write_v else '0';
        Crc_InLast  <= '1' when Write_v and SegEnd_v else '0';
        if Write_v and SegEnd_v then
            Crc_InBe <= keepOfBytes(r.HBytes, Bytes_c);
        else
            Crc_InBe <= (others => '1');
        end if;

        -- Apply to record
        r_next <= v;
    end process;

    Aborted <= r.Aborted;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.HValid   <= '0';
                r.HBytes   <= 0;
                r.HLast    <= '0';
                r.Beat     <= 0;
                r.Bytes    <= (others => '0');
                r.First    <= '1';
                r.DValid   <= '0';
                r.DCrc     <= (others => '0');
                r.DCrcKept <= '0';
                r.Aborted  <= '0';
            end if;
        end if;
    end process;

    -- CRC of the segments (PT-CR-01): CRC-16 with generator x^16 + x^12 + x^5 + 1, initial value all
    -- ones, no final inversion, byte lane 0 first and the most significant bit of a byte first
    g_crc : if Crc_g generate

        i_crc : entity olo.olo_base_crc
            generic map (
                DataWidth_g    => DataWidth_g,
                Polynomial_g   => x"1021",
                InitialValue_g => x"FFFF",
                BitOrder_g     => "MSB_FIRST",
                ByteOrder_g    => "LSB_FIRST"
            )
            port map (
                Clk       => Clk,
                Rst       => Rst,
                In_Data   => r.HData,
                In_Valid  => Crc_InValid,
                In_Ready  => open,
                In_Last   => Crc_InLast,
                In_Be     => Crc_InBe,
                Out_Crc   => Crc_Out,
                Out_Valid => open
            );

    else generate

        Crc_Out <= (others => '0');

    end generate;

end architecture;
