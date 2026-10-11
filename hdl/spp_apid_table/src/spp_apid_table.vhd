---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- APID table (TB-1, TB-2): one entry per APID in an ECC-protected and scrubbed RAM, initialised after
-- the reset, accessed by two clients with read-modify-write transactions that lock the table.
--
-- Documentation: hdl/spp_apid_table/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_ft_pkg_ecc.all;

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_apid_table is
    generic (
        Width_g       : positive;
        ClkFreqHz_g   : real   := 100.0e6;
        ScrubPeriod_g : real   := 0.0;
        RamStyle_g    : string := "auto"
    );
    port (
        -- Control
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Initialisation: every entry is written with Init_Value after the reset
        Init_Value     : in    std_logic_vector(Width_g - 1 downto 0);
        Init_Busy      : out   std_logic;
        -- Client A (priority client): request, read data, then write back or release
        A_Valid        : in    std_logic;
        A_Ready        : out   std_logic;
        A_Apid         : in    std_logic_vector(10 downto 0);
        A_RdValid      : out   std_logic;
        A_RdData       : out   std_logic_vector(Width_g - 1 downto 0);
        A_RdDed        : out   std_logic;
        A_WrEna        : in    std_logic;
        A_WrData       : in    std_logic_vector(Width_g - 1 downto 0);
        A_Release      : in    std_logic;
        -- Client B
        B_Valid        : in    std_logic                                                := '0';
        B_Ready        : out   std_logic;
        B_Apid         : in    std_logic_vector(10 downto 0)                            := (others => '0');
        B_RdValid      : out   std_logic;
        B_RdData       : out   std_logic_vector(Width_g - 1 downto 0);
        B_RdDed        : out   std_logic;
        B_WrEna        : in    std_logic                                                := '0';
        B_WrData       : in    std_logic_vector(Width_g - 1 downto 0)                   := (others => '0');
        B_Release      : in    std_logic                                                := '0';
        -- ECC: events of client reads and of the scrubber, error injection into the next client write
        Ecc_Sec        : out   std_logic;
        Ecc_Ded        : out   std_logic;
        Scrub_Sec      : out   std_logic;
        Scrub_Ded      : out   std_logic;
        Scrub_Enable   : in    std_logic                                                := '1';
        ErrInj_BitFlip : in    std_logic_vector(eccCodewordWidth(Width_g) - 1 downto 0) := (others => '0');
        ErrInj_Valid   : in    std_logic                                                := '0'
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_apid_table is

    constant Depth_c : positive := ApidCount_c;

    type Fsm_t is (Init_s, Idle_s, Read_s, Hold_s);

    type TwoProcess_r is record
        State    : Fsm_t;
        InitAddr : unsigned(10 downto 0);
        Owner    : std_logic;                      -- '0' client A, '1' client B
        LastB    : std_logic;                      -- the last transaction was B's (alternating priority)
        Addr     : std_logic_vector(10 downto 0);
        InjPend  : std_logic;
        InjFlip  : std_logic_vector(eccCodewordWidth(Width_g) - 1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

    -- RAM
    signal Wr_Addr  : std_logic_vector(10 downto 0);
    signal Wr_Ena   : std_logic;
    signal Wr_Data  : std_logic_vector(Width_g - 1 downto 0);
    signal Rd_Addr  : std_logic_vector(10 downto 0);
    signal Rd_Ena   : std_logic;
    signal Rd_Data  : std_logic_vector(Width_g - 1 downto 0);
    signal Rd_Valid : std_logic;
    signal Rd_Sec   : std_logic;
    signal Rd_Ded   : std_logic;
    signal Inj_Flip : std_logic_vector(eccCodewordWidth(Width_g) - 1 downto 0);
    signal Inj_Ena  : std_logic;
    signal ScrubEna : std_logic;

begin

    p_comb : process (all) is
        variable v        : TwoProcess_r;
        variable GrantA_v : boolean;
        variable GrantB_v : boolean;
    begin
        -- Hold variables stable
        v := r;

        -- Defaults
        A_Ready  <= '0';
        B_Ready  <= '0';
        Wr_Ena   <= '0';
        Wr_Addr  <= r.Addr;
        Wr_Data  <= A_WrData;
        Rd_Ena   <= '0';
        Rd_Addr  <= A_Apid;
        Inj_Ena  <= '0';
        GrantA_v := false;
        GrantB_v := false;

        -- Error injection: latched, applied to the next client write
        if ErrInj_Valid = '1' then
            v.InjPend := '1';
            v.InjFlip := ErrInj_BitFlip;
        end if;

        case r.State is

            when Init_s =>
                -- Every entry written with the initial value
                Wr_Ena  <= '1';
                Wr_Addr <= std_logic_vector(r.InitAddr);
                Wr_Data <= Init_Value;
                if r.InitAddr = Depth_c - 1 then
                    v.State := Idle_s;
                end if;
                v.InitAddr := r.InitAddr + 1;

            when Idle_s =>
                -- Alternating priority when both clients request
                if A_Valid = '1' and (B_Valid = '0' or r.LastB = '1') then
                    GrantA_v := true;
                elsif B_Valid = '1' then
                    GrantB_v := true;
                end if;

                if GrantA_v then
                    A_Ready <= '1';
                    Rd_Ena  <= '1';
                    Rd_Addr <= A_Apid;
                    v.Addr  := A_Apid;
                    v.Owner := '0';
                    v.LastB := '0';
                    v.State := Read_s;
                elsif GrantB_v then
                    B_Ready <= '1';
                    Rd_Ena  <= '1';
                    Rd_Addr <= B_Apid;
                    v.Addr  := B_Apid;
                    v.Owner := '1';
                    v.LastB := '1';
                    v.State := Read_s;
                end if;

            when Read_s =>
                -- Read data returns to the owner
                if Rd_Valid = '1' then
                    v.State := Hold_s;
                end if;

            when Hold_s =>
                -- The owner writes the entry back or releases it
                if r.Owner = '0' then
                    Wr_Data <= A_WrData;
                    if A_WrEna = '1' then
                        Wr_Ena <= '1';
                    end if;
                    if A_WrEna = '1' or A_Release = '1' then
                        v.State := Idle_s;
                    end if;
                else
                    Wr_Data <= B_WrData;
                    if B_WrEna = '1' then
                        Wr_Ena <= '1';
                    end if;
                    if B_WrEna = '1' or B_Release = '1' then
                        v.State := Idle_s;
                    end if;
                end if;
                if (r.Owner = '0' and A_WrEna = '1') or (r.Owner = '1' and B_WrEna = '1') then
                    if r.InjPend = '1' then
                        Inj_Ena   <= '1';
                        v.InjPend := '0';
                    end if;
                end if;

            -- coverage off
            when others =>
                v.State := Idle_s;
            -- coverage on

        end case;

        -- Apply to record
        r_next <= v;
    end process;

    -- Read data to both clients, qualified by the owner
    A_RdValid <= Rd_Valid when r.Owner = '0' else '0';
    B_RdValid <= Rd_Valid when r.Owner = '1' else '0';
    A_RdData  <= Rd_Data;
    B_RdData  <= Rd_Data;
    A_RdDed   <= Rd_Ded;
    B_RdDed   <= Rd_Ded;
    Ecc_Sec   <= Rd_Sec and Rd_Valid;
    Ecc_Ded   <= Rd_Ded and Rd_Valid;
    Init_Busy <= '1' when r.State = Init_s else '0';
    Inj_Flip  <= r.InjFlip;
    -- The scrubber starts after the initialisation
    ScrubEna <= Scrub_Enable when r.State /= Init_s else '0';

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State    <= Init_s;
                r.InitAddr <= (others => '0');
                r.Owner    <= '0';
                r.LastB    <= '0';
                r.InjPend  <= '0';
            end if;
        end if;
    end process;

    i_ram : entity olo.olo_ft_ram_sdp_scrub
        generic map (
            Depth_g        => Depth_c,
            Width_g        => Width_g,
            RamRdLatency_g => 1,
            RamStyle_g     => RamStyle_g,
            RamBehavior_g  => "RBW",
            EccPipeline_g  => 0,
            ScrubClkHz_g   => ClkFreqHz_g,
            ScrubPeriod_g  => ScrubPeriod_g
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            Wr_Addr        => Wr_Addr,
            Wr_Ena         => Wr_Ena,
            Wr_Data        => Wr_Data,
            Rd_Addr        => Rd_Addr,
            Rd_Ena         => Rd_Ena,
            Rd_Data        => Rd_Data,
            Rd_Valid       => Rd_Valid,
            Rd_EccSec      => Rd_Sec,
            Rd_EccDed      => Rd_Ded,
            ErrInj_BitFlip => Inj_Flip,
            ErrInj_Valid   => Inj_Ena,
            Scrub_Enable   => ScrubEna,
            Scrub_EccSec   => Scrub_Sec,
            Scrub_EccDed   => Scrub_Ded,
            Scrub_PassDone => open,
            Scrub_Overrun  => open
        );

end architecture;
