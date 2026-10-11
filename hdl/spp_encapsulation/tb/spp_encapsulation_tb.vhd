---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Testbench of the encapsulation and the decapsulation of the SpaceWire CCSDS Packet Transfer Protocol:
-- every CPTP packet and every Space Packet is compared byte by byte with the packet built by the packet
-- model; discarded packets are checked through the error events.
--
-- Documentation: hdl/spp_encapsulation/docs/verification_plan.md

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

library work;
    use work.spp_pkg.all;
    use work.spp_tb_pkg.all;
    use work.spp_tb_stream_pkg.all;
    use work.spp_tb_streamvar_pkg.all;
    use work.spp_tb_packet_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_encapsulation_tb is
    generic (
        runner_cfg  : string;
        DataWidth_g : positive := 32
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_encapsulation_tb is

    constant ClkPeriod_c : time    := 10 ns;
    constant NumDest_c   : natural := 4;
    constant AddrBytes_c : natural := 16;
    constant ChEncSrc_c  : natural := 0;
    constant ChEncSnk_c  : natural := 1;
    constant ChDecSrc_c  : natural := 2;
    constant ChDecSnk_c  : natural := 3;

    type NatArray_t is array (natural range <>) of natural;

    -- Destinations: address length, first address byte, Target Logical Address, User Application value
    constant DestLen_c : NatArray_t(0 to NumDest_c - 1) := (0, 1, 3, 16);
    constant DestTla_c : NatArray_t(0 to NumDest_c - 1) := (16#FE#, 16#40#, 16#41#, 16#42#);
    constant DestUa_c  : NatArray_t(0 to NumDest_c - 1) := (16#00#, 16#11#, 16#22#, 16#33#);

    signal Clk      : std_logic;
    signal Rst      : std_logic := '1';
    signal DestAddr : std_logic_vector(NumDest_c * 8 * AddrBytes_c - 1 downto 0);
    signal DestLen  : std_logic_vector(NumDest_c * 5 - 1 downto 0);
    signal DestTla  : std_logic_vector(NumDest_c * 8 - 1 downto 0);
    signal DestUa   : std_logic_vector(NumDest_c * 8 - 1 downto 0);
    -- Configured address lengths; a length beyond AddrBytes_c is limited to it
    signal DestCfg  : NatArray_t(0 to NumDest_c - 1) := DestLen_c;
    signal RxStrip  : std_logic_vector(3 downto 0)   := (others => '0');
    signal TlaCheck : std_logic                      := '0';
    signal Tla      : std_logic_vector(7 downto 0)   := x"40";
    signal ErrCount : integer_vector(0 to 31);
    signal ErrLast  : ErrEvent_t;

    -- Target SpaceWire Address of destination d: bytes 0x10 d + i
    function destAddrBytes (d : natural) return TbBytes_t is
    begin
        return tbCount(DestLen_c(d), 16 * d + 1);
    end function;

begin

    test_runner_watchdog(runner, 20 ms);

    -- Destinations
    g_dest : for d in 0 to NumDest_c - 1 generate
        constant Addr_c : TbBytes_t := tbCount(AddrBytes_c, 16 * d + 1);
    begin

        g_byte : for i in 0 to AddrBytes_c - 1 generate
            DestAddr(8 * (AddrBytes_c * d + i) + 7 downto 8 * (AddrBytes_c * d + i)) <= Addr_c(i);
        end generate;

        DestLen(5 * d + 4 downto 5 * d) <= std_logic_vector(to_unsigned(DestCfg(d), 5));
        DestTla(8 * d + 7 downto 8 * d) <= std_logic_vector(to_unsigned(DestTla_c(d), 8));
        DestUa(8 * d + 7 downto 8 * d)  <= std_logic_vector(to_unsigned(DestUa_c(d), 8));
    end generate;

    p_main : process is
        variable Rand_v : t_rand;
        variable Seed_v : natural := 1;
        variable D_v    : natural;
        variable Eep_v  : natural;
        variable Ua_v   : natural;
        variable S_v    : natural;
        variable Errs_v : natural;

        -- Space Packet of len bytes of payload through the encapsulation to destination index d
        procedure encap (
            d    : natural;
            len  : natural;
            seed : natural;
            eep  : natural := 0) is
            constant Pkt_c : TbBytes_t := tbSpacePacket(0, 0, seed mod 2048, 3, seed mod 16384, tbPayload(len, seed));
            variable E_v   : natural;
        begin
            E_v := d;
            if d >= NumDest_c then
                E_v := 0;
            end if;
            tbPush(ChEncSrc_c, Pkt_c, tbLinkUser(0, d), tbLinkUser(eep, d));
            tbPush(ChEncSnk_c, tbCptp(destAddrBytes(E_v), DestTla_c(E_v), DestUa_c(E_v), Pkt_c), tbLinkUser(0, d),
                   tbLinkUser(eep, d));
        end procedure;

        -- CPTP packet with strip leading address bytes through the decapsulation; the expected Space Packet
        procedure decap (
            strip : natural;
            tla   : natural;
            ua    : natural;
            len   : natural;
            seed  : natural;
            eep   : natural := 0) is
            constant Pkt_c : TbBytes_t := tbSpacePacket(1, 1, seed mod 2048, 3, 0, tbPayload(len, seed));
            variable U_v   : std_logic_vector(8 downto 0);
        begin
            tbPush(ChDecSrc_c, tbCptp(tbCount(strip, 200), tla, ua, Pkt_c), "0", std_logic_vector(to_unsigned(eep, 1)));
            U_v := std_logic_vector(to_unsigned(ua, 8)) & '0';
            tbPush(ChDecSnk_c, Pkt_c, U_v, std_logic_vector(to_unsigned(ua, 8)) & std_logic_vector(to_unsigned(eep, 1)));
        end procedure;

        -- Link packet that the decapsulation discards
        procedure discard (
            pkt : TbBytes_t;
            eep : natural := 0) is
        begin
            tbPush(ChDecSrc_c, pkt, "0", std_logic_vector(to_unsigned(eep, 1)));
        end procedure;

        procedure waitAll (timeout : time := 2 ms) is
        begin
            tbWaitEmpty(ChEncSrc_c, timeout, "encapsulation source");
            tbWaitEmpty(ChEncSnk_c, timeout, "encapsulation sink");
            tbWaitEmpty(ChDecSrc_c, timeout, "decapsulation source");
            tbWaitEmpty(ChDecSnk_c, timeout, "decapsulation sink");
            wait for 20 * ClkPeriod_c;
        end procedure;

    -- Test sequence
    begin
        test_runner_setup(runner, runner_cfg);
        Rand_v.set_rand_seeds(DataWidth_g, 5);

        while test_suite loop
            Rst <= '1';
            wait for 5 * ClkPeriod_c;
            wait until rising_edge(Clk);
            Rst <= '0';
            wait for 5 * ClkPeriod_c;

            if run("test_encapsulation") then
                -- Every destination (address of 0, 1, 3 and 16 bytes), an index beyond the destinations, EOP and EEP
                tbSetStall(ChEncSrc_c, 0.3);
                tbSetStall(ChEncSnk_c, 0.3);

                for i in 0 to 99 loop
                    D_v := i mod 5;
                    if D_v = 4 then
                        D_v := 9;
                    end if;
                    Eep_v  := 1 when i mod 7 = 3 else 0;
                    encap(D_v, Rand_v.rand(1, 200), Seed_v, Eep_v);
                    Seed_v := Seed_v + 1;
                end loop;

                waitAll;
                -- An address length beyond SpwAddrBytes_g is limited to it
                DestCfg(3) <= 20;
                wait until rising_edge(Clk);

                for i in 0 to 4 loop
                    encap(3, Rand_v.rand(1, 50), Seed_v);
                    Seed_v := Seed_v + 1;
                end loop;

                waitAll;

            elsif run("test_decapsulation") then
                -- 0 to 15 leading address bytes removed, User Application values, EOP and EEP passed on
                tbSetStall(ChDecSrc_c, 0.3);
                tbSetStall(ChDecSnk_c, 0.3);

                for s in 0 to 15 loop
                    RxStrip <= std_logic_vector(to_unsigned(s, 4));
                    wait until rising_edge(Clk);

                    for i in 0 to 5 loop
                        decap(s, 16#FE#, Rand_v.rand(0, 255), Rand_v.rand(1, 100), Seed_v, i mod 2);
                        Seed_v := Seed_v + 1;
                    end loop;

                    waitAll;
                end loop;

                check_value(ErrCount(to_integer(unsigned(ErrRxEep_c))), 0, ERROR, "packets with EEP are passed on");

            elsif run("test_decap_checks") then
                -- Protocol Identifier, Reserved field, Target Logical Address filter, packets without a Space Packet,
                -- EEP; each discarded packet followed by a correct one
                discard(tbCptp(TbNoBytes_c, 16#FE#, 0, tbSpacePacket(0, 0, 1, 3, 0, tbPayload(10, 1)), 1));
                decap(0, 16#FE#, 1, 10, 2);
                discard(tbCptp(TbNoBytes_c, 16#FE#, 0, tbSpacePacket(0, 0, 1, 3, 0, tbPayload(10, 3)), 2, 1));
                decap(0, 16#FE#, 2, 10, 4);
                waitAll;
                check_value(ErrCount(to_integer(unsigned(ErrRxProtocolId_c))), 1, ERROR, "Protocol Identifier 1");
                check_value(ErrCount(to_integer(unsigned(ErrRxReserved_c))), 1, ERROR, "Reserved field 1");
                -- Filter: own address and 0xFE accepted, another one discarded; filter off accepts it
                TlaCheck <= '1';
                wait until rising_edge(Clk);
                decap(0, 16#40#, 3, 10, 5);
                decap(0, 16#FE#, 4, 10, 6);
                discard(tbCptp(TbNoBytes_c, 16#41#, 0, tbSpacePacket(0, 0, 1, 3, 0, tbPayload(10, 7))));
                decap(0, 16#40#, 5, 10, 8);
                waitAll;
                check_value(ErrCount(to_integer(unsigned(ErrRxAddress_c))), 1, ERROR, "Target Logical Address 0x41");
                TlaCheck <= '0';
                wait until rising_edge(Clk);
                decap(0, 16#41#, 6, 10, 9);
                -- Only the CPTP header, and two bytes
                discard(tbCptp(TbNoBytes_c, 16#FE#, 0, TbNoBytes_c));
                discard(tbCount(2, 1));
                decap(0, 16#FE#, 7, 10, 10);
                waitAll;
                check_value(ErrCount(to_integer(unsigned(ErrRxShort_c))), 2, ERROR, "packets without a Space Packet");
                -- EEP on a packet with a wrong Protocol Identifier: reported as EEP
                discard(tbCptp(TbNoBytes_c, 16#FE#, 0, tbSpacePacket(0, 0, 1, 3, 0, tbPayload(10, 11)), 7), 1);
                decap(0, 16#FE#, 8, 10, 12);
                waitAll;
                check_value(ErrCount(to_integer(unsigned(ErrRxEep_c))), 1, ERROR, "EEP takes precedence");
                check_value(ErrCount(to_integer(unsigned(ErrRxProtocolId_c))), 1, ERROR, "Protocol Identifier");
                check_value(to_integer(unsigned(ErrLast.Code)), to_integer(unsigned(ErrRxEep_c)), ERROR, "last event");

            elsif run("test_random") then

                -- Random packets through both DUTs at the same time, random stalls and address removal
                for i in 0 to 299 loop
                    if i mod 50 = 0 then
                        waitAll(5 ms);
                        S_v     := Rand_v.rand(0, 15);
                        RxStrip <= std_logic_vector(to_unsigned(S_v, 4));
                        tbSetStall(ChEncSrc_c, Rand_v.rand(0.0, 0.5));
                        tbSetStall(ChEncSnk_c, Rand_v.rand(0.0, 0.5));
                        tbSetStall(ChDecSrc_c, Rand_v.rand(0.0, 0.5));
                        tbSetStall(ChDecSnk_c, Rand_v.rand(0.0, 0.5));
                        wait until rising_edge(Clk);
                    end if;
                    encap(Rand_v.rand(0, 15), Rand_v.rand(1, 300), Seed_v, Rand_v.rand(0, 1));
                    decap(S_v, 16#FE#, Rand_v.rand(0, 255), Rand_v.rand(1, 300), Seed_v + 7, Rand_v.rand(0, 1));
                    Seed_v := Seed_v + 1;
                end loop;

                waitAll(5 ms);

            elsif run("test_reset") then
                -- Reset while both DUTs hold a packet that the sinks do not accept; afterwards normal operation
                tbSetStall(ChEncSnk_c, 1.0);
                tbSetStall(ChDecSnk_c, 1.0);
                encap(1, 100, 1);
                decap(0, 16#FE#, 1, 100, 2);
                wait for 1 us;
                wait until rising_edge(Clk);
                Rst <= '1';
                SppTbStore_v.setAbort(ChEncSrc_c);
                SppTbStore_v.setAbort(ChDecSrc_c);
                SppTbStore_v.clear(ChEncSnk_c);
                SppTbStore_v.clear(ChDecSnk_c);
                wait until rising_edge(Clk);
                Rst <= '0';
                tbSetStall(ChEncSnk_c, 0.0);
                tbSetStall(ChDecSnk_c, 0.0);
                wait for 5 * ClkPeriod_c;

                for i in 0 to 9 loop
                    encap(i mod 4, 20 + i, 10 + i);
                    decap(0, 16#FE#, i, 20 + i, 30 + i);
                end loop;

                waitAll;
            end if;

            wait for 20 * ClkPeriod_c;
        end loop;

        sppTestEnd(runner);
        wait;
    end process;

    i_th : entity work.spp_encapsulation_th
        generic map (
            DataWidth_g    => DataWidth_g,
            NumDest_g      => NumDest_c,
            SpwAddrBytes_g => AddrBytes_c,
            ClkPeriod_g    => ClkPeriod_c,
            ChEncSrc_g     => ChEncSrc_c,
            ChEncSnk_g     => ChEncSnk_c,
            ChDecSrc_g     => ChDecSrc_c,
            ChDecSnk_g     => ChDecSnk_c
        )
        port map (
            Clk             => Clk,
            Rst             => Rst,
            Cfg_DestAddr    => DestAddr,
            Cfg_DestAddrLen => DestLen,
            Cfg_DestTla     => DestTla,
            Cfg_DestUa      => DestUa,
            Cfg_RxStrip     => RxStrip,
            Cfg_TlaCheck    => TlaCheck,
            Cfg_Tla         => Tla,
            ErrCount        => ErrCount,
            ErrLast         => ErrLast
        );

end architecture;
