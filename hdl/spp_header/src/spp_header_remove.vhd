---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Header removal (CM-2): removes the first 0 to MaxRemoveBytes_g bytes of every packet of a stream
-- with byte enables, realigns the remaining bytes and outputs the removed bytes alongside, one beat
-- per clock cycle.
--
-- Documentation: hdl/spp_header/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library olo;
    use olo.olo_base_pkg_math.all;

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_header_remove is
    generic (
        DataWidth_g      : positive := 32;
        MaxRemoveBytes_g : positive := 6;
        UserWidth_g      : positive := 1
    );
    port (
        -- Control
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Input packets; the number of bytes to remove is sampled with the first beat of a packet
        In_Valid       : in    std_logic;
        In_Ready       : out   std_logic;
        In_Data        : in    std_logic_vector(DataWidth_g - 1 downto 0);
        In_Keep        : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        In_Last        : in    std_logic;
        In_User        : in    std_logic_vector(UserWidth_g - 1 downto 0) := (others => '0');
        In_RemoveBytes : in    std_logic_vector(log2ceil(MaxRemoveBytes_g + 1) - 1 downto 0);
        -- Output packets without the removed bytes. Out_Header holds the removed bytes (byte 0 in bits
        -- 7:0, zero beyond the end of a short packet). A packet without a byte beyond the removed ones is
        -- output as one beat with Out_Keep all zero and Out_Empty = '1'.
        Out_Valid      : out   std_logic;
        Out_Ready      : in    std_logic                                  := '1';
        Out_Data       : out   std_logic_vector(DataWidth_g - 1 downto 0);
        Out_Keep       : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        Out_Last       : out   std_logic;
        Out_User       : out   std_logic_vector(UserWidth_g - 1 downto 0);
        Out_Header     : out   std_logic_vector(8 * MaxRemoveBytes_g - 1 downto 0);
        Out_Empty      : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_header_remove is

    constant Bytes_c : positive := DataWidth_g / 8;

    type Bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);

    type Fsm_t is (Idle_s, Data_s, Flush_s);

    type TwoProcess_r is record
        State  : Fsm_t;
        Remain : natural range 0 to MaxRemoveBytes_g;
        HdrCnt : natural range 0 to MaxRemoveBytes_g;
        Hdr    : Bytes_t(0 to MaxRemoveBytes_g - 1);
        Res    : Bytes_t(0 to Bytes_c - 1);
        ResCnt : natural range 0 to Bytes_c - 1;
        User   : std_logic_vector(UserWidth_g - 1 downto 0);
        OValid : std_logic;
        OData  : Bytes_t(0 to Bytes_c - 1);
        OKeep  : std_logic_vector(Bytes_c - 1 downto 0);
        OLast  : std_logic;
        OUser  : std_logic_vector(UserWidth_g - 1 downto 0);
        OHdr   : Bytes_t(0 to MaxRemoveBytes_g - 1);
        OEmpty : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    assert DataWidth_g mod 8 = 0
        report "spp_header_remove: DataWidth_g must be a multiple of 8"
        severity failure;

    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable InBytes_v : Bytes_t(0 to Bytes_c - 1);
        variable Hdr_v     : Bytes_t(0 to MaxRemoveBytes_g - 1);
        variable HdrCnt_v  : natural range 0 to MaxRemoveBytes_g;
        variable Rem_v     : natural range 0 to MaxRemoveBytes_g;
        variable Res_v     : Bytes_t(0 to Bytes_c - 1);
        variable ResCnt_v  : natural range 0 to Bytes_c - 1;
        variable Comb_v    : Bytes_t(0 to 2 * Bytes_c - 1);
        variable N_v       : natural range 0 to Bytes_c;
        variable K_v       : natural range 0 to Bytes_c;
        variable P_v       : natural range 0 to Bytes_c;
        variable Total_v   : natural range 0 to 2 * Bytes_c;
        variable OutFree_v : boolean;
    begin
        -- Hold variables stable
        v        := r;
        In_Ready <= '0';

        -- Output register: a beat is free after its handshake
        if Out_Ready = '1' then
            v.OValid := '0';
        end if;
        OutFree_v := v.OValid = '0';

        for i in 0 to Bytes_c - 1 loop
            InBytes_v(i) := In_Data(8 * i + 7 downto 8 * i);
        end loop;

        N_v := bytesOfKeep(In_Keep);

        case r.State is

            when Idle_s | Data_s =>
                -- A new packet starts with the removal count of its first beat and an empty residue
                if r.State = Idle_s then
                    Rem_v    := to_integer(unsigned(In_RemoveBytes));
                    HdrCnt_v := 0;
                    Hdr_v    := (others => (others => '0'));
                    ResCnt_v := 0;
                else
                    Rem_v    := r.Remain;
                    HdrCnt_v := r.HdrCnt;
                    Hdr_v    := r.Hdr;
                    ResCnt_v := r.ResCnt;
                end if;
                Res_v := r.Res;

                if OutFree_v then
                    In_Ready <= '1';
                end if;

                if In_Valid = '1' and OutFree_v then
                    -- Removed bytes of this beat
                    if Rem_v < N_v then
                        K_v := Rem_v;
                    else
                        K_v := N_v;
                    end if;

                    for h in 0 to MaxRemoveBytes_g - 1 loop

                        -- Input lane i is removed byte HdrCnt + i
                        for i in 0 to Bytes_c - 1 loop
                            if i < K_v and h = HdrCnt_v + i then
                                Hdr_v(h) := InBytes_v(i);
                            end if;
                        end loop;

                    end loop;

                    HdrCnt_v := HdrCnt_v + K_v;
                    Rem_v    := Rem_v - K_v;
                    P_v      := N_v - K_v;

                    -- Residue followed by the remaining bytes of the beat
                    for j in 0 to 2 * Bytes_c - 1 loop
                        Comb_v(j) := (others => '0');
                        if j < Bytes_c then
                            if j < ResCnt_v then
                                Comb_v(j) := Res_v(j);
                            end if;
                        end if;

                        -- Input lane i (not removed) goes to position residue + i - removed bytes of the beat
                        for i in 0 to Bytes_c - 1 loop
                            if i >= K_v and j + K_v = ResCnt_v + i then
                                Comb_v(j) := InBytes_v(i);
                            end if;
                        end loop;

                    end loop;

                    Total_v  := ResCnt_v + P_v;
                    v.User   := In_User;
                    v.Remain := Rem_v;
                    v.HdrCnt := HdrCnt_v;
                    v.Hdr    := Hdr_v;
                    v.OData  := Comb_v(0 to Bytes_c - 1);
                    v.OUser  := In_User;
                    v.OHdr   := Hdr_v;
                    v.OEmpty := '0';
                    if Total_v >= Bytes_c then
                        v.OValid := '1';
                        v.OKeep  := (others => '1');
                        v.Res    := Comb_v(Bytes_c to 2 * Bytes_c - 1);
                        v.ResCnt := Total_v - Bytes_c;
                        if In_Last = '0' then
                            v.OLast := '0';
                            v.State := Data_s;
                        elsif Total_v > Bytes_c then
                            v.OLast := '0';
                            v.State := Flush_s;
                        else
                            v.OLast := '1';
                            v.State := Idle_s;
                        end if;
                    elsif In_Last = '1' then
                        -- Last beat; a packet without a byte beyond the removed ones is marked empty
                        v.OValid := '1';
                        v.OKeep  := keepOfBytes(Total_v, Bytes_c);
                        v.OLast  := '1';
                        if Total_v = 0 then
                            v.OEmpty := '1';
                        end if;
                        v.State := Idle_s;
                    else
                        -- Not enough bytes for an output beat yet
                        v.Res    := Comb_v(0 to Bytes_c - 1);
                        v.ResCnt := Total_v;
                        v.State  := Data_s;
                    end if;
                end if;

            when Flush_s =>
                -- Last beat: the residue of the last input beat
                if OutFree_v then
                    v.OValid := '1';
                    v.OData  := r.Res;
                    v.OKeep  := keepOfBytes(r.ResCnt, Bytes_c);
                    v.OLast  := '1';
                    v.OUser  := r.User;
                    v.OHdr   := r.Hdr;
                    v.OEmpty := '0';
                    v.State  := Idle_s;
                end if;

            -- coverage off
            when others =>
                v.State := Idle_s;
            -- coverage on

        end case;

        -- Apply to record
        r_next <= v;
    end process;

    -- Outputs
    Out_Valid <= r.OValid;
    Out_Keep  <= r.OKeep;
    Out_Last  <= r.OLast;
    Out_User  <= r.OUser;
    Out_Empty <= r.OEmpty;

    g_data : for i in 0 to Bytes_c - 1 generate
        Out_Data(8 * i + 7 downto 8 * i) <= r.OData(i);
    end generate;

    g_hdr : for i in 0 to MaxRemoveBytes_g - 1 generate
        Out_Header(8 * i + 7 downto 8 * i) <= r.OHdr(i);
    end generate;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State  <= Idle_s;
                r.OValid <= '0';
            end if;
        end if;
    end process;

end architecture;
