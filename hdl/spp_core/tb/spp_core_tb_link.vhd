---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Link model between two cores: passes the packets of one core to the other, or the packets of an
-- injector stream when selected, and can drop packets or end them with an EEP. With Strip > 0 it
-- removes the leading bytes of every packet of the sending core, as the routers of a network remove
-- path address bytes.
--
-- What this model does NOT check or reproduce: the timing and the flow control of a SpaceWire or
-- SpaceFibre link; it never reorders packets; a packet is forwarded beat by beat with the handshake of
-- the receiving core (with Strip > 0: received completely, then sent).
--
-- Documentation: hdl/spp_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_core_tb_link is
    generic (
        DataWidth_g : positive
    );
    port (
        Clk        : in    std_logic;
        -- Packets of the sending core; TUser bit 0: EEP
        S_Valid    : in    std_logic;
        S_Ready    : out   std_logic;
        S_Data     : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Keep     : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Last     : in    std_logic;
        S_User     : in    std_logic_vector(4 downto 0);
        -- Injected packets
        Inj_Valid  : in    std_logic;
        Inj_Ready  : out   std_logic;
        Inj_Data   : in    std_logic_vector(DataWidth_g - 1 downto 0);
        Inj_Keep   : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        Inj_Last   : in    std_logic;
        Inj_User   : in    std_logic_vector(0 downto 0);
        -- Packets to the receiving core
        M_Valid    : out   std_logic;
        M_Ready    : in    std_logic;
        M_Data     : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Keep     : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Last     : out   std_logic;
        M_User     : out   std_logic_vector(0 downto 0);
        -- Control: '1' forwards the injected packets (between packets); the packets of the sending core are
        -- dropped up to DropTarget and ended with an EEP up to EepTarget (counted from the start); Strip > 0
        -- removes the first Strip bytes of every packet of the sending core (not combined with drop and EEP)
        Sel        : in    std_logic;
        DropTarget : in    natural;
        EepTarget  : in    natural;
        Strip      : in    natural := 0;
        Dropped    : out   natural;
        Eeped      : out   natural;
        Forwarded  : out   natural
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_core_tb_link is

    type Bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);

    constant Bytes_c : positive := DataWidth_g / 8;

    signal InPkt : boolean := false;
    signal Drop  : boolean := false;
    signal Eep   : boolean := false;
    signal NDrop : natural := 0;
    signal NEep  : natural := 0;
    signal NFwd  : natural := 0;

    -- Packets of the sending core without their first Strip bytes
    signal StSReady : std_logic                                      := '0';
    signal StValid  : std_logic                                      := '0';
    signal StData   : std_logic_vector(DataWidth_g - 1 downto 0)     := (others => '0');
    signal StKeep   : std_logic_vector(DataWidth_g / 8 - 1 downto 0) := (others => '0');
    signal StLast   : std_logic                                      := '0';
    signal StUser   : std_logic_vector(0 downto 0)                   := "0";

begin

    -- Decision for the packet starting now (held during the packet)
    p_comb : process (all) is
        variable Drop_v : boolean;
        variable Eep_v  : boolean;
    begin
        if InPkt then
            Drop_v := Drop;
            Eep_v  := Eep;
        else
            Drop_v := NDrop < DropTarget;
            Eep_v  := NEep < EepTarget;
        end if;

        if Sel = '1' then
            M_Valid   <= Inj_Valid;
            Inj_Ready <= M_Ready;
            M_Data    <= Inj_Data;
            M_Keep    <= Inj_Keep;
            M_Last    <= Inj_Last;
            M_User    <= Inj_User;
            S_Ready   <= '0';
        elsif Strip > 0 then
            M_Valid   <= StValid;
            Inj_Ready <= '0';
            M_Data    <= StData;
            M_Keep    <= StKeep;
            M_Last    <= StLast;
            M_User    <= StUser;
            S_Ready   <= StSReady;
        elsif Drop_v then
            M_Valid   <= '0';
            Inj_Ready <= '0';
            M_Data    <= S_Data;
            M_Keep    <= S_Keep;
            M_Last    <= S_Last;
            M_User    <= S_User(0 downto 0);
            S_Ready   <= '1';
        else
            M_Valid   <= S_Valid;
            Inj_Ready <= '0';
            M_Data    <= S_Data;
            M_Keep    <= S_Keep;
            M_Last    <= S_Last;
            if Eep_v and S_Last = '1' then
                M_User <= "1";
            else
                M_User <= S_User(0 downto 0);
            end if;
            S_Ready <= M_Ready;
        end if;
    end process;

    p_seq : process (Clk) is
        variable Drop_v : boolean;
        variable Eep_v  : boolean;
    begin
        if rising_edge(Clk) then
            if Sel = '0' and S_Valid = '1' and (S_Ready = '1') then
                if InPkt then
                    Drop_v := Drop;
                    Eep_v  := Eep;
                else
                    Drop_v := NDrop < DropTarget;
                    Eep_v  := NEep < EepTarget;
                end if;
                Drop  <= Drop_v;
                Eep   <= Eep_v;
                InPkt <= S_Last = '0';
                if S_Last = '1' then
                    if Drop_v then
                        NDrop <= NDrop + 1;
                    elsif Eep_v then
                        NEep <= NEep + 1;
                    else
                        NFwd <= NFwd + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Strip > 0: a packet of the sending core is received completely, then sent without its first Strip bytes
    p_strip : process is
        variable Buf_v : Bytes_t(0 to 2 ** 17 - 1);
        variable Len_v : natural;
        variable Pos_v : natural;
        variable Eep_v : std_logic;
    begin
        wait until rising_edge(Clk) and Strip > 0 and Sel = '0';
        Len_v    := 0;
        StSReady <= '1';

        loop
            wait until rising_edge(Clk) and S_Valid = '1';

            for b in 0 to Bytes_c - 1 loop
                if S_Keep(b) = '1' then
                    Buf_v(Len_v) := S_Data(8 * b + 7 downto 8 * b);
                    Len_v        := Len_v + 1;
                end if;
            end loop;

            exit when S_Last = '1';
        end loop;

        Eep_v    := S_User(0);
        StSReady <= '0';
        Pos_v    := Strip;

        while Pos_v < Len_v loop
            StKeep <= (others => '0');
            StData <= (others => '0');

            for b in 0 to Bytes_c - 1 loop
                if Pos_v + b < Len_v then
                    StData(8 * b + 7 downto 8 * b) <= Buf_v(Pos_v + b);
                    StKeep(b)                      <= '1';
                end if;
            end loop;

            StLast    <= '1' when Pos_v + Bytes_c >= Len_v else '0';
            StUser(0) <= Eep_v when Pos_v + Bytes_c >= Len_v else '0';
            StValid   <= '1';
            wait until rising_edge(Clk) and M_Ready = '1';
            Pos_v     := Pos_v + Bytes_c;
        end loop;

        StValid <= '0';
    end process;

    Dropped   <= NDrop;
    Eeped     <= NEep;
    Forwarded <= NFwd;

end architecture;
