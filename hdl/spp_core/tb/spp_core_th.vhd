---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the core: two cores A and B whose links are connected through link models, stream
-- sources and sinks on all user ports, injectors into both link inputs, an AXI4-Lite master VVC per
-- core, monitors of the error event outputs and statistics of the link and send ports.
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
        Clk      : out   std_logic := '0';
        RstA     : in    std_logic;
        RstB     : in    std_logic;
        LinkAB   : in    LinkCtrl_t;
        LinkBA   : in    LinkCtrl_t;
        StatAB   : out   LinkStat_t;
        StatBA   : out   LinkStat_t;
        Cores    : out   CoreStatArray_t
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

    signal Rst            : Slv_t;
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

    Rst(0) <= RstA;
    Rst(1) <= RstB;

    g_core : for c in 0 to NumCores_c - 1 generate
        constant ChTx_c  : natural := choose(c = 0, ChTxA_c, ChTxB_c);
        constant ChRx_c  : natural := choose(c = 0, ChRxA_c, ChRxB_c);
        constant ChInj_c : natural := choose(c = 0, ChInjA_c, ChInjB_c);

    begin

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
