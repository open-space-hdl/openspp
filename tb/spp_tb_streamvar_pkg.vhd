---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- The packet store shared by the stream models and the test sequencers, and the procedures of the
-- test sequencers that use it. The shared variable is declared in a package of its own, after the
-- body of its protected type.
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

library work;
    use work.spp_tb_stream_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package spp_tb_streamvar_pkg is

    shared variable SppTbStore_v : PacketStore_t;

    -- Queues a packet for the source of channel ch or as the expected packet of the sink of channel ch
    procedure tbPush (
        ch       : natural;
        data     : TbBytes_t;
        user     : std_logic_vector;
        userLast : std_logic_vector);

    procedure tbPush (
        ch   : natural;
        data : TbBytes_t;
        user : std_logic_vector := "0");

    -- Waits until the queue of channel ch is empty (all packets sent or received); alert on timeout
    procedure tbWaitEmpty (
        ch      : natural;
        timeout : time;
        msg     : string := "");

    -- Checks that the queue of channel ch is empty and that no further packet arrives within quiet
    procedure tbCheckEmpty (
        ch  : natural;
        msg : string := "");

    -- Probability of a cycle without valid (source) or ready (sink) on channel ch
    procedure tbSetStall (
        ch   : natural;
        prob : real);

    -- Source of channel ch: every packet ends with an additional last beat without byte enables
    procedure tbSetNullTail (
        ch     : natural;
        enable : boolean);

    -- Bits of TUser compared by the sink of channel ch
    procedure tbSetUserMask (
        ch   : natural;
        mask : std_logic_vector);

    -- Match mode of the sink of channel ch: expected packets in the queues ch to ch + queues - 1, selected
    -- by the bytes offset to offset + bytes - 1 (see spp_tb_stream_sink)
    procedure tbSetMatch (
        ch     : natural;
        queues : positive;
        offset : natural;
        bytes  : natural);

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body spp_tb_streamvar_pkg is

    procedure tbPush (
        ch       : natural;
        data     : TbBytes_t;
        user     : std_logic_vector;
        userLast : std_logic_vector) is
    begin
        SppTbStore_v.push(ch, data, user, userLast);
    end procedure;

    procedure tbPush (
        ch   : natural;
        data : TbBytes_t;
        user : std_logic_vector := "0") is
    begin
        SppTbStore_v.push(ch, data, user, user);
    end procedure;

    procedure tbWaitEmpty (
        ch      : natural;
        timeout : time;
        msg     : string := "") is
        variable End_v : time;
    begin
        End_v := now + timeout;

        while SppTbStore_v.count(ch) > 0 and now < End_v loop
            wait for 10 ns;
        end loop;

        if SppTbStore_v.count(ch) > 0 then
            alert(ERROR, "channel " & to_string(ch) & ": " & to_string(SppTbStore_v.count(ch)) &
                  " packets left after " & to_string(timeout) & " " & msg);
            SppTbStore_v.clear(ch);
        end if;
    end procedure;

    procedure tbCheckEmpty (
        ch  : natural;
        msg : string := "") is
    begin
        check_value(SppTbStore_v.count(ch), 0, ERROR, "channel " & to_string(ch) & " empty " & msg);
        SppTbStore_v.clear(ch);
    end procedure;

    procedure tbSetStall (
        ch   : natural;
        prob : real) is
    begin
        SppTbStore_v.setStall(ch, prob);
    end procedure;

    procedure tbSetNullTail (
        ch     : natural;
        enable : boolean) is
    begin
        SppTbStore_v.setNullTail(ch, enable);
    end procedure;

    procedure tbSetUserMask (
        ch   : natural;
        mask : std_logic_vector) is
    begin
        SppTbStore_v.setUserMask(ch, mask);
    end procedure;

    procedure tbSetMatch (
        ch     : natural;
        queues : positive;
        offset : natural;
        bytes  : natural) is
    begin
        SppTbStore_v.setMatch(ch, queues, offset, bytes);
    end procedure;

end package body;
