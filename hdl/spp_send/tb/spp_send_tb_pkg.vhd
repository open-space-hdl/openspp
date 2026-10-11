---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Constants, types and stimulus procedures of the testbench of the sending end.
--
-- Documentation: hdl/spp_send/docs/verification_plan.md

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
package spp_send_tb_pkg is

    constant ClkPeriod_c : time    := 10 ns;
    constant ChSink_c    : natural := 16;   -- sink; expected packets of port p in channel ChSink_c + p

    -- Access of the register file to the send APID table
    type TblReq_t is record
        Valid  : std_logic;
        Apid   : std_logic_vector(10 downto 0);
        WrEna  : std_logic;
        WrData : std_logic_vector(TxEntryWidth_c - 1 downto 0);
        Done   : std_logic;
    end record;

    constant TblReqIdle_c : TblReq_t := ('0', (others => '0'), '0', (others => '0'), '0');

    type TblRsp_t is record
        Ready   : std_logic;
        RdValid : std_logic;
        RdData  : std_logic_vector(TxEntryWidth_c - 1 downto 0);
        RdDed   : std_logic;
        Busy    : std_logic;
    end record;

    -- Error events counted per code, the last event
    type NatArray_t is array (natural range <>) of natural;

    type ErrLog_t is record
        Count : NatArray_t(0 to 31);
        Last  : ErrEvent_t;
        Total : natural;
    end record;

    -- Entry of the send APID table
    function txEntry (
        enable : natural;
        dest   : natural;
        count  : natural) return std_logic_vector;

    -- Octet String on send port p: the expected Space Packet carries the header built by the packet model
    procedure sendOctet (
        p         : natural;
        apid      : natural;
        data      : TbBytes_t;
        count     : natural;
        dest      : natural := 0;
        shi       : natural := 0;
        pktType   : natural := 0;
        nameValid : natural := 0;
        name      : natural := 0);

    -- Space Packet on send port p, expected intact
    procedure sendPacket (
        p    : natural;
        pkt  : TbBytes_t;
        dest : natural := 0);

    -- SDU on send port p that is rejected (no expected packet)
    procedure sendRejected (
        p    : natural;
        data : TbBytes_t;
        user : std_logic_vector(TxUserWidth_c - 1 downto 0));

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body spp_send_tb_pkg is

    function txEntry (
        enable : natural;
        dest   : natural;
        count  : natural) return std_logic_vector is
        variable E_v : std_logic_vector(TxEntryWidth_c - 1 downto 0);
    begin
        E_v(13 downto 0)  := std_logic_vector(to_unsigned(count, 14));
        E_v(17 downto 14) := std_logic_vector(to_unsigned(dest, 4));
        E_v(18)           := '1' when enable = 1 else '0';
        return E_v;
    end function;

    procedure sendOctet (
        p         : natural;
        apid      : natural;
        data      : TbBytes_t;
        count     : natural;
        dest      : natural := 0;
        shi       : natural := 0;
        pktType   : natural := 0;
        nameValid : natural := 0;
        name      : natural := 0) is
        variable Field_v : natural;
    begin
        if pktType = 1 and nameValid = 1 then
            Field_v := name;
        else
            Field_v := count;
        end if;
        tbPush(p, data, tbTxUser(apid, shi, pktType, nameValid, name));
        tbPush(ChSink_c + p, tbSpacePacket(pktType, shi, apid, 3, Field_v, data), tbLinkUser(0, dest));
    end procedure;

    procedure sendPacket (
        p    : natural;
        pkt  : TbBytes_t;
        dest : natural := 0) is
    begin
        tbPush(p, pkt, tbTxUser(0));
        tbPush(ChSink_c + p, pkt, tbLinkUser(0, dest));
    end procedure;

    procedure sendRejected (
        p    : natural;
        data : TbBytes_t;
        user : std_logic_vector(TxUserWidth_c - 1 downto 0)) is
    begin
        tbPush(p, data, user);
    end procedure;

end package body;
