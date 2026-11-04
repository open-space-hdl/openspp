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

    -- Reset control of a core. DpRst is applied while the field DpRst is '1'. A change of Arm arms the triggers
    -- once: in the cycle in which beat Beat of a packet (1 = first) is presented on M_Link (cycle 0), DpRst is
    -- applied from cycle DpDelay for DpCycles cycles and Rst from cycle RstDelay for RstCycles cycles; the link
    -- model stalls M_Link from the cycle in which beat StallBeat is presented for StallCycles cycles. A beat
    -- number 0 or a length 0 disables that part
    type ResetCtrl_t is record
        DpRst       : std_logic;
        Arm         : natural;
        Beat        : natural;
        DpDelay     : natural;
        DpCycles    : natural;
        RstDelay    : natural;
        RstCycles   : natural;
        StallBeat   : natural;
        StallCycles : natural;
    end record;

    constant ResetCtrlIdle_c : ResetCtrl_t := ('0', 0, 0, 0, 0, 0, 0, 0, 0);

    type ResetCtrlArray_t is array (0 to NumCores_c - 1) of ResetCtrl_t;

    -- Bins of the coverpoints of the resets (verification plan, section 6)
    type BinArray_t is array (0 to 7) of natural;

    -- DPRST_POINT: state of M_Link at the reset edge of DpRst
    constant PointNone_c       : natural := 0;
    constant PointFirstXfer_c  : natural := 1;
    constant PointMiddleXfer_c : natural := 2;
    constant PointLastXfer_c   : natural := 3;
    constant PointFirstPend_c  : natural := 4;
    constant PointMiddlePend_c : natural := 5;
    constant PointLastPend_c   : natural := 6;
    constant PointOpenIdle_c   : natural := 7;
    -- DPRST_LINK: no beat pending at the reset edge, a beat pending, end of the packet after the release
    constant LinkReady_c       : natural := 0;
    constant LinkPending_c     : natural := 1;
    constant LinkAfterRel_c    : natural := 2;
    -- DPRST_LENGTH: 1, 2 to 16, 17 to 2048, more than 2048 cycles
    constant Length1_c         : natural := 0;
    constant Length16_c        : natural := 1;
    constant Length2048_c      : natural := 2;
    constant LengthLong_c      : natural := 3;
    -- RESET_ORDER
    constant OrderDpRst_c      : natural := 0;
    constant OrderRst_c        : natural := 1;
    constant OrderSameEdge_c   : natural := 2;
    constant OrderRstInDp_c    : natural := 3;
    constant OrderDpInRst_c    : natural := 4;
    constant OrderRstFirst_c   : natural := 5;
    constant OrderDpFirst_c    : natural := 6;
    constant OrderSameRel_c    : natural := 7;
    -- RESET_SLINK
    constant SlinkIdle_c       : natural := 0;
    constant SlinkInside_c     : natural := 1;

    constant BinsZero_c : BinArray_t := (others => 0);

    -- Link output of a core (monitor spp_core_tb_monitor)
    type MonStat_t is record
        Beats   : natural;    -- beats transferred
        Packets : natural;    -- last beats transferred
        EepPkts : natural;    -- last beats with the EEP flag transferred
        Eeps    : natural;    -- EEP beats of the link output stage after DpRst transferred
        Point   : BinArray_t; -- DPRST_POINT
        Link    : BinArray_t; -- DPRST_LINK
    end record;

    constant MonStatInit_c : MonStat_t := (0, 0, 0, 0, BinsZero_c, BinsZero_c);

    type MonStatArray_t is array (0 to NumCores_c - 1) of MonStat_t;

    -- Ports of a core during its resets (reset probes of the harness)
    type ProbeStat_t is record
        Cycles     : natural; -- cycles checked in a reset
        Releases   : natural; -- release edges
        InReset    : boolean; -- a reset input was sampled '1' at the last edge
        SlinkBeats : natural; -- beats taken at S_Link of the packet in reception
        Length     : BinArray_t;
        Order      : BinArray_t;
        Slink      : BinArray_t;
    end record;

    constant ProbeStatInit_c : ProbeStat_t := (0, 0, false, 0, BinsZero_c, BinsZero_c, BinsZero_c);

    type ProbeStatArray_t is array (0 to NumCores_c - 1) of ProbeStat_t;

end package;
