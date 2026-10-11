---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Register file of OpenSPP (MG-1, MG-2): managed parameters, destinations, access to the APID tables,
-- counters per error reason and of the packets, event flags with interrupt and the EDAC monitor of the
-- buffers and tables, behind an AXI4-Lite slave. The register map is generated from
-- hdl/spp_mib/regs/spp_regs.yml.
--
-- Documentation: hdl/spp_mib/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;

library work;
    use work.spp_pkg.all;
    use work.spp_regs_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_mib is
    generic (
        DataWidth_g     : positive                                  := 32;
        NumTx_g         : positive range 1 to MaxPorts_c            := 1;
        NumRx_g         : positive range 1 to MaxPorts_c            := 1;
        NumDest_g       : positive range 1 to MaxDest_c             := 1;
        SpwAddrBytes_g  : natural range 0 to MaxSpwAddrBytes_c      := 4;
        Encapsulation_g : boolean                                   := true;
        TxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0) := (others => '1');
        RxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0) := (others => '1');
        TxBufferBytes_g : positive                                  := 4096;
        RxBufferBytes_g : positive                                  := 4096;
        MaxLength_g     : positive range 7 to 65542                 := 65542;
        RoundRobin_g    : std_logic                                 := '0';
        Tla_g           : std_logic_vector(7 downto 0)              := x"FE";
        NumErr_g        : positive                                  := 5
    );
    port (
        -- Control
        Clk               : in    std_logic;
        Rst               : in    std_logic;
        -- AXI4-Lite
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
        -- Managed parameters
        Cfg_MaxLength     : out   std_logic_vector(LengthWidth_c - 1 downto 0);
        Cfg_RoundRobin    : out   std_logic;
        Cfg_IdleDeliver   : out   std_logic;
        Cfg_TlaCheck      : out   std_logic;
        Cfg_RxStrip       : out   std_logic_vector(3 downto 0);
        Cfg_Tla           : out   std_logic_vector(7 downto 0);
        Cfg_DestAddr      : out   std_logic_vector(NumDest_g * 8 * maximum(SpwAddrBytes_g, 1) - 1 downto 0);
        Cfg_DestAddrLen   : out   std_logic_vector(NumDest_g * 5 - 1 downto 0);
        Cfg_DestTla       : out   std_logic_vector(NumDest_g * 8 - 1 downto 0);
        Cfg_DestUa        : out   std_logic_vector(NumDest_g * 8 - 1 downto 0);
        Cfg_ScrubEnable   : out   std_logic;
        -- Send APID table (client B)
        TxTbl_Valid       : out   std_logic;
        TxTbl_Ready       : in    std_logic;
        TxTbl_Apid        : out   std_logic_vector(10 downto 0);
        TxTbl_RdValid     : in    std_logic;
        TxTbl_RdData      : in    std_logic_vector(TxEntryWidth_c - 1 downto 0);
        TxTbl_RdDed       : in    std_logic;
        TxTbl_WrEna       : out   std_logic;
        TxTbl_WrData      : out   std_logic_vector(TxEntryWidth_c - 1 downto 0);
        TxTbl_Release     : out   std_logic;
        TxTbl_Busy        : in    std_logic;
        -- Receive APID table (client B)
        RxTbl_Valid       : out   std_logic;
        RxTbl_Ready       : in    std_logic;
        RxTbl_Apid        : out   std_logic_vector(10 downto 0);
        RxTbl_RdValid     : in    std_logic;
        RxTbl_RdData      : in    std_logic_vector(RxEntryWidth_c - 1 downto 0);
        RxTbl_RdDed       : in    std_logic;
        RxTbl_WrEna       : out   std_logic;
        RxTbl_WrData      : out   std_logic_vector(RxEntryWidth_c - 1 downto 0);
        RxTbl_Release     : out   std_logic;
        RxTbl_Busy        : in    std_logic;
        -- Events of the sending end, the transfer layer and the receiving end
        Err               : in    ErrEventArray_t(0 to NumErr_g - 1);
        Tx_Sent           : in    std_logic;
        Rx_Delivered      : in    std_logic_vector(NumRx_g - 1 downto 0);
        Rx_Loss           : in    std_logic;
        -- Last error event (one-cycle, the event of the lowest index when several occur in one cycle)
        Err_Valid         : out   std_logic;
        Err_Code          : out   std_logic_vector(4 downto 0);
        Err_Port          : out   std_logic_vector(3 downto 0);
        Err_Apid          : out   std_logic_vector(10 downto 0);
        -- ECC events of the 8 channels and error injection
        Ecc_Sec           : in    std_logic_vector(7 downto 0);
        Ecc_Ded           : in    std_logic_vector(7 downto 0);
        Inj_TxValid       : out   std_logic;
        Inj_RxValid       : out   std_logic;
        Inj_Channel       : out   std_logic_vector(5 downto 0);
        Inj_Double        : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_mib is

    constant AddrBytes_c  : positive := maximum(SpwAddrBytes_g, 1);
    constant EntryWidth_c : positive := RxEntryWidth_c;

    -- Error counters (16 bits), indexed by the error code
    type ErrCnt_t is array (0 to 31) of unsigned(15 downto 0);

    -- Error counter registers: two codes per register (bits 15:0, bits 31:16)
    type CodeArray_t is array (natural range <>) of natural;

    constant ErrRegs_c   : CodeArray_t(0 to 9) := (RegErrTx1_c, RegErrTx2_c, RegErrTx3_c, RegErrTx4_c, RegErrRx1_c,
                                                   RegErrRx2_c, RegErrRx3_c, RegErrRx4_c, RegErrRx5_c, RegErrRx6_c);
    constant ErrCodeLo_c : CodeArray_t(0 to 9) := (16#01#, 16#03#, 16#05#, 16#07#, 16#10#, 16#12#, 16#14#, 16#16#,
                                                   16#18#, 16#1A#);

    -- Access to one APID table
    type TblFsm_t is (TIdle_s, TReq_s, TWait_s, TDone_s);

    type Tbl_r is record
        State   : TblFsm_t;
        Apid    : std_logic_vector(10 downto 0);
        RdReq   : std_logic;
        WrReq   : std_logic;
        WrData  : std_logic_vector(EntryWidth_c - 1 downto 0);
        Entry   : std_logic_vector(EntryWidth_c - 1 downto 0);
        Ded     : std_logic;
        Overrun : std_logic;
    end record;

    type DestBytes_t is array (0 to NumDest_g - 1, 0 to AddrBytes_c - 1) of std_logic_vector(7 downto 0);

    type DestByte_t is array (0 to NumDest_g - 1) of std_logic_vector(7 downto 0);

    type DestLen_t is array (0 to NumDest_g - 1) of std_logic_vector(4 downto 0);

    type TwoProcess_r is record
        MaxLength   : std_logic_vector(LengthWidth_c - 1 downto 0);
        RoundRobin  : std_logic;
        IdleDeliver : std_logic;
        TlaCheck    : std_logic;
        RxStrip     : std_logic_vector(3 downto 0);
        Tla         : std_logic_vector(7 downto 0);
        ScrubEnable : std_logic;
        DestAddr    : DestBytes_t;
        DestLen     : DestLen_t;
        DestTla     : DestByte_t;
        DestUa      : DestByte_t;
        TxT         : Tbl_r;
        RxT         : Tbl_r;
        ErrCnt      : ErrCnt_t;
        TxPackets   : unsigned(31 downto 0);
        RxPackets   : unsigned(31 downto 0);
        RxLoss      : unsigned(31 downto 0);
        LastErr     : ErrEvent_t;
        ErrOut      : ErrEvent_t;
        Events      : std_logic_vector(6 downto 0);
        IrqEn       : std_logic_vector(6 downto 0);
        Irq         : std_logic;
        EccSelect   : std_logic_vector(2 downto 0);
        EccClr      : std_logic;
        EccRdClr    : std_logic;
        InjTx       : std_logic;
        InjRx       : std_logic;
        InjChannel  : std_logic_vector(5 downto 0);
        InjDouble   : std_logic;
        RdPend      : std_logic;
        RdAddr      : natural range 0 to 2047;
        RdValid     : std_logic;
        RdData      : std_logic_vector(31 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    signal RbAddr    : std_logic_vector(10 downto 0);
    signal RbWr      : std_logic;
    signal RbWrData  : std_logic_vector(31 downto 0);
    signal RbRd      : std_logic;
    signal EccSecCnt : std_logic_vector(15 downto 0);
    signal EccDedCnt : std_logic_vector(15 downto 0);
    signal EccDed    : std_logic_vector(7 downto 0);
    signal EvtSec    : std_logic;
    signal EvtDed    : std_logic;

    function toSl (b : boolean) return std_logic is
    begin
        if b then
            return '1';
        end if;
        return '0';
    end function;

    -- A table access is pending or running, or the table initialises
    function tblBusy (
        t    : Tbl_r;
        init : std_logic) return boolean is
    begin
        return t.State /= TIdle_s or t.RdReq = '1' or t.WrReq = '1' or init = '1';
    end function;

    -- Saturating counter step
    function incSat (
        c : unsigned;
        n : natural) return unsigned is
        variable S_v : unsigned(c'length downto 0);
    begin
        S_v := resize(c, c'length + 1) + n;
        if S_v(c'length) = '1' then
            return (c'range => '1');
        end if;
        return S_v(c'length - 1 downto 0);
    end function;

begin

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Addr_v  : natural range 0 to 2047;
        variable Wr_v    : std_logic_vector(31 downto 0);
        variable Rd_v    : std_logic_vector(31 downto 0);
        variable Len_v   : unsigned(LengthWidth_c - 1 downto 0);
        variable N_v     : natural range 0 to 255;
        variable First_v : boolean;
        variable Ent_v   : std_logic_vector(EntryWidth_c - 1 downto 0);

        -- Step of the access of one table (client B): request, read data, then write back or release
        procedure tblStep (
            variable t   : inout Tbl_r;
            init         : in std_logic;
            ready        : in std_logic;
            rdValid      : in std_logic;
            rdData       : in std_logic_vector;
            rdDed        : in std_logic;
            signal valid : out std_logic;
            signal wrEna : out std_logic;
            signal rel   : out std_logic) is
        begin
            valid <= '0';
            wrEna <= '0';
            rel   <= '0';

            case t.State is

                when TIdle_s =>
                    if (t.RdReq = '1' or t.WrReq = '1') and init = '0' then
                        t.State := TReq_s;
                    end if;

                when TReq_s =>
                    valid <= '1';
                    if ready = '1' then
                        t.State := TWait_s;
                    end if;

                when TWait_s =>
                    if rdValid = '1' then
                        if t.WrReq = '1' then
                            t.Entry := t.WrData;
                            t.Ded   := '0';
                        else
                            t.Entry                             := (others => '0');
                            t.Entry(rdData'length - 1 downto 0) := rdData;
                            t.Ded                               := rdDed;
                        end if;
                        t.State := TDone_s;
                    end if;

                when TDone_s =>
                    if t.WrReq = '1' then
                        wrEna <= '1';
                    else
                        rel <= '1';
                    end if;
                    t.RdReq := '0';
                    t.WrReq := '0';
                    t.State := TIdle_s;

                -- coverage off
                when others =>
                    t.State := TIdle_s;
                -- coverage on

            end case;

        end procedure;

    -- Register file
    begin
        -- Hold variables stable
        v          := r;
        v.EccClr   := '0';
        v.EccRdClr := '0';
        v.InjTx    := '0';
        v.InjRx    := '0';
        v.RdValid  := '0';
        v.ErrOut   := ErrEventNone_c;

        -------------------------------------------------------------------------------------------
        -- Register writes; a clear is applied before the events of the same cycle
        -------------------------------------------------------------------------------------------
        Addr_v := to_integer(unsigned(std_logic_vector'(RbAddr(10 downto 2) & "00")));
        Wr_v   := RbWrData;
        if RbWr = '1' then

            case Addr_v is

                when RegConfig_c =>
                    v.RoundRobin  := Wr_v(ConfigRoundRobin_c);
                    v.IdleDeliver := Wr_v(ConfigIdleDeliver_c);
                    v.TlaCheck    := Wr_v(ConfigTlaCheck_c);
                    v.RxStrip     := Wr_v(ConfigRxStripHi_c downto ConfigRxStripLo_c);
                    v.Tla         := Wr_v(ConfigTlaHi_c downto ConfigTlaLo_c);

                when RegMaxLength_c =>
                    -- Limited to the lengths of a Space Packet (SPP 4.1.2.2)
                    Len_v := unsigned(Wr_v(MaxLengthLengthHi_c downto MaxLengthLengthLo_c));
                    if Len_v < MinPacketBytes_c then
                        Len_v := to_unsigned(MinPacketBytes_c, LengthWidth_c);
                    elsif Len_v > MaxPacketBytes_c then
                        Len_v := to_unsigned(MaxPacketBytes_c, LengthWidth_c);
                    end if;
                    v.MaxLength := std_logic_vector(Len_v);

                when RegTxTableApid_c =>
                    if tblBusy(r.TxT, '0') then
                        v.TxT.Overrun := '1';
                    else
                        v.TxT.Apid  := Wr_v(TxTableApidApidHi_c downto TxTableApidApidLo_c);
                        v.TxT.RdReq := '1';
                    end if;

                when RegTxTableEntry_c =>
                    if tblBusy(r.TxT, '0') then
                        v.TxT.Overrun := '1';
                    else
                        v.TxT.WrData                              := (others => '0');
                        v.TxT.WrData(TxEntryWidth_c - 1 downto 0) := Wr_v(TxEntryWidth_c - 1 downto 0);
                        v.TxT.WrReq                               := '1';
                    end if;

                when RegRxTableApid_c =>
                    if tblBusy(r.RxT, '0') then
                        v.RxT.Overrun := '1';
                    else
                        v.RxT.Apid  := Wr_v(RxTableApidApidHi_c downto RxTableApidApidLo_c);
                        v.RxT.RdReq := '1';
                    end if;

                when RegRxTableEntry_c =>
                    if tblBusy(r.RxT, '0') then
                        v.RxT.Overrun := '1';
                    else
                        v.RxT.WrData := Wr_v(RxEntryWidth_c - 1 downto 0);
                        v.RxT.WrReq  := '1';
                    end if;

                when RegTableStatus_c =>
                    if Wr_v(TableStatusTxOverrun_c) = '1' then
                        v.TxT.Overrun := '0';
                    end if;
                    if Wr_v(TableStatusRxOverrun_c) = '1' then
                        v.RxT.Overrun := '0';
                    end if;

                when RegEvents_c =>
                    v.Events := r.Events and not Wr_v(6 downto 0);

                when RegIrqEn_c =>
                    v.IrqEn := Wr_v(IrqEnEnableHi_c downto IrqEnEnableLo_c);

                when RegEccStatus_c =>
                    v.EccClr := '1';

                when RegEccSelect_c =>
                    v.EccSelect := Wr_v(EccSelectChannelHi_c downto EccSelectChannelLo_c);

                when RegEccCount_c =>
                    v.EccRdClr := '1';

                when RegEccInject_c =>
                    if Wr_v(EccInjectSingle_c) = '1' or Wr_v(EccInjectDouble_c) = '1' then
                        v.InjTx      := not Wr_v(EccInjectRx_c);
                        v.InjRx      := Wr_v(EccInjectRx_c);
                        v.InjChannel := Wr_v(EccInjectChannelHi_c downto EccInjectChannelLo_c);
                        v.InjDouble  := Wr_v(EccInjectDouble_c);
                    end if;

                when RegScrub_c =>
                    v.ScrubEnable := Wr_v(ScrubEnable_c);

                when RegTxPackets_c =>
                    v.TxPackets := (others => '0');

                when RegRxPackets_c =>
                    v.RxPackets := (others => '0');

                when RegRxLoss_c =>
                    v.RxLoss := (others => '0');

                when others =>

                    -- Error counters: any write clears both counters of the register
                    for i in ErrRegs_c'range loop
                        if Addr_v = ErrRegs_c(i) then
                            v.ErrCnt(ErrCodeLo_c(i))     := (others => '0');
                            v.ErrCnt(ErrCodeLo_c(i) + 1) := (others => '0');
                        end if;
                    end loop;

                    -- Destinations
                    for d in 0 to NumDest_g - 1 loop
                        if Addr_v = RegDestCtrl_c + d * RegDestStride_c then
                            v.DestTla(d) := Wr_v(DestCtrlTlaHi_c downto DestCtrlTlaLo_c);
                            v.DestUa(d)  := Wr_v(DestCtrlUaHi_c downto DestCtrlUaLo_c);
                            v.DestLen(d) := Wr_v(DestCtrlAddrLenHi_c downto DestCtrlAddrLenLo_c);
                        end if;

                        -- No address bytes without SpwAddrBytes_g (empty loop)
                        for b in 0 to SpwAddrBytes_g - 1 loop
                            if Addr_v = RegDestAddr0_c + d * RegDestStride_c + 4 * (b / 4) then
                                v.DestAddr(d, b) := Wr_v(8 * (b mod 4) + 7 downto 8 * (b mod 4));
                            end if;
                        end loop;

                    end loop;

            end case;

        end if;

        -------------------------------------------------------------------------------------------
        -- Table accesses
        -------------------------------------------------------------------------------------------
        tblStep(v.TxT, TxTbl_Busy, TxTbl_Ready, TxTbl_RdValid, TxTbl_RdData, TxTbl_RdDed, TxTbl_Valid,
                TxTbl_WrEna, TxTbl_Release);
        tblStep(v.RxT, RxTbl_Busy, RxTbl_Ready, RxTbl_RdValid, RxTbl_RdData, RxTbl_RdDed, RxTbl_Valid,
                RxTbl_WrEna, RxTbl_Release);
        TxTbl_Apid   <= r.TxT.Apid;
        TxTbl_WrData <= r.TxT.WrData(TxEntryWidth_c - 1 downto 0);
        RxTbl_Apid   <= r.RxT.Apid;
        RxTbl_WrData <= r.RxT.WrData;

        -------------------------------------------------------------------------------------------
        -- Counted events
        -------------------------------------------------------------------------------------------
        First_v := true;

        for c in 1 to 31 loop
            N_v := 0;

            for i in Err'range loop
                if Err(i).Valid = '1' and to_integer(unsigned(Err(i).Code)) = c then
                    N_v := N_v + 1;
                end if;
            end loop;

            if N_v > 0 then
                v.ErrCnt(c) := incSat(v.ErrCnt(c), N_v);
            end if;
        end loop;

        -- Last error: the event of the lowest index of this cycle
        for i in Err'range loop
            if Err(i).Valid = '1' then
                if First_v then
                    v.LastErr := Err(i);
                    v.ErrOut  := Err(i);
                    First_v   := false;
                end if;
                if Err(i).Code(4) = '0' then
                    v.Events(EventsTxReject_c) := '1';
                else
                    v.Events(EventsRxDiscard_c) := '1';
                end if;
            end if;
        end loop;

        N_v := 0;

        for p in 0 to NumRx_g - 1 loop
            if Rx_Delivered(p) = '1' then
                N_v := N_v + 1;
            end if;
        end loop;

        if Tx_Sent = '1' then
            v.TxPackets              := incSat(v.TxPackets, 1);
            v.Events(EventsTxSent_c) := '1';
        end if;
        if N_v > 0 then
            v.RxPackets                   := incSat(v.RxPackets, N_v);
            v.Events(EventsRxDelivered_c) := '1';
        end if;
        if Rx_Loss = '1' then
            v.RxLoss                 := incSat(v.RxLoss, 1);
            v.Events(EventsRxLoss_c) := '1';
        end if;
        if EvtSec = '1' then
            v.Events(EventsEccSec_c) := '1';
        end if;
        if EvtDed = '1' then
            v.Events(EventsEccDed_c) := '1';
        end if;

        -- Interrupt
        v.Irq := toSl((r.Events and r.IrqEn) /= "0000000");

        -------------------------------------------------------------------------------------------
        -- Register reads: data one cycle after the request; a read of a table entry waits for its access
        -------------------------------------------------------------------------------------------
        if RbRd = '1' then
            v.RdPend := '1';
            v.RdAddr := to_integer(unsigned(std_logic_vector'(RbAddr(10 downto 2) & "00")));
        end if;
        Addr_v := v.RdAddr;
        Rd_v   := (others => '0');

        case Addr_v is

            when RegId_c =>
                Rd_v := RegMapId_c;

            when RegGenerics_c =>
                Rd_v(GenericsNumTxHi_c downto GenericsNumTxLo_c)               := std_logic_vector(to_unsigned(NumTx_g, 5));
                Rd_v(GenericsNumRxHi_c downto GenericsNumRxLo_c)               := std_logic_vector(to_unsigned(NumRx_g, 5));
                Rd_v(GenericsNumDestHi_c downto GenericsNumDestLo_c)           := std_logic_vector(to_unsigned(NumDest_g, 5));
                Rd_v(GenericsSpwAddrBytesHi_c downto GenericsSpwAddrBytesLo_c) := std_logic_vector(to_unsigned(SpwAddrBytes_g, 5));
                Rd_v(GenericsDataBytesHi_c downto GenericsDataBytesLo_c)       := std_logic_vector(to_unsigned(DataWidth_g / 8, 5));
                Rd_v(GenericsEncapsulation_c)                                  := toSl(Encapsulation_g);

            when RegServices_c =>
                Rd_v(ServicesTxOctetLo_c + NumTx_g - 1 downto ServicesTxOctetLo_c) := TxOctetString_g(NumTx_g - 1 downto 0);
                Rd_v(ServicesRxOctetLo_c + NumRx_g - 1 downto ServicesRxOctetLo_c) := RxOctetString_g(NumRx_g - 1 downto 0);

            when RegTxBuffer_c =>
                Rd_v := std_logic_vector(to_unsigned(TxBufferBytes_g, 32));

            when RegRxBuffer_c =>
                Rd_v := std_logic_vector(to_unsigned(RxBufferBytes_g, 32));

            when RegConfig_c =>
                Rd_v(ConfigRoundRobin_c)                         := r.RoundRobin;
                Rd_v(ConfigIdleDeliver_c)                        := r.IdleDeliver;
                Rd_v(ConfigTlaCheck_c)                           := r.TlaCheck;
                Rd_v(ConfigRxStripHi_c downto ConfigRxStripLo_c) := r.RxStrip;
                Rd_v(ConfigTlaHi_c downto ConfigTlaLo_c)         := r.Tla;

            when RegMaxLength_c =>
                Rd_v(MaxLengthLengthHi_c downto MaxLengthLengthLo_c) := r.MaxLength;

            when RegTxTableApid_c =>
                Rd_v(TxTableApidApidHi_c downto TxTableApidApidLo_c) := r.TxT.Apid;

            when RegTxTableEntry_c =>
                Rd_v(TxEntryWidth_c - 1 downto 0) := r.TxT.Entry(TxEntryWidth_c - 1 downto 0);
                Rd_v(TxTableEntryDed_c)           := r.TxT.Ded;

            when RegRxTableApid_c =>
                Rd_v(RxTableApidApidHi_c downto RxTableApidApidLo_c) := r.RxT.Apid;

            when RegRxTableEntry_c =>
                Rd_v(RxEntryWidth_c - 1 downto 0) := r.RxT.Entry;
                Rd_v(RxTableEntryDed_c)           := r.RxT.Ded;

            when RegTableStatus_c =>
                Rd_v(TableStatusTxBusy_c)    := toSl(tblBusy(r.TxT, TxTbl_Busy));
                Rd_v(TableStatusRxBusy_c)    := toSl(tblBusy(r.RxT, RxTbl_Busy));
                Rd_v(TableStatusTxOverrun_c) := r.TxT.Overrun;
                Rd_v(TableStatusRxOverrun_c) := r.RxT.Overrun;

            when RegLastError_c =>
                Rd_v(LastErrorCodeHi_c downto LastErrorCodeLo_c) := r.LastErr.Code;
                Rd_v(LastErrorPortHi_c downto LastErrorPortLo_c) := r.LastErr.Index;
                Rd_v(LastErrorApidHi_c downto LastErrorApidLo_c) := r.LastErr.Apid;

            when RegEvents_c =>
                Rd_v(6 downto 0) := r.Events;

            when RegIrqEn_c =>
                Rd_v(IrqEnEnableHi_c downto IrqEnEnableLo_c) := r.IrqEn;

            when RegIrqStatus_c =>
                Rd_v(IrqStatusIrq_c) := r.Irq;

            when RegEccStatus_c =>
                Rd_v(EccStatusDedHi_c downto EccStatusDedLo_c) := EccDed;

            when RegEccSelect_c =>
                Rd_v(EccSelectChannelHi_c downto EccSelectChannelLo_c) := r.EccSelect;

            when RegEccCount_c =>
                Rd_v := EccDedCnt & EccSecCnt;

            when RegScrub_c =>
                Rd_v(ScrubEnable_c) := r.ScrubEnable;

            when RegTxPackets_c =>
                Rd_v := std_logic_vector(r.TxPackets);

            when RegRxPackets_c =>
                Rd_v := std_logic_vector(r.RxPackets);

            when RegRxLoss_c =>
                Rd_v := std_logic_vector(r.RxLoss);

            when others =>

                for i in ErrRegs_c'range loop
                    if Addr_v = ErrRegs_c(i) then
                        Rd_v := std_logic_vector(r.ErrCnt(ErrCodeLo_c(i) + 1)) & std_logic_vector(r.ErrCnt(ErrCodeLo_c(i)));
                    end if;
                end loop;

                for d in 0 to NumDest_g - 1 loop
                    if Addr_v = RegDestCtrl_c + d * RegDestStride_c then
                        Rd_v(DestCtrlTlaHi_c downto DestCtrlTlaLo_c)         := r.DestTla(d);
                        Rd_v(DestCtrlUaHi_c downto DestCtrlUaLo_c)           := r.DestUa(d);
                        Rd_v(DestCtrlAddrLenHi_c downto DestCtrlAddrLenLo_c) := r.DestLen(d);
                    end if;

                    -- No address bytes without SpwAddrBytes_g (empty loop): DEST_ADDR reads zero
                    for b in 0 to SpwAddrBytes_g - 1 loop
                        if Addr_v = RegDestAddr0_c + d * RegDestStride_c + 4 * (b / 4) then
                            Rd_v(8 * (b mod 4) + 7 downto 8 * (b mod 4)) := r.DestAddr(d, b);
                        end if;
                    end loop;

                end loop;

        end case;

        -- A read of a table entry is answered when its access is complete
        if r.RdPend = '1' or RbRd = '1' then
            if not ((Addr_v = RegTxTableEntry_c and tblBusy(v.TxT, TxTbl_Busy)) or
                    (Addr_v = RegRxTableEntry_c and tblBusy(v.RxT, RxTbl_Busy))) then
                v.RdValid := '1';
                v.RdData  := Rd_v;
                v.RdPend  := '0';
            end if;
        end if;

        r_next <= v;
    end process;

    -- Outputs
    Irq             <= r.Irq;
    Cfg_MaxLength   <= r.MaxLength;
    Cfg_RoundRobin  <= r.RoundRobin;
    Cfg_IdleDeliver <= r.IdleDeliver;
    Cfg_TlaCheck    <= r.TlaCheck;
    Cfg_RxStrip     <= r.RxStrip;
    Cfg_Tla         <= r.Tla;
    Cfg_ScrubEnable <= r.ScrubEnable;
    Err_Valid       <= r.ErrOut.Valid;
    Err_Code        <= r.ErrOut.Code;
    Err_Port        <= r.ErrOut.Index;
    Err_Apid        <= r.ErrOut.Apid;
    Inj_TxValid     <= r.InjTx;
    Inj_RxValid     <= r.InjRx;
    Inj_Channel     <= r.InjChannel;
    Inj_Double      <= r.InjDouble;

    g_dest : for d in 0 to NumDest_g - 1 generate
        Cfg_DestAddrLen(5 * d + 4 downto 5 * d) <= r.DestLen(d);
        Cfg_DestTla(8 * d + 7 downto 8 * d)     <= r.DestTla(d);
        Cfg_DestUa(8 * d + 7 downto 8 * d)      <= r.DestUa(d);

        g_byte : for b in 0 to AddrBytes_c - 1 generate
            Cfg_DestAddr(8 * (AddrBytes_c * d + b) + 7 downto 8 * (AddrBytes_c * d + b)) <= r.DestAddr(d, b);
        end generate;

    end generate;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.MaxLength   <= std_logic_vector(to_unsigned(MaxLength_g, LengthWidth_c));
                r.RoundRobin  <= RoundRobin_g;
                r.IdleDeliver <= '0';
                r.TlaCheck    <= '0';
                r.RxStrip     <= (others => '0');
                r.Tla         <= Tla_g;
                r.ScrubEnable <= '1';
                r.DestAddr    <= (others => (others => (others => '0')));
                r.DestLen     <= (others => (others => '0'));
                r.DestTla     <= (others => DefaultLogicalAddr_c);
                r.DestUa      <= (others => (others => '0'));
                r.TxT         <= (TIdle_s, (others => '0'), '0', '0', (others => '0'), (others => '0'), '0', '0');
                r.RxT         <= (TIdle_s, (others => '0'), '0', '0', (others => '0'), (others => '0'), '0', '0');
                r.ErrCnt      <= (others => (others => '0'));
                r.TxPackets   <= (others => '0');
                r.RxPackets   <= (others => '0');
                r.RxLoss      <= (others => '0');
                r.LastErr     <= ErrEventNone_c;
                r.ErrOut      <= ErrEventNone_c;
                r.Events      <= (others => '0');
                r.IrqEn       <= (others => '0');
                r.Irq         <= '0';
                r.EccSelect   <= (others => '0');
                r.EccClr      <= '0';
                r.EccRdClr    <= '0';
                r.InjTx       <= '0';
                r.InjRx       <= '0';
                r.InjDouble   <= '0';
                r.RdPend      <= '0';
                r.RdValid     <= '0';
            end if;
        end if;
    end process;

    -- MG-1: AXI4-Lite slave; the read timeout covers a table access during the initialisation of a table
    i_axi : entity olo.olo_axi_lite_slave
        generic map (
            AxiAddrWidth_g    => 11,
            AxiDataWidth_g    => 32,
            ReadTimeoutClks_g => 4096
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
            Rb_Addr           => RbAddr,
            Rb_Wr             => RbWr,
            Rb_WrData         => RbWrData,
            Rb_Rd             => RbRd,
            Rb_RdData         => r.RdData,
            Rb_RdValid        => r.RdValid
        );

    -- MG-2: EDAC monitor of the 8 channels
    i_ecc : entity olo.olo_ft_ecc_monitor
        generic map (
            Channels_g     => 8,
            CounterWidth_g => 16
        )
        port map (
            Clk        => Clk,
            Rst        => Rst,
            Clr        => r.EccClr,
            In_EccSec  => Ecc_Sec,
            In_EccDed  => Ecc_Ded,
            DedSticky  => EccDed,
            Evt_Sec    => EvtSec,
            Evt_Ded    => EvtDed,
            Rd_Channel => r.EccSelect,
            Rd_Ena     => '1',
            Rd_Clr     => r.EccRdClr,
            Rd_SecCnt  => EccSecCnt,
            Rd_DedCnt  => EccDedCnt,
            Rd_Valid   => open
        );

end architecture;
