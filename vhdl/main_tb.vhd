-- Copyright (C) 2021 Markus Preston
-- This source describes Open Hardware and is licensed under the CERN-OHL-W v2 or later
-- You may redistribute and modify this documentation and make products
-- using it under the terms of the CERN-OHL-W v2 or later (https:/cern.ch/cern-ohl).
--
-- This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED
-- WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY
-- AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN-OHL-W v2
-- for applicable conditions.
--
-- Source location: https://github.com/markuspreston/FeatureExtraction/
-- As per CERN-OHL-W v2 section 4.1, should You produce hardware based on
-- these sources, You must maintain the Source Location visible on the
-- external case of the hardware or other product you make using
-- this documentation.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_TEXTIO.ALL;
USE STD.TEXTIO.ALL;
use IEEE.numeric_std.all;


-- This is the test bench, i. e. the simulation code. Here, the input file input_data.csv (from generate_pulse_data.py) is clocked in as input to the main program. Also here is where the output of the VHDL code is written to output_data.csv.

entity main_tb is
          Generic ( );
--  Port ( );
end main_tb;

architecture Behavioral of main_tb is

	-- defining the main part of the VHDL code. These are the output signals that may be used in the simulation.
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

    -- internal signals:
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
    


   
    -- Because the actual timing of the samples in the testbench simulation doesn't matter (we are only clocking in  and out data at one frequency, we make the clock period *unrealistically short* here (i. e. 0.25 ns). This is to limit the size of a temporary .xilwvdat file which is produced during simulation. The size of this file can become significant if simulating a large number of waveforms.
    constant period: time := 0.25 ns;         -- the inverse of the sampling frequency. For sampling frequency of 160 MHz, period is 6.25 ns
    
    

begin

	-- map ports to main.vhd
    UUT: main port map(clk => clk, ready => ready, data_in => data_from_file, average_out => average_out, baseline_out => baseline_out, cfd_out => cfd_out, cfd_time => cfd_time, trigger => trigger, u_out => of_u, v_out => of_v, final_trigger_out => final_trigger);
    
    
    -- to generate the clock:
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
            counter <= counter + 1;		-- used as timestamp
        end if;

    
    end process;
    
    
    -- the actual input/output I/O:
    file_io: PROCESS is
	    FILE in_file : TEXT;			-- the actual input file (from generate_pulse_data.py)
        VARIABLE in_line : LINE;		-- the line from input file
        variable str_stimulus_in: integer;	-- the signal data from the input file (i. e. the actual data)
        
        FILE out_file : TEXT;			-- the output file (to be analysed by reconstruct_A_and_T.py)
        VARIABLE out_line : LINE;
        

	-- Here, specify the locations of the input data (from generate_pulse_data.py) and output data (to be analysed by reconstruct_A_and_T.py). Note: absolute paths needed. Set the length of the string (e.g. (1 to 41) to match the actual length of the string
        variable INPUT_FILE_NAME : string(1 to 41) := "/home/markus/Dokument/Work/input_data.csv";
        variable OUTPUT_FILE_NAME : string(1 to 42) := "/home/markus/Dokument/Work/output_data.csv";        
                
    BEGIN
    


    
    --- NOTE ABOUT SIMULATION TIME:
    -- the assumed sampling period is 0.25 ns, and the first 100 samples are always empty (in the generated data, to allow time for FPGA setup).
    -- also, each event currently consists of 100 samples.
    -- Therefore, if you want to analyse N events with the VHDL code, you need to run the simulation for 0.25*100*(N + 1) ns
    -- For example, to analyse 10000 events, simulate for 0.25*100*(10000 + 1) ns = 250025 ns

    -- Set up the input and output:
    -- The input should be a file containing the sampled voltage every clock cycle every row.

    file_open(in_file,INPUT_FILE_NAME,READ_MODE);
    file_open(out_file,OUTPUT_FILE_NAME,WRITE_MODE);
    
    
    WHILE NOT ENDFILE(in_file) LOOP --do this till out of data
    
        wait until rising_edge(clk);
    
        READLINE(in_file, in_line);        --get line of input stimulus
        READ(in_line, str_stimulus_in);    --get first operand
        
	data_from_file <= std_logic_vector(to_unsigned(str_stimulus_in, 16));		-- the actual sampled data (here, specify the number of bits to represent that data - 16 in this case)
        
        
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
