-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2019 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): DOPLNIT
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
	signal PC_LD: std_logic:= '0';
	signal TMP_LD: std_logic:= '0';
	signal PC_INC: std_logic:= '0';
	signal PC_DEC: std_logic:= '0';
	signal PTR_INC: std_logic:= '0';
	signal PTR_DEC: std_logic:= '0';
   signal WHILE_INC: std_logic:= '0';
	signal WHILE_DEC: std_logic:= '0';
	signal PTR : std_logic_vector(12 downto 0):="1000000000000";
	signal TMP : std_logic_vector(12 downto 0):="1000000000000";
	signal PC : std_logic_vector(12 downto 0):=(others => '0');
	signal WHILE_C : std_logic_vector(12 downto 0):=(others => '0');
	signal W_OPTION : std_logic_vector(1 downto 0):="00";
	signal d_out : std_logic_vector(7 downto 0):=(others => '0');
	signal INST : std_logic_vector(7 downto 0):=(others => '0');
	signal USE_DATA : std_logic_vector(7 downto 0):=(others => '0');
	
	type FSMstate is (init, fetch, get_inst, inc_ptr, dec_ptr, inc_data, dec_data, 
							state_end, state_continue, print_data, LCD_print, scan_data, wait_for_data, 
							right_bracket, left_bracket, inst_load, while_check, while_check2, end_while_check, decrement, next_inst, 
							store_to_tmp, store_to_ptr, write_it);
	signal pstate: FSMstate;
	signal nstate: FSMstate;


 -- zde dopiste potrebne deklarace signalu

begin

 -- zde dopiste vlastni VHDL kod


 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --   - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --   - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.
	
	mxAddr: process(CLK, PC_LD, TMP_LD)
	begin
		case (PC_LD) is
			when '0' =>
				case (TMP_LD) is
					when '0' =>DATA_ADDR <= PTR;
					when '1' =>DATA_ADDR <= TMP;
					when others =>
				end case;
			when '1' => DATA_ADDR <= PC;
			when others =>
		end case;
	end process;
	
	mxWrite: process(CLK, W_OPTION)
	begin
		case (W_OPTION) is
			when "00" => DATA_WDATA <= IN_DATA;
			when "01" => DATA_WDATA <= USE_DATA + 1;
			when "10" => DATA_WDATA <= USE_DATA - 1;
			when others => DATA_WDATA <= USE_DATA; 
		end case;
	end process;
	
	pointer: process(RESET, CLK, PTR, PTR_INC, PTR_DEC)
	begin
		if(RESET = '1') then
			PTR <= "1000000000000";
		elsif(CLK'event) and(CLK = '1') then
			if (PTR_INC = '1') then 
				if (PTR = "1111111111111") then
					PTR <= "1000000000000";
				else
					PTR <= PTR + 1;
				end if;
			elsif (PTR_DEC = '1') then
				if (PTR = "1000000000000") then
					PTR <= "1111111111111";
				else
					PTR <= PTR - 1;
				end if;
			end if;
		end if;
	end process;
	
	counter: process(RESET, CLK, PC_INC, PC_DEC)
	begin
		if(RESET = '1') then
			PC <= "0000000000000";
		elsif(CLK'event) and(CLK = '1') then
			if (PC_INC = '1') then 
					PC <= PC + 1;
			elsif (PC_DEC = '1') then
					PC <= PC - 1;
			end if;
		end if;
	end process;
	
	while_cnt: process(RESET, CLK)
	begin
		if(RESET = '1') then
			WHILE_C <= "0000000000000";
		elsif(CLK'event) and(CLK = '1') then
			if (WHILE_INC = '1') then 
				if (WHILE_C = "1111111111111") then
					WHILE_C <= "1111111111111";
				else
					WHILE_C <= WHILE_C + 1;
				end if;
			elsif (WHILE_DEC = '1') then
				if (WHILE_C = "0000000000000") then
					WHILE_C <= "0000000000000";
				else
					WHILE_C <= WHILE_C - 1;
				end if;
			end if;
		end if;

	end process;
	
	
	pstatereg: process(RESET, CLK)
	begin
		if(RESET = '1') then
			pstate <= init;
		elsif (CLK'event) and (CLK = '1') then
			if(EN = '1') then
				pstate <= nstate;
			end if;
		end if;
	end process;
	
	
	
	nstate_logic: process (pstate, INST, DATA_RDATA, OUT_BUSY, IN_VLD, WHILE_C)
	begin
		DATA_EN <= '0';
		OUT_WE <= '0';
		PC_LD <= '0';
		PC_INC <= '0';
		PC_DEC <= '0';
		PTR_INC <= '0';
		PTR_DEC <= '0';
		WHILE_INC <= '0';
		WHILE_DEC <= '0';
		DATA_EN <= '0';
		DATA_RDWR <= '0';
		TMP_LD <= '0';
		IN_REQ <= '0';
		W_OPTION <= "00";
		
		case pstate is
			when init =>
				PC_LD <= '1';
				DATA_EN <= '1';
				nstate <= fetch;
			when fetch =>
				DATA_EN <= '1';
				INST <= DATA_RDATA;
				nstate <= get_inst;
			when get_inst =>
				--USE_DATA -> data nactene z adresy mem[PTR]
				USE_DATA <= DATA_RDATA;
				case INST is
					when X"3E" => nstate <= inc_ptr;
					when X"3C" => nstate <= dec_ptr;
					when X"2B" => nstate <= inc_data;
					when X"2D" => nstate <= dec_data;
					when X"2E" => nstate <= print_data;
					when X"2C" => nstate <= scan_data;
					when X"5B" => nstate <= left_bracket;
					when X"5D" => nstate <= right_bracket;
					when X"24" => nstate <= store_to_tmp;
					when X"21" =>
						DATA_EN <= '1';
						TMP_LD <= '1';
						nstate <= store_to_ptr;
					
					when X"00" => nstate <= state_end;
					when others => nstate <= state_continue;
				end case;
				
			when inc_ptr =>
				PC_INC <= '1';
				PTR_INC <= '1';
				nstate <= init;
			when dec_ptr =>
				PC_INC <= '1';
				PTR_DEC <= '1';
				nstate <= init;
			when inc_data => 
				PC_INC <= '1';
				W_OPTION <= "01";
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				nstate <= init;
			when dec_data =>
				PC_INC <= '1';
				W_OPTION <= "10";
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				nstate <= init;
			when print_data =>
				if (OUT_BUSY = '1') then
					nstate <= print_data;
				else
					PC_INC <= '1';
					DATA_EN <= '1';
					d_out <= DATA_RDATA;
					nstate <= LCD_print;
				end if;
			when LCD_print =>
				DATA_EN <= '1';
				OUT_WE <= '1';
				OUT_DATA <= d_out;
				nstate <= init;
			when scan_data =>
				PC_INC <= '1';
				IN_REQ <= '1';
				nstate <= wait_for_data;
			when wait_for_data =>
				if (IN_VLD = '0') then
					IN_REQ <= '1';
					nstate <= wait_for_data;
				else
					DATA_EN <= '1';
					DATA_RDWR <= '1';
					nstate <= init;
				end if;
			when left_bracket =>
				PC_INC <= '1';
				if(USE_DATA = "00000000") then
					WHILE_INC <= '1';
					PC_LD <= '1';
					DATA_EN <= '1';
					nstate <= next_inst;
				else
					nstate <= init;
				end if;
			when next_inst =>
				PC_INC <= '1';
				DATA_EN <= '1';
				INST <= DATA_RDATA;
				nstate <= end_while_check;
			when end_while_check =>
				if(WHILE_C = "0000000000000") then
					nstate <=get_inst;
				else
					if(INST = X"5B") then
						WHILE_INC <= '1';
						
					elsif(INST = X"5D") then
						WHILE_DEC <= '1';
					end if;
					PC_LD <= '1';
					DATA_EN <= '1';
					nstate <= next_inst;
				end if;
			when right_bracket =>
				if(USE_DATA = "00000000") then
					PC_INC <= '1';
					nstate <= init;
				else
					WHILE_INC <= '1';
					PC_DEC <= '1';
					nstate <= decrement;
				end if;
			when decrement =>
				PC_LD <= '1';
				DATA_EN <= '1';
				nstate <= inst_load;
			when inst_load =>
				DATA_EN <= '1';
				INST <= DATA_RDATA;
				nstate <= while_check;
			when while_check =>
				if(WHILE_C = "0000000000000") then
					nstate <= get_inst;
				else
					if (INST = X"5D") then
						WHILE_INC <= '1';
					elsif (INST = X"5B") then
						WHILE_DEC <= '1';
					end if;
					nstate <= while_check2;
				end if;
			when while_check2 =>
					if (WHILE_C = "0000000000000") then
						PC_INC <= '1';
						nstate <=init;
					else
						PC_DEC <= '1';
						PC_LD <= '1';
						DATA_EN <= '1';
						nstate <= inst_load;
					end if;
					
			when store_to_tmp =>
				PC_INC <= '1'; 
				TMP_LD <= '1';
				W_OPTION <= "11";
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				nstate <= init;
			when store_to_ptr =>
				PC_INC <= '1';
				USE_DATA <= DATA_RDATA;
				nstate <= write_it;
			when write_it =>
				W_OPTION <= "11";
				DATA_EN <= '1';
				DATA_RDWR <= '1';
				nstate <= init;
					
			when state_continue =>
				PC_INC <= '1';
				nstate <= init;
			when state_end =>
				nstate <= state_end;
			when others =>
				nstate <= state_end;
			end case;
				
		
	end process;
 
 
end behavioral;
 
