---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Demultiplexer (RE-2) of the Packet Reception Function: looks up the user port and the managed data
-- path of every received Space Packet in the receive APID table, checks the continuity of its Packet
-- Sequence Count and routes it with its indication parameters to the user port.
--
-- Documentation: hdl/spp_receive/docs/architecture.md

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
entity spp_receive_demux is
    generic (
        DataWidth_g     : positive                                  := 32;
        NumRx_g         : positive                                  := 1;
        RxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0) := (others => '1')
    );
    port (
        -- Control
        Clk         : in    std_logic;
        Rst         : in    std_logic;
        -- Descriptors of the reception
        Desc_Valid  : in    std_logic;
        Desc_Ready  : out   std_logic;
        Desc_Data   : in    std_logic_vector(RxDescWidth_c - 1 downto 0);
        Desc_Sec    : in    std_logic;
        Desc_Ded    : in    std_logic;
        -- Packets of the reception
        Data_Valid  : in    std_logic;
        Data_Ready  : out   std_logic;
        Data_Data   : in    std_logic_vector(DataWidth_g - 1 downto 0);
        Data_Last   : in    std_logic;
        Data_Next   : out   std_logic;
        Data_Sec    : in    std_logic;
        Data_Ded    : in    std_logic;
        -- Receive APID table (client A)
        Tbl_Valid   : out   std_logic;
        Tbl_Ready   : in    std_logic;
        Tbl_Apid    : out   std_logic_vector(10 downto 0);
        Tbl_RdValid : in    std_logic;
        Tbl_RdData  : in    std_logic_vector(RxEntryWidth_c - 1 downto 0);
        Tbl_RdDed   : in    std_logic;
        Tbl_WrEna   : out   std_logic;
        Tbl_WrData  : out   std_logic_vector(RxEntryWidth_c - 1 downto 0);
        Tbl_Release : out   std_logic;
        -- Packets routed to the user ports (valid and ready per port, the rest shared)
        Out_Valid   : out   std_logic_vector(NumRx_g - 1 downto 0);
        Out_Ready   : in    std_logic_vector(NumRx_g - 1 downto 0);
        Out_Data    : out   std_logic_vector(DataWidth_g - 1 downto 0);
        Out_Keep    : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        Out_Last    : out   std_logic;
        Out_User    : out   std_logic_vector(RxUserWidth_c - 1 downto 0);
        -- Events: discarded packets, loss indicator set, ECC events of the words read (0: data, 1: descriptor)
        Err         : out   ErrEvent_t;
        Loss        : out   std_logic;
        Ecc_Sec     : out   std_logic_vector(1 downto 0);
        Ecc_Ded     : out   std_logic_vector(1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_receive_demux is

    constant Bytes_c : positive := DataWidth_g / 8;

    type PrepFsm_t is (PIdle_s, PTable_s, PRead_s, PWrite_s, PJob_s);

    type StreamFsm_t is (SIdle_s, SStream_s);

    type TwoProcess_r is record
        -- Preparation of the next packet
        PState  : PrepFsm_t;
        PDesc   : std_logic_vector(RxDescWidth_c - 1 downto 0);
        PEntry  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
        PEntDed : std_logic;
        -- Prepared packet (job)
        JPort   : natural range 0 to NumRx_g - 1;
        JDrop   : std_logic;
        JLen    : unsigned(LengthWidth_c - 1 downto 0);
        JUser   : std_logic_vector(RxUserWidth_c - 1 downto 0);
        -- Packet in transfer
        SState  : StreamFsm_t;
        SPort   : natural range 0 to NumRx_g - 1;
        SDrop   : std_logic;
        SRem    : unsigned(LengthWidth_c - 1 downto 0);
        SUser   : std_logic_vector(RxUserWidth_c - 1 downto 0);
        SDed    : std_logic;
        -- Events
        Err     : ErrEvent_t;
        Loss    : std_logic;
        EccSec  : std_logic_vector(1 downto 0);
        EccDed  : std_logic_vector(1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Hdr_v   : std_logic_vector(47 downto 0);
        variable Apid_v  : std_logic_vector(10 downto 0);
        variable Count_v : std_logic_vector(13 downto 0);
        variable Entry_v : std_logic_vector(RxEntryWidth_c - 1 downto 0);
        variable Port_v  : natural range 0 to 15;
        variable Next_v  : unsigned(13 downto 0);
        variable Ready_v : std_logic;
    begin
        -- Hold variables stable
        v        := r;
        v.Err    := ErrEventNone_c;
        v.Loss   := '0';
        v.EccSec := "00";
        v.EccDed := "00";

        -- Defaults
        Desc_Ready  <= '0';
        Data_Ready  <= '0';
        Data_Next   <= '0';
        Tbl_Valid   <= '0';
        Tbl_WrEna   <= '0';
        Tbl_Release <= '0';
        Out_Valid   <= (others => '0');

        Hdr_v      := r.PDesc(RxDescHdr_t);
        Apid_v     := hdrApid(Hdr_v);
        Count_v    := hdrCount(Hdr_v);
        Entry_v    := r.PEntry;
        Port_v     := to_integer(unsigned(Entry_v(RxEntryPort_t)));
        Tbl_Apid   <= Apid_v;
        Tbl_WrData <= Entry_v;

        -------------------------------------------------------------------------------------------
        -- Preparation: descriptor, user port and managed data path, continuity
        -------------------------------------------------------------------------------------------
        case r.PState is

            when PIdle_s =>
                if Desc_Valid = '1' then
                    Desc_Ready  <= '1';
                    v.PDesc     := Desc_Data;
                    v.JLen      := unsigned(Desc_Data(RxDescLen_t));
                    v.EccSec(1) := Desc_Sec;
                    v.EccDed(1) := Desc_Ded;
                    if Desc_Ded = '1' then
                        -- Descriptor unreliable: the packet is discarded
                        v.JDrop     := '1';
                        v.JPort     := 0;
                        v.Err.Valid := '1';
                        v.Err.Code  := ErrRxBuffer_c;
                        v.Err.Index := (others => '0');
                        v.Err.Apid  := (others => '0');
                        v.PState    := PJob_s;
                    else
                        v.PState := PTable_s;
                    end if;
                end if;

            when PTable_s =>
                -- Entry of the APID (SPP 4.3.3.2)
                Tbl_Valid <= '1';
                if Tbl_Ready = '1' then
                    v.PState := PRead_s;
                end if;

            when PRead_s =>
                if Tbl_RdValid = '1' then
                    v.PEntry  := Tbl_RdData;
                    v.PEntDed := Tbl_RdDed;
                    v.PState  := PWrite_s;
                end if;

            when PWrite_s =>
                v.PState    := PJob_s;
                v.JDrop     := '1';
                v.JPort     := 0;
                v.Err.Index := std_logic_vector(to_unsigned(Port_v, 4));
                v.Err.Apid  := Apid_v;
                if r.PEntDed = '1' then
                    Tbl_Release <= '1';
                    v.Err.Valid := '1';
                    v.Err.Code  := ErrRxBuffer_c;
                elsif Entry_v(RxEntryEnable_c) = '0' or Port_v >= NumRx_g then
                    -- No managed data path to a user port
                    Tbl_Release <= '1';
                    v.Err.Valid := '1';
                    v.Err.Code  := ErrRxNoPath_c;
                elsif RxOctetString_g(Port_v) = '1' and hdrFlags(Hdr_v) /= Unsegmented_c then
                    -- Segmented User Data cannot be delivered as an Octet String (SPP 4.1.3.4.2.3)
                    Tbl_Release <= '1';
                    v.Err.Valid := '1';
                    v.Err.Code  := ErrRxFlags_c;
                else
                    v.JDrop := '0';
                    v.JPort := Port_v;
                    -- Indication parameters; the loss indicator from the continuity of the count (SPP 3.3.2.3,
                    -- 3.4.2.4): a count other than the last one plus one, modulo 16384
                    v.JUser               := (others => '0');
                    v.JUser(RxUserApid_t) := Apid_v;
                    v.JUser(RxUserShi_c)  := hdrShf(Hdr_v);
                    v.JUser(RxUserUa_t)   := r.PDesc(RxDescUa_t);
                    Next_v                := unsigned(Entry_v(RxEntryLast_t)) + 1;
                    if Entry_v(RxEntryCheck_c) = '1' and Entry_v(RxEntryValid_c) = '1' and
                       unsigned(Count_v) /= Next_v then
                        v.JUser(RxUserLoss_c) := '1';
                        v.Loss                := '1';
                    end if;
                    if Entry_v(RxEntryCheck_c) = '1' then
                        Entry_v(RxEntryLast_t)  := Count_v;
                        Entry_v(RxEntryValid_c) := '1';
                        Tbl_WrData              <= Entry_v;
                        Tbl_WrEna               <= '1';
                    else
                        Tbl_Release <= '1';
                    end if;
                end if;

            when PJob_s =>
                -- Taken by the transfer below as soon as it is idle
                if r.SState = SIdle_s then
                    v.PState := PIdle_s;
                end if;

            -- coverage off
            when others =>
                v.PState := PIdle_s;
            -- coverage on

        end case;

        -------------------------------------------------------------------------------------------
        -- Transfer of the prepared packet to its user port
        -------------------------------------------------------------------------------------------
        Ready_v := Out_Ready(r.SPort);

        case r.SState is

            when SIdle_s =>
                if r.PState = PJob_s then
                    v.SPort  := r.JPort;
                    v.SDrop  := r.JDrop;
                    v.SRem   := r.JLen;
                    v.SUser  := r.JUser;
                    v.SDed   := '0';
                    v.SState := SStream_s;
                end if;

            when SStream_s =>
                if r.SDrop = '1' then
                    -- Discarded packet: skipped in the buffer
                    Data_Ready <= '1';
                    Data_Next  <= '1';
                    if Data_Valid = '1' and Data_Last = '1' then
                        v.SState := SIdle_s;
                    end if;
                else
                    Out_Valid(r.SPort) <= Data_Valid;
                    Data_Ready         <= Ready_v;
                    if Data_Valid = '1' and Ready_v = '1' then
                        v.SDed      := r.SDed or Data_Ded;
                        v.EccSec(0) := Data_Sec;
                        v.EccDed(0) := Data_Ded;
                        if r.SRem > Bytes_c then
                            v.SRem := r.SRem - Bytes_c;
                        else
                            v.SRem := (others => '0');
                        end if;
                        if Data_Last = '1' then
                            v.SState := SIdle_s;
                        end if;
                    end if;
                end if;

            -- coverage off
            when others =>
                v.SState := SIdle_s;
            -- coverage on

        end case;

        -- Beat of the packet in transfer
        Out_Data <= Data_Data;
        Out_Last <= Data_Last;
        if r.SRem >= Bytes_c then
            Out_Keep <= (others => '1');
        else
            Out_Keep <= keepOfBytes(to_integer(r.SRem), Bytes_c);
        end if;
        Out_User <= r.SUser;
        -- A double error in any word of the packet is flagged with the last beat (D11)
        Out_User(RxUserError_c) <= (r.SDed or Data_Ded) and Data_Last;

        -- Apply to record
        r_next <= v;
    end process;

    Err     <= r.Err;
    Loss    <= r.Loss;
    Ecc_Sec <= r.EccSec;
    Ecc_Ded <= r.EccDed;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.PState    <= PIdle_s;
                r.SState    <= SIdle_s;
                r.SPort     <= 0;
                r.Err.Valid <= '0';
                r.Loss      <= '0';
                r.EccSec    <= "00";
                r.EccDed    <= "00";
            end if;
        end if;
    end process;

end architecture;
