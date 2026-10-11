---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Header insertion (CM-1): puts a header of 0 to MaxHeaderBytes_g bytes in front of every packet of
-- a stream with byte enables and realigns the packet bytes behind it, one beat per clock cycle.
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
entity spp_header_insert is
    generic (
        DataWidth_g      : positive := 32;
        MaxHeaderBytes_g : positive := 6;
        UserWidth_g      : positive := 1
    );
    port (
        -- Control
        Clk            : in    std_logic;
        Rst            : in    std_logic;
        -- Input packets; header and header length are sampled with the first beat of a packet
        In_Valid       : in    std_logic;
        In_Ready       : out   std_logic;
        In_Data        : in    std_logic_vector(DataWidth_g - 1 downto 0);
        In_Keep        : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        In_Last        : in    std_logic;
        In_User        : in    std_logic_vector(UserWidth_g - 1 downto 0) := (others => '0');
        In_Header      : in    std_logic_vector(8 * MaxHeaderBytes_g - 1 downto 0);
        In_HeaderBytes : in    std_logic_vector(log2ceil(MaxHeaderBytes_g + 1) - 1 downto 0);
        -- Output packets: header followed by the input bytes
        Out_Valid      : out   std_logic;
        Out_Ready      : in    std_logic                                  := '1';
        Out_Data       : out   std_logic_vector(DataWidth_g - 1 downto 0);
        Out_Keep       : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        Out_Last       : out   std_logic;
        Out_User       : out   std_logic_vector(UserWidth_g - 1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_header_insert is

    constant Bytes_c : positive := DataWidth_g / 8;

    type Bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);

    type Fsm_t is (Idle_s, Header_s, Data_s, Flush_s);

    type TwoProcess_r is record
        State  : Fsm_t;
        Hdr    : Bytes_t(0 to MaxHeaderBytes_g - 1);
        HdrRem : natural range 0 to MaxHeaderBytes_g;
        Res    : Bytes_t(0 to Bytes_c - 1);
        ResCnt : natural range 0 to Bytes_c - 1;
        User   : std_logic_vector(UserWidth_g - 1 downto 0);
        OValid : std_logic;
        OData  : Bytes_t(0 to Bytes_c - 1);
        OKeep  : std_logic_vector(Bytes_c - 1 downto 0);
        OLast  : std_logic;
        OUser  : std_logic_vector(UserWidth_g - 1 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

begin

    assert DataWidth_g mod 8 = 0
        report "spp_header_insert: DataWidth_g must be a multiple of 8"
        severity failure;

    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable InBytes_v : Bytes_t(0 to Bytes_c - 1);
        variable Hdr_v     : Bytes_t(0 to MaxHeaderBytes_g - 1);
        variable HdrRem_v  : natural range 0 to MaxHeaderBytes_g;
        variable Res_v     : Bytes_t(0 to Bytes_c - 1);
        variable ResCnt_v  : natural range 0 to Bytes_c - 1;
        variable Comb_v    : Bytes_t(0 to 2 * Bytes_c - 1);
        variable N_v       : natural range 0 to Bytes_c;
        variable Total_v   : natural range 0 to 2 * Bytes_c;
        variable OutFree_v : boolean;
        variable Consume_v : boolean;
        variable InReady_v : std_logic;
    begin
        -- Hold variables stable
        v         := r;
        InReady_v := '0';
        Consume_v := false;
        Res_v     := r.Res;
        ResCnt_v  := r.ResCnt;

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

            when Idle_s | Header_s =>
                -- Header phase: the header of a new packet comes from the input, later from the registers
                if r.State = Idle_s then

                    for i in 0 to MaxHeaderBytes_g - 1 loop
                        Hdr_v(i) := In_Header(8 * i + 7 downto 8 * i);
                    end loop;

                    HdrRem_v := to_integer(unsigned(In_HeaderBytes));
                else
                    Hdr_v    := r.Hdr;
                    HdrRem_v := r.HdrRem;
                end if;

                if HdrRem_v >= Bytes_c then
                    -- A beat of header bytes only
                    if (r.State = Header_s or In_Valid = '1') and OutFree_v then
                        if r.State = Idle_s then
                            v.User := In_User;
                        end if;
                        v.OValid := '1';

                        -- HdrRem_v >= Bytes_c: the beat is not wider than the header
                        for i in 0 to minimum(Bytes_c, MaxHeaderBytes_g) - 1 loop
                            v.OData(i) := Hdr_v(i);
                        end loop;

                        v.OKeep := (others => '1');
                        v.OLast := '0';
                        v.OUser := v.User;

                        for i in 0 to MaxHeaderBytes_g - 1 loop
                            if i + Bytes_c < MaxHeaderBytes_g then
                                v.Hdr(i) := Hdr_v(i + Bytes_c);
                            else
                                v.Hdr(i) := (others => '0');
                            end if;
                        end loop;

                        v.HdrRem := HdrRem_v - Bytes_c;
                        v.State  := Header_s;
                    end if;
                else
                    -- The remaining header bytes are the residue in front of the first input beat
                    ResCnt_v := HdrRem_v;

                    for i in 0 to Bytes_c - 1 loop
                        if i < MaxHeaderBytes_g then
                            Res_v(i) := Hdr_v(i);
                        else
                            Res_v(i) := (others => '0');
                        end if;
                    end loop;

                    InReady_v := '1' when OutFree_v else '0';
                    if In_Valid = '1' and OutFree_v then
                        Consume_v := true;
                    elsif r.State = Header_s then
                        v.Res    := Res_v;
                        v.ResCnt := ResCnt_v;
                        v.State  := Data_s;
                    end if;
                end if;

            when Data_s =>
                InReady_v := '1' when OutFree_v else '0';
                if In_Valid = '1' and OutFree_v then
                    Consume_v := true;
                end if;

            when Flush_s =>
                -- Last beat: the residue of the last input beat
                if OutFree_v then
                    v.OValid := '1';
                    v.OData  := r.Res;
                    v.OKeep  := keepOfBytes(r.ResCnt, Bytes_c);
                    v.OLast  := '1';
                    v.OUser  := r.User;
                    v.State  := Idle_s;
                end if;

            -- coverage off
            when others =>
                v.State := Idle_s;
            -- coverage on

        end case;

        -- Residue followed by the bytes of the input beat
        if Consume_v then

            for j in 0 to 2 * Bytes_c - 1 loop
                Comb_v(j) := (others => '0');
                if j < Bytes_c then
                    if j < ResCnt_v then
                        Comb_v(j) := Res_v(j);
                    end if;
                end if;

                -- Input lane i goes to position residue + i
                for i in 0 to Bytes_c - 1 loop
                    if j = ResCnt_v + i then
                        Comb_v(j) := InBytes_v(i);
                    end if;
                end loop;

            end loop;

            Total_v  := ResCnt_v + N_v;
            v.User   := In_User;
            v.OValid := '1';
            v.OData  := Comb_v(0 to Bytes_c - 1);
            v.OUser  := In_User;
            if Total_v >= Bytes_c then
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
            else
                -- Only the last beat of a packet is partial
                v.OKeep := keepOfBytes(Total_v, Bytes_c);
                v.OLast := '1';
                v.State := Idle_s;
            end if;
        end if;

        -- Outputs
        In_Ready <= InReady_v;

        -- Apply to record
        r_next <= v;
    end process;

    -- Outputs
    Out_Valid <= r.OValid;
    Out_Keep  <= r.OKeep;
    Out_Last  <= r.OLast;
    Out_User  <= r.OUser;

    g_data : for i in 0 to Bytes_c - 1 generate
        Out_Data(8 * i + 7 downto 8 * i) <= r.OData(i);
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
