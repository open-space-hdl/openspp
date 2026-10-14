---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Constants and types of the testbench of two cores connected by a link model.
--
-- Documentation: hdl/spp_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package spp_core_tb_pkg is

    constant ClkPeriod_c : time := 10 ns;
    -- Both cores: ports 0 and 2 to 15 Octet String Service, port 1 Packet Service, on both ends
    constant Octet_c     : std_logic_vector(MaxPorts_c - 1 downto 0) := x"FFFD";
    constant NumCores_c  : positive                                  := 2;

    -- AXI4-Lite VVC of core c
    constant AxiA_c : natural := 0;
    constant AxiB_c : natural := 1;

    -- Stream channels: send port p of core A / B, receive port p of core A / B (up to MaxPorts_c ports each),
    -- injectors into the link inputs of core A / B
    constant ChTxA_c     : natural := 0;
    constant ChTxB_c     : natural := 16;
    constant ChRxA_c     : natural := 32;
    constant ChRxB_c     : natural := 48;
    constant ChInjA_c    : natural := 64;
    constant ChInjB_c    : natural := 65;
    -- Statistics only (beats and packets with their times): link output and link input of core c, send port p
    -- of core c (ChTxIn_c + MaxPorts_c * c + p)
    constant ChLinkOut_c : natural := 66;
    constant ChLinkIn_c  : natural := 68;
    constant ChTxIn_c    : natural := 70;

    type NatArray_t is array (natural range <>) of natural;

    -- Control and observation of the link model from core X to core Y. Strip removes the leading bytes of
    -- every packet of the sending core, as the routers of a network remove path address bytes
    type LinkCtrl_t is record
        Sel        : std_logic;
        DropTarget : natural;
        EepTarget  : natural;
        Strip      : natural;
    end record;

    constant LinkCtrlIdle_c : LinkCtrl_t := ('0', 0, 0, 0);

    type LinkStat_t is record
        Dropped   : natural;
        Eeped     : natural;
        Forwarded : natural;
    end record;

    -- Error event outputs and interrupts of a core
    type CoreStat_t is record
        Irq    : std_logic;
        Errors : natural;
        Last   : ErrEvent_t;
    end record;

    type CoreStatArray_t is array (0 to NumCores_c - 1) of CoreStat_t;

end package;
