---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Packet store of the stream models of the testbenches: one queue of packets per channel. A stream
-- source sends the packets of its channel, a stream sink compares every received packet with the
-- next packet of its channel. Packets have any length; TUser is constant during a packet except on
-- the last beat.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package spp_tb_stream_pkg is

    constant TbUserBits_c : natural := 256;
    constant TbChannels_c : natural := 128;

    subtype TbUser_t is std_logic_vector(TbUserBits_c - 1 downto 0);

    -- Bytes of a packet, first byte at the lowest index
    type TbBytes_t is array (natural range <>) of std_logic_vector(7 downto 0);

    -- Zero-extends a user value to TbUser_t
    function tbUser (user : std_logic_vector) return TbUser_t;

    type PacketStore_t is protected

        -- Queue of a channel
        procedure push (
            ch       : natural;
            data     : TbBytes_t;
            user     : std_logic_vector;
            userLast : std_logic_vector);

        procedure push (
            ch   : natural;
            data : TbBytes_t;
            user : std_logic_vector);
        impure function count (ch : natural) return natural;
        impure function headLength (ch : natural) return natural;
        impure function headByte (
            ch  : natural;
            idx : natural) return std_logic_vector;
        impure function headUser (ch : natural) return TbUser_t;
        impure function headUserLast (ch : natural) return TbUser_t;

        procedure pop (ch : natural);

        procedure clear (ch : natural);

        -- Behaviour of the source or sink of a channel
        procedure setStall (
            ch   : natural;
            prob : real);
        impure function getStall (ch : natural) return real;

        -- Source: every packet ends with an additional last beat without byte enables (AXI4-Stream null bytes); a
        -- packet without bytes is then one such beat
        procedure setNullTail (
            ch     : natural;
            enable : boolean);
        impure function getNullTail (ch : natural) return boolean;

        procedure setUserMask (
            ch   : natural;
            mask : std_logic_vector);
        impure function getUserMask (ch : natural) return TbUser_t;

        -- Statistics: packets and bytes transferred, time of the first and the last beat
        procedure clearStats (ch : natural);

        procedure addBeat (
            ch    : natural;
            bytes : natural;
            t     : time);

        procedure addPacket (ch : natural);
        impure function packets (ch : natural) return natural;
        impure function bytes (ch : natural) return natural;
        impure function firstTime (ch : natural) return time;
        impure function lastTime (ch : natural) return time;

        -- Match mode of a sink: a received packet is compared with the head of the first of queues channels
        -- (ch to ch + queues - 1) whose bytes offset to offset + bytes - 1 equal the received ones; queues = 1
        -- compares every packet with the head of channel ch (default)
        procedure setMatch (
            ch     : natural;
            queues : positive;
            offset : natural;
            bytes  : natural);
        impure function matchQueues (ch : natural) return positive;
        impure function matchOffset (ch : natural) return natural;
        impure function matchBytes (ch : natural) return natural;

        -- Abort of the packet in transfer (reset tests): the source drops its current packet, the sink
        -- discards the bytes received so far
        procedure setAbort (ch : natural);
        impure function getAbort (ch : natural) return boolean;

        procedure clearAbort (ch : natural);

    end protected;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body spp_tb_stream_pkg is

    function tbUser (user : std_logic_vector) return TbUser_t is
        variable U_v : TbUser_t := (others => '0');
    begin
        U_v(user'length - 1 downto 0) := user;
        return U_v;
    end function;

    type DataPtr_t is access TbBytes_t;

    type Packet_t;

    type PacketPtr_t is access Packet_t;

    type Packet_t is record
        Data     : DataPtr_t;
        User     : TbUser_t;
        UserLast : TbUser_t;
        NextPkt  : PacketPtr_t;
    end record;

    type PacketStore_t is protected body

        type PtrArray_t is array (0 to TbChannels_c - 1) of PacketPtr_t;

        type NatArray_t is array (0 to TbChannels_c - 1) of natural;

        type RealArray_t is array (0 to TbChannels_c - 1) of real;

        type TimeArray_t is array (0 to TbChannels_c - 1) of time;

        type UserArray_t is array (0 to TbChannels_c - 1) of TbUser_t;

        type BoolArray_t is array (0 to TbChannels_c - 1) of boolean;

        variable Head_v    : PtrArray_t;
        variable Tail_v    : PtrArray_t;
        variable Count_v   : NatArray_t  := (others => 0);
        variable Stall_v   : RealArray_t := (others => 0.0);
        variable Mask_v    : UserArray_t := (others => (others => '1'));
        variable Packets_v : NatArray_t  := (others => 0);
        variable Bytes_v   : NatArray_t  := (others => 0);
        variable First_v   : TimeArray_t := (others => 0 ns);
        variable Last_v    : TimeArray_t := (others => 0 ns);
        variable Abort_v   : BoolArray_t := (others => false);
        variable NullTl_v  : BoolArray_t := (others => false);
        variable MQueues_v : NatArray_t  := (others => 1);
        variable MOffset_v : NatArray_t  := (others => 0);
        variable MBytes_v  : NatArray_t  := (others => 0);

        procedure push (
            ch       : natural;
            data     : TbBytes_t;
            user     : std_logic_vector;
            userLast : std_logic_vector) is
            variable P_v : PacketPtr_t;
        begin
            P_v          := new Packet_t;
            P_v.Data     := new TbBytes_t(0 to data'length - 1);
            P_v.Data.all := data;
            P_v.User     := tbUser(user);
            P_v.UserLast := tbUser(userLast);
            P_v.NextPkt  := null;
            if Head_v(ch) = null then
                Head_v(ch) := P_v;
            else
                Tail_v(ch).NextPkt := P_v;
            end if;
            Tail_v(ch)  := P_v;
            Count_v(ch) := Count_v(ch) + 1;
        end procedure;

        procedure push (
            ch   : natural;
            data : TbBytes_t;
            user : std_logic_vector) is
        begin
            push(ch, data, user, user);
        end procedure;

        impure function count (ch : natural) return natural is
        begin
            return Count_v(ch);
        end function;

        impure function headLength (ch : natural) return natural is
        begin
            return Head_v(ch).Data'length;
        end function;

        impure function headByte (
            ch  : natural;
            idx : natural) return std_logic_vector is
        begin
            return Head_v(ch).Data(idx);
        end function;

        impure function headUser (ch : natural) return TbUser_t is
        begin
            return Head_v(ch).User;
        end function;

        impure function headUserLast (ch : natural) return TbUser_t is
        begin
            return Head_v(ch).UserLast;
        end function;

        procedure pop (ch : natural) is
            variable P_v : PacketPtr_t;
        begin
            if Head_v(ch) /= null then
                P_v        := Head_v(ch);
                Head_v(ch) := P_v.NextPkt;
                if Head_v(ch) = null then
                    Tail_v(ch) := null;
                end if;
                deallocate(P_v.Data);
                deallocate(P_v);
                Count_v(ch) := Count_v(ch) - 1;
            end if;
        end procedure;

        procedure clear (ch : natural) is
        begin

            while Head_v(ch) /= null loop
                pop(ch);
            end loop;

        end procedure;

        procedure setStall (
            ch   : natural;
            prob : real) is
        begin
            Stall_v(ch) := prob;
        end procedure;

        impure function getStall (ch : natural) return real is
        begin
            return Stall_v(ch);
        end function;

        procedure setNullTail (
            ch     : natural;
            enable : boolean) is
        begin
            NullTl_v(ch) := enable;
        end procedure;

        impure function getNullTail (ch : natural) return boolean is
        begin
            return NullTl_v(ch);
        end function;

        procedure setUserMask (
            ch   : natural;
            mask : std_logic_vector) is
        begin
            Mask_v(ch) := tbUser(mask);
        end procedure;

        impure function getUserMask (ch : natural) return TbUser_t is
        begin
            return Mask_v(ch);
        end function;

        procedure clearStats (ch : natural) is
        begin
            Packets_v(ch) := 0;
            Bytes_v(ch)   := 0;
            First_v(ch)   := 0 ns;
            Last_v(ch)    := 0 ns;
        end procedure;

        procedure addBeat (
            ch    : natural;
            bytes : natural;
            t     : time) is
        begin
            if Bytes_v(ch) = 0 and Packets_v(ch) = 0 then
                First_v(ch) := t;
            end if;
            Bytes_v(ch) := Bytes_v(ch) + bytes;
            Last_v(ch)  := t;
        end procedure;

        procedure addPacket (ch : natural) is
        begin
            Packets_v(ch) := Packets_v(ch) + 1;
        end procedure;

        impure function packets (ch : natural) return natural is
        begin
            return Packets_v(ch);
        end function;

        impure function bytes (ch : natural) return natural is
        begin
            return Bytes_v(ch);
        end function;

        impure function firstTime (ch : natural) return time is
        begin
            return First_v(ch);
        end function;

        impure function lastTime (ch : natural) return time is
        begin
            return Last_v(ch);
        end function;

        procedure setMatch (
            ch     : natural;
            queues : positive;
            offset : natural;
            bytes  : natural) is
        begin
            MQueues_v(ch) := queues;
            MOffset_v(ch) := offset;
            MBytes_v(ch)  := bytes;
        end procedure;

        impure function matchQueues (ch : natural) return positive is
        begin
            return MQueues_v(ch);
        end function;

        impure function matchOffset (ch : natural) return natural is
        begin
            return MOffset_v(ch);
        end function;

        impure function matchBytes (ch : natural) return natural is
        begin
            return MBytes_v(ch);
        end function;

        procedure setAbort (ch : natural) is
        begin
            Abort_v(ch) := true;
        end procedure;

        impure function getAbort (ch : natural) return boolean is
        begin
            return Abort_v(ch);
        end function;

        procedure clearAbort (ch : natural) is
        begin
            Abort_v(ch) := false;
        end procedure;

    end protected body;

end package body;
