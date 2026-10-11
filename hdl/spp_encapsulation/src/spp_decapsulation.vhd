---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Decapsulation (EN-2) of the SpaceWire CCSDS Packet Transfer Protocol: removes leading address bytes
-- and the CPTP header, checks the Protocol Identifier, the Reserved field and optionally the Target
-- Logical Address, discards failed packets and passes the Space Packet with its User Application value.
--
-- Documentation: hdl/spp_encapsulation/docs/architecture.md

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
entity spp_decapsulation is
    generic (
        DataWidth_g : positive := 32
    );
    port (
        -- Control
        Clk          : in    std_logic;
        Rst          : in    std_logic;
        -- CPTP packets; TUser: error end of packet (with the last beat)
        S_Link_Valid : in    std_logic;
        S_Link_Ready : out   std_logic;
        S_Link_Data  : in    std_logic_vector(DataWidth_g - 1 downto 0);
        S_Link_Keep  : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        S_Link_Last  : in    std_logic;
        S_Link_User  : in    std_logic_vector(0 downto 0);
        -- Space Packets; TUser: error end of packet (bit 0, last beat), User Application value (8:1)
        M_Pkt_Valid  : out   std_logic;
        M_Pkt_Ready  : in    std_logic;
        M_Pkt_Data   : out   std_logic_vector(DataWidth_g - 1 downto 0);
        M_Pkt_Keep   : out   std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        M_Pkt_Last   : out   std_logic;
        M_Pkt_User   : out   std_logic_vector(RxPktUserWidth_c - 1 downto 0);
        -- Leading bytes removed before the CPTP header (0 to 15), Target Logical Address filter
        Cfg_RxStrip  : in    std_logic_vector(3 downto 0);
        Cfg_TlaCheck : in    std_logic;
        Cfg_Tla      : in    std_logic_vector(7 downto 0);
        -- Discarded packets
        Err          : out   ErrEvent_t
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture rtl of spp_decapsulation is

    constant MaxRemove_c : positive := MaxRxStripBytes_c + CptpHeaderBytes_c;

    type Fsm_t is (First_s, Forward_s, Drop_s);

    type TwoProcess_r is record
        State : Fsm_t;
        Code  : ErrCode_t;
        Err   : ErrEvent_t;
    end record;

    signal r, r_next : TwoProcess_r;

    -- Header removal; TUser: removal count (4:1), error end of packet (0)
    signal Rem_Bytes  : std_logic_vector(log2ceil(MaxRemove_c + 1) - 1 downto 0);
    signal Rem_InUser : std_logic_vector(4 downto 0);
    signal Rem_Valid  : std_logic;
    signal Rem_Ready  : std_logic;
    signal Rem_Last   : std_logic;
    signal Rem_User   : std_logic_vector(4 downto 0);
    signal Rem_Header : std_logic_vector(8 * MaxRemove_c - 1 downto 0);
    signal Rem_Empty  : std_logic;

begin

    Rem_Bytes  <= std_logic_vector(resize(unsigned(Cfg_RxStrip), Rem_Bytes'length) + CptpHeaderBytes_c);
    Rem_InUser <= Cfg_RxStrip & S_Link_User(0);

    i_remove : entity work.spp_header_remove
        generic map (
            DataWidth_g      => DataWidth_g,
            MaxRemoveBytes_g => MaxRemove_c,
            UserWidth_g      => 5
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            In_Valid       => S_Link_Valid,
            In_Ready       => S_Link_Ready,
            In_Data        => S_Link_Data,
            In_Keep        => S_Link_Keep,
            In_Last        => S_Link_Last,
            In_User        => Rem_InUser,
            In_RemoveBytes => Rem_Bytes,
            Out_Valid      => Rem_Valid,
            Out_Ready      => Rem_Ready,
            Out_Data       => M_Pkt_Data,
            Out_Keep       => M_Pkt_Keep,
            Out_Last       => Rem_Last,
            Out_User       => Rem_User,
            Out_Header     => Rem_Header,
            Out_Empty      => Rem_Empty
        );

    p_comb : process (all) is
        variable v       : TwoProcess_r;
        variable Strip_v : natural range 0 to MaxRxStripBytes_c;
        variable Tla_v   : std_logic_vector(7 downto 0);
        variable Pid_v   : std_logic_vector(7 downto 0);
        variable Res_v   : std_logic_vector(7 downto 0);
        variable Ua_v    : std_logic_vector(7 downto 0);
        variable Code_v  : ErrCode_t;
        variable Eep_v   : std_logic;
    begin
        -- Hold variables stable
        v     := r;
        v.Err := ErrEventNone_c;

        -- CPTP fields behind the removed address bytes of this packet
        Strip_v := to_integer(unsigned(Rem_User(4 downto 1)));
        Tla_v   := (others => '0');
        Pid_v   := (others => '0');
        Res_v   := (others => '0');
        Ua_v    := (others => '0');

        for s in 0 to MaxRxStripBytes_c loop
            if s = Strip_v then
                Tla_v := Rem_Header(8 * s + 7 downto 8 * s);
                Pid_v := Rem_Header(8 * s + 15 downto 8 * s + 8);
                Res_v := Rem_Header(8 * s + 23 downto 8 * s + 16);
                Ua_v  := Rem_Header(8 * s + 31 downto 8 * s + 24);
            end if;
        end loop;

        Eep_v := Rem_User(0) and Rem_Last;

        -- Checks of the first beat (CPTP 5.5.4)
        if Rem_Empty = '1' then
            Code_v := ErrRxShort_c;                                           -- no byte beyond the CPTP header
        elsif Pid_v /= CptpProtocolId_c then
            Code_v := ErrRxProtocolId_c;                                      -- CPTP 5.5.4.1
        elsif Res_v /= CptpReserved_c then
            Code_v := ErrRxReserved_c;                                        -- CPTP 5.5.4.3a
        elsif Cfg_TlaCheck = '1' and Tla_v /= Cfg_Tla and Tla_v /= DefaultLogicalAddr_c then
            Code_v := ErrRxAddress_c;                                         -- CPTP 5.3.2
        else
            Code_v := ErrNone_c;
        end if;

        -- Defaults
        M_Pkt_Valid <= '0';
        Rem_Ready   <= '0';

        case r.State is

            when First_s | Forward_s =>
                if r.State = First_s and Code_v /= ErrNone_c then
                    -- Discarded: consumed up to the end of the packet
                    Rem_Ready <= '1';
                    if Rem_Valid = '1' then
                        v.Code  := Code_v;
                        v.State := Drop_s;
                    end if;
                else
                    -- CPTP 5.5.4.2: the Space Packet and the User Application value to the user
                    M_Pkt_Valid <= Rem_Valid;
                    Rem_Ready   <= M_Pkt_Ready;
                    if Rem_Valid = '1' and M_Pkt_Ready = '1' then
                        if Rem_Last = '1' then
                            v.State := First_s;
                        else
                            v.State := Forward_s;
                        end if;
                    end if;
                end if;

            when Drop_s =>
                Rem_Ready <= '1';

            -- coverage off
            when others =>
                v.State := First_s;
            -- coverage on

        end case;

        -- Report of a discarded packet at its end; an EEP takes precedence (architecture D8)
        if v.State = Drop_s and Rem_Valid = '1' and Rem_Last = '1' then
            v.State     := First_s;
            v.Err.Valid := '1';
            if Eep_v = '1' then
                v.Err.Code := ErrRxEep_c;                                    -- CPTP 5.5.4.4
            else
                v.Err.Code := v.Code;
            end if;
        end if;

        M_Pkt_Last                 <= Rem_Last;
        M_Pkt_User(RxPktUserEep_c) <= Eep_v;
        M_Pkt_User(RxPktUserUa_t)  <= Ua_v;

        -- Apply to record
        r_next <= v;
    end process;

    Err <= r.Err;

    p_seq : process (Clk) is
    begin
        if rising_edge(Clk) then
            r <= r_next;
            if Rst = '1' then
                r.State     <= First_s;
                r.Err.Valid <= '0';
            end if;
        end if;
    end process;

end architecture;
