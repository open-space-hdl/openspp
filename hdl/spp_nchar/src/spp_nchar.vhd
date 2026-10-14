---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- N-Char adapter (AD-1): converts the link streams of the core to and from the N-Char packet stream of
-- a SpaceWire port of OpenWire (one character per beat, the end of packet marker as a separate beat).
--
-- Documentation: hdl/spp_nchar/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_nchar is
    generic (
        DataWidth_g : positive range 8 to 128 := 32
    );
    port (
        -- Control
        Clk           : in    std_logic;
        Rst           : in    std_logic;
        -- Link stream from the core (its M_Link); TUser: error end of packet (bit 0, last beat), destination (4:1)
        S_Link_Valid  : in    std_logic;
        S_Link_Ready  : out   std_logic;
        S_Link_Data   : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Link_Keep   : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Link_Last   : in    std_logic;
        S_Link_User   : in    std_logic_vector(LinkUserWidth_c - 1 downto 0);
        -- N-Char stream to the SpaceWire port: data characters, then the marker with TLast ('0' EOP, '1' EEP)
        M_NChar_Valid : out   std_logic;
        M_NChar_Ready : in    std_logic;
        M_NChar_Data  : out   std_logic_vector(7 downto 0);
        M_NChar_Last  : out   std_logic;
        -- N-Char stream from the SpaceWire port
        S_NChar_Valid : in    std_logic;
        S_NChar_Ready : out   std_logic;
        S_NChar_Data  : in    std_logic_vector(7 downto 0);
        S_NChar_Last  : in    std_logic;
        -- Link stream to the core (its S_Link); TUser: error end of packet (last beat)
        M_Link_Valid  : out   std_logic;
        M_Link_Ready  : in    std_logic;
        M_Link_Data   : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Link_Keep   : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Link_Last   : out   std_logic;
        M_Link_User   : out   std_logic_vector(0 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_nchar is

    constant Bytes_c : positive := DataWidth_g / 8;

    type TwoProcess_r is record
        -- Transmit: a packet end is in the converter (input blocked until its marker is sent), its EEP flag
        TxEnd    : std_logic;
        TxEep    : std_logic;
        TxMarker : std_logic;
        -- Transmit: the packet ended with a last beat without bytes (marker after the converter is empty); a data
        -- character of the packet was sent
        TxNull   : std_logic;
        TxData   : std_logic;
        -- Receive: the character held back until the next one shows whether it is the last
        RxHeld   : std_logic;
        RxData   : std_logic_vector(7 downto 0);
        RxEep    : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

    signal TxConv_InValid  : std_logic;
    signal TxConv_InReady  : std_logic;
    signal TxConv_OutValid : std_logic;
    signal TxConv_OutReady : std_logic;
    signal TxConv_OutData  : std_logic_vector(7 downto 0);
    signal TxConv_OutLast  : std_logic;
    signal RxConv_InValid  : std_logic;
    signal RxConv_InReady  : std_logic;
    signal RxConv_InData   : std_logic_vector(7 downto 0);
    signal RxConv_InLast   : std_logic;
    signal RxConv_OutValid : std_logic;
    signal RxConv_OutLast  : std_logic;
    signal RxConv_WordEna  : std_logic_vector(Bytes_c - 1 downto 0);

begin

    p_comb : process (all) is
        variable v        : TwoProcess_r;
        variable EepNow_v : std_logic;
        variable Null_v   : std_logic;
    begin
        -- Hold variables stable
        v        := r;
        EepNow_v := '0';

        -------------------------------------------------------------------------------------------
        -- Transmit: bytes of the beats, then the end of packet marker
        -------------------------------------------------------------------------------------------
        -- A beat enters the converter only when no packet end waits for its marker. A last beat without bytes
        -- (AXI4-Stream null bytes) does not enter it: its marker follows the bytes of the earlier beats.
        if S_Link_Last = '1' and S_Link_Keep = (S_Link_Keep'range => '0') then
            Null_v := '1';
        else
            Null_v := '0';
        end if;
        TxConv_InValid <= S_Link_Valid and not r.TxEnd and not Null_v;
        S_Link_Ready   <= (TxConv_InReady or Null_v) and not r.TxEnd;
        if S_Link_Valid = '1' and (TxConv_InReady = '1' or Null_v = '1') and r.TxEnd = '0' and S_Link_Last = '1' then
            v.TxEnd  := '1';
            v.TxEep  := S_Link_User(LinkUserEep_c);
            v.TxNull := Null_v;
        end if;

        if r.TxMarker = '1' then
            -- End of packet marker
            M_NChar_Valid   <= '1';
            M_NChar_Data    <= "0000000" & r.TxEep;
            M_NChar_Last    <= '1';
            TxConv_OutReady <= '0';
            if M_NChar_Ready = '1' then
                v.TxMarker := '0';
                v.TxEnd    := '0';
                v.TxData   := '0';
            end if;
        else
            -- Data character
            M_NChar_Valid   <= TxConv_OutValid;
            M_NChar_Data    <= TxConv_OutData;
            M_NChar_Last    <= '0';
            TxConv_OutReady <= M_NChar_Ready;
            if TxConv_OutValid = '1' and M_NChar_Ready = '1' then
                v.TxData := '1';
                if TxConv_OutLast = '1' then
                    v.TxMarker := '1';
                end if;
            end if;
            -- Packet ended by a last beat without bytes: the marker once the converter is empty; a packet without
            -- any byte sends nothing (no packet of zero length)
            if r.TxNull = '1' and TxConv_OutValid = '0' then
                v.TxNull := '0';
                if r.TxData = '1' then
                    v.TxMarker := '1';
                else
                    v.TxEnd := '0';
                end if;
            end if;
        end if;

        -------------------------------------------------------------------------------------------
        -- Receive: a data character is passed on when the next character arrives; with the marker it is
        -- the last byte of the packet. A marker without a data character is discarded.
        -------------------------------------------------------------------------------------------
        -- The EEP flag belongs to the last beat of the packet; it is cleared with that beat (before the flag of
        -- the next packet can be set in the same cycle)
        if RxConv_OutValid = '1' and M_Link_Ready = '1' and RxConv_OutLast = '1' then
            v.RxEep := '0';
        end if;

        RxConv_InValid <= '0';
        RxConv_InData  <= r.RxData;
        RxConv_InLast  <= S_NChar_Last;
        S_NChar_Ready  <= '0';
        if S_NChar_Valid = '1' then
            if r.RxHeld = '0' then
                -- Nothing held: take a data character, drop a marker of an empty packet
                S_NChar_Ready <= '1';
                if S_NChar_Last = '0' then
                    v.RxHeld := '1';
                    v.RxData := S_NChar_Data;
                end if;
            else
                -- Pass the held character on, as the last one when a marker follows
                RxConv_InValid <= '1';
                S_NChar_Ready  <= RxConv_InReady;
                if RxConv_InReady = '1' then
                    if S_NChar_Last = '1' then
                        v.RxHeld := '0';
                        v.RxEep  := S_NChar_Data(0);
                        EepNow_v := S_NChar_Data(0);
                    else
                        v.RxData := S_NChar_Data;
                    end if;
                end if;
            end if;
        end if;

        -- Error end of packet flag of the last beat: at 8 bits the converter passes the character in the same
        -- cycle, at wider streams the beat leaves the converter after the flag was registered
        if DataWidth_g = 8 then
            M_Link_User(0) <= EepNow_v and RxConv_OutLast;
        else
            M_Link_User(0) <= r.RxEep and RxConv_OutLast;
        end if;

        -- Apply to record
        r_next <= v;
    end process;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.TxEnd    <= '0';
                r.TxEep    <= '0';
                r.TxMarker <= '0';
                r.TxNull   <= '0';
                r.TxData   <= '0';
                r.RxHeld   <= '0';
                r.RxEep    <= '0';
            end if;
        end if;
    end process;

    -- Bytes of the link beats, the last one flagged (byte enables as word enables of the converter)
    i_tx : entity olo.olo_base_wconv_xn2n
        generic map (
            InWidth_g  => DataWidth_g,
            OutWidth_g => 8
        )
        port map (
            Clk        => Clk,
            Rst        => Rst,
            In_Valid   => TxConv_InValid,
            In_Ready   => TxConv_InReady,
            In_Data    => S_Link_Data,
            In_Last    => S_Link_Last,
            In_WordEna => S_Link_Keep,
            Out_Valid  => TxConv_OutValid,
            Out_Ready  => TxConv_OutReady,
            Out_Data   => TxConv_OutData,
            Out_Last   => TxConv_OutLast
        );

    -- Link beats of the received characters
    i_rx : entity olo.olo_base_wconv_n2xn
        generic map (
            InWidth_g  => 8,
            OutWidth_g => DataWidth_g
        )
        port map (
            Clk         => Clk,
            Rst         => Rst,
            In_Valid    => RxConv_InValid,
            In_Ready    => RxConv_InReady,
            In_Data     => RxConv_InData,
            In_Last     => RxConv_InLast,
            Out_Valid   => RxConv_OutValid,
            Out_Ready   => M_Link_Ready,
            Out_Data    => M_Link_Data,
            Out_Last    => RxConv_OutLast,
            Out_WordEna => RxConv_WordEna
        );

    M_Link_Valid <= RxConv_OutValid;
    M_Link_Last  <= RxConv_OutLast;
    M_Link_Keep  <= RxConv_WordEna;

end architecture;
