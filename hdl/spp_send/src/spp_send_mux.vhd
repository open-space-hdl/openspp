---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Multiplexer (SE-2) of the Packet Transfer Function: selects the next send buffer with a complete
-- SDU by fixed priority (port 0 first) or round robin, the Packet Multiplexing Scheme of management.
--
-- Documentation: hdl/spp_send/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_logic.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_send_mux is
    generic (
        NumTx_g : positive := 1
    );
    port (
        -- Control
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Multiplexing scheme: '0' fixed priority, '1' round robin (SPP 4.2.3.2)
        Cfg_RoundRobin : in    std_logic;
        -- Ports with a complete SDU, the selected port (one-hot) and its acceptance
        Req            : in    std_logic_vector(NumTx_g - 1 downto 0);
        Grant          : out   std_logic_vector(NumTx_g - 1 downto 0);
        Grant_Valid    : out   std_logic;
        Grant_Ack      : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_send_mux is

    -- The arbiters give the left-most bit the highest priority: port 0 is mapped to the left-most bit
    signal ReqRev    : std_logic_vector(NumTx_g - 1 downto 0);
    signal GrantPrio : std_logic_vector(NumTx_g - 1 downto 0);
    signal GrantRr   : std_logic_vector(NumTx_g - 1 downto 0);
    signal ValidRr   : std_logic;
    signal ReadyRr   : std_logic;

begin

    ReqRev  <= invertBitOrder(Req);
    ReadyRr <= Grant_Ack and Cfg_RoundRobin;

    i_prio : entity olo.olo_base_arb_prio
        generic map (
            Width_g   => NumTx_g,
            Latency_g => 0
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Req    => ReqRev,
            Out_Grant => GrantPrio
        );

    i_rr : entity olo.olo_base_arb_rr
        generic map (
            Width_g => NumTx_g
        )
        port map (
            Clk       => Clk,
            Rst       => Rst,
            In_Req    => ReqRev,
            Out_Grant => GrantRr,
            Out_Ready => ReadyRr,
            Out_Valid => ValidRr
        );

    Grant       <= invertBitOrder(GrantRr) when Cfg_RoundRobin = '1' else invertBitOrder(GrantPrio);
    Grant_Valid <= ValidRr when Cfg_RoundRobin = '1' else (or Req);

end architecture;
