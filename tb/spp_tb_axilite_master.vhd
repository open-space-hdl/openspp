---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- AXI4-Lite master: wrapper of the UVVM AXI-Lite VVC with plain ports (32-bit data).

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library bitvis_vip_axilite;
    use bitvis_vip_axilite.axilite_bfm_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_tb_axilite_master is
    generic (
        InstanceIdx_g : natural;
        AddrWidth_g   : positive
    );
    port (
        Clk     : in    std_logic;
        ArAddr  : out   std_logic_vector(AddrWidth_g-1 downto 0);
        ArValid : out   std_logic;
        ArReady : in    std_logic;
        AwAddr  : out   std_logic_vector(AddrWidth_g-1 downto 0);
        AwValid : out   std_logic;
        AwReady : in    std_logic;
        WData   : out   std_logic_vector(31 downto 0);
        WStrb   : out   std_logic_vector(3 downto 0);
        WValid  : out   std_logic;
        WReady  : in    std_logic;
        BResp   : in    std_logic_vector(1 downto 0);
        BValid  : in    std_logic;
        BReady  : out   std_logic;
        RData   : in    std_logic_vector(31 downto 0);
        RResp   : in    std_logic_vector(1 downto 0);
        RValid  : in    std_logic;
        RReady  : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_tb_axilite_master is

    signal AxiIf : t_axilite_if(
                                 write_address_channel(
                                                          AwAddr(AddrWidth_g-1 downto 0)),
                                 write_data_channel(
                                                       WData(31 downto 0),
                                                       WStrb(3 downto 0)),
                                 read_address_channel(
                                                         ArAddr(AddrWidth_g-1 downto 0)),
                                 read_data_channel(
                                                      RData(31 downto 0))) := init_axilite_if_signals(AddrWidth_g, 32);

begin

    -- Signals driven by the DUT side
    AxiIf.write_address_channel.awready <= AwReady;
    AxiIf.write_data_channel.wready     <= WReady;
    AxiIf.write_response_channel.bresp  <= BResp;
    AxiIf.write_response_channel.bvalid <= BValid;
    AxiIf.read_address_channel.arready  <= ArReady;
    AxiIf.read_data_channel.rdata       <= RData;
    AxiIf.read_data_channel.rresp       <= RResp;
    AxiIf.read_data_channel.rvalid      <= RValid;

    ArAddr  <= AxiIf.read_address_channel.araddr;
    ArValid <= AxiIf.read_address_channel.arvalid;
    AwAddr  <= AxiIf.write_address_channel.awaddr;
    AwValid <= AxiIf.write_address_channel.awvalid;
    WData   <= AxiIf.write_data_channel.wdata;
    WStrb   <= AxiIf.write_data_channel.wstrb;
    WValid  <= AxiIf.write_data_channel.wvalid;
    BReady  <= AxiIf.write_response_channel.bready;
    RReady  <= AxiIf.read_data_channel.rready;

    i_vvc : entity bitvis_vip_axilite.axilite_vvc
        generic map (
            Gc_Addr_Width   => AddrWidth_g,
            Gc_Data_Width   => 32,
            Gc_Instance_Idx => InstanceIdx_g
        )
        port map (
            Clk                   => Clk,
            Axilite_Vvc_Master_If => AxiIf
        );

end architecture;
