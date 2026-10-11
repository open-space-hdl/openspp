---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the register file: every register through the AXI4-Lite VVC, the configuration
-- outputs, the access to both APID tables, the counters, the event flags with the interrupt, the EDAC
-- monitor and the error injection.
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

library bitvis_vip_axilite;
    context bitvis_vip_axilite.vvc_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.spp_pkg.all;
    use work.spp_regs_pkg.all;
    use work.spp_tb_pkg.all;
    use work.spp_mib_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_mib_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_mib_tb is

    signal Clk      : std_logic;
    signal Rst      : std_logic                    := '1';
    signal MibIn    : MibIn_t                      := MibInIdle_c;
    signal MibOut   : MibOut_t;
    signal InjTxCnt : natural                      := 0;
    signal InjRxCnt : natural                      := 0;
    signal ErrOuts  : natural                      := 0;
    signal InjTx    : std_logic_vector(6 downto 0) := (others => '0');
    signal InjRx    : std_logic_vector(6 downto 0) := (others => '0');
    signal ErrSeen  : ErrEvent_t                   := ErrEventNone_c;

begin

    test_runner_watchdog(runner, 20 ms);

    p_main : process is
        -- Error codes and the counter register and half (0: bits 15:0, 1: bits 31:16) of each
        type CodeList_t is array (natural range <>) of natural;

        constant Codes_c : CodeList_t(0 to 19) := (16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#, 16#08#,
                                                   16#10#, 16#11#, 16#12#, 16#13#, 16#14#, 16#15#, 16#16#, 16#17#,
                                                   16#18#, 16#19#, 16#1A#, 16#1B#);
        constant Regs_c  : CodeList_t(0 to 9)  := (RegErrTx1_c, RegErrTx2_c, RegErrTx3_c, RegErrTx4_c, RegErrRx1_c,
                                                   RegErrRx2_c, RegErrRx3_c, RegErrRx4_c, RegErrRx5_c, RegErrRx6_c);

        procedure regWrite (
            addr : natural;
            data : std_logic_vector(31 downto 0)) is
        begin
            axilite_write(AXILITE_VVCT, Axi_c, to_unsigned(addr, 11), data, "write 0x" & to_hstring(to_unsigned(addr, 12)));
            await_completion(AXILITE_VVCT, Axi_c, 100 us);
        end procedure;

        procedure regCheck (
            addr : natural;
            data : std_logic_vector(31 downto 0);
            msg  : string) is
        begin
            axilite_check(AXILITE_VVCT, Axi_c, to_unsigned(addr, 11), data, msg);
            await_completion(AXILITE_VVCT, Axi_c, 100 us);
        end procedure;

        -- One cycle with the given error events
        procedure events (ev : ErrEventArray_t(0 to NumErr_c - 1)) is
        begin
            wait until rising_edge(Clk);
            MibIn.Err <= ev;
            wait until rising_edge(Clk);
            MibIn.Err <= (others => ErrEventNone_c);
        end procedure;

        function ev (
            code : ErrCode_t;
            idx  : natural := 0;
            apid : natural := 0) return ErrEvent_t is
        begin
            return ('1', code, std_logic_vector(to_unsigned(idx, 4)), std_logic_vector(to_unsigned(apid, 11)));
        end function;

        procedure oneEvent (
            i    : natural;
            code : ErrCode_t;
            idx  : natural := 0;
            apid : natural := 0) is
            variable E_v : ErrEventArray_t(0 to NumErr_c - 1) := (others => ErrEventNone_c);
        begin
            E_v(i) := ev(code, idx, apid);
            events(E_v);
        end procedure;

        procedure pulse (n : natural; kind : natural) is
        begin

            for k in 1 to n loop
                wait until rising_edge(Clk);

                case kind is
                    when 0 => MibIn.TxSent <= '1';
                    when 1 => MibIn.RxDelivered <= (others => '1');
                    when others => MibIn.RxLoss <= '1';
                end case;

                wait until rising_edge(Clk);
                MibIn.TxSent      <= '0';
                MibIn.RxDelivered <= (others => '0');
                MibIn.RxLoss      <= '0';
            end loop;

        end procedure;

        procedure ecc (channel : natural; ded : boolean) is
        begin
            wait until rising_edge(Clk);
            if ded then
                MibIn.EccDed(channel) <= '1';
            else
                MibIn.EccSec(channel) <= '1';
            end if;
            wait until rising_edge(Clk);
            MibIn.EccSec <= (others => '0');
            MibIn.EccDed <= (others => '0');
        end procedure;

        function word (n : natural) return std_logic_vector is
        begin
            return std_logic_vector(to_unsigned(n, 32));
        end function;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        await_uvvm_initialization(VOID);
        shared_axilite_vvc_config(Axi_c).bfm_config.max_wait_cycles := 10000;
        disable_log_msg(ALL_MESSAGES);
        enable_log_msg(ID_LOG_HDR);

        while test_suite loop
            Rst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            Rst <= '0';
            wait for 5 * ClkPeriod_c;

            if run("test_identification") then
                regCheck(RegId_c, x"53505001", "ID");
                regCheck(RegGenerics_c, x"02830C43", "generics: 3 send ports, 2 receive ports, 3 destinations, 6 address bytes, 8 bytes per beat, CPTP");
                regCheck(RegServices_c, x"00010005", "services of the ports");
                regCheck(RegTxBuffer_c, word(TxBuffer_c), "send buffer");
                regCheck(RegRxBuffer_c, word(RxBuffer_c), "receive buffer");
                -- Unused addresses read zero
                regCheck(16#014#, x"00000000", "unused address");
                regCheck(16#7FC#, x"00000000", "unused address at the end");

            elsif run("test_config") then
                -- Reset values and configuration outputs
                regCheck(RegConfig_c, x"00004001", "CONFIG after reset");
                regCheck(RegMaxLength_c, word(MaxLength_c), "MAX_LENGTH after reset");
                regCheck(RegScrub_c, x"00000001", "SCRUB after reset");
                check_value(MibOut.RoundRobin, '1', ERROR, "round robin after reset");
                check_value(MibOut.Tla, Tla_c, ERROR, "own TLA after reset");
                check_value(to_integer(unsigned(MibOut.MaxLength)), MaxLength_c, ERROR, "maximum length after reset");
                -- Writes
                regWrite(RegConfig_c, x"0000A5F6");
                regCheck(RegConfig_c, x"0000A5F6", "CONFIG");
                check_value(MibOut.RoundRobin, '0', ERROR, "round robin");
                check_value(MibOut.IdleDeliver, '1', ERROR, "idle delivery");
                check_value(MibOut.TlaCheck, '1', ERROR, "TLA filter");
                check_value(MibOut.RxStrip, x"F", ERROR, "strip count");
                check_value(MibOut.Tla, x"A5", ERROR, "own TLA");
                regWrite(RegMaxLength_c, word(4000));
                regCheck(RegMaxLength_c, word(4000), "MAX_LENGTH 4000");
                check_value(to_integer(unsigned(MibOut.MaxLength)), 4000, ERROR, "maximum length output");
                regWrite(RegMaxLength_c, word(3));
                regCheck(RegMaxLength_c, word(7), "MAX_LENGTH limited to 7");
                regWrite(RegMaxLength_c, x"0001FFFF");
                regCheck(RegMaxLength_c, word(65542), "MAX_LENGTH limited to 65542");
                regWrite(RegScrub_c, x"00000000");
                regCheck(RegScrub_c, x"00000000", "SCRUB");
                check_value(MibOut.ScrubEnable, '0', ERROR, "scrubbers disabled");
                -- Reset restores the reset values
                Rst <= '1';
                wait until rising_edge(Clk);
                Rst <= '0';
                regCheck(RegConfig_c, x"00004001", "CONFIG after the second reset");
                regCheck(RegMaxLength_c, word(MaxLength_c), "MAX_LENGTH after the second reset");

            elsif run("test_destinations") then

                for d in 0 to NumDest_c - 1 loop
                    regCheck(RegDestCtrl_c + d * RegDestStride_c, x"000000FE", "destination after reset");
                    regWrite(RegDestCtrl_c + d * RegDestStride_c, word(65536 * (d + 3) + 256 * (16 + d) + d + 1));
                    regWrite(RegDestAddr0_c + d * RegDestStride_c, x"04030201" xor word(d));
                    regWrite(RegDestAddr1_c + d * RegDestStride_c, x"08070605");
                end loop;

                for d in 0 to NumDest_c - 1 loop
                    regCheck(RegDestCtrl_c + d * RegDestStride_c, word(65536 * (d + 3) + 256 * (16 + d) + d + 1), "DEST_CTRL");
                    regCheck(RegDestAddr0_c + d * RegDestStride_c, x"04030201" xor word(d), "DEST_ADDR0");
                    -- Bytes beyond the 6 address bytes are not stored
                    regCheck(RegDestAddr1_c + d * RegDestStride_c, x"00000605", "DEST_ADDR1");
                    regCheck(RegDestAddr2_c + d * RegDestStride_c, x"00000000", "DEST_ADDR2");
                    check_value(MibOut.DestTla(8 * d + 7 downto 8 * d), std_logic_vector(to_unsigned(d + 1, 8)), ERROR, "TLA output");
                    check_value(MibOut.DestUa(8 * d + 7 downto 8 * d), std_logic_vector(to_unsigned(16 + d, 8)), ERROR, "UA output");
                    check_value(MibOut.DestAddrLen(5 * d + 4 downto 5 * d), std_logic_vector(to_unsigned(d + 3, 5)), ERROR, "length output");
                    check_value(MibOut.DestAddr(48 * d + 47 downto 48 * d), x"0605" & (x"04030201" xor word(d)), ERROR, "address output");
                end loop;

                -- A destination beyond NUM_DEST does not exist
                regWrite(RegDestCtrl_c + 3 * RegDestStride_c, x"001F1234");
                regCheck(RegDestCtrl_c + 3 * RegDestStride_c, x"00000000", "destination 3 does not exist");

            elsif run("test_tables") then
                -- During the initialisation a read of an entry waits for the access
                regWrite(RegTxTableApid_c, word(5));
                regCheck(RegTxTableEntry_c, x"00040000", "send table entry after the initialisation");
                regWrite(RegRxTableApid_c, word(2047));
                regCheck(RegRxTableEntry_c, x"00100000", "receive table entry after the initialisation");
                regCheck(RegTableStatus_c, x"00000000", "tables idle");
                -- Write and read back
                regWrite(RegTxTableApid_c, word(100));
                regWrite(RegTxTableEntry_c, x"0004C123");
                regWrite(RegTxTableApid_c, word(101));
                regCheck(RegTxTableEntry_c, x"00040000", "other entry unchanged");
                regWrite(RegTxTableApid_c, word(100));
                regCheck(RegTxTableEntry_c, x"0004C123", "send table entry 100");
                regCheck(RegTxTableApid_c, word(100), "TX_TABLE_APID");
                regWrite(RegRxTableApid_c, word(7));
                regWrite(RegRxTableEntry_c, x"0011C055");
                regWrite(RegRxTableApid_c, word(7));
                regCheck(RegRxTableEntry_c, x"0011C055", "receive table entry 7");
                regCheck(RegRxTableApid_c, word(7), "RX_TABLE_APID");
                -- A write during a pending access is ignored and flagged
                MibIn.TxHold <= '1';
                wait for 10 * ClkPeriod_c;
                regWrite(RegTxTableApid_c, word(9));
                regWrite(RegTxTableEntry_c, x"00040009");
                regCheck(RegTableStatus_c, x"00000005", "send table busy, overrun");
                MibIn.TxHold <= '0';
                wait for 10 * ClkPeriod_c;
                regCheck(RegTxTableEntry_c, x"00040000", "entry 9 read after the hold");
                -- The same on the receive table; the read of the entry waits for the end of the hold
                MibIn.RxHold <= '1', '0' after 2 us;
                wait for 10 * ClkPeriod_c;
                regWrite(RegRxTableApid_c, word(9));
                regWrite(RegRxTableEntry_c, x"00100009");
                regCheck(RegTableStatus_c, x"0000000E", "receive table busy, both overruns");
                regCheck(RegRxTableEntry_c, x"00100000", "receive entry 9 read after the hold");
                -- Each overrun flag is cleared by its own bit
                regWrite(RegTableStatus_c, x"00000008");
                regCheck(RegTableStatus_c, x"00000004", "send table overrun kept");
                regWrite(RegTableStatus_c, x"00000004");
                regCheck(RegTableStatus_c, x"00000000", "overrun cleared");
                -- Double error in an entry
                regWrite(RegEccInject_c, x"00000206");
                regWrite(RegTxTableApid_c, word(12));
                regWrite(RegTxTableEntry_c, x"00040012");
                regWrite(RegTxTableApid_c, word(12));
                regCheck(RegTxTableEntry_c, x"80040012", "double error flagged with the entry");

            elsif run("test_counters") then

                -- Every error code once, port and APID in LAST_ERROR
                for i in Codes_c'range loop
                    oneEvent(i mod NumErr_c, std_logic_vector(to_unsigned(Codes_c(i), 5)), i mod 16, 100 + i);
                end loop;

                wait for 5 * ClkPeriod_c;

                for k in Regs_c'range loop
                    regCheck(Regs_c(k), x"00010001", "one event per code");
                end loop;

                regCheck(RegLastError_c, word(65536 * 119 + 256 * (19 mod 16) + 16#1B#), "LAST_ERROR");
                -- The same code from every source in one cycle
                events((others => ev(ErrRxEep_c, 1, 1)));
                wait for 5 * ClkPeriod_c;
                regCheck(RegErrRx1_c, word(65536 * 1 + 1 + NumErr_c), "EEP counted from every source");
                -- Two events in one cycle: the lower index is reported
                events((2 => ev(ErrTxNoPath_c, 2, 22), 5 => ev(ErrRxIdle_c, 0, 2047), others => ErrEventNone_c));
                wait for 5 * ClkPeriod_c;
                regCheck(RegLastError_c, word(65536 * 22 + 256 * 2 + 16#07#), "LAST_ERROR of the lower index");
                check_value(ErrOuts, 22, ERROR, "error events on the event output (one per cycle)");
                check_value(ErrSeen.Code, ErrTxNoPath_c, ERROR, "event output of the lower index");
                -- A write clears both counters of a register
                regWrite(RegErrRx1_c, x"00000000");
                regCheck(RegErrRx1_c, x"00000000", "counters cleared");
                -- Saturation at 0xFFFF
                wait until rising_edge(Clk);
                MibIn.Err(0) <= ev(ErrTxShort_c);
                wait for 65540 * ClkPeriod_c;
                wait until rising_edge(Clk);
                MibIn.Err(0) <= ErrEventNone_c;
                regCheck(RegErrTx1_c, x"FFFF0001", "counter saturated");
                -- Packet counters
                pulse(10, 0);
                pulse(5, 1);
                pulse(3, 2);
                regCheck(RegTxPackets_c, word(10), "packets sent");
                regCheck(RegRxPackets_c, word(10), "SDUs delivered (two ports)");
                regCheck(RegRxLoss_c, word(3), "loss indications");
                regWrite(RegTxPackets_c, x"00000000");
                regWrite(RegRxPackets_c, x"00000000");
                regWrite(RegRxLoss_c, x"00000000");
                regCheck(RegTxPackets_c, word(0), "packets sent cleared");
                regCheck(RegRxPackets_c, word(0), "SDUs delivered cleared");
                regCheck(RegRxLoss_c, word(0), "loss indications cleared");

            elsif run("test_events") then
                -- Every event flag, the interrupt with its enable, write one to clear
                oneEvent(0, ErrTxOversize_c);
                oneEvent(4, ErrRxEep_c);
                pulse(1, 0);
                pulse(1, 1);
                pulse(1, 2);
                ecc(0, false);
                ecc(1, true);
                wait for 5 * ClkPeriod_c;
                regCheck(RegEvents_c, x"0000007F", "all event flags");
                check_value(MibOut.Irq, '0', ERROR, "no interrupt without enable");

                for b in 0 to 6 loop
                    regWrite(RegIrqEn_c, word(2 ** b));
                    regCheck(RegIrqEn_c, word(2 ** b), "IRQ_EN");
                    wait for 2 * ClkPeriod_c;
                    check_value(MibOut.Irq, '1', ERROR, "interrupt of event " & to_string(b));
                    regCheck(RegIrqStatus_c, x"00000001", "IRQ_STATUS");
                    regWrite(RegEvents_c, word(2 ** b));
                    wait for 2 * ClkPeriod_c;
                    check_value(MibOut.Irq, '0', ERROR, "interrupt cleared with event " & to_string(b));
                end loop;

                regCheck(RegEvents_c, x"00000000", "all event flags cleared");

            elsif run("test_ecc") then
                -- Counters of the EDAC monitor, sticky double error flags, clear
                ecc(3, false);
                ecc(3, false);
                ecc(3, true);
                ecc(7, true);
                wait for 5 * ClkPeriod_c;
                regCheck(RegEccStatus_c, x"00000088", "double errors of channels 3 and 7");
                regWrite(RegEccSelect_c, word(3));
                regCheck(RegEccSelect_c, word(3), "ECC_SELECT");
                regCheck(RegEccCount_c, x"00010002", "counters of channel 3");
                regWrite(RegEccCount_c, x"00000000");
                regCheck(RegEccCount_c, x"00000000", "counters of channel 3 cleared");
                regWrite(RegEccSelect_c, word(7));
                regCheck(RegEccCount_c, x"00010000", "counters of channel 7");
                regWrite(RegEccStatus_c, x"00000000");
                regCheck(RegEccStatus_c, x"00000000", "flags cleared");
                regCheck(RegEccCount_c, x"00000000", "all counters cleared");
                -- Injection commands
                regWrite(RegEccInject_c, x"00000104");
                regWrite(RegEccInject_c, x"00000282");
                regWrite(RegEccInject_c, x"00000005");
                wait for 5 * ClkPeriod_c;
                check_value(InjTxCnt, 1, ERROR, "one injection into the sending end");
                check_value(InjTx, "0000100", ERROR, "single error into channel 4 of the sending end");
                check_value(InjRxCnt, 1, ERROR, "one injection into the receiving end");
                check_value(InjRx, "1000010", ERROR, "double error into channel 2 of the receiving end");
                regCheck(RegEccInject_c, x"00000000", "ECC_INJECT reads zero");
            end if;

            wait for 10 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    -- Injection commands and error event output as the register file outputs them
    p_monitor : process (Clk) is
    begin
        if rising_edge(Clk) then
            if MibOut.InjTxValid = '1' then
                InjTxCnt <= InjTxCnt + 1;
                InjTx    <= MibOut.InjDouble & MibOut.InjChannel;
            end if;
            if MibOut.InjRxValid = '1' then
                InjRxCnt <= InjRxCnt + 1;
                InjRx    <= MibOut.InjDouble & MibOut.InjChannel;
            end if;
            if MibOut.ErrValid = '1' then
                ErrOuts <= ErrOuts + 1;
                ErrSeen <= ('1', MibOut.ErrCode, MibOut.ErrPort, MibOut.ErrApid);
            end if;
        end if;
    end process;

    i_th : entity work.spp_mib_th
        port map (
            Clk     => Clk,
            Rst     => Rst,
            Mib_In  => MibIn,
            Mib_Out => MibOut
        );

end architecture;
