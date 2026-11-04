---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- CRC trailer of the packetizer (PT-1): appends the two bytes of In_User behind the last valid byte
-- of every packet, bits 15:8 first, and adds a beat when the last beat has no room for them.
--
-- Documentation: hdl/spp_packetizer/docs/architecture.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library work;
    use work.spp_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_packetizer_trailer is
    generic (
        DataWidth_g : positive := 32
    );
    port (
        -- Control
        Clk       : in    std_logic;
        Rst       : in    std_logic;
        -- Input packets, the trailer bytes in In_User of the last beat
        In_Valid  : in    std_logic;
        In_Ready  : out   std_logic;
        In_Data   : in    std_logic_vector(DataWidth_g - 1 downto 0);
        In_Keep   : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        In_Last   : in    std_logic;
        In_User   : in    std_logic_vector(15 downto 0);
        -- Output packets with the trailer
        Out_Valid : out   std_logic;
        Out_Ready : in    std_logic;
        Out_Data  : out   std_logic_vector(DataWidth_g - 1 downto 0);
        Out_Keep  : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        Out_Last  : out   std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_packetizer_trailer is

    constant Bytes_c : positive := DataWidth_g / 8;

    type TwoProcess_r is record
        -- Output register
        OValid : std_logic;
        OData  : std_logic_vector(DataWidth_g - 1 downto 0);
        OKeep  : std_logic_vector(Bytes_c - 1 downto 0);
        OLast  : std_logic;
        -- Trailer bytes still to be output in an added beat, the next one in bits 15:8
        Pend   : natural range 0 to 2;
        PData  : std_logic_vector(15 downto 0);
    end record;

    signal r, r_next : TwoProcess_r;

begin

    p_comb : process (all) is
        variable v         : TwoProcess_r;
        variable OutFree_v : boolean;
        variable InReady_v : std_logic;
        variable N_v       : natural range 0 to Bytes_c;
        variable Rem_v     : natural range 0 to 2;
        variable T_v       : std_logic_vector(15 downto 0);
    begin
        -- Hold variables stable
        v         := r;
        InReady_v := '0';

        if r.OValid = '1' and Out_Ready = '1' then
            v.OValid := '0';
        end if;
        OutFree_v := v.OValid = '0';

        if r.Pend > 0 then
            -- Added beat with the remaining trailer bytes
            if OutFree_v then
                Rem_v   := r.Pend;
                T_v     := r.PData;
                v.OKeep := (others => '0');
                v.OData := (others => '0');

                for i in 0 to Bytes_c - 1 loop
                    if Rem_v > 0 then
                        v.OData(8 * i + 7 downto 8 * i) := T_v(15 downto 8);
                        v.OKeep(i)                      := '1';
                        T_v                             := T_v(7 downto 0) & x"00";
                        Rem_v                           := Rem_v - 1;
                    end if;
                end loop;

                v.OValid := '1';
                v.OLast  := '1' when Rem_v = 0 else '0';
                v.Pend   := Rem_v;
                v.PData  := T_v;
            end if;
        else
            InReady_v := '1' when OutFree_v else '0';
            if In_Valid = '1' and OutFree_v then
                v.OValid := '1';
                v.OData  := In_Data;
                v.OKeep  := In_Keep;
                v.OLast  := In_Last;
                if In_Last = '1' then
                    -- The trailer bytes fill the lanes behind the last valid byte, the rest follows
                    N_v   := bytesOfKeep(In_Keep);
                    Rem_v := 2;
                    T_v   := In_User;

                    for i in 0 to Bytes_c - 1 loop
                        if i >= N_v and Rem_v > 0 then
                            v.OData(8 * i + 7 downto 8 * i) := T_v(15 downto 8);
                            v.OKeep(i)                      := '1';
                            T_v                             := T_v(7 downto 0) & x"00";
                            Rem_v                           := Rem_v - 1;
                        end if;
                    end loop;

                    v.OLast := '1' when Rem_v = 0 else '0';
                    v.Pend  := Rem_v;
                    v.PData := T_v;
                end if;
            end if;
        end if;

        -- Outputs
        In_Ready  <= InReady_v;
        Out_Valid <= r.OValid;
        Out_Data  <= r.OData;
        Out_Keep  <= r.OKeep;
        Out_Last  <= r.OLast;

        -- Apply to record
        r_next <= v;
    end process;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.OValid <= '0';
                r.Pend   <= 0;
            end if;
        end if;
    end process;

end architecture;
