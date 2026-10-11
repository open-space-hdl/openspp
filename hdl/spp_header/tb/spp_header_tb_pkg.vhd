---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Constants and stimulus procedures of the testbench of the header insertion and removal.
--
-- Documentation: hdl/spp_header/docs/verification_plan.md

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
    use work.spp_tb_packet_pkg.all;
    use work.spp_tb_streamvar_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package spp_header_tb_pkg is

    constant ClkPeriod_c       : time    := 10 ns;
    constant MaxHdr_c          : natural := 20;
    constant HdrLenBits_c      : natural := 5;
    constant UserBits_c        : natural := 4;
    constant InsSrcUserWidth_c : natural := UserBits_c + HdrLenBits_c + 8 * MaxHdr_c;
    constant RemSrcUserWidth_c : natural := UserBits_c + HdrLenBits_c;
    constant RemSnkUserWidth_c : natural := UserBits_c + 8 * MaxHdr_c + 1;

    constant ChInsSrc_c : natural := 0;
    constant ChInsSnk_c : natural := 1;
    constant ChRemSrc_c : natural := 2;
    constant ChRemSnk_c : natural := 3;

    -- Packet of len bytes through the insertion with a header of hdrLen bytes; the expected output is
    -- the header followed by the packet
    procedure insertPacket (
        len    : natural;
        hdrLen : natural;
        seed   : natural;
        user   : natural := 5);

    -- Packet of len bytes through the removal of rem bytes; the expected output is the packet without
    -- the first rem bytes (empty when it has no more bytes), the removed bytes and the empty flag
    procedure removePacket (
        len    : natural;
        remove : natural;
        seed   : natural;
        user   : natural := 9);

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body spp_header_tb_pkg is

    function bytesToSlv (
        a     : TbBytes_t;
        bytes : natural) return std_logic_vector is
        variable V_v : std_logic_vector(8 * bytes - 1 downto 0) := (others => '0');
    begin

        for i in 0 to a'length - 1 loop
            if i < bytes then
                V_v(8 * i + 7 downto 8 * i) := a(a'low + i);
            end if;
        end loop;

        return V_v;
    end function;

    procedure insertPacket (
        len    : natural;
        hdrLen : natural;
        seed   : natural;
        user   : natural := 5) is
        constant Data_c : TbBytes_t                                 := tbPayload(len, seed);
        constant Hdr_c  : TbBytes_t                                 := tbPayload(hdrLen, seed + 7919);
        constant User_c : std_logic_vector(UserBits_c - 1 downto 0) := std_logic_vector(to_unsigned(user, UserBits_c));
    begin
        tbPush(ChInsSrc_c, Data_c,
               bytesToSlv(Hdr_c, MaxHdr_c) & std_logic_vector(to_unsigned(hdrLen, HdrLenBits_c)) & User_c);
        tbPush(ChInsSnk_c, tbCat(Hdr_c, Data_c), User_c);
    end procedure;

    procedure removePacket (
        len    : natural;
        remove : natural;
        seed   : natural;
        user   : natural := 9) is
        constant Data_c : TbBytes_t                                 := tbPayload(len, seed);
        constant User_c : std_logic_vector(UserBits_c - 1 downto 0) := std_logic_vector(to_unsigned(user, UserBits_c));
        variable Hdr_v  : std_logic_vector(8 * MaxHdr_c - 1 downto 0);
    begin
        tbPush(ChRemSrc_c, Data_c, std_logic_vector(to_unsigned(remove, HdrLenBits_c)) & User_c);
        if len > remove then
            Hdr_v := bytesToSlv(tbSlice(Data_c, 0, remove - 1), MaxHdr_c);
            tbPush(ChRemSnk_c, tbSlice(Data_c, remove, len - 1), '0' & Hdr_v & User_c);
        else
            Hdr_v := bytesToSlv(Data_c, MaxHdr_c);
            tbPush(ChRemSnk_c, TbNoBytes_c, '1' & Hdr_v & User_c);
        end if;
    end procedure;

end package body;
