---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Common constants, types and functions of OpenSPP: fields of the Space Packet (CCSDS 133.0-B-2) and
-- of the CPTP packet (ECSS-E-ST-50-53C), layouts of TUser, error codes and byte enable helpers.
--
-- Documentation: hdl/spp_pkg/docs/specification.md

---------------------------------------------------------------------------------------------------
-- Libraries
---------------------------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

---------------------------------------------------------------------------------------------------
-- Package Header
---------------------------------------------------------------------------------------------------
package spp_pkg is

    -----------------------------------------------------------------------------------------------
    -- Space Packet (SPP 4.1)
    -----------------------------------------------------------------------------------------------
    constant PrimaryHeaderBytes_c  : natural                       := 6;               -- SPP 4.1.3.1
    constant MinPacketBytes_c      : natural                       := 7;               -- SPP 4.1.2.2
    constant MaxPacketBytes_c      : natural                       := 65542;           -- SPP 4.1.2.2
    constant MaxOctetStringBytes_c : natural                       := 65536;           -- SPP 3.2.3.1
    constant PacketVersion_c       : std_logic_vector(2 downto 0)  := "000";           -- SPP 4.1.3.2.2
    constant IdleApid_c            : std_logic_vector(10 downto 0) := (others => '1'); -- SPP 4.1.3.3.4.4
    constant Unsegmented_c         : std_logic_vector(1 downto 0)  := "11";            -- SPP 4.1.3.4.2.2d
    constant SeqCountModulo_c      : natural                       := 16384;           -- SPP 4.1.3.4.3.4
    constant ApidCount_c           : natural                       := 2048;
    -- Byte counts: 17 bits hold every legal length; counters saturate at the maximum
    constant LengthWidth_c         : natural := 17;
    constant LengthMax_c           : natural := 2**LengthWidth_c - 1;

    -----------------------------------------------------------------------------------------------
    -- CPTP packet (CPTP 5.3, 5.4)
    -----------------------------------------------------------------------------------------------
    constant CptpHeaderBytes_c    : natural                      := 4;
    constant CptpProtocolId_c     : std_logic_vector(7 downto 0) := x"02"; -- CPTP 5.3.3b
    constant CptpReserved_c       : std_logic_vector(7 downto 0) := x"00"; -- CPTP 5.3.4a
    constant DefaultLogicalAddr_c : std_logic_vector(7 downto 0) := x"FE"; -- CPTP 5.3.2 note 2
    constant MaxSpwAddrBytes_c    : natural                      := 16;
    constant MaxRxStripBytes_c    : natural                      := 15;

    -----------------------------------------------------------------------------------------------
    -- Ports and destinations
    -----------------------------------------------------------------------------------------------
    constant MaxPorts_c : natural := 16;
    constant MaxDest_c  : natural := 16;

    -----------------------------------------------------------------------------------------------
    -- TUser of the send ports (Octet String Service)
    -----------------------------------------------------------------------------------------------
    constant TxUserWidth_c     : natural := 28;
    subtype TxUserApid_t is natural range 10 downto 0;
    constant TxUserShi_c       : natural := 11;
    constant TxUserType_c      : natural := 12;
    constant TxUserNameValid_c : natural := 13;
    subtype TxUserName_t is natural range 27 downto 14;

    -----------------------------------------------------------------------------------------------
    -- TUser of the receive ports
    -----------------------------------------------------------------------------------------------
    constant RxUserWidth_c : natural := 22;
    subtype RxUserApid_t is natural range 10 downto 0;
    constant RxUserShi_c   : natural := 11;
    constant RxUserLoss_c  : natural := 12;
    constant RxUserError_c : natural := 13;
    subtype RxUserUa_t is natural range 21 downto 14;

    -----------------------------------------------------------------------------------------------
    -- TUser of the link ports
    -----------------------------------------------------------------------------------------------
    constant LinkUserWidth_c : natural := 5;
    constant LinkUserEep_c   : natural := 0;
    subtype LinkUserDest_t is natural range 4 downto 1;

    -----------------------------------------------------------------------------------------------
    -- Entries of the APID tables
    -----------------------------------------------------------------------------------------------
    -- Send table: Packet Sequence Count, destination index, path enable
    constant TxEntryWidth_c  : natural := 19;
    subtype TxEntryCount_t is natural range 13 downto 0;
    subtype TxEntryDest_t is natural range 17 downto 14;
    constant TxEntryEnable_c : natural := 18;
    -- Receive table: last Packet Sequence Count, its validity, continuity check enable, user port, path enable
    constant RxEntryWidth_c  : natural := 21;
    subtype RxEntryLast_t is natural range 13 downto 0;
    constant RxEntryValid_c  : natural := 14;
    constant RxEntryCheck_c  : natural := 15;
    subtype RxEntryPort_t is natural range 19 downto 16;
    constant RxEntryEnable_c : natural := 20;

    -----------------------------------------------------------------------------------------------
    -- Descriptor of an SDU in a send buffer: byte length and request parameters (TUser layout; for a
    -- Space Packet only the APID of its header)
    -----------------------------------------------------------------------------------------------
    constant TxDescWidth_c : natural := LengthWidth_c + TxUserWidth_c;
    subtype TxDescLen_t is natural range LengthWidth_c - 1 downto 0;
    subtype TxDescUser_t is natural range TxDescWidth_c - 1 downto LengthWidth_c;

    -----------------------------------------------------------------------------------------------
    -- TUser of the received Space Packets between the decapsulation and the receiving end: error end
    -- of packet (bit 0, with the last beat), User Application value (bits 8:1)
    -----------------------------------------------------------------------------------------------
    constant RxPktUserWidth_c : natural := 9;
    constant RxPktUserEep_c   : natural := 0;
    subtype RxPktUserUa_t is natural range 8 downto 1;

    -----------------------------------------------------------------------------------------------
    -- Descriptor of a received Space Packet: byte length, Packet Primary Header, User Application value
    -----------------------------------------------------------------------------------------------
    constant RxDescWidth_c : natural := LengthWidth_c + 48 + 8;
    subtype RxDescLen_t is natural range LengthWidth_c - 1 downto 0;
    subtype RxDescHdr_t is natural range LengthWidth_c + 47 downto LengthWidth_c;
    subtype RxDescUa_t is natural range RxDescWidth_c - 1 downto LengthWidth_c + 48;

    -----------------------------------------------------------------------------------------------
    -- Descriptor of a segment of the packetizer: length minus one, first and last segment of its data
    -- unit, CRC of the segment (the CRC bits are stored only with Crc_g)
    -----------------------------------------------------------------------------------------------
    constant PkDescWidth_c : natural := 34;
    subtype PkDescLen_t is natural range 15 downto 0;
    constant PkDescFirst_c : natural := 16;
    constant PkDescLast_c  : natural := 17;
    subtype PkDescCrc_t is natural range 33 downto 18;

    -----------------------------------------------------------------------------------------------
    -- Error codes (reasons of rejected SDUs and discarded packets)
    -----------------------------------------------------------------------------------------------
    constant ErrCodeWidth_c    : natural   := 5;
    subtype ErrCode_t is std_logic_vector(ErrCodeWidth_c - 1 downto 0);
    constant ErrNone_c         : ErrCode_t := "00000";
    -- Sending end
    constant ErrTxOversize_c   : ErrCode_t := "00001";
    constant ErrTxShort_c      : ErrCode_t := "00010";
    constant ErrTxVersion_c    : ErrCode_t := "00011";
    constant ErrTxLength_c     : ErrCode_t := "00100";
    constant ErrTxIdle_c       : ErrCode_t := "00101";
    constant ErrTxName_c       : ErrCode_t := "00110";
    constant ErrTxNoPath_c     : ErrCode_t := "00111";
    constant ErrTxBuffer_c     : ErrCode_t := "01000";
    -- Receiving end
    constant ErrRxEep_c        : ErrCode_t := "10000";
    constant ErrRxProtocolId_c : ErrCode_t := "10001";
    constant ErrRxReserved_c   : ErrCode_t := "10010";
    constant ErrRxAddress_c    : ErrCode_t := "10011";
    constant ErrRxShort_c      : ErrCode_t := "10100";
    constant ErrRxVersion_c    : ErrCode_t := "10101";
    constant ErrRxLength_c     : ErrCode_t := "10110";
    constant ErrRxOversize_c   : ErrCode_t := "10111";
    constant ErrRxIdle_c       : ErrCode_t := "11000";
    constant ErrRxNoPath_c     : ErrCode_t := "11001";
    constant ErrRxFlags_c      : ErrCode_t := "11010";
    constant ErrRxBuffer_c     : ErrCode_t := "11011";

    -- Error event: one-cycle report of a rejected SDU or a discarded packet
    type ErrEvent_t is record
        Valid : std_logic;
        Code  : ErrCode_t;
        Index : std_logic_vector(3 downto 0);  -- user port of the SDU or packet, 0 when unknown
        Apid  : std_logic_vector(10 downto 0); -- APID of the SDU or packet, 0 when unknown
    end record;

    constant ErrEventNone_c : ErrEvent_t := (Valid => '0', Code => ErrNone_c, Index => (others => '0'),
                                             Apid  => (others => '0'));

    type ErrEventArray_t is array (natural range <>) of ErrEvent_t;

    -----------------------------------------------------------------------------------------------
    -- Functions
    -----------------------------------------------------------------------------------------------
    -- Byte enables of a beat of width bytes holding the first n bytes (n >= width: all bytes)
    function keepOfBytes (
        n     : natural;
        width : positive) return std_logic_vector;

    -- Number of bytes of contiguous byte enables (lane 0 upwards)
    function bytesOfKeep (keep : std_logic_vector) return natural;

    -- Error injection pattern of a codeword of width bits: bit 0 flipped (single error) or bits 0 and 1
    -- flipped (double error)
    function injPattern (
        width  : positive;
        double : std_logic) return std_logic_vector;

    -- Error injection pattern that flips data bits of an Open Logic SECDED codeword of width bits: data
    -- bit 0 (codeword position 3, single error) or data bits 0 and 1 (positions 3 and 5, double error)
    function injDataPattern (
        width  : positive;
        double : std_logic) return std_logic_vector;

    -- Packet Primary Header (SPP 4.1.3) as six bytes, byte 0 in bits 7:0
    function primaryHeader (
        pktType : std_logic;
        shf     : std_logic;
        apid    : std_logic_vector(10 downto 0);
        flags   : std_logic_vector(1 downto 0);
        count   : std_logic_vector(13 downto 0);
        pdl     : std_logic_vector(15 downto 0)) return std_logic_vector;

    -- Fields of a Packet Primary Header given as six bytes, byte 0 in bits 7:0
    function hdrVersion (hdr : std_logic_vector(47 downto 0)) return std_logic_vector;
    function hdrType (hdr : std_logic_vector(47 downto 0)) return std_logic;
    function hdrShf (hdr : std_logic_vector(47 downto 0)) return std_logic;
    function hdrApid (hdr : std_logic_vector(47 downto 0)) return std_logic_vector;
    function hdrFlags (hdr : std_logic_vector(47 downto 0)) return std_logic_vector;
    function hdrCount (hdr : std_logic_vector(47 downto 0)) return std_logic_vector;
    function hdrPdl (hdr : std_logic_vector(47 downto 0)) return std_logic_vector;

end package;

---------------------------------------------------------------------------------------------------
-- Package Body
---------------------------------------------------------------------------------------------------
package body spp_pkg is

    function keepOfBytes (
        n     : natural;
        width : positive) return std_logic_vector is
        variable Keep_v : std_logic_vector(width - 1 downto 0) := (others => '0');
    begin

        for i in 0 to width - 1 loop
            if i < n then
                Keep_v(i) := '1';
            end if;
        end loop;

        return Keep_v;
    end function;

    function bytesOfKeep (keep : std_logic_vector) return natural is
        variable N_v : natural := 0;
    begin

        for i in keep'range loop
            if keep(i) = '1' then
                N_v := N_v + 1;
            end if;
        end loop;

        return N_v;
    end function;

    function primaryHeader (
        pktType : std_logic;
        shf     : std_logic;
        apid    : std_logic_vector(10 downto 0);
        flags   : std_logic_vector(1 downto 0);
        count   : std_logic_vector(13 downto 0);
        pdl     : std_logic_vector(15 downto 0)) return std_logic_vector is
        variable Hdr_v : std_logic_vector(47 downto 0);
    begin
        -- SPP 4.1.3.2 to 4.1.3.5: version, identification, sequence control, data length (bit 0 first)
        Hdr_v(7 downto 0)   := PacketVersion_c & pktType & shf & apid(10 downto 8);
        Hdr_v(15 downto 8)  := apid(7 downto 0);
        Hdr_v(23 downto 16) := flags & count(13 downto 8);
        Hdr_v(31 downto 24) := count(7 downto 0);
        Hdr_v(39 downto 32) := pdl(15 downto 8);
        Hdr_v(47 downto 40) := pdl(7 downto 0);
        return Hdr_v;
    end function;

    function injPattern (
        width  : positive;
        double : std_logic) return std_logic_vector is
        variable P_v : std_logic_vector(width - 1 downto 0) := (others => '0');
    begin
        P_v(0) := '1';
        if double = '1' then
            P_v(1) := '1';
        end if;
        return P_v;
    end function;

    function injDataPattern (
        width  : positive;
        double : std_logic) return std_logic_vector is
        variable P_v : std_logic_vector(width - 1 downto 0) := (others => '0');
    begin
        P_v(3) := '1';
        if double = '1' then
            P_v(5) := '1';
        end if;
        return P_v;
    end function;

    function hdrVersion (hdr : std_logic_vector(47 downto 0)) return std_logic_vector is
    begin
        return hdr(7 downto 5);
    end function;

    function hdrType (hdr : std_logic_vector(47 downto 0)) return std_logic is
    begin
        return hdr(4);
    end function;

    function hdrShf (hdr : std_logic_vector(47 downto 0)) return std_logic is
    begin
        return hdr(3);
    end function;

    function hdrApid (hdr : std_logic_vector(47 downto 0)) return std_logic_vector is
    begin
        return hdr(2 downto 0) & hdr(15 downto 8);
    end function;

    function hdrFlags (hdr : std_logic_vector(47 downto 0)) return std_logic_vector is
    begin
        return hdr(23 downto 22);
    end function;

    function hdrCount (hdr : std_logic_vector(47 downto 0)) return std_logic_vector is
    begin
        return hdr(21 downto 16) & hdr(31 downto 24);
    end function;

    function hdrPdl (hdr : std_logic_vector(47 downto 0)) return std_logic_vector is
    begin
        return hdr(39 downto 32) & hdr(47 downto 40);
    end function;

end package body;
