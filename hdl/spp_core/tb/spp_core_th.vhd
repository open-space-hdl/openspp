---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the core: two cores A and B whose links are connected through link models, stream
-- sources and sinks on all user ports, injectors into both link inputs, an AXI4-Lite master VVC per
-- core, monitors of the error event outputs and statistics of the link and send ports. For the reset
-- tests: Rst and DpRst of each core, triggers that apply them and stall the link at a beat of a packet
-- on the link output, a monitor of each link output and probes of the ports during a reset.
--
-- Documentation: hdl/spp_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library olo;
    use olo.olo_base_pkg_math.all;

library work;
    use work.spp_pkg.all;
    use work.spp_tb_streamvar_pkg.all;
    use work.spp_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_core_th is
    generic (
        DataWidth_g     : positive;
        Encapsulation_g : boolean;
        BufferBeats_g   : positive;
        NChar_g         : boolean  := false;
        PathDefault_g   : boolean  := true;
        SpwAddrBytes_g  : natural  := 4;
        NumTx_g         : positive := 3;
        NumRx_g         : positive := 3;
        NumDest_g       : positive := 4;
        TxMaxPackets_g  : positive := 8;
        RxMaxPackets_g  : positive := 8;
        MaxLength_g     : positive := 65542;
        RoundRobin_g    : boolean  := false;
        Tla_g           : natural  := 16#FE#
    );
    port (
        Clk       : out   std_logic := '0';
        RstA      : in    std_logic;
        RstB      : in    std_logic;
        ResetCtrl : in    ResetCtrlArray_t;
        LinkAB    : in    LinkCtrl_t;
        LinkBA    : in    LinkCtrl_t;
        StatAB    : out   LinkStat_t;
        StatBA    : out   LinkStat_t;
        Cores     : out   CoreStatArray_t;
        Mon       : out   MonStatArray_t;
        Probe     : out   ProbeStatArray_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_core_th is

    constant Bytes_c  : positive := DataWidth_g / 8;
    constant Buffer_c : positive := Bytes_c * BufferBeats_g;

    type Slv_t is array (0 to NumCores_c - 1) of std_logic;

    type TxSlv_t is array (0 to NumCores_c - 1) of std_logic_vector(NumTx_g - 1 downto 0);

    type TxData_t is array (0 to NumCores_c - 1) of std_logic_vector(NumTx_g * DataWidth_g - 1 downto 0);

    type TxKeep_t is array (0 to NumCores_c - 1) of std_logic_vector(NumTx_g * Bytes_c - 1 downto 0);

    type TxUser_t is array (0 to NumCores_c - 1) of std_logic_vector(NumTx_g * TxUserWidth_c - 1 downto 0);

    type RxSlv_t is array (0 to NumCores_c - 1) of std_logic_vector(NumRx_g - 1 downto 0);

    type RxData_t is array (0 to NumCores_c - 1) of std_logic_vector(NumRx_g * DataWidth_g - 1 downto 0);

    type RxKeep_t is array (0 to NumCores_c - 1) of std_logic_vector(NumRx_g * Bytes_c - 1 downto 0);

    type RxUser_t is array (0 to NumCores_c - 1) of std_logic_vector(NumRx_g * RxUserWidth_c - 1 downto 0);

    type Data_t is array (0 to NumCores_c - 1) of std_logic_vector(DataWidth_g - 1 downto 0);

    type Keep_t is array (0 to NumCores_c - 1) of std_logic_vector(Bytes_c - 1 downto 0);

    type LinkUser_t is array (0 to NumCores_c - 1) of std_logic_vector(LinkUserWidth_c - 1 downto 0);

    type Addr_t is array (0 to NumCores_c - 1) of std_logic_vector(10 downto 0);

    type Word_t is array (0 to NumCores_c - 1) of std_logic_vector(31 downto 0);

    type Strb_t is array (0 to NumCores_c - 1) of std_logic_vector(3 downto 0);

    type Resp_t is array (0 to NumCores_c - 1) of std_logic_vector(1 downto 0);

    type One_t is array (0 to NumCores_c - 1) of std_logic_vector(0 downto 0);

    type Code_t is array (0 to NumCores_c - 1) of std_logic_vector(4 downto 0);

    type Port4_t is array (0 to NumCores_c - 1) of std_logic_vector(3 downto 0);

    type Data8_t is array (0 to NumCores_c - 1) of std_logic_vector(7 downto 0);

    type Nat_t is array (0 to NumCores_c - 1) of natural;

    signal RstTb          : Slv_t;
    signal Rst            : Slv_t;
    signal DpRst          : Slv_t;
    signal Stall          : Slv_t;
    signal MonPkt         : Nat_t;
    signal TxValid        : TxSlv_t;
    signal TxReady        : TxSlv_t;
    signal TxLast         : TxSlv_t;
    signal TxData         : TxData_t;
    signal TxKeep         : TxKeep_t;
    signal TxUser         : TxUser_t;
    signal RxValid        : RxSlv_t;
    signal RxReady        : RxSlv_t;
    signal RxLast         : RxSlv_t;
    signal RxData         : RxData_t;
    signal RxKeep         : RxKeep_t;
    signal RxUser         : RxUser_t;
    signal LoValid        : Slv_t;
    signal LoReady        : Slv_t;
    signal LoLast         : Slv_t;     -- link outputs of the cores
    signal LoData         : Data_t;
    signal LoKeep         : Keep_t;
    signal LoUser         : LinkUser_t;
    signal LiValid        : Slv_t;
    signal LiReady        : Slv_t;
    signal LiLast         : Slv_t;     -- link inputs of the cores
    signal LiData         : Data_t;
    signal LiKeep         : Keep_t;
    signal LiUser         : One_t;
    signal LmValid        : Slv_t;
    signal LmReady        : Slv_t;
    signal LmLast         : Slv_t;     -- link models toward the cores
    signal LmData         : Data_t;
    signal LmKeep         : Keep_t;
    signal LmUser         : One_t;
    signal NcValid        : Slv_t;
    signal NcReady        : Slv_t;
    signal NcLast         : Slv_t;     -- N-Char streams out of the adapters
    signal NcData         : Data8_t;
    signal IjValid        : Slv_t;
    signal IjReady        : Slv_t;
    signal IjLast         : Slv_t;     -- injectors into the link inputs
    signal IjData         : Data_t;
    signal IjKeep         : Keep_t;
    signal IjUser         : One_t;
    signal ArAddr, AwAddr : Addr_t;
    signal ArValid        : Slv_t;
    signal ArReady        : Slv_t;
    signal AwValid        : Slv_t;
    signal AwReady        : Slv_t;
    signal WData, RData   : Word_t;
    signal WStrb          : Strb_t;
    signal WValid         : Slv_t;
    signal WReady         : Slv_t;
    signal BValid         : Slv_t;
    signal BReady         : Slv_t;
    signal RValid         : Slv_t;
    signal RReady         : Slv_t;
    signal BResp, RResp   : Resp_t;
    signal Irq, ErrValid  : Slv_t;
    signal ErrCode        : Code_t;
    signal ErrPort        : Port4_t;
    signal ErrApid        : Addr_t;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    -- The clock is driven on the port, so that testbench and DUT see the same signal (no delta cycle between them)
    Clk <= not Clk after ClkPeriod_c / 2;

    RstTb(0) <= RstA;
    RstTb(1) <= RstB;

    g_core : for c in 0 to NumCores_c - 1 generate
        constant ChTx_c  : natural := choose(c = 0, ChTxA_c, ChTxB_c);
        constant ChRx_c  : natural := choose(c = 0, ChRxA_c, ChRxB_c);
        constant ChInj_c : natural := choose(c = 0, ChInjA_c, ChInjB_c);

        -- Triggers: armed by a change of ResetCtrl(c).Arm; T is 0 in the cycle of the trigger beat, then 1, 2, ...
        signal TArmed   : boolean := false;
        signal TCount   : integer := -1;
        signal SArmed   : boolean := false;
        signal SCount   : natural := 0;
        signal TrigNow  : boolean;
        signal StallNow : boolean;
        signal T        : integer;

    begin

        -- Reset and stall triggers at a beat of a packet presented on the link output (MonPkt beats transferred)
        TrigNow  <= TArmed and LoValid(c) = '1' and MonPkt(c) + 1 = ResetCtrl(c).Beat;
        StallNow <= SArmed and LoValid(c) = '1' and MonPkt(c) + 1 = ResetCtrl(c).StallBeat;
        T        <= 0 when TrigNow else TCount;

        DpRst(c) <= '1' when ResetCtrl(c).DpRst = '1' or
                             (T >= ResetCtrl(c).DpDelay and T < ResetCtrl(c).DpDelay + ResetCtrl(c).DpCycles) else
                    '0';
        Rst(c)   <= '1' when RstTb(c) = '1' or
                             (T >= ResetCtrl(c).RstDelay and T < ResetCtrl(c).RstDelay + ResetCtrl(c).RstCycles) else
                    '0';
        Stall(c) <= '1' when StallNow or SCount > 0 else
                    '0';

        p_trigger : process (Clk) is
            variable Arm_v : natural := 0;
            variable Lim_v : natural;
        begin
            if rising_edge(Clk) then
                Lim_v := maximum(ResetCtrl(c).DpDelay + ResetCtrl(c).DpCycles,
                                 ResetCtrl(c).RstDelay + ResetCtrl(c).RstCycles);
                if ResetCtrl(c).Arm /= Arm_v then
                    Arm_v  := ResetCtrl(c).Arm;
                    TArmed <= ResetCtrl(c).Beat > 0;
                    SArmed <= ResetCtrl(c).StallBeat > 0;
                    TCount <= -1;
                    SCount <= 0;
                else
                    if TrigNow then
                        TArmed <= false;
                        TCount <= 1 when Lim_v > 1 else -1;
                    elsif TCount >= 1 and TCount + 1 < Lim_v then
                        TCount <= TCount + 1;
                    else
                        TCount <= -1;
                    end if;
                    if StallNow then
                        SArmed <= false;
                        SCount <= 1 when ResetCtrl(c).StallCycles > 1 else 0;
                    elsif SCount > 0 and SCount + 1 < ResetCtrl(c).StallCycles then
                        SCount <= SCount + 1;
                    else
                        SCount <= 0;
                    end if;
                end if;
            end if;
        end process;

        -- Link output: AXI4-Stream rules and the link output stage at the resets
        i_monitor : entity work.spp_core_tb_monitor
            generic map (
                DataWidth_g => DataWidth_g,
                Name_g      => "link output of core " & to_string(c)
            )
            port map (
                Clk      => Clk,
                Rst      => Rst(c),
                DpRst    => DpRst(c),
                Valid    => LoValid(c),
                Ready    => LoReady(c),
                Data     => LoData(c),
                Keep     => LoKeep(c),
                Last     => LoLast(c),
                User     => LoUser(c),
                PktBeats => MonPkt(c),
                Stat     => Mon(c)
            );

        -- Ports during a reset (specification CO-RS-09 to CO-RS-11) and the coverpoints of the reset episodes
        p_probe : process (Clk) is
            constant Name_c   : string      := "core " & to_string(c) & " in reset: ";
            variable St_v     : ProbeStat_t := ProbeStatInit_c;
            variable InRst_v  : boolean     := false;
            variable Ep_v     : boolean     := false;
            variable RstNow_v : boolean;
            variable DpNow_v  : boolean;
            variable RstSn_v  : boolean     := false;
            variable DpSn_v   : boolean     := false;
            variable Start_v  : natural     := 0;
            variable RstEnd_v : natural     := 0;
            variable DpEnd_v  : natural     := 0;
            variable Edge_v   : natural     := 0;
            variable DpLen_v  : natural     := 0;
            variable Sl_v     : natural     := 0;
        begin
            if rising_edge(Clk) then
                Edge_v   := Edge_v + 1;
                RstNow_v := Rst(c) = '1';
                DpNow_v  := DpRst(c) = '1';

                -- Values of a cycle that started with an edge at which a reset input was sampled '1' and in which a
                -- reset input is still '1' (the cycle that ends with the release edge may show the released core)
                if InRst_v and (RstNow_v or DpNow_v) then
                    St_v.Cycles := St_v.Cycles + 1;
                    if TxReady(c) /= (TxReady(c)'range => '0') then
                        alert(ERROR, Name_c & "S_Tx_Ready " & to_string(TxReady(c)));
                    end if;
                    if RxValid(c) /= (RxValid(c)'range => '0') then
                        alert(ERROR, Name_c & "M_Rx_Valid " & to_string(RxValid(c)));
                    end if;
                    if ArReady(c) /= '0' or AwReady(c) /= '0' or WReady(c) /= '0' or BValid(c) /= '0' or
                       RValid(c) /= '0' then
                        alert(ERROR, Name_c & "AXI4-Lite ready or response");
                    end if;
                    if Irq(c) /= '0' or ErrValid(c) /= '0' then
                        alert(ERROR, Name_c & "Irq or Err_Valid");
                    end if;
                    if LiReady(c) /= choose(Encapsulation_g, '1', '0') then
                        alert(ERROR, Name_c & "S_Link_Ready " & to_string(LiReady(c)));
                    end if;
                end if;

                -- Reset episodes: from the first reset edge of either input to the release edge
                if (RstNow_v or DpNow_v) and not Ep_v then
                    Ep_v    := true;
                    RstSn_v := RstNow_v;
                    DpSn_v  := DpNow_v;
                    if RstNow_v and DpNow_v then
                        Start_v := OrderSameEdge_c;
                    elsif DpNow_v then
                        Start_v := OrderRstInDp_c;
                    else
                        Start_v := OrderDpInRst_c;
                    end if;
                    if Sl_v > 0 then
                        St_v.Slink(SlinkInside_c) := St_v.Slink(SlinkInside_c) + 1;
                    else
                        St_v.Slink(SlinkIdle_c) := St_v.Slink(SlinkIdle_c) + 1;
                    end if;
                end if;
                if RstNow_v then
                    RstSn_v  := true;
                    RstEnd_v := Edge_v;
                end if;
                if DpNow_v then
                    DpSn_v  := true;
                    DpEnd_v := Edge_v;
                    DpLen_v := DpLen_v + 1;
                elsif DpLen_v > 0 then
                    if DpLen_v = 1 then
                        St_v.Length(Length1_c) := St_v.Length(Length1_c) + 1;
                    elsif DpLen_v <= 16 then
                        St_v.Length(Length16_c) := St_v.Length(Length16_c) + 1;
                    elsif DpLen_v <= 2048 then
                        St_v.Length(Length2048_c) := St_v.Length(Length2048_c) + 1;
                    else
                        St_v.Length(LengthLong_c) := St_v.Length(LengthLong_c) + 1;
                    end if;
                    DpLen_v := 0;
                end if;

                -- Beats at the link input; the next beat after the release starts a packet
                if LiValid(c) = '1' and LiReady(c) = '1' then
                    if LiLast(c) = '1' then
                        Sl_v := 0;
                    else
                        Sl_v := Sl_v + 1;
                    end if;
                end if;

                if Ep_v and not RstNow_v and not DpNow_v then
                    -- Release edge: order of the inputs in the episode
                    if not RstSn_v then
                        St_v.Order(OrderDpRst_c) := St_v.Order(OrderDpRst_c) + 1;
                    elsif not DpSn_v then
                        St_v.Order(OrderRst_c) := St_v.Order(OrderRst_c) + 1;
                    else
                        St_v.Order(Start_v) := St_v.Order(Start_v) + 1;
                        if RstEnd_v < DpEnd_v then
                            St_v.Order(OrderRstFirst_c) := St_v.Order(OrderRstFirst_c) + 1;
                        elsif DpEnd_v < RstEnd_v then
                            St_v.Order(OrderDpFirst_c) := St_v.Order(OrderDpFirst_c) + 1;
                        else
                            St_v.Order(OrderSameRel_c) := St_v.Order(OrderSameRel_c) + 1;
                        end if;
                    end if;
                    St_v.Releases := St_v.Releases + 1;
                    Ep_v          := false;
                    Sl_v          := 0;
                end if;

                InRst_v         := RstNow_v or DpNow_v;
                St_v.InReset    := InRst_v;
                St_v.SlinkBeats := Sl_v;
                Probe(c)        <= St_v;
            end if;
        end process;

        -- User ports
        g_tx_port : for p in 0 to NumTx_g - 1 generate

            i_src : entity work.spp_tb_stream_source
                generic map (
                    Channel_g   => ChTx_c + p,
                    DataWidth_g => DataWidth_g,
                    UserWidth_g => TxUserWidth_c
                )
                port map (
                    Clk       => Clk,
                    Out_Valid => TxValid(c)(p),
                    Out_Ready => TxReady(c)(p),
                    Out_Data  => TxData(c)((p + 1) * DataWidth_g - 1 downto p * DataWidth_g),
                    Out_Keep  => TxKeep(c)((p + 1) * Bytes_c - 1 downto p * Bytes_c),
                    Out_Last  => TxLast(c)(p),
                    Out_User  => TxUser(c)((p + 1) * TxUserWidth_c - 1 downto p * TxUserWidth_c)
                );

        end generate;

        g_rx_port : for p in 0 to NumRx_g - 1 generate

            i_snk : entity work.spp_tb_stream_sink
                generic map (
                    Channel_g   => ChRx_c + p,
                    DataWidth_g => DataWidth_g,
                    UserWidth_g => RxUserWidth_c,
                    Name_g      => "core " & to_string(c) & " port " & to_string(p)
                )
                port map (
                    Clk      => Clk,
                    In_Valid => RxValid(c)(p),
                    In_Ready => RxReady(c)(p),
                    In_Data  => RxData(c)((p + 1) * DataWidth_g - 1 downto p * DataWidth_g),
                    In_Keep  => RxKeep(c)((p + 1) * Bytes_c - 1 downto p * Bytes_c),
                    In_Last  => RxLast(c)(p),
                    In_User  => RxUser(c)((p + 1) * RxUserWidth_c - 1 downto p * RxUserWidth_c)
                );

        end generate;

        -- Injector into the link input
        i_inj : entity work.spp_tb_stream_source
            generic map (
                Channel_g   => ChInj_c,
                DataWidth_g => DataWidth_g,
                UserWidth_g => 1
            )
            port map (
                Clk       => Clk,
                Out_Valid => IjValid(c),
                Out_Ready => IjReady(c),
                Out_Data  => IjData(c),
                Out_Keep  => IjKeep(c),
                Out_Last  => IjLast(c),
                Out_User  => IjUser(c)
            );

        i_axi : entity work.spp_tb_axilite_master
            generic map (
                InstanceIdx_g => c,
                AddrWidth_g   => 11
            )
            port map (
                Clk     => Clk,
                ArAddr  => ArAddr(c),
                ArValid => ArValid(c),
                ArReady => ArReady(c),
                AwAddr  => AwAddr(c),
                AwValid => AwValid(c),
                AwReady => AwReady(c),
                WData   => WData(c),
                WStrb   => WStrb(c),
                WValid  => WValid(c),
                WReady  => WReady(c),
                BResp   => BResp(c),
                BValid  => BValid(c),
                BReady  => BReady(c),
                RData   => RData(c),
                RResp   => RResp(c),
                RValid  => RValid(c),
                RReady  => RReady(c)
            );

        i_core : entity work.spp_core
            generic map (
                DataWidth_g     => DataWidth_g,
                NumTx_g         => NumTx_g,
                NumRx_g         => NumRx_g,
                TxOctetString_g => Octet_c,
                RxOctetString_g => Octet_c,
                TxBufferBytes_g => Buffer_c,
                TxMaxPackets_g  => TxMaxPackets_g,
                RxBufferBytes_g => Buffer_c,
                RxMaxPackets_g  => RxMaxPackets_g,
                Encapsulation_g => Encapsulation_g,
                NumDest_g       => NumDest_g,
                SpwAddrBytes_g  => SpwAddrBytes_g,
                MaxLength_g     => MaxLength_g,
                RoundRobin_g    => choose(RoundRobin_g, '1', '0'),
                Tla_g           => std_logic_vector(to_unsigned(Tla_g, 8)),
                TxPathDefault_g => PathDefault_g,
                RxPathDefault_g => PathDefault_g
            )
            port map (
                Clk               => Clk,
                Rst               => Rst(c),
                DpRst             => DpRst(c),
                S_Tx_Valid        => TxValid(c),
                S_Tx_Ready        => TxReady(c),
                S_Tx_Data         => TxData(c),
                S_Tx_Keep         => TxKeep(c),
                S_Tx_Last         => TxLast(c),
                S_Tx_User         => TxUser(c),
                M_Rx_Valid        => RxValid(c),
                M_Rx_Ready        => RxReady(c),
                M_Rx_Data         => RxData(c),
                M_Rx_Keep         => RxKeep(c),
                M_Rx_Last         => RxLast(c),
                M_Rx_User         => RxUser(c),
                M_Link_Valid      => LoValid(c),
                M_Link_Ready      => LoReady(c),
                M_Link_Data       => LoData(c),
                M_Link_Keep       => LoKeep(c),
                M_Link_Last       => LoLast(c),
                M_Link_User       => LoUser(c),
                S_Link_Valid      => LiValid(c),
                S_Link_Ready      => LiReady(c),
                S_Link_Data       => LiData(c),
                S_Link_Keep       => LiKeep(c),
                S_Link_Last       => LiLast(c),
                S_Link_User       => LiUser(c),
                S_AxiLite_ArAddr  => ArAddr(c),
                S_AxiLite_ArValid => ArValid(c),
                S_AxiLite_ArReady => ArReady(c),
                S_AxiLite_AwAddr  => AwAddr(c),
                S_AxiLite_AwValid => AwValid(c),
                S_AxiLite_AwReady => AwReady(c),
                S_AxiLite_WData   => WData(c),
                S_AxiLite_WStrb   => WStrb(c),
                S_AxiLite_WValid  => WValid(c),
                S_AxiLite_WReady  => WReady(c),
                S_AxiLite_BResp   => BResp(c),
                S_AxiLite_BValid  => BValid(c),
                S_AxiLite_BReady  => BReady(c),
                S_AxiLite_RData   => RData(c),
                S_AxiLite_RResp   => RResp(c),
                S_AxiLite_RValid  => RValid(c),
                S_AxiLite_RReady  => RReady(c),
                Irq               => Irq(c),
                Err_Valid         => ErrValid(c),
                Err_Code          => ErrCode(c),
                Err_Port          => ErrPort(c),
                Err_Apid          => ErrApid(c)
            );

        -- Error event output and interrupt
        p_monitor : process (Clk) is
            variable N_v : natural := 0;
        begin
            if rising_edge(Clk) then
                if ErrValid(c) = '1' then
                    N_v           := N_v + 1;
                    Cores(c).Last <= ('1', ErrCode(c), ErrPort(c), ErrApid(c));
                end if;
                if Rst(c) = '1' then
                    N_v := 0;
                end if;
                Cores(c).Errors <= N_v;
            end if;
        end process;

        Cores(c).Irq <= Irq(c);

        -- Beats and packets of the link ports and the send ports with their times, for the throughput test
        p_link_stats : process (Clk) is
        begin
            if rising_edge(Clk) then

                for p in 0 to NumTx_g - 1 loop
                    if TxValid(c)(p) = '1' and TxReady(c)(p) = '1' then
                        SppTbStore_v.addBeat(ChTxIn_c + MaxPorts_c * c + p,
                                             bytesOfKeep(TxKeep(c)((p + 1) * Bytes_c - 1 downto p * Bytes_c)), now);
                        if TxLast(c)(p) = '1' then
                            SppTbStore_v.addPacket(ChTxIn_c + MaxPorts_c * c + p);
                        end if;
                    end if;
                end loop;

                if LoValid(c) = '1' and LoReady(c) = '1' then
                    SppTbStore_v.addBeat(ChLinkOut_c + c, bytesOfKeep(LoKeep(c)), now);
                    if LoLast(c) = '1' then
                        SppTbStore_v.addPacket(ChLinkOut_c + c);
                    end if;
                end if;
                if LiValid(c) = '1' and LiReady(c) = '1' then
                    SppTbStore_v.addBeat(ChLinkIn_c + c, bytesOfKeep(LiKeep(c)), now);
                    if LiLast(c) = '1' then
                        SppTbStore_v.addPacket(ChLinkIn_c + c);
                    end if;
                end if;
            end if;
        end process;

    end generate;

    -- Link from core A to core B and back
    i_link_ab : entity work.spp_core_tb_link
        generic map (
            DataWidth_g => DataWidth_g
        )
        port map (
            Clk        => Clk,
            S_Valid    => LoValid(0),
            S_Ready    => LoReady(0),
            S_Data     => LoData(0),
            S_Keep     => LoKeep(0),
            S_Last     => LoLast(0),
            S_User     => LoUser(0),
            Inj_Valid  => IjValid(1),
            Inj_Ready  => IjReady(1),
            Inj_Data   => IjData(1),
            Inj_Keep   => IjKeep(1),
            Inj_Last   => IjLast(1),
            Inj_User   => IjUser(1),
            M_Valid    => LmValid(1),
            M_Ready    => LmReady(1),
            M_Data     => LmData(1),
            M_Keep     => LmKeep(1),
            M_Last     => LmLast(1),
            M_User     => LmUser(1),
            Sel        => LinkAB.Sel,
            DropTarget => LinkAB.DropTarget,
            EepTarget  => LinkAB.EepTarget,
            Strip      => LinkAB.Strip,
            Stall      => Stall(0),
            Dropped    => StatAB.Dropped,
            Eeped      => StatAB.Eeped,
            Forwarded  => StatAB.Forwarded
        );

    i_link_ba : entity work.spp_core_tb_link
        generic map (
            DataWidth_g => DataWidth_g
        )
        port map (
            Clk        => Clk,
            S_Valid    => LoValid(1),
            S_Ready    => LoReady(1),
            S_Data     => LoData(1),
            S_Keep     => LoKeep(1),
            S_Last     => LoLast(1),
            S_User     => LoUser(1),
            Inj_Valid  => IjValid(0),
            Inj_Ready  => IjReady(0),
            Inj_Data   => IjData(0),
            Inj_Keep   => IjKeep(0),
            Inj_Last   => IjLast(0),
            Inj_User   => IjUser(0),
            M_Valid    => LmValid(0),
            M_Ready    => LmReady(0),
            M_Data     => LmData(0),
            M_Keep     => LmKeep(0),
            M_Last     => LmLast(0),
            M_User     => LmUser(0),
            Sel        => LinkBA.Sel,
            DropTarget => LinkBA.DropTarget,
            EepTarget  => LinkBA.EepTarget,
            Strip      => LinkBA.Strip,
            Stall      => Stall(1),
            Dropped    => StatBA.Dropped,
            Eeped      => StatBA.Eeped,
            Forwarded  => StatBA.Forwarded
        );

    -- Link inputs of the cores: directly from the link models, or through two N-Char adapters per direction
    g_direct : if not NChar_g generate
        LiValid <= LmValid;
        LmReady <= LiReady;
        LiData  <= LmData;
        LiKeep  <= LmKeep;
        LiLast  <= LmLast;
        LiUser  <= LmUser;
    end generate;

    g_nchar : if NChar_g generate

        -- Adapter k sends the packets of the link model toward the other core as N-Char characters and
        -- delivers the characters of the other adapter to core k
        g_adapter : for k in 0 to NumCores_c - 1 generate
            -- A signal, not an expression, as the actual of the port (docs/conventions.md)
            signal LinkUser : std_logic_vector(LinkUserWidth_c - 1 downto 0);
        begin

            LinkUser <= "0000" & LmUser(1 - k);

            i_nchar : entity work.spp_nchar
                generic map (
                    DataWidth_g => DataWidth_g
                )
                port map (
                    Clk           => Clk,
                    Rst           => Rst(k),
                    S_Link_Valid  => LmValid(1 - k),
                    S_Link_Ready  => LmReady(1 - k),
                    S_Link_Data   => LmData(1 - k),
                    S_Link_Keep   => LmKeep(1 - k),
                    S_Link_Last   => LmLast(1 - k),
                    S_Link_User   => LinkUser,
                    M_NChar_Valid => NcValid(k),
                    M_NChar_Ready => NcReady(k),
                    M_NChar_Data  => NcData(k),
                    M_NChar_Last  => NcLast(k),
                    S_NChar_Valid => NcValid(1 - k),
                    S_NChar_Ready => NcReady(1 - k),
                    S_NChar_Data  => NcData(1 - k),
                    S_NChar_Last  => NcLast(1 - k),
                    M_Link_Valid  => LiValid(k),
                    M_Link_Ready  => LiReady(k),
                    M_Link_Data   => LiData(k),
                    M_Link_Keep   => LiKeep(k),
                    M_Link_Last   => LiLast(k),
                    M_Link_User   => LiUser(k)
                );

        end generate;

    end generate;

end architecture;
