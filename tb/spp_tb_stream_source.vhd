---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stream source model: sends the packets of its channel of the packet store as an AXI4-Stream with
-- byte enables (first byte in lane 0, only the last beat partial) and random cycles without valid.
-- Lanes without byte enable carry random data.
--
-- What this model does NOT check or reproduce: it does not check the handshake of the receiver
-- beyond waiting for ready; it never sends a packet without bytes.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library work;
    use work.spp_tb_stream_pkg.all;
    use work.spp_tb_streamvar_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_tb_stream_source is
    generic (
        Channel_g   : natural;
        DataWidth_g : positive;
        UserWidth_g : positive := 1
    );
    port (
        Clk       : in    std_logic;
        Out_Valid : out   std_logic;
        Out_Ready : in    std_logic;
        Out_Data  : out   std_logic_vector(DataWidth_g - 1 downto 0);
        Out_Keep  : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        Out_Last  : out   std_logic;
        Out_User  : out   std_logic_vector(UserWidth_g - 1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_tb_stream_source is

    constant Bytes_c : positive := DataWidth_g / 8;

begin

    p_source : process is
        variable Seed1_v : positive := 17 + Channel_g;
        variable Seed2_v : positive := 4711 + 3 * Channel_g;
        variable Rand_v  : real;
        variable Len_v   : natural;
        variable Beats_v : natural;
        variable Idx_v   : natural;
        variable User_v  : TbUser_t;
    begin
        Out_Valid <= '0';
        Out_Last  <= '0';
        Out_Data  <= (others => '0');
        Out_Keep  <= (others => '0');
        Out_User  <= (others => '0');
        wait until rising_edge(Clk);

        loop
            if SppTbStore_v.count(Channel_g) = 0 then
                Out_Valid <= '0';
                wait until rising_edge(Clk);
            else
                Len_v   := SppTbStore_v.headLength(Channel_g);
                Beats_v := (Len_v + Bytes_c - 1) / Bytes_c;

                for b in 0 to Beats_v - 1 loop

                    -- Random cycles without valid
                    loop
                        uniform(Seed1_v, Seed2_v, Rand_v);
                        exit when Rand_v >= SppTbStore_v.getStall(Channel_g);
                        Out_Valid <= '0';
                        wait until rising_edge(Clk);
                    end loop;

                    for i in 0 to Bytes_c - 1 loop
                        Idx_v := b * Bytes_c + i;
                        if Idx_v < Len_v then
                            Out_Data(8 * i + 7 downto 8 * i) <= SppTbStore_v.headByte(Channel_g, Idx_v);
                            Out_Keep(i)                      <= '1';
                        else
                            uniform(Seed1_v, Seed2_v, Rand_v);
                            Out_Data(8 * i + 7 downto 8 * i) <= std_logic_vector(to_unsigned(integer(Rand_v * 255.0), 8));
                            Out_Keep(i)                      <= '0';
                        end if;
                    end loop;

                    if b = Beats_v - 1 then
                        User_v   := SppTbStore_v.headUserLast(Channel_g);
                        Out_Last <= '1';
                    else
                        User_v   := SppTbStore_v.headUser(Channel_g);
                        Out_Last <= '0';
                    end if;
                    Out_User  <= User_v(UserWidth_g - 1 downto 0);
                    Out_Valid <= '1';

                    loop
                        wait until rising_edge(Clk);
                        exit when Out_Ready = '1' or SppTbStore_v.getAbort(Channel_g);
                    end loop;

                    -- Reset tests: the rest of the packet is dropped
                    if SppTbStore_v.getAbort(Channel_g) then
                        SppTbStore_v.clearAbort(Channel_g);
                        Out_Valid <= '0';
                        exit;
                    end if;

                end loop;

                SppTbStore_v.pop(Channel_g);
            end if;
        end loop;

    end process;

end architecture;
