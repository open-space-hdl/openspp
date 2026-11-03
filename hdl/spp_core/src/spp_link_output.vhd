---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Link output stage (LK-1): the last register of the transmit path of the core, one beat with a
-- combinational ready path. The data path reset DpRst does not reset it: a beat presented on the link
-- stays presented until its transfer, and a packet that is open on the link is ended with one EEP beat
-- of one byte. Rst resets the stage and takes precedence.
--
-- Documentation: hdl/spp_core/docs/architecture.md

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
entity spp_link_output is
    generic (
        DataWidth_g : positive := 32
    );
    port (
        -- Control: Rst resets the stage, DpRst (data path reset of the core) makes it end an open packet
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        DpRst        : in    std_logic;
        -- Link packets of the core; TUser: error end of packet (bit 0, last beat), destination (4:1)
        S_Pkt_Valid  : in    std_logic;
        S_Pkt_Ready  : out   std_logic;
        S_Pkt_Data   : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Pkt_Keep   : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Pkt_Last   : in    std_logic;
        S_Pkt_User   : in    std_logic_vector(LinkUserWidth_c - 1 downto 0);
        -- Link output; TUser as the input
        M_Link_Valid : out   std_logic;
        M_Link_Ready : in    std_logic;
        M_Link_Data  : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Link_Keep  : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Link_Last  : out   std_logic;
        M_Link_User  : out   std_logic_vector(LinkUserWidth_c - 1 downto 0)
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_link_output is

    constant Bytes_c : positive := DataWidth_g / 8;

    -- Byte enables of the EEP beat: byte lane 0 only
    constant EepKeep_c : std_logic_vector(Bytes_c - 1 downto 0) := std_logic_vector(to_unsigned(1, Bytes_c));

    -- Pass_s forwards the beats of the core; End_s ends the packet that is open at the data path reset and waits
    -- for the release of DpRst
    type Fsm_t is (Pass_s, End_s);

    type TwoProcess_r is record
        State   : Fsm_t;
        OValid  : std_logic;
        OData   : std_logic_vector(DataWidth_g - 1 downto 0);
        OKeep   : std_logic_vector(Bytes_c - 1 downto 0);
        OLast   : std_logic;
        OUser   : std_logic_vector(LinkUserWidth_c - 1 downto 0);
        -- A packet has beats transferred on the link and its last beat is not transferred
        PktOpen : std_logic;
    end record;

    signal r, r_next : TwoProcess_r;

begin

    assert DataWidth_g mod 8 = 0
        report "spp_link_output: DataWidth_g must be a multiple of 8"
        severity failure;

    p_comb : process (all) is
        variable v          : TwoProcess_r;
        variable Hs_v       : boolean;
        variable Free_v     : boolean;
        variable OpenNext_v : std_logic;
        variable Fwd_v      : boolean;
        variable End_v      : boolean;
        variable InReady_v  : std_logic;
    begin
        -- Hold variables stable
        v         := r;
        InReady_v := '0';

        -- The beat in the register is transferred at the end of this cycle; the register can take a beat
        Hs_v   := r.OValid = '1' and M_Link_Ready = '1';
        Free_v := r.OValid = '0' or M_Link_Ready = '1';

        -- A packet is open after this cycle when the transferred beat is not its last one
        if Hs_v then
            v.OValid   := '0';
            OpenNext_v := not r.OLast;
        else
            OpenNext_v := r.PktOpen;
        end if;

        case r.State is

            when Pass_s =>
                -- The reset edge of DpRst (or DpRst still applied after Rst) ends the open packet
                Fwd_v := DpRst = '0';
                End_v := DpRst = '1';

            when End_s =>
                Fwd_v := false;
                End_v := true;

            -- coverage off
            when others =>
                Fwd_v   := false;
                End_v   := false;
                v.State := Pass_s;
            -- coverage on

        end case;

        if Fwd_v then
            -- Register stage of one beat
            if Free_v then
                InReady_v := '1';
                if S_Pkt_Valid = '1' then
                    v.OValid := '1';
                    v.OData  := S_Pkt_Data;
                    v.OKeep  := S_Pkt_Keep;
                    v.OLast  := S_Pkt_Last;
                    v.OUser  := S_Pkt_User;
                end if;
            end if;
        elsif End_v then
            -- No beat of the core enters; a pending beat stays presented until its transfer, then the open
            -- packet ends with one EEP beat of one byte (CPTP 5.5.4.4a: the target discards it)
            v.State := End_s;
            if Free_v then
                if OpenNext_v = '1' then
                    v.OValid := '1';
                    v.OData  := (others => '0');
                    v.OKeep  := EepKeep_c;
                    v.OLast  := '1';
                    v.OUser  := r.OUser(LinkUserDest_t) & '1';
                elsif DpRst = '0' then
                    v.State := Pass_s;
                end if;
            end if;
        end if;

        v.PktOpen := OpenNext_v;

        -- Outputs
        S_Pkt_Ready <= InReady_v;

        -- Apply to record
        r_next <= v;
    end process;

    -- Outputs
    M_Link_Valid <= r.OValid;
    M_Link_Data  <= r.OData;
    M_Link_Keep  <= r.OKeep;
    M_Link_Last  <= r.OLast;
    M_Link_User  <= r.OUser;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            -- Rst takes precedence over DpRst: the packet is cut, a pending beat or EEP beat withdrawn
            if Rst = '1' then
                r.State   <= Pass_s;
                r.OValid  <= '0';
                r.OKeep   <= (others => '0');
                r.OLast   <= '0';
                r.OUser   <= (others => '0');
                r.PktOpen <= '0';
            end if;
        end if;
    end process;

end architecture;
