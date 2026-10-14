---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the register file: clock, DUT, the send and the receive APID table it accesses, an
-- AXI4-Lite master VVC and a client A of the send APID table that can hold an entry.
--
-- Documentation: hdl/spp_mib/docs/verification_plan.md

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
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.spp_pkg.all;
    use work.spp_mib_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_mib_th is
    port (
        Clk     : out   std_logic := '0';
        Rst     : in    std_logic;
        Mib_In  : in    MibIn_t;
        Mib_Out : out   MibOut_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_mib_th is

    -- Initial table entries: send path enabled, receive path enabled (names as actuals, docs/conventions.md)
    constant TxInit_c : std_logic_vector(TxEntryWidth_c - 1 downto 0) := "100" & x"0000";
    constant RxInit_c : std_logic_vector(RxEntryWidth_c - 1 downto 0) := '1' & x"00000";

    signal ArAddr      : std_logic_vector(10 downto 0);
    signal ArValid     : std_logic;
    signal ArReady     : std_logic;
    signal AwAddr      : std_logic_vector(10 downto 0);
    signal AwValid     : std_logic;
    signal AwReady     : std_logic;
    signal WData       : std_logic_vector(31 downto 0);
    signal WStrb       : std_logic_vector(3 downto 0);
    signal WValid      : std_logic;
    signal WReady      : std_logic;
    signal BResp       : std_logic_vector(1 downto 0);
    signal BValid      : std_logic;
    signal BReady      : std_logic;
    signal RData       : std_logic_vector(31 downto 0);
    signal RResp       : std_logic_vector(1 downto 0);
    signal RValid      : std_logic;
    signal RReady      : std_logic;
    -- Send APID table
    signal TxB_Valid   : std_logic;
    signal TxB_Ready   : std_logic;
    signal TxB_Apid    : std_logic_vector(10 downto 0);
    signal TxB_RdValid : std_logic;
    signal TxB_RdData  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
    signal TxB_RdDed   : std_logic;
    signal TxB_WrEna   : std_logic;
    signal TxB_WrData  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
    signal TxB_Release : std_logic;
    signal TxA_Valid   : std_logic;
    signal TxA_Ready   : std_logic;
    signal TxA_Release : std_logic;
    signal TxA_Held    : std_logic := '0';
    -- Receive APID table
    signal RxB_Valid   : std_logic;
    signal RxB_Ready   : std_logic;
    signal RxB_Apid    : std_logic_vector(10 downto 0);
    signal RxB_RdValid : std_logic;
    signal RxB_RdData  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
    signal RxB_RdDed   : std_logic;
    signal RxB_WrEna   : std_logic;
    signal RxB_WrData  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
    signal RxB_Release : std_logic;
    signal RxA_Valid   : std_logic;
    signal RxA_Ready   : std_logic;
    signal RxA_Release : std_logic;
    signal RxA_Held    : std_logic := '0';
    signal TxBusy      : std_logic;
    signal RxBusy      : std_logic;
    signal TxInj       : std_logic;

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    -- The clock is driven on the port, so that testbench and DUT see the same signal (no delta cycle between them)
    Clk <= not Clk after ClkPeriod_c / 2;

    i_axi : entity work.spp_tb_axilite_master
        generic map (
            InstanceIdx_g => Axi_c,
            AddrWidth_g   => 11
        )
        port map (
            Clk     => Clk,
            ArAddr  => ArAddr,
            ArValid => ArValid,
            ArReady => ArReady,
            AwAddr  => AwAddr,
            AwValid => AwValid,
            AwReady => AwReady,
            WData   => WData,
            WStrb   => WStrb,
            WValid  => WValid,
            WReady  => WReady,
            BResp   => BResp,
            BValid  => BValid,
            BReady  => BReady,
            RData   => RData,
            RResp   => RResp,
            RValid  => RValid,
            RReady  => RReady
        );

    i_dut : entity work.spp_mib
        generic map (
            DataWidth_g     => 64,
            NumTx_g         => NumTx_c,
            NumRx_g         => NumRx_c,
            NumDest_g       => NumDest_c,
            SpwAddrBytes_g  => SpwAddrBytes_c,
            Encapsulation_g => true,
            TxOctetString_g => TxOctet_c,
            RxOctetString_g => RxOctet_c,
            TxBufferBytes_g => TxBuffer_c,
            RxBufferBytes_g => RxBuffer_c,
            MaxLength_g     => MaxLength_c,
            RoundRobin_g    => '1',
            Tla_g           => Tla_c,
            NumErr_g        => NumErr_c
        )
        port map (
            Clk               => Clk,
            Rst               => Rst,
            S_AxiLite_ArAddr  => ArAddr,
            S_AxiLite_ArValid => ArValid,
            S_AxiLite_ArReady => ArReady,
            S_AxiLite_AwAddr  => AwAddr,
            S_AxiLite_AwValid => AwValid,
            S_AxiLite_AwReady => AwReady,
            S_AxiLite_WData   => WData,
            S_AxiLite_WStrb   => WStrb,
            S_AxiLite_WValid  => WValid,
            S_AxiLite_WReady  => WReady,
            S_AxiLite_BResp   => BResp,
            S_AxiLite_BValid  => BValid,
            S_AxiLite_BReady  => BReady,
            S_AxiLite_RData   => RData,
            S_AxiLite_RResp   => RResp,
            S_AxiLite_RValid  => RValid,
            S_AxiLite_RReady  => RReady,
            Irq               => Mib_Out.Irq,
            Cfg_MaxLength     => Mib_Out.MaxLength,
            Cfg_RoundRobin    => Mib_Out.RoundRobin,
            Cfg_IdleDeliver   => Mib_Out.IdleDeliver,
            Cfg_TlaCheck      => Mib_Out.TlaCheck,
            Cfg_RxStrip       => Mib_Out.RxStrip,
            Cfg_Tla           => Mib_Out.Tla,
            Cfg_DestAddr      => Mib_Out.DestAddr,
            Cfg_DestAddrLen   => Mib_Out.DestAddrLen,
            Cfg_DestTla       => Mib_Out.DestTla,
            Cfg_DestUa        => Mib_Out.DestUa,
            Cfg_ScrubEnable   => Mib_Out.ScrubEnable,
            TxTbl_Valid       => TxB_Valid,
            TxTbl_Ready       => TxB_Ready,
            TxTbl_Apid        => TxB_Apid,
            TxTbl_RdValid     => TxB_RdValid,
            TxTbl_RdData      => TxB_RdData,
            TxTbl_RdDed       => TxB_RdDed,
            TxTbl_WrEna       => TxB_WrEna,
            TxTbl_WrData      => TxB_WrData,
            TxTbl_Release     => TxB_Release,
            TxTbl_Busy        => TxBusy,
            RxTbl_Valid       => RxB_Valid,
            RxTbl_Ready       => RxB_Ready,
            RxTbl_Apid        => RxB_Apid,
            RxTbl_RdValid     => RxB_RdValid,
            RxTbl_RdData      => RxB_RdData,
            RxTbl_RdDed       => RxB_RdDed,
            RxTbl_WrEna       => RxB_WrEna,
            RxTbl_WrData      => RxB_WrData,
            RxTbl_Release     => RxB_Release,
            RxTbl_Busy        => RxBusy,
            Err               => Mib_In.Err,
            Tx_Sent           => Mib_In.TxSent,
            Rx_Delivered      => Mib_In.RxDelivered,
            Rx_Loss           => Mib_In.RxLoss,
            Err_Valid         => Mib_Out.ErrValid,
            Err_Code          => Mib_Out.ErrCode,
            Err_Port          => Mib_Out.ErrPort,
            Err_Apid          => Mib_Out.ErrApid,
            Ecc_Sec           => Mib_In.EccSec,
            Ecc_Ded           => Mib_In.EccDed,
            Inj_TxValid       => Mib_Out.InjTxValid,
            Inj_RxValid       => Mib_Out.InjRxValid,
            Inj_Channel       => Mib_Out.InjChannel,
            Inj_Double        => Mib_Out.InjDouble
        );

    Mib_Out.TxBusy <= TxBusy;

    -- Clients A of the send and the receive APID table: hold an entry while TxHold or RxHold is set
    p_hold : process (Clk) is
    begin
        if rising_edge(Clk) then
            if TxA_Ready = '1' then
                TxA_Held <= '1';
            elsif TxA_Release = '1' then
                TxA_Held <= '0';
            end if;
            if RxA_Ready = '1' then
                RxA_Held <= '1';
            elsif RxA_Release = '1' then
                RxA_Held <= '0';
            end if;
        end if;
    end process;

    TxA_Valid   <= Mib_In.TxHold and not TxA_Held;
    TxA_Release <= TxA_Held and not Mib_In.TxHold;
    RxA_Valid   <= Mib_In.RxHold and not RxA_Held;
    RxA_Release <= RxA_Held and not Mib_In.RxHold;

    i_txtable : entity work.spp_apid_table
        generic map (
            Width_g => TxEntryWidth_c
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Init_Value     => TxInit_c,
            Init_Busy      => TxBusy,
            A_Valid        => TxA_Valid,
            A_Ready        => TxA_Ready,
            A_Apid         => "00000000101",
            A_RdValid      => open,
            A_RdData       => open,
            A_RdDed        => open,
            A_WrEna        => '0',
            A_WrData       => (others => '0'),
            A_Release      => TxA_Release,
            B_Valid        => TxB_Valid,
            B_Ready        => TxB_Ready,
            B_Apid         => TxB_Apid,
            B_RdValid      => TxB_RdValid,
            B_RdData       => TxB_RdData,
            B_RdDed        => TxB_RdDed,
            B_WrEna        => TxB_WrEna,
            B_WrData       => TxB_WrData,
            B_Release      => TxB_Release,
            Ecc_Sec        => open,
            Ecc_Ded        => open,
            Scrub_Sec      => open,
            Scrub_Ded      => open,
            ErrInj_BitFlip => injPattern(eccCodewordWidth(TxEntryWidth_c), Mib_Out.InjDouble),
            ErrInj_Valid   => TxInj
        );

    -- Injection channel 2 NumTx_c of the sending end is the send APID table
    TxInj <= Mib_Out.InjTxValid when unsigned(Mib_Out.InjChannel) = 2 * NumTx_c else '0';

    i_rxtable : entity work.spp_apid_table
        generic map (
            Width_g => RxEntryWidth_c
        )
        port map (
            Clk         => Clk,
            Rst         => Rst,
            Init_Value  => RxInit_c,
            Init_Busy   => RxBusy,
            A_Valid     => RxA_Valid,
            A_Ready     => RxA_Ready,
            A_Apid      => "00000000101",
            A_RdValid   => open,
            A_RdData    => open,
            A_RdDed     => open,
            A_WrEna     => '0',
            A_WrData    => (others => '0'),
            A_Release   => RxA_Release,
            B_Valid     => RxB_Valid,
            B_Ready     => RxB_Ready,
            B_Apid      => RxB_Apid,
            B_RdValid   => RxB_RdValid,
            B_RdData    => RxB_RdData,
            B_RdDed     => RxB_RdDed,
            B_WrEna     => RxB_WrEna,
            B_WrData    => RxB_WrData,
            B_Release   => RxB_Release,
            Ecc_Sec     => open,
            Ecc_Ded     => open,
            Scrub_Sec   => open,
            Scrub_Ded   => open
        );

end architecture;
