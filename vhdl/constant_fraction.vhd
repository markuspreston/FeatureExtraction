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
-- Source location: XXXXXX
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

entity constant_fraction is
    Generic (CFD_DELAY : integer := 2;                                  -- the CFD delay parameter. Note that the CFD attenuation factor is set to 0.5 (division by 2) below.
            THRESHOLD_CFD : integer := 5);                            -- Set the (fixed) threshold that the derivative of the CFD at the zero crossing has to be larger than
    Port ( clk : in STD_LOGIC;
       data_in : in t_sample_buffer;                                    -- the raw data
       baseline : in t_baseline_sel_buffer;                             -- the current baseline buffer. Comes from the baseline selector, which sends out either the 16-sample MA baseline or a reconstructed tail (if a preceding pulse has been detected)
       baseline_state : in t_baseline_state;                            -- the baseline state (i.e. 'setup', 'awake' or 'sleeping')
       cfd_time : out integer;                                          -- will return the # of the determined BCFD zero-crossing interval. That is, cfd_time is either '1', '2', '3' or '4' in this implementation, since there are four sub-sample intervals.
       data_out : out integer);                                          -- the actual CFD signal (i.e. the sum of the delayed and the attenuated+inverted)
end constant_fraction;

architecture Behavioral of constant_fraction is


-- these four signals are only used for diagnostics/debugging purposes (i.e. to see the different components that make up the complete CFD signal). They are not used in the actual calculations
signal r_baseline_subtracted : integer;
signal r_baseline_subtracted_delayed : integer;
signal r_inverted : integer;
signal r_delayed : integer;

signal r_cfd : integer := 0;                            -- the actual CFD signal value




signal r_cfd_buffer : t_cfd_buffer;                         -- a 2-sample buffer, which keeps the previous two calculated CFD values. Used to find the zero-crossing sample: check if r_cfd_buffer[1] < 0 and r_cfd_buffer[0] >= 0.


signal r_bisection : integer := 0;                          -- will be the (internal) signal telling which of the four sub-sample intervals the zero crossing is in.

signal r_cfd_state : t_cfd_state := waiting;                -- can be either 'waiting' or 'triggered'. Only goes into 'triggered' on the sample where the zero crossing has occured. Then, the BCFD interval is located.





begin


sequential : process(clk)


-- in the BCFD algorithm, evaluate the linear interpolation at fixed sub-sample intervals. This is done by splitting the sample into finer and finer regions. The y0prime and y1prime values will be updated to keep the evaluated y values.
variable v_y0prime : signed(15 downto 0);
variable v_y1prime : signed(15 downto 0);

begin
    if rising_edge(clk) then
        r_cfd_buffer(1) <= r_cfd_buffer(0);             -- Update the CFD buffer (push first element back by one, put in latest r_cfd data).
        r_cfd_buffer(0) <= r_cfd;
        
        -- Here, the actual CFD signal is calculated. This is the delayed raw data (minus the equally delayed baseline) MINUS the attenuated (non-delayed) baseline-subtracted data. Note how the attenuation is performed using a 1-bit right shift (i.e. division by two). This is where the CFD attenuation factor f=0.5 comes in!
        r_cfd <= to_integer(data_in(CFD_DELAY)) - baseline(CFD_DELAY) - to_integer(shift_right(to_signed(to_integer(data_in(0)) - baseline(0), 17), 1));        -- the baseline is the same for the delayed and attenuated sample IF this is not a piled-up pulse. If it is a piled-up pulse, then the baseline will be different depending on where on the tail of the preceding pulse this pulse arrives.
        
        
        if ((r_cfd_state = waiting) and (baseline_state = sleeping)) then                   -- i.e. if a trigger signal is issued from the baseline_calculator and we're not in the middle of a CFD calculation
            case r_bisection is
                when 0 =>               -- this is the default case, i.e. when we have not yet found the BCFD interval.
                    if ((r_cfd_buffer(0) < 0) and (r_cfd >= 0)) then                -- there is a CFD zero crossing.
		        if (r_cfd - r_cfd_buffer(0) > THRESHOLD_CFD) then                  -- Check the 'derivative', i.e. the difference between the first CFD sample above zero and the previous one. If it's a fake trigger (for example due to noise), then this difference should be small. So, require it to be large, over some threshold.
                            r_cfd_state <= triggered;
                            
                            
                            -- Now, the BCFD algorithm should try to find the zero-crossing interval.
                            
                            
			    v_y0prime := shift_right(to_signed(r_cfd_buffer(0), 16) + to_signed(r_cfd, 16), 1);             -- Evaluate the CFD linear interpolation at 50% of the sample width. To do that, redefine sample width to be 4 and t=0 at the previous sample. Then, using a standard linear interpolation we have (y-y0)/(x-x0) = (y1-y0)/(x1-x0). We know y0 = r_cfd_buffer(0) and y1 = r_cfd. x0 = 0 and x1 = 4, and x = 2 (since we're first looking at half the sample). Then, (y-y0) = 2*(y1-y0)/4 = (y1-y0)/2 => y = y1/2 + y0/2 = (y0 + y1)/2. y in this case is what I call y0prime. Here, I compare the previous CFD value with the newest one and divide by two, to find the (lin. interpolated) CFD value at 50%. This will be the y0prime value.
                            
                            if (v_y0prime < 0) then         -- intersection in second half of sample. Use y0prime as new y0
			        v_y1prime := shift_right(v_y0prime + to_signed(r_cfd, 16), 1);                              -- Do same thing again (with updated y0 value, but keeping old y1). Split this interval in two and find the (interpolated) CFD val at 50% of this (i.e. 75% of the original sample width). Always the interval width is defined as 4, meaning that half-way is 2.
                                
                                if (v_y1prime < 0) then      -- intersection in second half of second half
                                    r_bisection <= 4;
                                else
                                    r_bisection <= 3;	     -- intersection in first half of second half
                                end if;
                            else                            -- intersection in first half of sample. Use y0prime as new y1
                                v_y1prime := shift_right(to_signed(r_cfd_buffer(0), 16) + v_y0prime, 1);                    -- Do same as above, but now look at 25% of the orignal sample width
                                
                                if (v_y1prime < 0) then      -- intersection in second half of first half
                                    r_bisection <= 2;
                                else
                                    r_bisection <= 1;		-- intersection in first half of first half
                                end if;
                            end if;
                        end if;
                    else
                        r_bisection <= 0;                   -- again, this is the default value.
                    end if;
                when others =>
                        -- do nothing...
            end case;
        else
                -- do nothing...
        end if;
        
        
        if (r_cfd_state = triggered) then                   -- that is, the BCFD algorithm was triggered on the previous sample, reset the CFD state and the bisection value.
            r_cfd_state <= waiting;
            r_bisection <= 0;
        end if;
        
    end if;
    
    

end process;

-- these are just used for diagnostics/debugging, as stated above.
r_baseline_subtracted <= to_integer(data_in(0)) - baseline(0);
r_baseline_subtracted_delayed <= to_integer(data_in(CFD_DELAY)) - baseline(CFD_DELAY);
r_inverted <= -to_integer(shift_right(to_signed(to_integer(data_in(0)) - baseline(0), 17), 1));
r_delayed <= to_integer(data_in(CFD_DELAY)) - baseline(CFD_DELAY);


--- Outputs:
cfd_time <= r_bisection;                    -- the BCFD zero-crossing interval (1, 2, 3, or 4)
data_out <= r_cfd;                          -- the actual CFD data



end Behavioral;
