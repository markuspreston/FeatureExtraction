-- Copyright (C) 2021 Markus Preston
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

----------------------------------------------------------------------------------
-- Company: Stockholm University
-- Engineer: Markus Preston
-- 
-- Create Date: 06.08.2019 14:05:48
-- Design Name: 
-- Module Name: main_tb - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_TEXTIO.ALL;
USE STD.TEXTIO.ALL;
use IEEE.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;




--- Note: you should specify the filename of the first and second pile-up pulses, and also the time difference between the two pulses here:

entity main_tb is
          Generic ( RUN_NUMBER_1 : string(1 to 9) := "100417730";
                    RUN_NUMBER_2 : string(1 to 9) := "n00000030";                  
                    PILEUP_DEGREE : string(1 to 2) := "40");
--  Port ( );
end main_tb;

architecture Behavioral of main_tb is

    component main
        Port ( clk : in STD_LOGIC;
               ready : in STD_LOGIC;
               data_in : in STD_LOGIC_VECTOR (15 downto 0);
               average_out : out integer range 0 to 65535;
               baseline_out : out integer range 0 to 65535;
               cfd_out : out integer;
               cfd_time : out integer;
               trigger : out std_logic;
               u_out : out integer;
               v_out : out integer;
               final_trigger_out : out std_logic);
    end component;

    signal clk : std_logic := '0';
    signal ready : std_logic := '0';
    signal data_from_file : std_logic_vector(15 downto 0);
    signal average_out : integer range 0 to 65535;
    signal baseline_out : integer range 0 to 65535;
    signal cfd_out : integer;
    signal cfd_time : integer;
    signal trigger : std_logic;
    signal of_u : integer;
    signal of_v : integer;
    
    
    
    signal final_trigger : std_logic;

    signal counter : integer := 0;
    
    signal data_test : std_logic;


   
    -- MAKING THE CLOCK PERIOD UNREALISTICALLY SHORT HERE: This is to limit the size of the .xilwvdat temporary file (appears to depend on the actual simulated time, rather than number of clock cycles)
    constant period: time := 0.25 ns;         -- the inverse of the sampling frequency. For sampling frequency of 160 MHz, period is 6.25 ns
    
    signal test1 : integer := 0;
    

begin

    UUT: main port map(clk => clk, ready => ready, data_in => data_from_file, average_out => average_out, baseline_out => baseline_out, cfd_out => cfd_out, cfd_time => cfd_time, trigger => trigger, u_out => of_u, v_out => of_v, final_trigger_out => final_trigger);
    
    
    set_ready: process is
    begin
        wait for 1 ns;
        ready <= '1';
    end process;
    
    clock: process(clk)
    begin
        clk <= not clk after period/2;
    end process;
    
    read_data: process(clk)
    begin
        if rising_edge(clk) then
            counter <= counter + 1;
        end if;

    
    end process;
    
    
    file_io: PROCESS is
        FILE in_file : TEXT;
        VARIABLE in_line : LINE;
        VARIABLE a,b,c : STD_LOGIC;
        variable str_stimulus_in: integer;
        
        FILE out_file : TEXT;
        VARIABLE out_line : LINE;
        

        variable INPUT_FILE_NAME : string(1 to 41) := "/home/markus/Dokument/Work/input_data.csv";
        variable OUTPUT_FILE_NAME : string(1 to 42) := "/home/markus/Dokument/Work/output_data.csv";        
                
    BEGIN
    


    
    --- NOTE ABOUT SIMULATION TIME:
    -- since the sampling period is 6.25 ns, and the first 100 samples are always empty (in the generated data, to allow time for FPGA setup).
    -- also, each event currently consists of 100 samples.
    -- Therefore, if you want to analyse N events with the VHDL code, you need to run the simulation for 6.25*100*(N + 1) ns
    -- For example, to analyse 10000 events, simulate for 6.25*100*(10000 + 1) ns = 6250625 ns
    -- To analyse 50000 events, simulate for 6.25*100*(50000 + 1) ns = 31250625 ns
    -- One can also use a shorter sampling period (as I have defined above as 0.25 ns). For the simulation, this does not matter since everything (reading and writing data) is done on every clock cycle. This is just to decrease the size of temp. files produced by Vivado (and possibly to speed up the sim.)

    -- Set up the input and output:
    -- The input should be a file containing the sampled voltage every clock cycle every row.

    file_open(in_file,INPUT_FILE_NAME,READ_MODE);
        

    file_open(out_file,OUTPUT_FILE_NAME,WRITE_MODE);
    
    
    WHILE NOT ENDFILE(in_file) LOOP --do this till out of data
    
        wait until rising_edge(clk);
    
        READLINE(in_file, in_line);        --get line of input stimulus
        READ(in_line, str_stimulus_in);    --get first operand
        
        test1 <= str_stimulus_in;
        
        data_test <= a;
        
        data_from_file <= std_logic_vector(to_unsigned(str_stimulus_in, 16));
        
        
        -- Write output to a text file - much of this is just for diagnostics/debugging. The most interesting are final_trigger (issued whenever the full algorithm has identified and processed a pulse), cfd_time (the BCFD window), of_u and of_v (contain the results of the OF - i.e. the final estimates on A and A*tau).
        

        WRITE(out_line, counter);                       -- Keeps track of the clock-cycle number
        WRITE(out_line, ',');
        WRITE(out_line, str_stimulus_in);               -- The data used as input to the algorithm (i.e. coming from the Geant4 model)
        WRITE(out_line, ',');
        WRITE(out_line, average_out);
        WRITE(out_line, ',');
        WRITE(out_line, baseline_out);
        WRITE(out_line, ',');
        WRITE(out_line, trigger);
        WRITE(out_line, ',');
        WRITE(out_line, cfd_out);                       
        WRITE(out_line, ',');
        WRITE(out_line, cfd_time);                      -- the BCFD window/interval (i. e. 1, 2, 3 or 4)
        WRITE(out_line, ',');     
        WRITE(out_line, of_u);                          -- the result of the first OF calculation, i.e. the amplitude
        WRITE(out_line, ',');
        WRITE(out_line, of_v);                          -- the result of the second OF calculation, i.e. the amplitude*tau (A*tau)
        WRITE(out_line, ',');
        WRITE(out_line, final_trigger);                 -- the final trigger (issued by the OF when pulse is identified and processed (see Fig. 11.6 in thesis, where it is referred to as the "pulse trigger").
        WRITELINE(out_file, out_line);
        
        
        
    END LOOP;
    
    file_close(in_file);
    file_close(out_file);
    
    WAIT; --allows the simulation to halt!
    END PROCESS;
    
    
    


end Behavioral;
