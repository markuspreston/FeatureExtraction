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

-- Using arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- library containing some defined data types used in the code:
use work.my_types.all;

entity baseline_selector is
    Port ( clk : in STD_LOGIC;
       baseline_from_average : in integer range 0 to 65535;                     -- the baseline, as calculated using the 16-sample MA in baseline_calculator
       reconstructed_pulse_0 : in t_reconstructed_pulse;                        -- the reconstructed pulse from the optimal_filter.
       OF_state : in t_OF_state;                                                -- the OF state, i.e. either 'waiting', 'triggered_pulse_0' or 'triggered_pulse_1'.
       baseline_out : out t_baseline_sel_buffer := (others => 0));              -- the baseline that is sent out. Will be selected by this code.
end baseline_selector;

architecture Behavioral of baseline_selector is

signal baseline_temp : t_baseline_sel_buffer := (others => 0);		-- signal to keep the baseline data.

begin



sequential : process(clk)

variable v_buffer_fill_counter : integer := 0;

begin
    if rising_edge(clk) then
        if (OF_state = waiting) then			-- i. e. no detection signalled by the OF.
            baseline_temp(8 downto 0) <= (others => baseline_from_average);                         -- use the 16-sample MA baseline
        elsif (OF_state = triggered_pulse_0) then	-- a pulse has been found by the OF. Tail should be reconstructed.
            for i in 0 to 8 loop
                baseline_temp(i) <= baseline_from_average + reconstructed_pulse_0(i);             -- Get the baseline from the one calculated pre-trigger (the 16-sample MA) PLUS the reconstructed tail. This is done if the OF has identified a pulse, which should then be subtracted.
            end loop;
        else
            baseline_temp(8 downto 0) <= (others => baseline_from_average);                          -- use the 16-sample MA baseline
        end if;
    end if;
end process;

baseline_out <= baseline_temp;			-- send out the correct baseline


end Behavioral;
