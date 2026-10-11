---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Stream sink model: receives an AXI4-Stream with byte enables with random cycles without ready and
-- compares every packet byte by byte with the next expected packet of its channel of the packet
-- store, TUser on every beat (masked) and the byte enables (all set except in the last beat, which
-- is contiguous from lane 0). In match mode the expected packet is the head of the first of several
-- queues whose bytes at a given position equal the received ones, so that packets of several sources
-- that arrive in any order are each checked in the order of their source. Mismatches raise UVVM
-- alerts of level ERROR.
--
-- What this model does NOT check or reproduce: a beat with all byte enables clear is accepted only
-- as the single beat of an expected packet of length 0; it does not check that valid stays asserted
-- until the handshake.
--
-- Documentation: docs/conventions.md (section Verification)

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.spp_tb_stream_pkg.all;
    use work.spp_tb_streamvar_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_tb_stream_sink is
    generic (
        Channel_g   : natural;
        DataWidth_g : positive;
        UserWidth_g : positive := 1;
        Name_g      : string   := "sink"
    );
    port (
        Clk      : in    std_logic;
        In_Valid : in    std_logic;
        In_Ready : out   std_logic;
        In_Data  : in    std_logic_vector(DataWidth_g - 1 downto 0);
        In_Keep  : in    std_logic_vector(DataWidth_g / 8 - 1 downto 0);
        In_Last  : in    std_logic;
        In_User  : in    std_logic_vector(UserWidth_g - 1 downto 0) := (others => '0')
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_tb_stream_sink is

    constant Bytes_c   : positive := DataWidth_g / 8;
    constant PendMax_c : positive := 256;

    type ByteArrayPtr_t is access TbBytes_t;

    type UserArray_t is array (0 to PendMax_c - 1) of TbUser_t;

begin

    p_sink : process is
        variable Seed1_v  : positive       := 33 + Channel_g;
        variable Seed2_v  : positive       := 977 + 5 * Channel_g;
        variable Rand_v   : real;
        variable Buf_v    : ByteArrayPtr_t := new TbBytes_t(0 to 131071);
        variable Len_v    : natural        := 0;
        variable N_v      : natural;
        variable Gap_v    : boolean;
        variable Mism_v   : natural;
        variable First_v  : integer;
        variable ExpLen_v : natural;
        -- Channel of the expected packet (-1 while unknown), TUser of the beats received before it is known
        variable Sel_v    : integer := -1;
        variable Pend_v   : UserArray_t;
        variable PLast_v  : boolean;
        variable NPend_v  : natural := 0;
        variable Ok_v     : boolean;
        variable MOff_v   : natural;
        variable MLen_v   : natural;

        -- TUser of a beat against the expected packet of channel ch
        procedure checkUser (
            ch   : natural;
            user : TbUser_t;
            last : boolean;
            pos  : natural) is
            variable Exp_v  : TbUser_t;
            variable Mask_v : TbUser_t;
        begin
            Mask_v := SppTbStore_v.getUserMask(Channel_g);
            if last then
                Exp_v := SppTbStore_v.headUserLast(ch);
            else
                Exp_v := SppTbStore_v.headUser(ch);
            end if;
            if (user and Mask_v) /= (Exp_v and Mask_v) then
                alert(ERROR, Name_g & ": TUser 0x" & to_hstring(user(UserWidth_g - 1 downto 0)) &
                      ", expected 0x" & to_hstring(Exp_v(UserWidth_g - 1 downto 0)) & " at byte " & to_string(pos));
            end if;
        end procedure;

    -- Reception
    begin
        In_Ready <= '0';

        loop
            wait until rising_edge(Clk);

            -- Reset tests: the bytes received so far are discarded
            if SppTbStore_v.getAbort(Channel_g) then
                SppTbStore_v.clearAbort(Channel_g);
                Len_v   := 0;
                Sel_v   := -1;
                NPend_v := 0;
            end if;

            if In_Valid = '1' and In_Ready = '1' then
                -- Byte enables: all set except in the last beat, contiguous from lane 0
                N_v   := 0;
                Gap_v := false;

                for i in 0 to Bytes_c - 1 loop
                    if In_Keep(i) = '1' then
                        if Gap_v then
                            alert(ERROR, Name_g & ": byte enables not contiguous: " & to_string(In_Keep));
                        end if;
                        Buf_v(Len_v + N_v) := In_Data(8 * i + 7 downto 8 * i);
                        N_v                := N_v + 1;
                    else
                        Gap_v := true;
                    end if;
                end loop;

                if In_Last = '0' and N_v /= Bytes_c then
                    alert(ERROR, Name_g & ": byte enables of a beat that is not the last: " & to_string(In_Keep));
                end if;
                if N_v = 0 and Len_v > 0 then
                    alert(ERROR, Name_g & ": last beat without bytes after " & to_string(Len_v) & " bytes");
                end if;

                SppTbStore_v.addBeat(Channel_g, N_v, now);
                PLast_v := In_Last = '1';
                Len_v   := Len_v + N_v;

                -- Channel of the expected packet
                if Sel_v < 0 then
                    if SppTbStore_v.matchQueues(Channel_g) = 1 then
                        if SppTbStore_v.count(Channel_g) > 0 then
                            Sel_v := Channel_g;
                        end if;
                    else
                        MOff_v := SppTbStore_v.matchOffset(Channel_g);
                        MLen_v := SppTbStore_v.matchBytes(Channel_g);
                        if Len_v >= MOff_v + MLen_v then

                            for q in Channel_g to Channel_g + SppTbStore_v.matchQueues(Channel_g) - 1 loop
                                if Sel_v < 0 and SppTbStore_v.count(q) > 0 then
                                    Ok_v := SppTbStore_v.headLength(q) >= MOff_v + MLen_v;

                                    for i in MOff_v to MOff_v + MLen_v - 1 loop
                                        if Ok_v then
                                            Ok_v := Buf_v(i) = SppTbStore_v.headByte(q, i);
                                        end if;
                                    end loop;

                                    if Ok_v then
                                        Sel_v := q;
                                    end if;
                                end if;
                            end loop;

                        end if;
                    end if;

                    -- TUser of the beats so far
                    if Sel_v >= 0 then

                        for b in 0 to NPend_v - 1 loop
                            checkUser(Sel_v, Pend_v(b), false, b * Bytes_c);
                        end loop;

                        NPend_v := 0;
                        checkUser(Sel_v, tbUser(In_User), PLast_v, Len_v - N_v);
                    elsif NPend_v < PendMax_c then
                        Pend_v(NPend_v) := tbUser(In_User);
                        NPend_v         := NPend_v + 1;
                    end if;
                else
                    checkUser(Sel_v, tbUser(In_User), PLast_v, Len_v - N_v);
                end if;

                if PLast_v then
                    if Sel_v < 0 then
                        alert(ERROR, Name_g & ": unexpected packet of " & to_string(Len_v) & " bytes");
                    else
                        ExpLen_v := SppTbStore_v.headLength(Sel_v);
                        Mism_v   := 0;
                        First_v  := -1;

                        for i in 0 to minimum(Len_v, ExpLen_v) - 1 loop
                            if Buf_v(i) /= SppTbStore_v.headByte(Sel_v, i) then
                                Mism_v := Mism_v + 1;
                                if First_v < 0 then
                                    First_v := i;
                                end if;
                            end if;
                        end loop;

                        check_value(Len_v, ExpLen_v, ERROR, Name_g & ": packet length");
                        if Mism_v > 0 then
                            alert(ERROR, Name_g & ": " & to_string(Mism_v) & " byte mismatches, first at byte " &
                                  to_string(First_v) & " (0x" & to_hstring(Buf_v(First_v)) & ", expected 0x" &
                                  to_hstring(SppTbStore_v.headByte(Sel_v, First_v)) & ")");
                        end if;
                        log(ID_PACKET_COMPLETE, Name_g & ": packet of " & to_string(Len_v) & " bytes received");
                        SppTbStore_v.pop(Sel_v);
                    end if;
                    SppTbStore_v.addPacket(Channel_g);
                    Len_v   := 0;
                    Sel_v   := -1;
                    NPend_v := 0;
                end if;
            end if;

            -- Random cycles without ready
            uniform(Seed1_v, Seed2_v, Rand_v);
            if Rand_v >= SppTbStore_v.getStall(Channel_g) then
                In_Ready <= '1';
            else
                In_Ready <= '0';
            end if;
        end loop;

    end process;

end architecture;
