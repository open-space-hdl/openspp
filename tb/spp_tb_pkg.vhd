---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Verification helpers shared by all OpenSPP testbenches (VUnit runner plus UVVM).
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package spp_tb_pkg is

    -- Ends a test: prints the UVVM alert summary, raises a TB_ERROR when an unexpected alert occurred
    -- or an expected alert did not occur (this stops the simulation and fails the VUnit test) and
    -- hands over to the VUnit runner.
    procedure sppTestEnd (signal runner : inout runner_sync_t);

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body spp_tb_pkg is

    procedure sppTestEnd (signal runner : inout runner_sync_t) is
    begin
        report_alert_counters(FINAL);
        if shared_uvvm_status.mismatch_on_expected_simulation_warnings_or_worse /= 0 then
            alert(TB_ERROR, "UVVM alert counters do not match the expected alerts", "sppTestEnd");
        end if;
        test_runner_cleanup(runner);
    end procedure;

end package body;
