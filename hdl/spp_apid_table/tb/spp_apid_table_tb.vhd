---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the APID table: initialisation, reads and writes of both clients against a reference
-- model, atomic read-modify-write under concurrent access, ECC error injection with the scrubber and
-- a reset in the middle of a transaction.
--
-- Documentation: hdl/spp_apid_table/docs/verification_plan.md

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

library vunit_lib;
    context vunit_lib.vunit_run_context;

library olo;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.spp_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_apid_table_tb is
    generic (
        runner_cfg : string
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_apid_table_tb is

    constant ClkPeriod_c : time                                   := 10 ns;
    constant Width_c     : positive                               := 21;
    constant Init_c      : std_logic_vector(Width_c - 1 downto 0) := '1' & x"2345A";
    constant Cw_c        : positive                               := eccCodewordWidth(Width_c);

    type Client_t is record
        Valid  : std_logic;
        Apid   : std_logic_vector(10 downto 0);
        WrEna  : std_logic;
        WrData : std_logic_vector(Width_c - 1 downto 0);
        Done   : std_logic;
    end record;

    constant ClientIdle_c : Client_t := ('0', (others => '0'), '0', (others => '0'), '0');

    type Rsp_t is record
        Ready   : std_logic;
        RdValid : std_logic;
        RdData  : std_logic_vector(Width_c - 1 downto 0);
        RdDed   : std_logic;
    end record;

    signal Clk         : std_logic                           := '0';
    signal Rst         : std_logic                           := '1';
    signal InitBusy    : std_logic;
    signal A           : Client_t                            := ClientIdle_c;
    signal B           : Client_t                            := ClientIdle_c;
    signal BCon        : Client_t                            := ClientIdle_c; -- client B of the concurrent increments
    signal BDut        : Client_t;
    signal ARsp        : Rsp_t;
    signal BRsp        : Rsp_t;
    signal EccSec      : std_logic;
    signal EccDed      : std_logic;
    signal ScrubSec    : std_logic;
    signal ScrubDed    : std_logic;
    signal ScrubEnable : std_logic                           := '1';
    signal InjFlip     : std_logic_vector(Cw_c - 1 downto 0) := (others => '0');
    signal InjValid    : std_logic                           := '0';
    signal BRun        : boolean                             := false;
    signal BDone       : boolean                             := false;
    signal SecCnt      : natural                             := 0;
    signal DedCnt      : natural                             := 0;
    signal ScrubSecCnt : natural                             := 0;
    signal ScrubDedCnt : natural                             := 0;
    signal Grants      : natural                             := 0;

    -- One read-modify-write transaction of a client: request, read data, then write back data (write) or
    -- release the entry
    procedure transact (
        signal cl    : inout Client_t;
        signal rsp   : in    Rsp_t;
        signal clk   : in    std_logic;
        apid         : in    natural;
        write        : in    boolean;
        data         : in    std_logic_vector(Width_c - 1 downto 0);
        variable rd  : out   std_logic_vector(Width_c - 1 downto 0);
        variable ded : out   std_logic;
        holdCycles   : in    natural := 0) is
    begin
        cl.Valid <= '1';
        cl.Apid  <= std_logic_vector(to_unsigned(apid, 11));

        loop
            wait until rising_edge(clk);
            exit when rsp.Ready = '1';
        end loop;

        cl.Valid <= '0';

        loop
            wait until rising_edge(clk);
            exit when rsp.RdValid = '1';
        end loop;

        rd  := rsp.RdData;
        ded := rsp.RdDed;

        for i in 1 to holdCycles loop
            wait until rising_edge(clk);
        end loop;

        if write then
            cl.WrEna  <= '1';
            cl.WrData <= data;
        else
            cl.Done <= '1';
        end if;
        wait until rising_edge(clk);
        cl.WrEna <= '0';
        cl.Done  <= '0';
    end procedure;

begin

    test_runner_watchdog(runner, 20 ms);

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    Clk <= not Clk after ClkPeriod_c / 2;

    p_main : process is
        type Model_t is array (0 to 2047) of std_logic_vector(Width_c - 1 downto 0);

        variable Model_v : Model_t;
        variable Rand_v  : t_rand;
        variable Rd_v    : std_logic_vector(Width_c - 1 downto 0);
        variable Ded_v   : std_logic;
        variable Apid_v  : natural;
        variable Data_v  : std_logic_vector(Width_c - 1 downto 0);
        variable Cnt_v   : natural;
        variable T_v     : time;

        procedure resetDut is
        begin
            Rst     <= '1';
            wait until rising_edge(Clk);
            wait until rising_edge(Clk);
            Rst     <= '0';
            wait until rising_edge(Clk);
            wait until InitBusy = '0';
            wait until rising_edge(Clk);
            Model_v := (others => Init_c);
        end procedure;

        procedure readCheck (
            apid : natural;
            exp  : std_logic_vector(Width_c - 1 downto 0);
            msg  : string) is
        begin
            transact(A, ARsp, Clk, apid, false, Init_c, Rd_v, Ded_v);
            check_value(Rd_v, exp, ERROR, msg & ": entry " & to_string(apid), msg_id => ID_NEVER);
            check_value(Ded_v, '0', ERROR, msg & ": no double error at " & to_string(apid), msg_id => ID_NEVER);
        end procedure;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        Rand_v.set_rand_seeds(77, 31);

        while test_suite loop
            Rst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            Rst <= '0';

            if run("test_init") then
                -- Busy for exactly 2048 cycles, no request granted meanwhile, then every entry holds the
                -- initial value
                A.Valid <= '1';
                Cnt_v   := 0;
                wait until rising_edge(Clk);

                while InitBusy = '1' loop
                    check_value(ARsp.Ready, '0', ERROR, "no grant during the initialisation", msg_id => ID_NEVER);
                    Cnt_v := Cnt_v + 1;
                    wait until rising_edge(Clk);
                end loop;

                check_value(Cnt_v, 2048, ERROR, "initialisation cycles");
                -- The request held during the initialisation is granted afterwards: release the entry
                check_value(ARsp.Ready, '1', ERROR, "request granted after the initialisation");
                A.Valid <= '0';

                loop
                    wait until rising_edge(Clk);
                    exit when ARsp.RdValid = '1';
                end loop;

                A.Done  <= '1';
                wait until rising_edge(Clk);
                A.Done  <= '0';
                Model_v := (others => Init_c);

                for apid in 0 to 2047 loop
                    transact(B, BRsp, Clk, apid, false, Init_c, Rd_v, Ded_v);
                    check_value(Rd_v, Init_c, ERROR, "initial value of entry " & to_string(apid), msg_id => ID_NEVER);
                end loop;

                check_value(DedCnt, 0, ERROR, "no double error after the initialisation");
                check_value(SecCnt, 0, ERROR, "no single error after the initialisation");

            elsif run("test_read_write") then
                wait until InitBusy = '0';
                wait until rising_edge(Clk);
                Model_v := (others => Init_c);

                -- Random writes and releases by both clients against the reference model
                for i in 0 to 999 loop
                    Apid_v := Rand_v.rand(0, 2047);
                    Data_v := Rand_v.rand(Width_c);
                    if Rand_v.rand(0, 1) = 0 then
                        transact(A, ARsp, Clk, Apid_v, true, Data_v, Rd_v, Ded_v, Rand_v.rand(0, 3));
                    else
                        transact(B, BRsp, Clk, Apid_v, true, Data_v, Rd_v, Ded_v, Rand_v.rand(0, 3));
                    end if;
                    check_value(Rd_v, Model_v(Apid_v), ERROR, "old value of entry " & to_string(Apid_v), msg_id => ID_NEVER);
                    Model_v(Apid_v) := Data_v;
                    -- A release does not change the entry
                    transact(B, BRsp, Clk, Apid_v, false, not Data_v, Rd_v, Ded_v);
                    check_value(Rd_v, Data_v, ERROR, "written value of entry " & to_string(Apid_v), msg_id => ID_NEVER);
                end loop;

                -- First and last entry
                transact(A, ARsp, Clk, 0, true, '0' & x"00001", Rd_v, Ded_v);
                transact(A, ARsp, Clk, 2047, true, '1' & x"FFFFE", Rd_v, Ded_v);
                readCheck(0, '0' & x"00001", "first entry");
                readCheck(2047, '1' & x"FFFFE", "last entry");

            elsif run("test_arbitration") then
                -- Both clients increment the same entry 300 times at the same time: the transactions are atomic,
                -- so no increment is lost, and client B is served while client A requests continuously
                wait until InitBusy = '0';
                wait until rising_edge(Clk);
                transact(A, ARsp, Clk, 100, true, std_logic_vector(to_unsigned(0, Width_c)), Rd_v, Ded_v);
                BRun <= true;

                for i in 1 to 300 loop
                    transact(A, ARsp, Clk, 100, false, Init_c, Rd_v, Ded_v);
                    -- The read data of this transaction is the current value; write back the increment
                    A.Valid <= '1';
                    A.Apid  <= std_logic_vector(to_unsigned(100, 11));

                    loop
                        wait until rising_edge(Clk);
                        exit when ARsp.Ready = '1';
                    end loop;

                    A.Valid <= '0';

                    loop
                        wait until rising_edge(Clk);
                        exit when ARsp.RdValid = '1';
                    end loop;

                    A.WrEna  <= '1';
                    A.WrData <= std_logic_vector(unsigned(ARsp.RdData) + 1);
                    wait until rising_edge(Clk);
                    A.WrEna  <= '0';
                end loop;

                if not BDone then
                    wait until BDone;
                end if;
                BRun <= false;
                readCheck(100, std_logic_vector(to_unsigned(600, Width_c)), "600 increments of both clients");
                check_value(Grants >= 300, ERROR, "client B served while client A requests");

            elsif run("test_ecc") then
                wait until InitBusy = '0';
                wait until rising_edge(Clk);
                ScrubEnable <= '0';
                -- Single bit error injected into a write: corrected on read, SEC reported
                InjFlip    <= (others => '0');
                InjFlip(3) <= '1';
                InjValid   <= '1';
                wait until rising_edge(Clk);
                InjValid   <= '0';
                transact(A, ARsp, Clk, 7, true, '0' & x"0F0F0", Rd_v, Ded_v);
                readCheck(7, '0' & x"0F0F0", "single bit error corrected");
                check_value(SecCnt, 1, ERROR, "single error reported");
                -- A read corrects the data, not the stored entry: overwrite it
                transact(A, ARsp, Clk, 7, true, '0' & x"0F0F0", Rd_v, Ded_v);
                -- Double bit error: reported to the client and as DED
                InjFlip           <= (others => '0');
                InjFlip(1)        <= '1';
                InjFlip(Cw_c - 2) <= '1';
                InjValid          <= '1';
                wait until rising_edge(Clk);
                InjValid          <= '0';
                transact(B, BRsp, Clk, 9, true, '1' & x"55555", Rd_v, Ded_v);
                transact(A, ARsp, Clk, 9, false, Init_c, Rd_v, Ded_v);
                check_value(Ded_v, '1', ERROR, "double error reported to the client");
                check_value(DedCnt, 1, ERROR, "double error reported");
                -- Overwriting the entry repairs it
                transact(A, ARsp, Clk, 9, true, '1' & x"55555", Rd_v, Ded_v);
                readCheck(9, '1' & x"55555", "repaired entry");
                -- Scrubber: a single error in a stored entry is found and written back corrected
                InjFlip              <= (others => '0');
                InjFlip(Width_c - 1) <= '1';
                InjValid             <= '1';
                wait until rising_edge(Clk);
                InjValid             <= '0';
                transact(A, ARsp, Clk, 1500, true, '0' & x"ABCDE", Rd_v, Ded_v);
                ScrubEnable          <= '1';
                T_v                  := now;

                while ScrubSecCnt = 0 and now < T_v + 200 us loop
                    wait until rising_edge(Clk);
                end loop;

                check_value(ScrubSecCnt, 1, ERROR, "single error found by the scrubber");
                -- The scrubber writes the corrected entry back in its next free write slot
                wait for 20 * ClkPeriod_c;
                ScrubEnable <= '0';
                wait for 20 * ClkPeriod_c;
                Cnt_v       := SecCnt;
                readCheck(1500, '0' & x"ABCDE", "scrubbed entry");
                check_value(SecCnt, Cnt_v, ERROR, "scrubbed entry read without single error");
                check_value(ScrubDedCnt, 0, ERROR, "no double error found by the scrubber");

            elsif run("test_reset") then
                -- Reset while client A holds an entry: the table initialises again and serves both clients
                wait until InitBusy = '0';
                wait until rising_edge(Clk);
                transact(A, ARsp, Clk, 3, true, '0' & x"00333", Rd_v, Ded_v);
                A.Valid <= '1';
                A.Apid  <= std_logic_vector(to_unsigned(3, 11));
                wait until rising_edge(Clk) and ARsp.Ready = '1';
                A.Valid <= '0';
                wait for 5 * ClkPeriod_c;
                resetDut;
                readCheck(3, Init_c, "entry after the reset");
                transact(B, BRsp, Clk, 4, true, '0' & x"00444", Rd_v, Ded_v);
                readCheck(4, '0' & x"00444", "write after the reset");
                -- Reset in the cycle of a read
                A.Valid <= '1';
                A.Apid  <= std_logic_vector(to_unsigned(4, 11));
                wait until rising_edge(Clk) and ARsp.Ready = '1';
                A.Valid <= '0';
                resetDut;
                readCheck(4, Init_c, "entry after the reset during a read");
            end if;

            wait for 10 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    -- Client B of the arbitration test: 300 increments of entry 100
    p_client_b : process is
        variable Rd_v  : std_logic_vector(Width_c - 1 downto 0);
        variable Ded_v : std_logic;
    begin
        wait until BRun;

        for i in 1 to 300 loop
            BCon.Valid <= '1';
            BCon.Apid  <= std_logic_vector(to_unsigned(100, 11));

            loop
                wait until rising_edge(Clk);
                exit when BRsp.Ready = '1';
            end loop;

            Grants     <= Grants + 1;
            BCon.Valid <= '0';

            loop
                wait until rising_edge(Clk);
                exit when BRsp.RdValid = '1';
            end loop;

            BCon.WrEna  <= '1';
            BCon.WrData <= std_logic_vector(unsigned(BRsp.RdData) + 1);
            wait until rising_edge(Clk);
            BCon.WrEna  <= '0';
        end loop;

        BDone <= true;
        wait;
    end process;

    BDut <= BCon when BRun else B;

    -- ECC event counters
    p_count : process (Clk) is
    begin
        if rising_edge(Clk) then
            if EccSec = '1' then
                SecCnt <= SecCnt + 1;
            end if;
            if EccDed = '1' then
                DedCnt <= DedCnt + 1;
            end if;
            if ScrubSec = '1' then
                ScrubSecCnt <= ScrubSecCnt + 1;
            end if;
            if ScrubDed = '1' then
                ScrubDedCnt <= ScrubDedCnt + 1;
            end if;
        end if;
    end process;

    i_dut : entity work.spp_apid_table
        generic map (
            Width_g     => Width_c,
            ClkFreqHz_g => 100.0e6
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Init_Value     => Init_c,
            Init_Busy      => InitBusy,
            A_Valid        => A.Valid,
            A_Ready        => ARsp.Ready,
            A_Apid         => A.Apid,
            A_RdValid      => ARsp.RdValid,
            A_RdData       => ARsp.RdData,
            A_RdDed        => ARsp.RdDed,
            A_WrEna        => A.WrEna,
            A_WrData       => A.WrData,
            A_Release      => A.Done,
            B_Valid        => BDut.Valid,
            B_Ready        => BRsp.Ready,
            B_Apid         => BDut.Apid,
            B_RdValid      => BRsp.RdValid,
            B_RdData       => BRsp.RdData,
            B_RdDed        => BRsp.RdDed,
            B_WrEna        => BDut.WrEna,
            B_WrData       => BDut.WrData,
            B_Release      => BDut.Done,
            Ecc_Sec        => EccSec,
            Ecc_Ded        => EccDed,
            Scrub_Sec      => ScrubSec,
            Scrub_Ded      => ScrubDed,
            Scrub_Enable   => ScrubEnable,
            ErrInj_BitFlip => InjFlip,
            ErrInj_Valid   => InjValid
        );

end architecture;
