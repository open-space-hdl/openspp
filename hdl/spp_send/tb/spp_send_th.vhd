---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the sending end: clock, DUT, a stream source per send port, a stream sink on the
-- packet output, counters of the error events, the packets sent and the ECC events.
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

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library work;
    use work.spp_pkg.all;
    use work.spp_send_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_send_th is
    generic (
        DataWidth_g     : positive;
        NumTx_g         : positive;
        TxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0);
        BufferBytes_g   : positive
    );
    port (
        Clk            : out   std_logic := '0';
        Rst            : in    std_logic;
        Cfg_MaxLength  : in    std_logic_vector(LengthWidth_c - 1 downto 0);
        Cfg_RoundRobin : in    std_logic;
        Cfg_TableInit  : in    std_logic_vector(TxEntryWidth_c - 1 downto 0);
        Tbl_Req        : in    TblReq_t;
        Tbl_Rsp        : out   TblRsp_t;
        Errors         : out   ErrLog_t;
        Sent           : out   natural;
        EccSec         : out   NatArray_t(0 to 3);
        EccDed         : out   NatArray_t(0 to 3);
        ErrInj_Channel : in    std_logic_vector(5 downto 0);
        ErrInj_Double  : in    std_logic;
        ErrInj_Valid   : in    std_logic;
        Scrub_Enable   : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_send_th is

    constant Bytes_c : positive := DataWidth_g / 8;

    signal Tx_Valid  : std_logic_vector(NumTx_g - 1 downto 0);
    signal Tx_Ready  : std_logic_vector(NumTx_g - 1 downto 0);
    signal Tx_Data   : std_logic_vector(NumTx_g * DataWidth_g - 1 downto 0);
    signal Tx_Keep   : std_logic_vector(NumTx_g * Bytes_c - 1 downto 0);
    signal Tx_Last   : std_logic_vector(NumTx_g - 1 downto 0);
    signal Tx_User   : std_logic_vector(NumTx_g * TxUserWidth_c - 1 downto 0);
    signal Pkt_Valid : std_logic;
    signal Pkt_Ready : std_logic;
    signal Pkt_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Pkt_Keep  : std_logic_vector(Bytes_c - 1 downto 0);
    signal Pkt_Last  : std_logic;
    signal Pkt_User  : std_logic_vector(LinkUserWidth_c - 1 downto 0);
    signal Err       : ErrEventArray_t(0 to NumTx_g);
    signal SentPulse : std_logic;
    signal Ecc_Sec   : std_logic_vector(3 downto 0);
    signal Ecc_Ded   : std_logic_vector(3 downto 0);

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    -- The clock is driven on the port, so that testbench and DUT see the same signal (no delta cycle between them)
    Clk <= not Clk after ClkPeriod_c / 2;

    -- Requests of the user ports
    g_src : for p in 0 to NumTx_g - 1 generate

        i_src : entity work.spp_tb_stream_source
            generic map (
                Channel_g   => p,
                DataWidth_g => DataWidth_g,
                UserWidth_g => TxUserWidth_c
            )
            port map (
                Clk       => Clk,
                Out_Valid => Tx_Valid(p),
                Out_Ready => Tx_Ready(p),
                Out_Data  => Tx_Data((p + 1) * DataWidth_g - 1 downto p * DataWidth_g),
                Out_Keep  => Tx_Keep((p + 1) * Bytes_c - 1 downto p * Bytes_c),
                Out_Last  => Tx_Last(p),
                Out_User  => Tx_User((p + 1) * TxUserWidth_c - 1 downto p * TxUserWidth_c)
            );

    end generate;

    i_dut : entity work.spp_send
        generic map (
            DataWidth_g     => DataWidth_g,
            NumTx_g         => NumTx_g,
            TxOctetString_g => TxOctetString_g,
            BufferBytes_g   => BufferBytes_g,
            MaxPackets_g    => 8,
            ClkFreqHz_g     => 100.0e6
        )
        port map (
            Clk            => Clk,
            Rst            => Rst,
            S_Tx_Valid     => Tx_Valid,
            S_Tx_Ready     => Tx_Ready,
            S_Tx_Data      => Tx_Data,
            S_Tx_Keep      => Tx_Keep,
            S_Tx_Last      => Tx_Last,
            S_Tx_User      => Tx_User,
            M_Pkt_Valid    => Pkt_Valid,
            M_Pkt_Ready    => Pkt_Ready,
            M_Pkt_Data     => Pkt_Data,
            M_Pkt_Keep     => Pkt_Keep,
            M_Pkt_Last     => Pkt_Last,
            M_Pkt_User     => Pkt_User,
            Cfg_MaxLength  => Cfg_MaxLength,
            Cfg_RoundRobin => Cfg_RoundRobin,
            Cfg_TableInit  => Cfg_TableInit,
            Tbl_Valid      => Tbl_Req.Valid,
            Tbl_Ready      => Tbl_Rsp.Ready,
            Tbl_Apid       => Tbl_Req.Apid,
            Tbl_RdValid    => Tbl_Rsp.RdValid,
            Tbl_RdData     => Tbl_Rsp.RdData,
            Tbl_RdDed      => Tbl_Rsp.RdDed,
            Tbl_WrEna      => Tbl_Req.WrEna,
            Tbl_WrData     => Tbl_Req.WrData,
            Tbl_Release    => Tbl_Req.Done,
            Tbl_Busy       => Tbl_Rsp.Busy,
            Err            => Err,
            Sent           => SentPulse,
            Ecc_Sec        => Ecc_Sec,
            Ecc_Ded        => Ecc_Ded,
            ErrInj_Channel => ErrInj_Channel,
            ErrInj_Double  => ErrInj_Double,
            ErrInj_Valid   => ErrInj_Valid,
            Scrub_Enable   => Scrub_Enable
        );

    i_snk : entity work.spp_tb_stream_sink
        generic map (
            Channel_g   => ChSink_c,
            DataWidth_g => DataWidth_g,
            UserWidth_g => LinkUserWidth_c,
            Name_g      => "packets"
        )
        port map (
            Clk      => Clk,
            In_Valid => Pkt_Valid,
            In_Ready => Pkt_Ready,
            In_Data  => Pkt_Data,
            In_Keep  => Pkt_Keep,
            In_Last  => Pkt_Last,
            In_User  => Pkt_User
        );

    -- Counters
    p_count : process (Clk) is
        variable Log_v  : ErrLog_t           := ((others => 0), ErrEventNone_c, 0);
        variable Sent_v : natural            := 0;
        variable Sec_v  : NatArray_t(0 to 3) := (others => 0);
        variable Ded_v  : NatArray_t(0 to 3) := (others => 0);
    begin
        if rising_edge(Clk) then

            for i in Err'range loop
                if Err(i).Valid = '1' then
                    Log_v.Count(to_integer(unsigned(Err(i).Code))) := Log_v.Count(to_integer(unsigned(Err(i).Code))) + 1;
                    Log_v.Last                                     := Err(i);
                    Log_v.Total                                    := Log_v.Total + 1;
                end if;
            end loop;

            if SentPulse = '1' then
                Sent_v := Sent_v + 1;
            end if;

            for i in 0 to 3 loop
                if Ecc_Sec(i) = '1' then
                    Sec_v(i) := Sec_v(i) + 1;
                end if;
                if Ecc_Ded(i) = '1' then
                    Ded_v(i) := Ded_v(i) + 1;
                end if;
            end loop;

            if Rst = '1' then
                Log_v  := ((others => 0),
                           ErrEventNone_c,
                           0);
                Sent_v := 0;
                Sec_v  := (others => 0);
                Ded_v  := (others => 0);
            end if;
            Errors <= Log_v;
            Sent   <= Sent_v;
            EccSec <= Sec_v;
            EccDed <= Ded_v;
        end if;
    end process;

end architecture;
