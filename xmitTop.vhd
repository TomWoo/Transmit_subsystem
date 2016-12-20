library ieee;
use ieee.std_logic_1164.all;

entity xmitTop is port(
	reset:				in std_logic;
	clk_sys:				in std_logic; -- 50 MHz
	clk_phy:				in std_logic; -- 25 MHz
	
	f_hi_priority:		in std_logic;
	f_rec_data_valid:	in std_logic;
	f_rec_frame_valid:in std_logic;
	f_data_in:			in std_logic_vector(7 downto 0);
	f_ctrl_in: 			in std_logic_vector(23 downto 0);
	
	phy_data_out: 		out std_logic_vector(3 downto 0);
	phy_tx_en:			out std_logic;
	m_discard_en: 		out std_logic;
	m_discard_frame:	out std_logic_vector(11 downto 0);
	m_tx_frame:			out std_logic_vector(23 downto 0);
	m_tx_done:			out std_logic
);
end entity;

architecture rtl of xmitTop is

-- Components --

component in_FSM
port(
	reset:					in std_logic;
	clk_sys:					in std_logic;
	
	wrenc: 					in std_logic; --ctrl write enable;
	controli: 				in std_logic_vector(23 downto 0);
	wrend: 					in std_logic; --data write enable;
	datai: 					in std_logic_vector(7 downto 0);
	in_priority:			in std_logic;
	numusedhi:				in std_logic_vector(14 downto 0);
	numusedlo: 				in std_logic_vector(14 downto 0);
	
	controlo: 				out std_logic_vector(23 downto 0);
	datao: 					out std_logic_vector(7 downto 0);
	out_priority: 			out std_logic;
	out_m_discard_en:		out std_logic;
	out_wren:				out std_logic;
	start:					out std_logic;
	stop:						out std_logic;
	
	frame_seq_num_out:	out std_logic_vector(11 downto 0)
);
end component;

component out_FSM
port(
	reset					: in std_logic;
	clk_phy				: in std_logic;
	
	data_hi_in			: in std_logic_vector(7 downto 0);
	start_hi_in			: in std_logic;
	stop_hi_in			: in std_logic;
	usedw_hi_in			: in std_logic_vector(14 downto 0);
	data_lo_in			: in std_logic_vector(7 downto 0);
	start_lo_in			: in std_logic;
	stop_lo_in			: in std_logic;
	usedw_lo_in			: in std_logic_vector(14 downto 0);
	
	phy_data_out		: out std_logic_vector(3 downto 0);
	phy_tx_en			: out std_logic;
	xmit_done_out		: out std_logic;
	pop_hi				: out std_logic;
	pop_lo				: out std_logic
);
end component;

component dataFIFO
PORT(
	aclr					: IN STD_LOGIC  := '0';
	data					: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
	rdclk					: IN STD_LOGIC ;
	rdreq					: IN STD_LOGIC ;
	wrclk					: IN STD_LOGIC ;
	wrreq					: IN STD_LOGIC ;
	
	q						: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
	rdempty				: OUT STD_LOGIC ;
	rdfull				: OUT STD_LOGIC ;
	wrempty				: OUT STD_LOGIC ;
	wrfull				: OUT STD_LOGIC ;
	wrusedw				: OUT STD_LOGIC_VECTOR (14 DOWNTO 0)
);
end component;

component FIFO_1
PORT(
	aclr					: IN STD_LOGIC  := '0';
	data					: IN STD_LOGIC_VECTOR (0 DOWNTO 0);
	rdclk					: IN STD_LOGIC ;
	rdreq					: IN STD_LOGIC ;
	wrclk					: IN STD_LOGIC ;
	wrreq					: IN STD_LOGIC ;
	
	q						: OUT STD_LOGIC_VECTOR (0 DOWNTO 0);
	rdempty				: OUT STD_LOGIC ;
	wrfull				: OUT STD_LOGIC 
);
end component;

-- Signals --

-- Wires from in_FSM to FIFOs

signal out_wren:			std_logic;
signal data_fifo_in:		std_logic_vector(7 downto 0);
signal out_priority:		std_logic;
signal start_fifo_in:	std_logic;
signal stop_fifo_in:		std_logic;

signal push_hi:			std_logic;
signal push_lo:			std_logic;

-- Wires from in_FSM to monitoring_logic

signal controlo:			std_logic_vector(23 downto 0);
signal discard_en:		std_logic;
signal frame_seq_num:	std_logic_vector(11 downto 0);

-- Wires from FIFOs to out_FSM

signal data_fifo_hi_out:	std_logic_vector(7 downto 0);
signal empty_hi:				std_logic;
signal overflow_hi:			std_logic;
signal usedw_hi:				std_logic_vector(14 downto 0);
signal start_fifo_hi_out:	std_logic;
signal stop_fifo_hi_out:	std_logic;

signal data_fifo_lo_out:	std_logic_vector(7 downto 0);
signal empty_lo:				std_logic;
signal overflow_lo:			std_logic;
signal usedw_lo:				std_logic_vector(14 downto 0);
signal start_fifo_lo_out:	std_logic;
signal stop_fifo_lo_out:	std_logic;

-- Wires from out_FSM to FIFOs

signal pop_hi:					std_logic;
signal pop_lo:					std_logic;

begin

-- Processes

/*
process(all) begin
	push_hi <= f_rec_data_valid and f_hi_priority;
	push_lo <= f_rec_data_valid and not(f_hi_priority);
end process;
*/

-- Registered inputs to FIFOs

process(clk_sys, reset) begin
	if(reset = '1') then
		push_hi <= '0';
		push_lo <= '0';
	elsif(rising_edge(clk_sys)) then
		push_hi <= f_rec_data_valid and f_hi_priority;
		push_lo <= f_rec_data_valid and not(f_hi_priority);
	end if;
end process;

-- Registered outputs to monitoring_logic

process(clk_sys, reset) begin
	if(reset = '1') then
		m_discard_en <= '0';
		m_discard_frame <= X"000";
		m_tx_frame <= X"000000";
	elsif(rising_edge(clk_sys)) then
		m_discard_en <= discard_en;
		m_discard_frame <= frame_seq_num;
		m_tx_frame <= controlo;
	end if;
end process;

-- Entities

input_FSM: in_FSM port map(
	reset							=> reset,
	clk_sys						=> clk_sys,
	
	wrenc							=> f_rec_frame_valid,
	controli						=> f_ctrl_in,
	wrend							=> f_rec_data_valid,
	datai							=> f_data_in,
	in_priority					=> f_hi_priority,
	numusedhi					=> usedw_hi,
	numusedlo					=> usedw_lo,
	
	controlo						=> controlo,
	datao							=> data_fifo_in,
	out_priority				=> out_priority,
	out_m_discard_en			=> discard_en,
	out_wren						=> out_wren,
	start							=> start_fifo_in,
	stop							=> stop_fifo_in,
	
	frame_seq_num_out			=> frame_seq_num
);

output_FSM: out_FSM port map(
	reset							=> reset,
	clk_phy						=> clk_phy,
	
	data_hi_in					=> data_fifo_hi_out,
	start_hi_in					=> start_fifo_hi_out,
	stop_hi_in					=> stop_fifo_hi_out,
	usedw_hi_in					=> usedw_hi, -- TODO: rd?
	data_lo_in					=> data_fifo_lo_out,
	start_lo_in					=> start_fifo_lo_out,
	stop_lo_in					=> stop_fifo_lo_out,
	usedw_lo_in					=> usedw_lo, -- TODO: rd?
	
	phy_data_out				=> phy_data_out,
	phy_tx_en					=> phy_tx_en,
	xmit_done_out				=> m_tx_done,
	pop_hi						=> pop_hi,
	pop_lo						=> pop_lo
);

-- FIFOs

data_fifo_hi: dataFIFO PORT MAP(
	aclr						=> reset,
	data						=> data_fifo_in,
	rdclk						=> clk_phy,
	rdreq						=> pop_hi,
	wrclk						=> clk_sys,
	wrreq						=> push_hi,
	
	q							=> data_fifo_hi_out,
	rdempty					=> empty_hi,
	wrfull					=> overflow_hi,
	wrusedw					=> usedw_hi
);

start_fifo_hi: FIFO_1 PORT MAP(
	aclr						=> reset,
	data(0)					=> start_fifo_in,
	rdclk						=> clk_phy,
	rdreq						=> pop_hi,
	wrclk						=> clk_sys,
	wrreq						=> push_hi,
	
	q(0)						=> start_fifo_hi_out
);

stop_fifo_hi: FIFO_1 PORT MAP(
	aclr						=> reset,
	data(0)					=> stop_fifo_in,
	rdclk						=> clk_phy,
	rdreq						=> pop_hi,
	wrclk						=> clk_sys,
	wrreq						=> push_hi,
	
	q(0)						=> stop_fifo_hi_out
);

data_fifo_lo: dataFIFO PORT MAP(
	aclr						=> reset,
	data						=> data_fifo_in,
	rdclk						=> clk_phy,
	rdreq						=> pop_lo,
	wrclk						=> clk_sys,
	wrreq						=> push_lo,
	
	q							=> data_fifo_lo_out,
	rdempty					=> empty_lo,
	wrfull					=> overflow_lo,
	wrusedw					=> usedw_lo
);

start_fifo_lo: FIFO_1 PORT MAP(
	aclr						=> reset,
	data(0)					=> start_fifo_in,
	rdclk						=> clk_phy,
	rdreq						=> pop_lo,
	wrclk						=> clk_sys,
	wrreq						=> push_lo,
	
	q(0)						=> start_fifo_lo_out
);

stop_fifo_lo: FIFO_1 PORT MAP(
	aclr						=> reset,
	data(0)					=> stop_fifo_in,
	rdclk						=> clk_phy,
	rdreq						=> pop_lo,
	wrclk						=> clk_sys,
	wrreq						=> push_lo,
	
	q(0)						=> stop_fifo_lo_out
);

end architecture;
