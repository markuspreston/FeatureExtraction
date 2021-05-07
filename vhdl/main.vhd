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



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Using arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- library containing some defined data types used in the code:
use work.my_types.all;

entity main is
    Port ( clk : in STD_LOGIC;
           ready : in STD_LOGIC;                                -- 0 if not yet ready for data. 1 if ready to take data.
           data_in : in STD_LOGIC_VECTOR (15 downto 0);		-- the sampled data from the detector (or sim)
	   average_out : out integer range 0 to 65535;		-- for debugging - the average used in the baseline calculator
	   baseline_out : out integer range 0 to 65535;		-- for debugging - the baseline from baseline calculator
	   cfd_out : out integer;				-- for debugging - the CFD signal calculated from the data
           cfd_time : out integer;				-- the BCFD window where the CFD zero crossing was found
	   trigger : out std_logic;				-- for debugging - the 'trigger' signal from the baseline calculator
           u_out : out integer;					-- the first output from the OF. u = A
           v_out : out integer;					-- the second output from the OF. v = A*tau
	   final_trigger_out : out std_logic);			-- the 'final trigger' signals that a pulse has been successfully identified and processed. Can be used to trigger readout of data.
end main;

architecture Behavioral of main is

    -- below are signals used internally here, mainly to couple different components to each other or to convey the signals to outputs of the main
	signal r_sample_buffer : t_sample_buffer := (others => (others => '0'));	-- the sampled data (from a detector or such) will be stored in a buffer with a length defined in my_types.vhd (the t_sample_buffer type). Necessary because it can be needed to acquire earlier samples (for example to calculate the OF). Initialise to all zeros here. t_sample_buffer is a 17-element array of 16-bit integers (the data from the ADC is stored in 16-bit representation, although the actual data may be fewer bits)



    signal clk_counter : unsigned(63 downto 0) := (others => '0');                  -- used for debugging, to see counter updated every clk in simulation
    
    signal r_baseline_state : t_baseline_state;					-- stores the state of the baseline calculator (can be 'setup', 'awake' or 'sleeping'). 'setup' when the algorithm is initialising (takes a number of samples to stabilise at an estimate for the baseline). 'awake' when actually calculating the baseline. 'sleeping' when a pulse is being processed and no new baseline should be calculated.
    signal baseline_from_average : integer range 0 to 65535;			-- stores the baseline calculated by the moving average in baseline_calculator
    signal baseline : t_baseline_sel_buffer;					-- stores the actual baseline (from baseline_selector). This value will be used by other components (CFD, OF), and is held in the type t_baseline_sel_buffer (defined in my_types.vhd)
    signal cfd_time_output : integer;						-- stores the BCFD window of the CFD zero crossing
    signal cfd_output : integer;						-- stores the actual CFD signal
    signal of_u_output : integer;						-- stores the OF output u (=A)
    signal of_v_output : integer;						-- stores the OF output v (=A*tau)
    
    signal OF_state : t_OF_state := waiting;					-- stores the state of the OF. Initialise as 'waiting', but can be 'waiting', 'triggered_pulse_0' or 'triggered_pulse_1' (to denote whether a pulse has been detected by the OF. Declared in main because the OF trigger is needed by the baseline_selector (to know whether to reconstruct pulse tail)
    
    signal reconstructed_pulse_0 : t_reconstructed_pulse;			-- stores the reconstructed pulse (from the optimal_filter). Needed here because the reconstructed pulse is used by the baseline_selector.
    
    
    signal of_final_trigger : std_logic;					-- set to '1' if the OF has identified a pulse (which is reasonable). Defined here because the OF trigger is used by the baseline_calculator (because the baseline_calculator starts to calculate the baseline from average a certain number of samples after the last pulse, to avoid the sytem being stuck in a state)
    
    --- Define the different components used:

    -- Baseline selector: use either the baseline from moving average *or* a reconstructed pulse tail
    component baseline_selector is
        Port ( clk : in STD_LOGIC;
           baseline_from_average : in integer range 0 to 65535;
           reconstructed_pulse_0 : in t_reconstructed_pulse;
           OF_state : in t_OF_state;
           baseline_out : out t_baseline_sel_buffer);
    end component;
    
    -- Baseline calculator: calculate the baseline using a moving average. Paused when the input data exceeds some threshold.
    component baseline_calculator
        Port ( clk : in STD_LOGIC;
               data_in : in t_sample_buffer;
               of_final_trigger : in std_logic;
               average_out : out integer range 0 to 65535;
               baseline_out : out integer range 0 to 65535;
               baseline_state : out t_baseline_state;
               trigger : out std_logic);
    end component;
    
    -- The CFD algorithm, used to determine the BCFD zero crossing window.
    component constant_fraction
        Port ( clk : in STD_LOGIC;
               data_in : in t_sample_buffer;
               baseline : in t_baseline_sel_buffer;
               baseline_state : in t_baseline_state;
               cfd_time : out integer;
               data_out : out integer);
    end component;
    
    -- The optimal filter, used to determine the pulse amplitude and phase shift, and to provide the 'final trigger', signalling data ready for readout.
    component optimal_filter is
        Port ( clk : in STD_LOGIC;
       data_in : in t_sample_buffer;
       baseline : in t_baseline_sel_buffer;
       baseline_state : in t_baseline_state;
       cfd_time : in integer;
       OF_state : out t_OF_state;
       u_out : out integer;
       v_out : out integer;
       reconstructed_pulse_0 : out t_reconstructed_pulse;
       final_trigger : out std_logic);
    end component;

    
    
begin
    -- Basically the only thing done in this part of the code (except holding all other components together and sending their data to the simulation testbench, main_tb): Buffer the raw data into the r_sample_buffer. This will then be used by all other parts of the code.

    sequential : process(clk)		-- each clock cycle, push new data into the buffer and push out old data
    begin
        if rising_edge(clk) then
            r_sample_buffer(16 downto 1) <= r_sample_buffer(15 downto 0);
            r_sample_buffer(0) <= unsigned(data_in);
            
            
	    clk_counter <= clk_counter + 1;			-- used for the simulation, to keep track of time
        
        end if;
    end process;
    

    -- The port maps:

    baseline_selector0: baseline_selector port map(clk => clk, baseline_from_average => baseline_from_average, reconstructed_pulse_0 => reconstructed_pulse_0, OF_state => OF_state, baseline_out => baseline);
    
    baseline_calculator0: baseline_calculator port map(clk => clk, data_in => r_sample_buffer, of_final_trigger => of_final_trigger, average_out => average_out, baseline_out => baseline_from_average, baseline_state => r_baseline_state, trigger => trigger);
    
    constant_fraction0: constant_fraction port map(clk => clk, data_in => r_sample_buffer, baseline => baseline, baseline_state => r_baseline_state, cfd_time => cfd_time_output, data_out => cfd_output);
    
    optimal_filter0: optimal_filter port map(clk => clk, data_in => r_sample_buffer, baseline => baseline, baseline_state => r_baseline_state, cfd_time => cfd_time_output, OF_state => OF_state, u_out => of_u_output, v_out => of_v_output, reconstructed_pulse_0 => reconstructed_pulse_0, final_trigger => of_final_trigger);
    
    

    
    baseline_out <= baseline(0);			-- just take the last value of the baseline and send to output (for debugging)
    
    cfd_time <= cfd_time_output;			-- send the BCFD window to output
    cfd_out <= cfd_output;				-- send the CFD signal to output
    
    -- Send the OF outputs to output:
    u_out <= of_u_output;
    v_out <= of_v_output;
    
    final_trigger_out <= of_final_trigger;		-- The final trigger output
    
end Behavioral;
