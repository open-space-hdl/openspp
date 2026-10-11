---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the header insertion and removal: every output packet is compared byte by byte with
-- the packet built by the testbench, for all header lengths, packet lengths around the beat width,
-- random backpressure, back-to-back packets and a reset in the middle of a packet.
--
-- Documentation: hdl/spp_header/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library vunit_lib;
    context vunit_lib.vunit_run_context;

library work;
    use work.spp_tb_pkg.all;
    use work.spp_tb_streamvar_pkg.all;
    use work.spp_header_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_header_tb is
    generic (
        runner_cfg  : string;
        DataWidth_g : positive := 32
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_header_tb is

    constant Bytes_c : positive := DataWidth_g / 8;

    signal Clk : std_logic;
    signal Rst : std_logic := '1';

begin

    test_runner_watchdog(runner, 50 ms);

    p_main : process is
        variable Seed_v     : natural := 1;
        variable Rand_v     : t_rand;
        variable Len_v      : natural;
        variable Hdr_v      : natural;
        variable InBeats_v  : natural;
        variable OutBeats_v : natural;
        variable Cycles_v   : natural;

        -- Packet lengths around the beat width
        type NatArray_t is array (natural range <>) of natural;

        constant Lengths_c : NatArray_t := (1, 2, Bytes_c - 1, Bytes_c, Bytes_c + 1, 2 * Bytes_c + 3, 3 * Bytes_c, 41);

        procedure setStalls (prob : real) is
        begin
            tbSetStall(ChInsSrc_c, prob);
            tbSetStall(ChInsSnk_c, prob);
            tbSetStall(ChRemSrc_c, prob);
            tbSetStall(ChRemSnk_c, prob);
        end procedure;

        procedure waitAll (timeout : time) is
        begin
            tbWaitEmpty(ChInsSrc_c, timeout, "insertion source");
            tbWaitEmpty(ChInsSnk_c, timeout, "insertion sink");
            tbWaitEmpty(ChRemSrc_c, timeout, "removal source");
            tbWaitEmpty(ChRemSnk_c, timeout, "removal sink");
        end procedure;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        Rand_v.set_rand_seeds(runner_cfg'length, DataWidth_g);

        while test_suite loop
            Rst <= '1';
            wait for 10 * ClkPeriod_c;
            wait until rising_edge(Clk);
            Rst <= '0';
            wait for 5 * ClkPeriod_c;

            if run("test_insert") then
                -- Every header length with packet lengths around the beat width, random backpressure
                setStalls(0.3);

                for h in 0 to MaxHdr_c loop

                    for l in Lengths_c'range loop
                        if Lengths_c(l) > 0 then
                            insertPacket(Lengths_c(l), h, Seed_v, (h + l) mod 16);
                            Seed_v := Seed_v + 1;
                        end if;
                    end loop;

                end loop;

                waitAll(5 ms);

            elsif run("test_remove") then
                -- Every removal count with packet lengths shorter than, equal to and longer than it
                setStalls(0.3);

                for r in 0 to MaxHdr_c loop

                    for l in 1 to MaxHdr_c + 2 * Bytes_c + 2 loop
                        if l <= r + 2 * Bytes_c + 2 then
                            removePacket(l, r, Seed_v, (r + l) mod 16);
                            Seed_v := Seed_v + 1;
                        end if;
                    end loop;

                end loop;

                waitAll(10 ms);

            elsif run("test_random") then
                -- Random lengths, header lengths and backpressure on both DUTs at the same time

                for i in 0 to 399 loop
                    if i mod 100 = 0 then
                        tbSetStall(ChInsSrc_c, Rand_v.rand(0.0, 0.6));
                        tbSetStall(ChInsSnk_c, Rand_v.rand(0.0, 0.6));
                        tbSetStall(ChRemSrc_c, Rand_v.rand(0.0, 0.6));
                        tbSetStall(ChRemSnk_c, Rand_v.rand(0.0, 0.6));
                    end if;
                    insertPacket(Rand_v.rand(1, 300), Rand_v.rand(0, MaxHdr_c), Seed_v, Rand_v.rand(0, 15));
                    removePacket(Rand_v.rand(1, 300), Rand_v.rand(0, MaxHdr_c), Seed_v + 50000, Rand_v.rand(0, 15));
                    Seed_v := Seed_v + 1;
                end loop;

                waitAll(20 ms);

            elsif run("test_line_rate") then
                -- Back-to-back packets without stalls: every output beat follows the previous one without a
                -- gap, so the insertion transfers one beat per clock cycle (header beats included)
                setStalls(0.0);
                SppTbStore_v.clearStats(ChInsSnk_c);
                SppTbStore_v.clearStats(ChRemSnk_c);
                InBeats_v  := 0;
                OutBeats_v := 0;

                for i in 0 to 49 loop
                    Len_v      := 64 + i;
                    Hdr_v      := 6 + (i mod 10);
                    insertPacket(Len_v, Hdr_v, Seed_v);
                    OutBeats_v := OutBeats_v + (Len_v + Hdr_v + Bytes_c - 1) / Bytes_c;
                    removePacket(Len_v, Hdr_v, Seed_v + 50000);
                    InBeats_v  := InBeats_v + (Len_v + Bytes_c - 1) / Bytes_c;
                    Seed_v     := Seed_v + 1;
                end loop;

                waitAll(5 ms);
                Cycles_v := (SppTbStore_v.lastTime(ChInsSnk_c) - SppTbStore_v.firstTime(ChInsSnk_c)) / ClkPeriod_c + 1;
                check_value(Cycles_v, OutBeats_v, ERROR, "insertion: clock cycles from the first to the last beat");
                -- The removal consumes one input beat per cycle and needs at most one cycle more per packet
                -- (the residue of the last input beat)
                Cycles_v := (SppTbStore_v.lastTime(ChRemSnk_c) - SppTbStore_v.firstTime(ChRemSnk_c)) / ClkPeriod_c + 1;
                check_value(Cycles_v <= InBeats_v + 50, ERROR, "removal: " & to_string(Cycles_v) &
                            " clock cycles for " & to_string(InBeats_v) & " input beats");

            elsif run("test_reset") then
                -- Reset while both DUTs hold a packet that the sinks do not accept, then normal operation
                tbSetStall(ChInsSnk_c, 1.0);
                tbSetStall(ChRemSnk_c, 1.0);
                insertPacket(8 * Bytes_c + 5, 7, Seed_v);
                removePacket(8 * Bytes_c + 5, 7, Seed_v + 1);
                wait for 50 * ClkPeriod_c;
                wait until rising_edge(Clk);
                Rst <= '1';
                SppTbStore_v.setAbort(ChInsSrc_c);
                SppTbStore_v.setAbort(ChRemSrc_c);
                SppTbStore_v.clear(ChInsSnk_c);
                SppTbStore_v.clear(ChRemSnk_c);
                wait until rising_edge(Clk);
                Rst <= '0';
                wait for 5 * ClkPeriod_c;
                check_value(SppTbStore_v.count(ChInsSrc_c), 0, ERROR, "insertion source idle");
                check_value(SppTbStore_v.count(ChRemSrc_c), 0, ERROR, "removal source idle");
                setStalls(0.2);

                for i in 0 to 19 loop
                    insertPacket(Rand_v.rand(1, 100), Rand_v.rand(0, MaxHdr_c), Seed_v + 10 + i);
                    removePacket(Rand_v.rand(1, 100), Rand_v.rand(0, MaxHdr_c), Seed_v + 100 + i);
                end loop;

                waitAll(2 ms);
            end if;

            wait for 20 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    i_th : entity work.spp_header_th
        generic map (
            DataWidth_g => DataWidth_g
        )
        port map (
            Clk => Clk,
            Rst => Rst
        );

end architecture;
