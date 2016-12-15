library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity in_FSM is
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
	stop:						out std_logic
);
end entity;

architecture rtl of in_FSM is
	type state is (s_idle, s_stream, s_discard);
	signal my_state		: state;
	
	signal count			: integer range 0 to 4095; -- max size of packet in bytes
	
	signal frame_len		: integer range 0 to 4095;
	signal usedw_hi		: integer range 0 to 32767;
	signal usedw_lo		: integer range 0 to 32767;
	signal mem_avail		: std_logic;
	signal stop_out		: std_logic;
begin

-- Asynchronous signals
process(all) begin
	frame_len <= to_integer(unsigned(controli(11 downto 0)));
	usedw_hi <= to_integer(unsigned(numusedhi));
	usedw_lo <= to_integer(unsigned(numusedlo));
	
	if((32768-usedw_hi>=frame_len and in_priority='1') or
		(32768-usedw_lo>=frame_len and in_priority='0')) then
		mem_avail <= '1';
	else
		mem_avail <= '0';
	end if;
	
	if(count = frame_len) then
		stop_out <= '1';
	else
		stop_out <= '0';
	end if;
end process;

-- Moore machine
process(clk_sys, reset) begin
	if(reset = '1') then
		my_state <= s_idle;
		count <= 0;
	elsif(rising_edge(clk_sys)) then
		case my_state is
		when s_idle =>
			if(wrenc = '1' and mem_avail = '1') then
				my_state <= s_stream;
				count <= 0;
			elsif(wrenc = '1') then
				my_state <= s_discard;
				count <= 0;
			end if;
		when others => -- s_stream or s_discard
			if(stop_out = '1') then
				my_state <= s_idle;
				count <= 0;
			else
				count <= count + 1;
			end if;
		end case;
		
		controlo <= controli;
		datao <= datai;
		out_priority <= in_priority;
		start <= wrenc;
	end if;
end process;

-- Output signals
process(all) begin
	case my_state is
	when s_idle =>
		out_m_discard_en <= '0';
		out_wren <= '0';
	when s_stream =>
		out_m_discard_en <= '0';
		out_wren <= '1';
	when others =>
		out_m_discard_en <= '1';
		out_wren <= '0';
	end case;
	
	stop <= stop_out;
end process;

end architecture;
