---------------------------------------------------------------------------------------------------
-- Copyright (c) 2026 by Julian Schneider
-- Authors: Julian Schneider
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Description
---------------------------------------------------------------------------------------------------
-- Test harness of the receiving end: clock, DUT, a stream source of received Space Packets, a stream
-- sink per user port, counters of the error events, the delivered SDUs and the ECC events.
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

library uvvm_vvc_framework;
    use uvvm_vvc_framework.ti_vvc_framework_support_pkg.all;

library work;
    use work.spp_pkg.all;
    use work.spp_receive_tb_pkg.all;

---------------------------------------------------------------------------------------------------
-- Entity
---------------------------------------------------------------------------------------------------
entity spp_receive_th is
    generic (
        DataWidth_g     : positive;
        NumRx_g         : positive;
        RxOctetString_g : std_logic_vector(MaxPorts_c - 1 downto 0);
        BufferBytes_g   : positive
    );
    port (
        Clk             : out   std_logic := '0';
        Rst             : in    std_logic;
        Cfg_MaxLength   : in    std_logic_vector(LengthWidth_c - 1 downto 0);
        Cfg_IdleDeliver : in    std_logic;
        Cfg_TableInit   : in    std_logic_vector(RxEntryWidth_c - 1 downto 0);
        Tbl_Req         : in    TblReq_t;
        Tbl_Rsp         : out   TblRsp_t;
        Errors          : out   ErrLog_t;
        Delivered       : out   natural;
        EccSec          : out   NatArray_t(0 to 3);
        EccDed          : out   NatArray_t(0 to 3);
        ErrInj_Channel  : in    std_logic_vector(5 downto 0);
        ErrInj_Double   : in    std_logic;
        ErrInj_Valid    : in    std_logic;
        Scrub_Enable    : in    std_logic
    );
end entity;

---------------------------------------------------------------------------------------------------
-- Architecture
---------------------------------------------------------------------------------------------------
architecture sim of spp_receive_th is

    constant Bytes_c : positive := DataWidth_g / 8;

    signal Pkt_Valid : std_logic;
    signal Pkt_Ready : std_logic;
    signal Pkt_Data  : std_logic_vector(DataWidth_g - 1 downto 0);
    signal Pkt_Keep  : std_logic_vector(Bytes_c - 1 downto 0);
    signal Pkt_Last  : std_logic;
    signal Pkt_User  : std_logic_vector(RxPktUserWidth_c - 1 downto 0);
    signal Rx_Valid  : std_logic_vector(NumRx_g - 1 downto 0);
    signal Rx_Ready  : std_logic_vector(NumRx_g - 1 downto 0);
    signal Rx_Data   : std_logic_vector(NumRx_g * DataWidth_g - 1 downto 0);
    signal Rx_Keep   : std_logic_vector(NumRx_g * Bytes_c - 1 downto 0);
    signal Rx_Last   : std_logic_vector(NumRx_g - 1 downto 0);
    signal Rx_User   : std_logic_vector(NumRx_g * RxUserWidth_c - 1 downto 0);
    signal Err       : ErrEventArray_t(0 to 1);
    signal Deliv     : std_logic_vector(NumRx_g - 1 downto 0);
    signal Ecc_Sec   : std_logic_vector(3 downto 0);
    signal Ecc_Ded   : std_logic_vector(3 downto 0);

begin

    i_ti_uvvm_engine : entity uvvm_vvc_framework.ti_uvvm_engine;

    -- The clock is driven on the port, so that testbench and DUT see the same signal (no delta cycle between them)
    Clk <= not Clk after ClkPeriod_c / 2;

    i_src : entity work.spp_tb_stream_source
        generic map (
            Channel_g   => ChSrc_c,
            DataWidth_g => DataWidth_g,
            UserWidth_g => RxPktUserWidth_c
        )
        port map (
            Clk       => Clk,
            Out_Valid => Pkt_Valid,
            Out_Ready => Pkt_Ready,
            Out_Data  => Pkt_Data,
            Out_Keep  => Pkt_Keep,
            Out_Last  => Pkt_Last,
            Out_User  => Pkt_User
        );

    i_dut : entity work.spp_receive
        generic map (
            DataWidth_g     => DataWidth_g,
            NumRx_g         => NumRx_g,
            RxOctetString_g => RxOctetString_g,
            BufferBytes_g   => BufferBytes_g,
            MaxPackets_g    => 8,
            ClkFreqHz_g     => 100.0e6
        )
        port map (
            Clk             => Clk,
            Rst             => Rst,
            S_Pkt_Valid     => Pkt_Valid,
            S_Pkt_Ready     => Pkt_Ready,
            S_Pkt_Data      => Pkt_Data,
            S_Pkt_Keep      => Pkt_Keep,
            S_Pkt_Last      => Pkt_Last,
            S_Pkt_User      => Pkt_User,
            M_Rx_Valid      => Rx_Valid,
            M_Rx_Ready      => Rx_Ready,
            M_Rx_Data       => Rx_Data,
            M_Rx_Keep       => Rx_Keep,
            M_Rx_Last       => Rx_Last,
            M_Rx_User       => Rx_User,
            Cfg_MaxLength   => Cfg_MaxLength,
            Cfg_IdleDeliver => Cfg_IdleDeliver,
            Cfg_TableInit   => Cfg_TableInit,
            Tbl_Valid       => Tbl_Req.Valid,
            Tbl_Ready       => Tbl_Rsp.Ready,
            Tbl_Apid        => Tbl_Req.Apid,
            Tbl_RdValid     => Tbl_Rsp.RdValid,
            Tbl_RdData      => Tbl_Rsp.RdData,
            Tbl_RdDed       => Tbl_Rsp.RdDed,
            Tbl_WrEna       => Tbl_Req.WrEna,
            Tbl_WrData      => Tbl_Req.WrData,
            Tbl_Release     => Tbl_Req.Done,
            Tbl_Busy        => Tbl_Rsp.Busy,
            Err             => Err,
            Loss            => open,
            Delivered       => Deliv,
            Ecc_Sec         => Ecc_Sec,
            Ecc_Ded         => Ecc_Ded,
            ErrInj_Channel  => ErrInj_Channel,
            ErrInj_Double   => ErrInj_Double,
            ErrInj_Valid    => ErrInj_Valid,
            Scrub_Enable    => Scrub_Enable
        );

    g_snk : for p in 0 to NumRx_g - 1 generate

        i_snk : entity work.spp_tb_stream_sink
            generic map (
                Channel_g   => ChPort_c + p,
                DataWidth_g => DataWidth_g,
                UserWidth_g => RxUserWidth_c,
                Name_g      => "port " & to_string(p)
            )
            port map (
                Clk      => Clk,
                In_Valid => Rx_Valid(p),
                In_Ready => Rx_Ready(p),
                In_Data  => Rx_Data((p + 1) * DataWidth_g - 1 downto p * DataWidth_g),
                In_Keep  => Rx_Keep((p + 1) * Bytes_c - 1 downto p * Bytes_c),
                In_Last  => Rx_Last(p),
                In_User  => Rx_User((p + 1) * RxUserWidth_c - 1 downto p * RxUserWidth_c)
            );

    end generate;

    -- Counters
    p_count : process (Clk) is
        variable Log_v   : ErrLog_t           := ((others => 0), ErrEventNone_c, 0);
        variable Deliv_v : natural            := 0;
        variable Sec_v   : NatArray_t(0 to 3) := (others => 0);
        variable Ded_v   : NatArray_t(0 to 3) := (others => 0);
    begin
        if rising_edge(Clk) then

            for i in Err'range loop
                if Err(i).Valid = '1' then
                    Log_v.Count(to_integer(unsigned(Err(i).Code))) := Log_v.Count(to_integer(unsigned(Err(i).Code))) + 1;
                    Log_v.Last                                     := Err(i);
                    Log_v.Total                                    := Log_v.Total + 1;
                end if;
            end loop;

            for p in 0 to NumRx_g - 1 loop
                if Deliv(p) = '1' then
                    Deliv_v := Deliv_v + 1;
                end if;
            end loop;

            for i in 0 to 3 loop
                if Ecc_Sec(i) = '1' then
                    Sec_v(i) := Sec_v(i) + 1;
                end if;
                if Ecc_Ded(i) = '1' then
                    Ded_v(i) := Ded_v(i) + 1;
                end if;
            end loop;

            if Rst = '1' then
                Log_v   := ((others => 0),
                            ErrEventNone_c,
                            0);
                Deliv_v := 0;
                Sec_v   := (others => 0);
                Ded_v   := (others => 0);
            end if;
            Errors    <= Log_v;
            Delivered <= Deliv_v;
            EccSec    <= Sec_v;
            EccDed    <= Ded_v;
        end if;
    end process;

end architecture;
