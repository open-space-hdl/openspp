---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Packet assembly (SE-3): takes the SDU selected by the multiplexer, looks up the managed data path
-- of its APID in the send APID table, builds the Packet Primary Header of an Octet String with the
-- Packet Sequence Count or the Packet Name, and streams the Space Packet with its destination.
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

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_send_assembly is
    generic (
        DataWidth_g     : positive                                  := 32;
        NumTx_g         : positive                                  := 1;
        TxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0) := (others => '1')
    );
    port (
        -- Control
        Clk         : in    std_logic;
        Rst         : in    std_logic;
        -- Port selected by the multiplexer
        Grant       : in    std_logic_vector(NumTx_g - 1 downto 0);
        Grant_Valid : in    std_logic;
        Grant_Ack   : out   std_logic;
        -- Descriptors of the send buffers
        Desc_Ready  : out   std_logic_vector(NumTx_g - 1 downto 0);
        Desc_Data   : in    std_logic_vector(NumTx_g * TxDescWidth_c - 1 downto 0);
        Desc_Sec    : in    std_logic_vector(NumTx_g - 1 downto 0);
        Desc_Ded    : in    std_logic_vector(NumTx_g - 1 downto 0);
        -- SDUs of the send buffers
        Data_Valid  : in    std_logic_vector(NumTx_g - 1 downto 0);
        Data_Ready  : out   std_logic_vector(NumTx_g - 1 downto 0);
        Data_Data   : in    std_logic_vector(NumTx_g * DataWidth_g - 1 downto 0);
        Data_Last   : in    std_logic_vector(NumTx_g - 1 downto 0);
        Data_Next   : out   std_logic_vector(NumTx_g - 1 downto 0);
        Data_Sec    : in    std_logic_vector(NumTx_g - 1 downto 0);
        Data_Ded    : in    std_logic_vector(NumTx_g - 1 downto 0);
        -- Send APID table (client A)
        Tbl_Valid   : out   std_logic;
        Tbl_Ready   : in    std_logic;
        Tbl_Apid    : out   std_logic_vector(10 downto 0);
        Tbl_RdValid : in    std_logic;
        Tbl_RdData  : in    std_logic_vector(TxEntryWidth_c - 1 downto 0);
        Tbl_RdDed   : in    std_logic;
        Tbl_WrEna   : out   std_logic;
        Tbl_WrData  : out   std_logic_vector(TxEntryWidth_c - 1 downto 0);
        Tbl_Release : out   std_logic;
        -- Space Packets; TUser: error end of packet (bit 0), destination (bits 4:1)
        M_Valid     : out   std_logic;
        M_Ready     : in    std_logic;
        M_Data      : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Keep      : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Last      : out   std_logic;
        M_User      : out   std_logic_vector(LinkUserWidth_c - 1 downto 0);
        -- Events: discarded SDU, packet sent, ECC events of the words read (0: data, 1: descriptor)
        Err         : out   ErrEvent_t;
        Sent        : out   std_logic;
        Ecc_Sec     : out   std_logic_vector(1 downto 0);
        Ecc_Ded     : out   std_logic_vector(1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_send_assembly is

    constant Bytes_c : positive := DataWidth_g / 8;

    type PrepFsm_t is (PIdle_s, PTable_s, PRead_s, PWrite_s, PJob_s);

    type StreamFsm_t is (SIdle_s, SStream_s);

    type TwoProcess_r is record
        -- Preparation of the next packet (header, path)
        PState  : PrepFsm_t;
        PPort   : natural range 0 to NumTx_g - 1;
        PDesc   : std_logic_vector(TxDescWidth_c - 1 downto 0);
        PEntry  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
        PEntDed : std_logic;
        -- Prepared packet (job)
        JPort   : natural range 0 to NumTx_g - 1;
        JDrop   : std_logic;
        JHdrLen : std_logic_vector(2 downto 0);
        JHdr    : std_logic_vector(47 downto 0);
        JLen    : unsigned(LengthWidth_c - 1 downto 0);
        JDest   : std_logic_vector(3 downto 0);
        -- Packet in transfer
        SState  : StreamFsm_t;
        SPort   : natural range 0 to NumTx_g - 1;
        SDrop   : std_logic;
        SHdrLen : std_logic_vector(2 downto 0);
        SHdr    : std_logic_vector(47 downto 0);
        SRem    : unsigned(LengthWidth_c - 1 downto 0);
        SDest   : std_logic_vector(3 downto 0);
        SDed    : std_logic;
        -- Events
        Err     : ErrEvent_t;
        EccSec  : std_logic_vector(1 downto 0);
        EccDed  : std_logic_vector(1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- Descriptor of port p
    function selDesc (
        vec : std_logic_vector;
        p   : natural) return std_logic_vector is
        variable D_v : std_logic_vector(TxDescWidth_c - 1 downto 0) := (others => '0');
    begin

        for i in 0 to NumTx_g - 1 loop
            if i = p then
                D_v := vec((i + 1) * TxDescWidth_c - 1 downto i * TxDescWidth_c);
            end if;
        end loop;

        return D_v;
    end function;

    -- Data beat of port p
    function selData (
        vec : std_logic_vector;
        p   : natural) return std_logic_vector is
        variable D_v : std_logic_vector(DataWidth_g - 1 downto 0) := (others => '0');
    begin

        for i in 0 to NumTx_g - 1 loop
            if i = p then
                D_v := vec((i + 1) * DataWidth_g - 1 downto i * DataWidth_g);
            end if;
        end loop;

        return D_v;
    end function;

    -- Header insertion
    signal Ins_Valid  : std_logic;
    signal Ins_Ready  : std_logic;
    signal Ins_Data   : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Ins_Keep   : std_logic_vector(Bytes_c - 1 downto 0);
    signal Ins_Last   : std_logic;
    signal Ins_User   : std_logic_vector(LinkUserWidth_c - 1 downto 0);
    signal M_ValidInt : std_logic;
    signal M_LastInt  : std_logic;
    signal M_UserInt  : std_logic_vector(LinkUserWidth_c - 1 downto 0);

begin

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable P_v     : natural range 0 to NumTx_g - 1;
        variable User_v  : std_logic_vector(TxUserWidth_c - 1 downto 0);
        variable Apid_v  : std_logic_vector(10 downto 0);
        variable Field_v : std_logic_vector(13 downto 0);
        variable Entry_v : std_logic_vector(TxEntryWidth_c - 1 downto 0);
        variable Pdl_v   : unsigned(LengthWidth_c - 1 downto 0);
        variable Final_v : std_logic;
    begin
        -- Hold variables stable
        v        := r;
        v.Err    := ErrEventNone_c;
        v.EccSec := "00";
        v.EccDed := "00";

        -- Defaults
        Grant_Ack   <= '0';
        Desc_Ready  <= (others => '0');
        Data_Ready  <= (others => '0');
        Data_Next   <= (others => '0');
        Tbl_Valid   <= '0';
        Tbl_WrEna   <= '0';
        Tbl_Release <= '0';
        Ins_Valid   <= '0';

        User_v     := r.PDesc(TxDescUser_t);
        Apid_v     := User_v(TxUserApid_t);
        Tbl_Apid   <= Apid_v;
        Entry_v    := r.PEntry;
        Tbl_WrData <= Entry_v;

        -------------------------------------------------------------------------------------------
        -- Preparation: descriptor, managed data path, header
        -------------------------------------------------------------------------------------------
        case r.PState is

            when PIdle_s =>
                if Grant_Valid = '1' then
                    -- Port of the one-hot grant
                    P_v := 0;

                    for i in 0 to NumTx_g - 1 loop
                        if Grant(i) = '1' then
                            P_v := i;
                        end if;
                    end loop;

                    Grant_Ack       <= '1';
                    Desc_Ready(P_v) <= '1';
                    v.PPort         := P_v;
                    v.PDesc         := selDesc(Desc_Data, P_v);
                    v.EccSec(1)     := Desc_Sec(P_v);
                    v.EccDed(1)     := Desc_Ded(P_v);
                    v.JPort         := P_v;
                    v.JLen          := unsigned(v.PDesc(TxDescLen_t));
                    if Desc_Ded(P_v) = '1' then
                        -- Descriptor unreliable: the SDU is discarded
                        v.JDrop     := '1';
                        v.Err.Valid := '1';
                        v.Err.Code  := ErrTxBuffer_c;
                        v.Err.Index := std_logic_vector(to_unsigned(P_v, 4));
                        v.Err.Apid  := (others => '0');
                        v.PState    := PJob_s;
                    else
                        v.PState := PTable_s;
                    end if;
                end if;

            when PTable_s =>
                -- Entry of the APID (SPP 4.2.3.3)
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
                v.JDest   := Entry_v(TxEntryDest_t);
                v.JDrop   := '0';
                v.JHdrLen := "000";
                v.PState  := PJob_s;
                if r.PEntDed = '1' or Entry_v(TxEntryEnable_c) = '0' then
                    -- No reliable entry or no managed data path: the SDU is discarded
                    Tbl_Release <= '1';
                    v.JDrop     := '1';
                    v.Err.Valid := '1';
                    v.Err.Index := std_logic_vector(to_unsigned(r.PPort, 4));
                    v.Err.Apid  := Apid_v;
                    if r.PEntDed = '1' then
                        v.Err.Code := ErrTxBuffer_c;
                    else
                        v.Err.Code := ErrTxNoPath_c;
                    end if;
                elsif TxOctetString_g(r.PPort) = '1' then
                    -- Packet Assembly Function (SPP 4.2.2): Packet Sequence Count of the APID, or the Packet Name
                    -- of a telecommand packet (SPP 4.1.3.4.3.2)
                    if User_v(TxUserType_c) = '1' and User_v(TxUserNameValid_c) = '1' then
                        Field_v     := User_v(TxUserName_t);
                        Tbl_Release <= '1';
                    else
                        Field_v                 := Entry_v(TxEntryCount_t);
                        Entry_v(TxEntryCount_t) := std_logic_vector(unsigned(Entry_v(TxEntryCount_t)) + 1); -- SPP 4.1.3.4.3.4
                        Tbl_WrData              <= Entry_v;
                        Tbl_WrEna               <= '1';
                    end if;
                    Pdl_v     := r.JLen - 1;   -- SPP 4.1.3.5.3: the Packet Data Field is the Octet String
                    v.JHdr    := primaryHeader(User_v(TxUserType_c), User_v(TxUserShi_c), Apid_v, Unsegmented_c,
                                               Field_v, std_logic_vector(Pdl_v(15 downto 0)));
                    v.JHdrLen := "110";
                else
                    -- Packet Service: the Space Packet is transferred intact (SPP 3.3.1)
                    Tbl_Release <= '1';
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
        -- Transfer of the prepared packet
        -------------------------------------------------------------------------------------------
        P_v := r.SPort;

        -- The beat with the last bytes of the SDU ends the packet; a stored beat after it carries no byte (a last beat
        -- without byte enables) and is skipped
        if r.SRem <= Bytes_c then
            Final_v := '1';
        else
            Final_v := '0';
        end if;

        case r.SState is

            when SIdle_s =>
                if r.PState = PJob_s then
                    v.SPort   := r.JPort;
                    v.SDrop   := r.JDrop;
                    v.SHdrLen := r.JHdrLen;
                    v.SHdr    := r.JHdr;
                    v.SRem    := r.JLen;
                    v.SDest   := r.JDest;
                    v.SDed    := '0';
                    v.SState  := SStream_s;
                end if;

            when SStream_s =>
                if r.SDrop = '1' then
                    -- Discarded SDU: skipped in the send buffer
                    Data_Ready(P_v) <= '1';
                    Data_Next(P_v)  <= '1';
                    if Data_Valid(P_v) = '1' and Data_Last(P_v) = '1' then
                        v.SState := SIdle_s;
                    end if;
                else
                    Ins_Valid       <= Data_Valid(P_v);
                    Data_Ready(P_v) <= Ins_Ready;
                    if Data_Valid(P_v) = '1' and Ins_Ready = '1' then
                        v.SDed      := r.SDed or Data_Ded(P_v);
                        v.EccSec(0) := Data_Sec(P_v);
                        v.EccDed(0) := Data_Ded(P_v);
                        if r.SRem > Bytes_c then
                            v.SRem := r.SRem - Bytes_c;
                        else
                            v.SRem := (others => '0');
                        end if;
                        if Data_Last(P_v) = '1' then
                            v.SState := SIdle_s;
                        elsif Final_v = '1' then
                            -- Beats without bytes follow: skipped like a discarded SDU
                            v.SDrop := '1';
                        end if;
                    end if;
                end if;

            -- coverage off
            when others =>
                v.SState := SIdle_s;
            -- coverage on

        end case;

        -- Beat of the selected send buffer
        Ins_Data <= selData(Data_Data, P_v);
        Ins_Last <= Final_v;
        if r.SRem >= Bytes_c then
            Ins_Keep <= (others => '1');
        else
            Ins_Keep <= keepOfBytes(to_integer(r.SRem), Bytes_c);
        end if;
        -- A double error in any word of the SDU ends the packet with an EEP (D11), flagged with the last beat
        Ins_User(LinkUserEep_c)  <= (r.SDed or Data_Ded(P_v)) and Final_v;
        Ins_User(LinkUserDest_t) <= r.SDest;

        -- Apply to record
        r_next <= v;
    end process;

    Err     <= r.Err;
    Ecc_Sec <= r.EccSec;
    Ecc_Ded <= r.EccDed;
    M_Valid <= M_ValidInt;
    -- The EEP flag is defined with the last beat only
    M_User <= M_UserInt(LinkUserDest_t) & (M_UserInt(LinkUserEep_c) and M_LastInt);
    M_Last <= M_LastInt;
    Sent   <= M_ValidInt and M_Ready and M_LastInt;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.PState    <= PIdle_s;
                r.PDesc     <= (others => '0');
                r.PEntry    <= (others => '0');
                r.JHdrLen   <= "000";
                r.JLen      <= (others => '0');
                r.SState    <= SIdle_s;
                r.SHdrLen   <= "000";
                r.SRem      <= (others => '0');
                r.Err.Valid <= '0';
                r.EccSec    <= "00";
                r.EccDed    <= "00";
            end if;
        end if;
    end process;

    -- Packet Primary Header in front of an Octet String
    i_insert : entity work.spp_header_insert
        generic map (
            DataWidth_g      => DataWidth_g,
            MaxHeaderBytes_g => PrimaryHeaderBytes_c,
            UserWidth_g      => LinkUserWidth_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => Ins_Valid,
            In_Ready       => Ins_Ready,
            In_Data        => Ins_Data,
            In_Keep        => Ins_Keep,
            In_Last        => Ins_Last,
            In_User        => Ins_User,
            In_Header      => r.SHdr,
            In_HeaderBytes => r.SHdrLen,
            Out_Valid      => M_ValidInt,
            Out_Ready      => M_Ready,
            Out_Data       => M_Data,
            Out_Keep       => M_Keep,
            Out_Last       => M_LastInt,
            Out_User       => M_UserInt
        );

end architecture;
