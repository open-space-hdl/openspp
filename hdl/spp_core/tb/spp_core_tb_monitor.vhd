---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Monitor of the link output of a core: checks the AXI4-Stream rules in every cycle (a presented beat
-- stays unchanged until its transfer, except across Rst; byte enables contiguous from lane 0 and not
-- empty; the EEP flag only with TLast) and the behaviour of the link output stage at the resets: Rst
-- clears the output, DpRst ends an open packet with exactly one EEP beat in the cycle after the reset
-- edge or after the transfer of the pending beat, and no beat follows the end of the packet before the
-- release (specification CO-RS-03 to CO-RS-08). Counts the beats, packets and EEP beats and samples
-- the coverpoints DPRST_POINT and DPRST_LINK.
--
-- What this monitor does NOT check: the content of the packets (the stream sinks and the receiving
-- core do), and that the first packet after the release belongs to an SDU taken after the release (the
-- testbench checks the SDUs delivered by the other core).
--
-- Documentation: hdl/spp_core/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.spp_core_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_core_tb_monitor is
    generic (
        DataWidth_g : positive;
        Name_g      : string
    );
    port (
        Clk      : in    std_logic;
        Rst      : in    std_logic;
        DpRst    : in    std_logic;
        -- Link output of the core; User: EEP (bit 0), destination (4:1)
        Valid    : in    std_logic;
        Ready    : in    std_logic;
        Data     : in    std_logic_vector(DataWidth_g - 1 downto 0);
        Keep     : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        Last     : in    std_logic;
        User     : in    std_logic_vector(4 downto 0);
        -- Beats of the current packet transferred so far, statistics
        PktBeats : out   natural   := 0;
        Stat     : out   MonStat_t := MonStatInit_c
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_core_tb_monitor is

    constant Bytes_c   : positive                               := DataWidth_g / 8;
    constant EepKeep_c : std_logic_vector(Bytes_c - 1 downto 0) := std_logic_vector(to_unsigned(1, Bytes_c));

    -- Expectation after a reset edge of DpRst: none, the pending beat, the EEP beat, no beat up to the release
    type State_t is (Normal_s, WaitPend_s, ExpEep_s, Quiet_s);

begin

    p_monitor : process (Clk) is
        variable State_v    : State_t                      := Normal_s;
        variable St_v       : MonStat_t                    := MonStatInit_c;
        variable Pkt_v      : natural                      := 0;
        variable Before_v   : natural;
        variable Dest_v     : std_logic_vector(3 downto 0) := "0000";
        variable PValid_v   : std_logic                    := '0';
        variable PHs_v      : boolean                      := false;
        variable PData_v    : std_logic_vector(DataWidth_g - 1 downto 0);
        variable PKeep_v    : std_logic_vector(Bytes_c - 1 downto 0);
        variable PLast_v    : std_logic;
        variable PUser_v    : std_logic_vector(4 downto 0);
        variable RstS_v     : boolean                      := false;
        variable PendLast_v : std_logic                    := '0';
        variable Rel_v      : boolean                      := false;
        variable Hs_v       : boolean;
        variable N_v        : natural;
        variable Gap_v      : boolean;
        variable Ended_v    : boolean;
    begin
        if rising_edge(Clk) then
            Hs_v := Valid = '1' and Ready = '1';

            -- A presented beat stays unchanged until its transfer (Arm IHI 0051B 2.2.1); Rst may withdraw it
            if PValid_v = '1' and not PHs_v and not RstS_v then
                if Valid /= '1' or Data /= PData_v or Keep /= PKeep_v or Last /= PLast_v or User /= PUser_v then
                    alert(ERROR, Name_g & ": beat withdrawn or changed before its transfer");
                end if;
            end if;

            -- No beat in the cycle after a reset edge of Rst (CO-RS-07)
            if RstS_v and Valid = '1' then
                alert(ERROR, Name_g & ": beat in the cycle after an edge with Rst");
            end if;

            -- Format of a beat
            if Valid = '1' then
                N_v   := 0;
                Gap_v := false;

                for i in 0 to Bytes_c - 1 loop
                    if Keep(i) = '1' then
                        if Gap_v then
                            alert(ERROR, Name_g & ": byte enables not contiguous: " & to_string(Keep));
                        end if;
                        N_v := N_v + 1;
                    else
                        Gap_v := true;
                    end if;
                end loop;

                if N_v = 0 then
                    alert(ERROR, Name_g & ": beat without valid bytes");
                end if;
                if Last = '0' and N_v /= Bytes_c then
                    alert(ERROR, Name_g & ": byte enables of a beat that is not the last: " & to_string(Keep));
                end if;
                if Last = '0' and User(0) = '1' then
                    alert(ERROR, Name_g & ": EEP flag without TLast");
                end if;
            end if;

            -- Transfers
            Before_v := Pkt_v;
            Ended_v  := false;
            if Hs_v then
                St_v.Beats := St_v.Beats + 1;
                Dest_v     := User(4 downto 1);
                if Last = '1' then
                    St_v.Packets := St_v.Packets + 1;
                    if User(0) = '1' then
                        St_v.EepPkts := St_v.EepPkts + 1;
                    end if;
                    Pkt_v := 0;
                else
                    Pkt_v := Pkt_v + 1;
                end if;
            end if;

            -- Link output stage at the resets: Rst takes precedence
            if Rst = '1' then
                State_v := Normal_s;
                Pkt_v   := 0;
            else

                case State_v is

                    when Normal_s =>
                        -- First edge with DpRst for the stage (its reset edge, or DpRst still applied after Rst)
                        if DpRst = '1' then
                            Rel_v := false;
                            if Valid = '0' then
                                St_v.Link(LinkReady_c) := St_v.Link(LinkReady_c) + 1;
                                if Before_v > 0 then
                                    St_v.Point(PointOpenIdle_c) := St_v.Point(PointOpenIdle_c) + 1;
                                    State_v                     := ExpEep_s;
                                else
                                    St_v.Point(PointNone_c) := St_v.Point(PointNone_c) + 1;
                                    State_v                 := Quiet_s;
                                end if;
                            elsif Hs_v then
                                St_v.Link(LinkReady_c) := St_v.Link(LinkReady_c) + 1;
                                if Last = '1' then
                                    St_v.Point(PointLastXfer_c) := St_v.Point(PointLastXfer_c) + 1;
                                    State_v                     := Quiet_s;
                                elsif Before_v = 0 then
                                    St_v.Point(PointFirstXfer_c) := St_v.Point(PointFirstXfer_c) + 1;
                                    State_v                      := ExpEep_s;
                                else
                                    St_v.Point(PointMiddleXfer_c) := St_v.Point(PointMiddleXfer_c) + 1;
                                    State_v                       := ExpEep_s;
                                end if;
                            else
                                St_v.Link(LinkPending_c) := St_v.Link(LinkPending_c) + 1;
                                Dest_v                   := User(4 downto 1);
                                PendLast_v               := Last;
                                State_v                  := WaitPend_s;
                                if Last = '1' then
                                    St_v.Point(PointLastPend_c) := St_v.Point(PointLastPend_c) + 1;
                                elsif Before_v = 0 then
                                    St_v.Point(PointFirstPend_c) := St_v.Point(PointFirstPend_c) + 1;
                                else
                                    St_v.Point(PointMiddlePend_c) := St_v.Point(PointMiddlePend_c) + 1;
                                end if;
                            end if;
                        end if;

                    when WaitPend_s =>
                        -- The pending beat is held (checked above); after its transfer the EEP beat follows at once
                        if Hs_v then
                            if PendLast_v = '1' then
                                Ended_v := true;
                            else
                                State_v := ExpEep_s;
                            end if;
                        end if;

                    when ExpEep_s =>
                        if Valid /= '1' or Last /= '1' or Keep /= EepKeep_c or unsigned(Data) /= 0 or
                           User /= Dest_v & '1' then
                            alert(ERROR, Name_g & ": EEP beat expected (Data 0, Keep lane 0, TLast, TUser " &
                                  to_string(Dest_v & '1') & "), got Valid " & to_string(Valid) & ", Keep " &
                                  to_string(Keep) & ", Last " & to_string(Last) & ", TUser " & to_string(User));
                        end if;
                        if Hs_v then
                            St_v.Eeps := St_v.Eeps + 1;
                            Ended_v   := true;
                        end if;

                    when Quiet_s =>
                        if Valid = '1' then
                            alert(ERROR, Name_g & ": beat after the end of the packet before the release of DpRst");
                        end if;
                        if DpRst = '0' then
                            State_v := Normal_s;
                        end if;

                end case;

                -- End of the packet that was open at the reset edge
                if Ended_v then
                    if Rel_v then
                        St_v.Link(LinkAfterRel_c) := St_v.Link(LinkAfterRel_c) + 1;
                    end if;
                    if DpRst = '1' then
                        State_v := Quiet_s;
                    else
                        State_v := Normal_s;
                    end if;
                end if;

                -- The core left the reset while the end of the packet is pending
                if DpRst = '0' and (State_v = WaitPend_s or State_v = ExpEep_s) then
                    Rel_v := true;
                end if;
            end if;

            PValid_v := Valid;
            PHs_v    := Hs_v;
            PData_v  := Data;
            PKeep_v  := Keep;
            PLast_v  := Last;
            PUser_v  := User;
            RstS_v   := Rst = '1';
            PktBeats <= Pkt_v;
            Stat     <= St_v;
        end if;
    end process;

end architecture;
