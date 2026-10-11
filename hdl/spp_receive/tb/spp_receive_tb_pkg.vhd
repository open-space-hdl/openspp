---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Constants, types and stimulus procedures of the testbench of the receiving end.
--
-- Documentation: hdl/spp_receive/docs/verification_plan.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library uvvm_util;
    context uvvm_util.uvvm_util_context;

library work;
    use work.spp_pkg.all;
    use work.spp_tb_stream_pkg.all;
    use work.spp_tb_streamvar_pkg.all;
    use work.spp_tb_packet_pkg.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package spp_receive_tb_pkg is

    constant ClkPeriod_c : time    := 10 ns;
    constant ChSrc_c     : natural := 0;  -- received Space Packets
    constant ChPort_c    : natural := 16; -- indications of user port p in channel ChPort_c + p

    -- Access of the register file to the receive APID table
    type TblReq_t is record
        Valid  : std_logic;
        Apid   : std_logic_vector(10 downto 0);
        WrEna  : std_logic;
        WrData : std_logic_vector(RxEntryWidth_c - 1 downto 0);
        Done   : std_logic;
    end record;

    constant TblReqIdle_c : TblReq_t := ('0', (others => '0'), '0', (others => '0'), '0');

    type TblRsp_t is record
        Ready   : std_logic;
        RdValid : std_logic;
        RdData  : std_logic_vector(RxEntryWidth_c - 1 downto 0);
        RdDed   : std_logic;
        Busy    : std_logic;
    end record;

    type NatArray_t is array (natural range <>) of natural;

    type ErrLog_t is record
        Count : NatArray_t(0 to 31);
        Last  : ErrEvent_t;
        Total : natural;
    end record;

    -- Entry of the receive APID table
    function rxEntry (
        enable : natural;
        port_i : natural;
        check  : natural := 0;
        valid  : natural := 0;
        last   : natural := 0) return std_logic_vector;

    -- A received Space Packet with its User Application value, terminated by an EOP or an EEP
    procedure receive (
        pkt : TbBytes_t;
        ua  : natural := 0;
        eep : natural := 0);

    -- Expected indication on user port p: the Octet String (Packet Data Field) or the Space Packet intact
    procedure expect (
        p     : natural;
        octet : boolean;
        pkt   : TbBytes_t;
        ua    : natural := 0;
        loss  : natural := 0;
        err   : natural := 0);

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body spp_receive_tb_pkg is

    function rxEntry (
        enable : natural;
        port_i : natural;
        check  : natural := 0;
        valid  : natural := 0;
        last   : natural := 0) return std_logic_vector is
        variable E_v : std_logic_vector(RxEntryWidth_c - 1 downto 0);
    begin
        E_v(13 downto 0)  := std_logic_vector(to_unsigned(last, 14));
        E_v(14)           := '1' when valid = 1 else '0';
        E_v(15)           := '1' when check = 1 else '0';
        E_v(19 downto 16) := std_logic_vector(to_unsigned(port_i, 4));
        E_v(20)           := '1' when enable = 1 else '0';
        return E_v;
    end function;

    procedure receive (
        pkt : TbBytes_t;
        ua  : natural := 0;
        eep : natural := 0) is
        constant Ua_c : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(ua, 8));
    begin
        if eep = 1 then
            tbPush(ChSrc_c, pkt, Ua_c & '0', Ua_c & '1');
        else
            tbPush(ChSrc_c, pkt, Ua_c & '0', Ua_c & '0');
        end if;
    end procedure;

    procedure expect (
        p     : natural;
        octet : boolean;
        pkt   : TbBytes_t;
        ua    : natural := 0;
        loss  : natural := 0;
        err   : natural := 0) is
        -- Fields of the header of the packet, as the testbench reads them
        constant Hi_c   : std_logic_vector(2 downto 0) := pkt(pkt'low)(2 downto 0);
        constant Lo_c   : std_logic_vector(7 downto 0) := pkt(pkt'low + 1);
        constant Apid_c : natural                      := to_integer(unsigned(std_logic_vector'(Hi_c & Lo_c)));
        constant Shf_c  : natural                      := to_integer(unsigned(std_logic_vector'('0', pkt(pkt'low)(3))));
    begin
        if octet then
            tbPush(ChPort_c + p, tbSlice(pkt, 6, pkt'length - 1), tbRxUser(Apid_c, Shf_c, loss, 0, ua),
                   tbRxUser(Apid_c, Shf_c, loss, err, ua));
        else
            tbPush(ChPort_c + p, pkt, tbRxUser(Apid_c, Shf_c, loss, 0, ua), tbRxUser(Apid_c, Shf_c, loss, err, ua));
        end if;
    end procedure;

end package body;
