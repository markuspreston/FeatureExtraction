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
USE STD.TEXTIO.ALL;

-- Using arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- library containing some defined data types used in the code:
use work.my_types.all;

entity baseline_calculator is
	Generic ( THRESHOLD_RISING : integer := 3;                            -- Set the (fixed) threshold that the smoothed signal has to go above. When this happens, the baseline calculator will go into state 'sleeping'
            THRESHOLD_FALLING : integer := 3;                          -- Set the (fixed) threshold that the smoothed signal has to go below to release the trigger.
            PULSE_WIDTH_BEFORE_RESET : integer := 50);                  --the number of samples that MUST have passed since the original baseline trigger before the state can go from sleeping -> awake. Used to avoid taking undershoots into account (i.e. in experimental data there might not be 100% pole-zero cancellation, so there could be some undershoot, or baseline shift)
    Port ( clk : in STD_LOGIC;                                          -- the clock that drives everything
           data_in : in t_sample_buffer;                                -- this is raw data (but is kept in a buffer set up in the 'main' program)
           of_final_trigger : in std_logic;                             -- '1' if the OF has identified A and tau (and sent those out). '0' otherwise
           average_out : out integer range 0 to 65535;                  -- The 2-sample MA data
           baseline_out : out integer range 0 to 65535;                 -- The 16-sample MA, used for the baseline.
           baseline_state : out t_baseline_state;                       -- the state of the baseline determination ('setup' during initialisation (no trigger can be issued then), 'awake' when calculating baseline from avg, 'sleeping' when a trigger has been issued and the baseline should be locked.
           trigger : out std_logic := '0');                             -- The trigger signal, issued when the 2-sample MA goes above the fixed threshold.
end baseline_calculator;


architecture Behavioral of baseline_calculator is

signal r_current_average : unsigned(16 downto 0);                       -- Will contain the latest calculated 2-MA value.

signal r_baseline_state : t_baseline_state := setup;
signal r_baseline_setup_counter : integer := 0; 
signal r_baseline_buffer : t_baseline_buffer;

signal r_current_baseline : unsigned(19 downto 0);                      -- Will contain the latest calculated 16-MA value (i.e. the baseline)

signal r_final_trigger_counter : integer := 0;            -- will be incremented by one every clock cycle after getting latest final trigger from OF. Reset when going into awake.
type t_final_trigger_counter_state is (idle, counting);		-- will go into 'counting' when the OF has issued its final trigger. This state variable keeps track of when r_final_trigger_counted is incremented after this has happened.
signal r_final_trigger_counter_state : t_final_trigger_counter_state := idle;		-- initialise

begin




-- process to count number of clock cycles after the OF final trigger. After this counter reaches PULSE_WIDTH_BEFORE_RESET, new data can be put into the baseline buffer
final_trigger_count : process(clk)
begin
    if rising_edge(clk) then
        case r_final_trigger_counter_state is
            when idle =>
                r_final_trigger_counter <= 0;
                
                if (of_final_trigger = '1') then
                    r_final_trigger_counter_state <= counting;
                end if;
            when counting =>
                if (of_final_trigger = '1') then
                    r_final_trigger_counter <= 0;
                else
                    r_final_trigger_counter <= r_final_trigger_counter + 1;
                end if;
            
                
                
                if (r_final_trigger_counter > PULSE_WIDTH_BEFORE_RESET) then
                    r_final_trigger_counter_state <= idle;
                end if;
        end case;
    end if;
end process;


sequential : process(clk)
    variable v_average_sum : integer;
    variable v_baseline_sum : integer;

begin
    if rising_edge(clk) then
        v_average_sum := to_integer(data_in(0)) + to_integer(data_in(1));                       -- sum the latest to elements in the data_in buffer.
	r_current_average <= shift_right(to_unsigned(v_average_sum, 17), 1);                    -- divide by two (i.e. 1-bit right shift). This forms a 2-sample moving average
        
        

        
        
        case r_baseline_state is
            when setup =>
                r_baseline_setup_counter <= r_baseline_setup_counter + 1;
                        
                if (r_baseline_setup_counter = 25) then                                             -- assume that we need 25 samples to reach a proper baseline estimate (i.e. there should be no pulse in this range). After this, the state goes to 'awake'
                    r_baseline_state <= awake;
                end if;

                v_baseline_sum := r_baseline_buffer(0) + r_baseline_buffer(1) + r_baseline_buffer(2) + r_baseline_buffer(3) + r_baseline_buffer(4) + r_baseline_buffer(5) + r_baseline_buffer(6) + r_baseline_buffer(7) + r_baseline_buffer(8) + r_baseline_buffer(9) + r_baseline_buffer(10) + r_baseline_buffer(11) + r_baseline_buffer(12) + r_baseline_buffer(13) + r_baseline_buffer(14) + r_baseline_buffer(15);          -- sum the latest 16 samples in the baseline buffer
                r_current_baseline <= shift_right(to_unsigned(v_baseline_sum, 20), 4);          -- divide by 16 (i.e. 4-bit right shift)
                
                r_baseline_buffer(20 downto 1) <= r_baseline_buffer(19 downto 0);               -- after we have calculated the baseline from the latest 16 values in the baseline buffer, insert the latest new sample from the data_in buffer into the baseline buffer (i.e. shift all content up and insert one element at zero)
                r_baseline_buffer(0) <= to_integer(data_in(0));
            when awake =>
                if (to_integer(r_current_average) - to_integer(r_current_baseline) > THRESHOLD_RISING) then       -- I.e. the 2-sample MA goes above the trigger threshold - trigger.
                    v_baseline_sum := r_baseline_buffer(5) + r_baseline_buffer(6) + r_baseline_buffer(7) + r_baseline_buffer(8) + r_baseline_buffer(9) + r_baseline_buffer(10) + r_baseline_buffer(11) + r_baseline_buffer(12) + r_baseline_buffer(13) + r_baseline_buffer(14) + r_baseline_buffer(15) + r_baseline_buffer(16) + r_baseline_buffer(17) + r_baseline_buffer(18) + r_baseline_buffer(19) + r_baseline_buffer(20);         -- to avoid including any signal rising edge in the baseline estimate, go back 5 samples into the baseline buffer and fetch the 16 samples starting from there. These will be used in a new baseline estimate.
                    r_current_baseline <= shift_right(to_unsigned(v_baseline_sum, 20), 4);              -- divide the selected values by 16.
    
                    r_baseline_buffer(15 downto 0) <= r_baseline_buffer(20 downto 5);                   -- take the "delayed" baseline data and put them first in the baseline buffer (i.e. throw away elements 4 downto 0, as these could be compromised by rising-edge data)
                    
                    -- set the trigger to '1', and go into sleeping mode.                    
                    trigger <= '1';
                    r_baseline_state <= sleeping;
                    
                else            -- the data does NOT exceed the threshold. Update the baseline estimate.
                    if (r_final_trigger_counter_state = idle) then          -- only put data into the baseline buffer if a sufficient number of clk cycles have passed since the last final_trigger. Done to avoid counting undershoot (potential expt artifact) into the baseline estimate
                        v_baseline_sum := r_baseline_buffer(0) + r_baseline_buffer(1) + r_baseline_buffer(2) + r_baseline_buffer(3) + r_baseline_buffer(4) + r_baseline_buffer(5) + r_baseline_buffer(6) + r_baseline_buffer(7) + r_baseline_buffer(8) + r_baseline_buffer(9) + r_baseline_buffer(10) + r_baseline_buffer(11) + r_baseline_buffer(12) + r_baseline_buffer(13) + r_baseline_buffer(14) + r_baseline_buffer(15);
                        r_current_baseline <= shift_right(to_unsigned(v_baseline_sum, 20), 4);
                        
                        -- Update the baseline, same as above (under 'setup')
                        r_baseline_buffer(20 downto 1) <= r_baseline_buffer(19 downto 0);
                        r_baseline_buffer(0) <= to_integer(data_in(0));
                    end if;                        
                

                end if;
            when others =>      -- i.e. sleeping
                if ((to_integer(r_current_average) - to_integer(r_current_baseline) < THRESHOLD_FALLING)) then              -- if the data goes below a fixed level, make detection of new signals possible.
                    trigger <= '0';     -- reset trigger
                    r_baseline_state <= awake;

                end if;
        end case;
        
    end if; 

            
end process;

-- These three signals go out, and are used by other parts of the code:
average_out <= to_integer(r_current_average(15 downto 0));
baseline_out <= to_integer(r_current_baseline(15 downto 0));
baseline_state <= r_baseline_state;


end Behavioral;
