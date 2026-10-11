---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Constants and types of the testbench of the register file.
--
-- Documentation: hdl/spp_mib/docs/verification_plan.md

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
package spp_mib_tb_pkg is

    constant ClkPeriod_c    : time    := 10 ns;
    constant Axi_c          : natural := 0;
    -- Configuration of the DUT
    constant NumTx_c        : positive                                  := 3;
    constant NumRx_c        : positive                                  := 2;
    constant NumDest_c      : positive                                  := 3;
    constant SpwAddrBytes_c : natural                                   := 6;
    constant NumErr_c       : positive                                  := NumTx_c + 4;
    constant TxOctet_c      : std_logic_vector(MaxPorts_c - 1 downto 0) := x"0005";
    constant RxOctet_c      : std_logic_vector(MaxPorts_c - 1 downto 0) := x"0001";
    constant TxBuffer_c     : positive                                  := 4096;
    constant RxBuffer_c     : positive                                  := 8192;
    constant MaxLength_c    : positive                                  := 1000;
    constant Tla_c          : std_logic_vector(7 downto 0)              := x"40";

    -- Inputs of the register file driven by the test sequencer
    type MibIn_t is record
        Err         : ErrEventArray_t(0 to NumErr_c - 1);
        TxSent      : std_logic;
        RxDelivered : std_logic_vector(NumRx_c - 1 downto 0);
        RxLoss      : std_logic;
        EccSec      : std_logic_vector(7 downto 0);
        EccDed      : std_logic_vector(7 downto 0);
        TxHold      : std_logic; -- '1': client A holds an entry of the send APID table
        RxHold      : std_logic; -- '1': client A holds an entry of the receive APID table
    end record;

    constant MibInIdle_c : MibIn_t := ((others => ErrEventNone_c), '0', (others => '0'), '0', (others => '0'),
                                       (others => '0'), '0', '0');

    -- Outputs of the register file
    type MibOut_t is record
        MaxLength   : std_logic_vector(LengthWidth_c - 1 downto 0);
        RoundRobin  : std_logic;
        IdleDeliver : std_logic;
        TlaCheck    : std_logic;
        RxStrip     : std_logic_vector(3 downto 0);
        Tla         : std_logic_vector(7 downto 0);
        DestAddr    : std_logic_vector(NumDest_c * 8 * SpwAddrBytes_c - 1 downto 0);
        DestAddrLen : std_logic_vector(NumDest_c * 5 - 1 downto 0);
        DestTla     : std_logic_vector(NumDest_c * 8 - 1 downto 0);
        DestUa      : std_logic_vector(NumDest_c * 8 - 1 downto 0);
        ScrubEnable : std_logic;
        Irq         : std_logic;
        ErrValid    : std_logic;
        ErrCode     : std_logic_vector(4 downto 0);
        ErrPort     : std_logic_vector(3 downto 0);
        ErrApid     : std_logic_vector(10 downto 0);
        InjTxValid  : std_logic;
        InjRxValid  : std_logic;
        InjChannel  : std_logic_vector(5 downto 0);
        InjDouble   : std_logic;
        TxBusy      : std_logic;
    end record;

end package;
