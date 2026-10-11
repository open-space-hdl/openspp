---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Packet model of the testbenches: builds Space Packets (CCSDS 133.0-B-2 section 4.1), CPTP packets
-- (ECSS-E-ST-50-53C clause 5.4) and the TUser values of the ports. It is written from the standards
-- independently of the RTL: the Packet Primary Header is assembled bit by bit in transmission order
-- (bit 0 first, SPP 1.6.3) and then cut into octets.
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
package spp_tb_packet_pkg is

    constant TbNoBytes_c : TbBytes_t(0 to -1) := (others => (others => '0'));

    -- n bytes, pseudo-random and deterministic from seed
    function tbPayload (
        n    : natural;
        seed : natural) return TbBytes_t;

    -- n bytes with the values (first + i) mod 256
    function tbCount (
        n     : natural;
        first : natural := 0) return TbBytes_t;

    -- Concatenation of two byte arrays
    function tbCat (
        a : TbBytes_t;
        b : TbBytes_t) return TbBytes_t;

    -- Bytes from..to of a byte array (positions counted from 0)
    function tbSlice (
        a    : TbBytes_t;
        from : natural;
        to_i : integer) return TbBytes_t;

    -- Packet Primary Header (SPP 4.1.3) with all fields given explicitly
    function tbPrimaryHeader (
        version : natural;
        pktType : natural;
        shf     : natural;
        apid    : natural;
        flags   : natural;
        count   : natural;
        pdl     : natural) return TbBytes_t;

    -- Space Packet: primary header followed by the Packet Data Field data, PDL = data'length - 1
    function tbSpacePacket (
        pktType : natural;
        shf     : natural;
        apid    : natural;
        flags   : natural;
        count   : natural;
        data    : TbBytes_t) return TbBytes_t;

    -- CPTP packet (CPTP 5.4.1.1): Target SpaceWire Address, Target Logical Address, Protocol Identifier,
    -- Reserved, User Application and the Space Packet
    function tbCptp (
        addr     : TbBytes_t;
        tla      : natural;
        ua       : natural;
        pkt      : TbBytes_t;
        pid      : natural := 2;
        reserved : natural := 0) return TbBytes_t;

    -- TUser of a send port (28 bits): APID 10:0, SHI 11, Packet Type 12, Packet Name valid 13, Packet Name 27:14
    function tbTxUser (
        apid      : natural;
        shi       : natural := 0;
        pktType   : natural := 0;
        nameValid : natural := 0;
        name      : natural := 0) return std_logic_vector;

    -- TUser of a receive port (22 bits): APID 10:0, SHI 11, loss 12, error 13, User Application 21:14
    function tbRxUser (
        apid : natural;
        shi  : natural := 0;
        loss : natural := 0;
        err  : natural := 0;
        ua   : natural := 0) return std_logic_vector;

    -- TUser of a link port (5 bits): EEP 0, destination 4:1
    function tbLinkUser (
        eep  : natural;
        dest : natural := 0) return std_logic_vector;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body spp_tb_packet_pkg is

    function tbPayload (
        n    : natural;
        seed : natural) return TbBytes_t is
        variable A_v : TbBytes_t(0 to n - 1);
        variable X_v : unsigned(31 downto 0);
    begin
        X_v := to_unsigned(seed, 32) xor x"9E3779B9";

        for i in 0 to n - 1 loop
            -- xorshift32
            X_v    := X_v xor shift_left(X_v, 13);
            X_v    := X_v xor shift_right(X_v, 17);
            X_v    := X_v xor shift_left(X_v, 5);
            A_v(i) := std_logic_vector(X_v(7 downto 0));
        end loop;

        return A_v;
    end function;

    function tbCount (
        n     : natural;
        first : natural := 0) return TbBytes_t is
        variable A_v : TbBytes_t(0 to n - 1);
    begin

        for i in 0 to n - 1 loop
            A_v(i) := std_logic_vector(to_unsigned((first + i) mod 256, 8));
        end loop;

        return A_v;
    end function;

    function tbCat (
        a : TbBytes_t;
        b : TbBytes_t) return TbBytes_t is
        variable C_v : TbBytes_t(0 to a'length + b'length - 1);
    begin

        for i in 0 to a'length - 1 loop
            C_v(i) := a(a'low + i);
        end loop;

        for i in 0 to b'length - 1 loop
            C_v(a'length + i) := b(b'low + i);
        end loop;

        return C_v;
    end function;

    function tbSlice (
        a    : TbBytes_t;
        from : natural;
        to_i : integer) return TbBytes_t is
        variable S_v : TbBytes_t(0 to to_i - from);
    begin

        for i in 0 to to_i - from loop
            S_v(i) := a(a'low + from + i);
        end loop;

        return S_v;
    end function;

    function tbPrimaryHeader (
        version : natural;
        pktType : natural;
        shf     : natural;
        apid    : natural;
        flags   : natural;
        count   : natural;
        pdl     : natural) return TbBytes_t is
        -- Bit 0 is the first transmitted bit (most significant bit of the first octet)
        variable Bits_v : std_logic_vector(0 to 47);
        variable Hdr_v  : TbBytes_t(0 to 5);

        procedure put (
            first : natural;
            width : natural;
            value : natural) is
            variable U_v : unsigned(width - 1 downto 0);
        begin
            U_v := to_unsigned(value, width);

            for i in 0 to width - 1 loop
                Bits_v(first + i) := U_v(width - 1 - i);
            end loop;

        end procedure;

    -- Fields in transmission order
    begin
        put(0, 3, version);  -- Packet Version Number, SPP 4.1.3.2
        put(3, 1, pktType);  -- Packet Type, SPP 4.1.3.3.2
        put(4, 1, shf);      -- Secondary Header Flag, SPP 4.1.3.3.3
        put(5, 11, apid);    -- APID, SPP 4.1.3.3.4
        put(16, 2, flags);   -- Sequence Flags, SPP 4.1.3.4.2
        put(18, 14, count);  -- Packet Sequence Count or Packet Name, SPP 4.1.3.4.3
        put(32, 16, pdl);    -- Packet Data Length, SPP 4.1.3.5

        for k in 0 to 5 loop

            for b in 0 to 7 loop
                Hdr_v(k)(7 - b) := Bits_v(8 * k + b);
            end loop;

        end loop;

        return Hdr_v;
    end function;

    function tbSpacePacket (
        pktType : natural;
        shf     : natural;
        apid    : natural;
        flags   : natural;
        count   : natural;
        data    : TbBytes_t) return TbBytes_t is
    begin
        return tbCat(tbPrimaryHeader(0, pktType, shf, apid, flags, count, data'length - 1), data);
    end function;

    function tbCptp (
        addr     : TbBytes_t;
        tla      : natural;
        ua       : natural;
        pkt      : TbBytes_t;
        pid      : natural := 2;
        reserved : natural := 0) return TbBytes_t is
        variable Hdr_v : TbBytes_t(0 to 3);
    begin
        Hdr_v(0) := std_logic_vector(to_unsigned(tla, 8));
        Hdr_v(1) := std_logic_vector(to_unsigned(pid, 8));
        Hdr_v(2) := std_logic_vector(to_unsigned(reserved, 8));
        Hdr_v(3) := std_logic_vector(to_unsigned(ua, 8));
        return tbCat(tbCat(addr, Hdr_v), pkt);
    end function;

    function tbTxUser (
        apid      : natural;
        shi       : natural := 0;
        pktType   : natural := 0;
        nameValid : natural := 0;
        name      : natural := 0) return std_logic_vector is
        variable U_v : std_logic_vector(27 downto 0);
    begin
        U_v(10 downto 0)  := std_logic_vector(to_unsigned(apid, 11));
        U_v(11)           := '1' when shi = 1 else '0';
        U_v(12)           := '1' when pktType = 1 else '0';
        U_v(13)           := '1' when nameValid = 1 else '0';
        U_v(27 downto 14) := std_logic_vector(to_unsigned(name, 14));
        return U_v;
    end function;

    function tbRxUser (
        apid : natural;
        shi  : natural := 0;
        loss : natural := 0;
        err  : natural := 0;
        ua   : natural := 0) return std_logic_vector is
        variable U_v : std_logic_vector(21 downto 0);
    begin
        U_v(10 downto 0)  := std_logic_vector(to_unsigned(apid, 11));
        U_v(11)           := '1' when shi = 1 else '0';
        U_v(12)           := '1' when loss = 1 else '0';
        U_v(13)           := '1' when err = 1 else '0';
        U_v(21 downto 14) := std_logic_vector(to_unsigned(ua, 8));
        return U_v;
    end function;

    function tbLinkUser (
        eep  : natural;
        dest : natural := 0) return std_logic_vector is
        variable U_v : std_logic_vector(4 downto 0);
    begin
        U_v(0)          := '1' when eep = 1 else '0';
        U_v(4 downto 1) := std_logic_vector(to_unsigned(dest, 4));
        return U_v;
    end function;

end package body;
