library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity out_FSM is
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
end entity;

architecture rtl of out_FSM is
	type state is (s_init, s_gap, s_wait_96, s_wait_start, s_preamble, s_SFD, s_data);
	signal my_state		: state;
	
	signal count			: integer range 0 to 4095; -- max size of packet in bytes
	signal is_even			: std_logic;
	
	type priority_state is (s_hi, s_lo);
	signal my_priority_state		: priority_state;
	
	signal usedw_hi		: integer range 0 to 32767;
	signal usedw_lo		: integer range 0 to 32767;
	
	signal data_in			: std_logic_vector(7 downto 0);
	signal start_in		: std_logic;
	signal stop_in			: std_logic;
begin

-- Asynchronous signals
process(all) begin
	if(count mod 2 = 0) then
		is_even <= '1';
	else
		is_even <= '0';
	end if;
	
	usedw_hi <= to_integer(unsigned(usedw_hi_in));
	usedw_lo <= to_integer(unsigned(usedw_lo_in));
	
	-- priority logic
	if(my_priority_state = s_hi) then
		data_in <= data_hi_in;
		start_in <= start_hi_in;
		stop_in <= stop_hi_in;
	else -- s_lo
		data_in <= data_lo_in;
		start_in <= start_lo_in;
		stop_in <= stop_lo_in;
	end if;
end process;

-- Moore machine (my_state)
process(clk_phy, reset) begin
	if(reset = '1') then
		my_state <= s_init;
		count <= 0;
	elsif(rising_edge(clk_phy)) then
		case my_state is
		when s_init =>
			if(start_in = '1') then
				my_state <= s_preamble;
				count <= 0;
			end if;
		when s_gap =>
			if(count >= 96/4) then
				my_state <= s_wait_start;
			elsif(start_in = '1') then
				my_state <= s_wait_96;
				count <= count + 1;
			else
				count <= count + 1;
			end if;
		when s_wait_start =>
			if(start_in = '1') then
				my_state <= s_preamble;
				count <= 0;
			end if;
		when s_wait_96 =>
			if(count >= 96/4) then
				my_state <= s_preamble;
				count <= 0;
			else
				count <= count + 1;
			end if;
		when s_preamble =>
			if(count >= 56/4) then
				my_state <= s_SFD;
				count <= 0;
			else
				count <= count + 1;
			end if;
		when s_SFD =>
			if(count >= 8/4) then
				my_state <= s_data;
				count <= 0;
			else
				count <= count + 1;
			end if;
		when others => -- s_data
			if(stop_in = '1') then
				my_state <= s_gap;
				count <= 0;
			else
				count <= count + 1;
			end if;
		end case;
	end if;
end process;

-- Moore machine (my_priority_state)
process(clk_phy, reset) begin
	if(reset = '1') then
		my_priority_state <= s_lo;
	elsif(rising_edge(clk_phy)) then
		if(start_hi_in = '1' and usedw_hi > 0) then
			my_priority_state <= s_hi;
		elsif(start_lo_in = '1') then
			my_priority_state <= s_lo;
		end if;
	end if;
end process;

-- Output signals
process(all) begin
	case my_state is
	when s_init | s_gap =>
		phy_data_out <= X"0";
		phy_tx_en <= '0';
		xmit_done_out <= '0';
		if(usedw_hi > 0) then
			pop_hi <= '1';
			pop_lo <= '0';
		elsif(usedw_lo > 0) then
			pop_hi <= '0';
			pop_lo <= '1';
		end if;
	when s_wait_start | s_wait_96 =>
		phy_data_out <= X"0";
		phy_tx_en <= '0';
		xmit_done_out <= '0';
		pop_hi <= '0';
		pop_lo <= '0';
	when s_preamble =>
		phy_data_out <= X"A";
		phy_tx_en <= '0';
		xmit_done_out <= '0';
		pop_hi <= '0';
		pop_lo <= '0';
	when s_SFD =>
		phy_data_out <= X"B";
		phy_tx_en <= '0';
		xmit_done_out <= '0';
		pop_hi <= '0';
		pop_lo <= '0';
	when others => -- s_data
		if(is_even) then
			phy_data_out <= data_in(3 downto 0);
		else
			phy_data_out <= data_in(7 downto 4);
		end if;
		phy_tx_en <= '1';
		xmit_done_out <= stop_in;
		if(my_priority_state = s_hi) then
			pop_hi <= is_even;
			pop_lo <= '0';
		else -- s_lo
			pop_hi <= '0';
			pop_lo <= is_even;
		end if;
	end case;
end process;

end architecture;
