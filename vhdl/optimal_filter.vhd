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

entity optimal_filter is
    Generic (FIR_LENGTH : integer := 4;                                     -- the number of samples to include in the OF calculation.
             OF_AMPLITUDE_THRESHOLD : integer := 15;                        -- need a lower threshold on the accepted OF amplitude. Was set to correspond to an energy deposition < 3 MeV (EMC threshold) in the current application, but of course depends on the gain used.
             OF_AMPLITUDE_THRESHOLD_FRACTION : integer := 5;              -- I found out that if I set the OF amplitude threshold for triggering to a fixed value (line above), then for big pulses there is a risk that the subtracted tail fluctuates quite a bit (on order of ~2% relative to the amplitude of the first pulse). So, to avoid triggering on these oscillations on the tail (which is not a real pulse), set the threshold to a fraction of the amplitude of pulse 0 (if OF_AMPLITUDE_THRESHOLD_FRACTION = 5, then the relative threshold is 1/(2^5) = 1/32 of the amplitude of pulse 0). This will mean that very small actual pulses on the tail of a large one will be below this threshold, but the probability of such a combination is anyways quite small in a real-life application. One potential idea would be to make this depend on the time since the first pulse, as the oscillations in the reconstruction will be smaller the further away from the first pulse you get. But this is a later idea.
             OF_ALIGNMENT_N_SAMPLES : integer := 7);                        -- When an Optimal Filter trigger has been found, then it's time to start reconstructing the tail of that pulse. In the g_values_1, etc vectors below, the (amplitude normalised) pulse shape values are stored for a *full* pulse. However, due to the setting of the OF and the CFD, the OF trigger will only come once the pulse has gone over it's maximum value. So, it is only necessary to reconstruct the tail under the samples *after* that point. For this reason, one should only start looking into the pulse-shape vectors at some delayed starting point. This is set using this variable, and was found to be 7, if the CFD delay used is 2 samples and 4 samples are used for the OF (although it depends on how the quantised vectors of g and d_g were calculated in the .py scripts). So, one should confirm the value of this shift by looking at the baseline-subtracted data used by the BCFD (after detection of a first pulse, when there should be tail subtraction). That is, this parameter is to somehow "compensate" for the overall latency of the algorithm.
    Port ( clk : in STD_LOGIC;
   data_in : in t_sample_buffer;                                            -- Raw data from detector (buffered)
   baseline : in t_baseline_sel_buffer;                                     -- The current baseline values
   baseline_state : in t_baseline_state;                                    -- The baseline state (can be 'setup', 'awake', 'sleeping')
   cfd_time : in integer;                                                   -- the zero-crossing interval from the BCFD algorithm
   OF_state : out t_OF_state;                                               -- output, the OF state (either 'waiting', 'triggered_pulse_0' or 'triggered_pulse_1'). Determines whether pile-up reconstruction is due.
   u_out : out integer;                                                     -- this is the OF estimate of the amplitude (I use the notation of Cleland&Stern, 1993, i.e. that the first OF sum gives u, which is the amplitude and that the second gives v = A*tau)
   v_out : out integer;                                                     -- the second OF output, v = A*tau
   reconstructed_pulse_0 : out t_reconstructed_pulse;                       -- will contain the reconstructed pulse (for tail subtraction in pile-up reconstruction). Is used by the baseline selector.
   final_trigger : out std_logic);                                          -- set to '1' when the OF has identified a pulse (by determining A and tau)
end optimal_filter;

architecture Behavioral of optimal_filter is


-- Set up some components that I will generate multiple components of. Note how these use the Xilinx Multiplier v12.0 LogiCORE IP, which is not included here, so you need to instantiate those in your own design.
COMPONENT mult_gen_0                             -- based on Optimal Filter method from Cleland and Stern. In my case, I only use first N samples of the actual pulse, to maintain sensitivity to pileups.
  PORT (
    A : IN STD_LOGIC_VECTOR(24 DOWNTO 0);               -- This will be the OF coefficient (here I used quite many bits, so this could be optimised)
    B : IN STD_LOGIC_VECTOR(15 DOWNTO 0);               -- The raw data (S), which go into the OF calculations
    P : OUT STD_LOGIC_VECTOR(40 DOWNTO 0)               -- The resulting product.
  );
END COMPONENT;

-- For reconstructing the tail, you'll also need some multiplications:
COMPONENT Reconstruction_mult_gen                 -- uses the A and A*tau estimates from the OF to calculate a "reconstructed" pulse, which is subtracted from the incoming data. This is done to identify pileups.
  PORT (
    A : IN STD_LOGIC_VECTOR(19 DOWNTO 0);               -- either A or A*tau
    B : IN STD_LOGIC_VECTOR(17 DOWNTO 0);                   -- the (amplitude-normalised) tail template
    P : OUT STD_LOGIC_VECTOR(37 DOWNTO 0)               -- the resulting product.
  );
END COMPONENT;


-- DEFINE THE OF FIR COEFFICIENTS. These come from the get_OF_coefficients.py script.


-- First, the a coefficients (needed for the A estimate). Four sets of coefficients, one for each BCFD zero-crossing interval.
signal FIR_coefficients_a : t_fir_coefficients;
signal FIR_coefficients_a_1 : t_fir_coefficients := (74,  638,  823,  742);
signal FIR_coefficients_a_2 : t_fir_coefficients := ( -54,  557,  866,  828);
signal FIR_coefficients_a_3 : t_fir_coefficients := (-184,  354,  912,  980);
signal FIR_coefficients_a_4 : t_fir_coefficients := (-165,   78,  925, 1158);

signal FIR_coefficients_a_vector : t_fir_coefficients_vector;                       -- vector which will be filled up with the correct set of coefficients (and used by the DSP multiplier)

-- Then, the coefficients b, for the A*tau estimate.
signal FIR_coefficients_b : t_fir_coefficients;
signal FIR_coefficients_b_1 : t_fir_coefficients := (-1240272,  -312121,   374481,   546442);
signal FIR_coefficients_b_2 : t_fir_coefficients := (-1165072,  -528337,   286879,   543618);
signal FIR_coefficients_b_3 : t_fir_coefficients := (-1003735,  -962595,   193180,   659799);
signal FIR_coefficients_b_4 : t_fir_coefficients := (-560924, -1347950,    65231,   775239);

signal FIR_coefficients_b_vector : t_fir_coefficients_vector;




signal FIR_data : t_fir_data;                           -- will be used to store the four samples of data (minus baseline) used in the OF calculations.

-- These are used for the results of the DSP multiplier calculations of the OF FIRs:
signal FIR_product_a : t_fir_product;
signal FIR_product_b : t_fir_product;

-- To get the OF estimates, need to sum up the calculated products. The resulting sums are stored as SUM_A and SUM_B (note that u_out is SUM_A (shifted right by 11 bits to correct for the accuracy in the OF coefficients needed for the A estimate), and v_out is SUM_B shifted right by 11 bits). The 11 bits come from the Get_OF_weights.C script where I selected the quantised coefficients with this accuracy. So, if one changes the accuracy in the OF-coeff quantisation, one has to change the conversion SUM_A => u_out etc.
signal SUM_A : signed(50 downto 0);
signal SUM_B : signed(50 downto 0);


--- HERE ARE THE (copied/pasted) g and g' values (from the get_OF_coefficients.py script). Needed for reconstructing the pulse tail.

signal g_values_1 : t_pulse_shape_values := (0,     0,   161, 28231, 60576, 64469, 54497, 41924, 30941,        22438, 16180, 11674,  8457,  6162,  4520,  3340,  2486,  1864,         1408,  1070,   819,   631,   489,   381,   299,   236,   187,          149,   119,    95,    77,    62,    51,    41,    34,    28,           23,    19,    16,    13,    11,     9,     7,     6,     5,            4,     4,     3,     2,     2,     2,     1,     1,     1,            1,     1,     0,     0,     0,     0,     0,     0,     0,            0,     0,     0,     0,     0,     0,     0,     0,     0,            0,     0,     0,     0,     0,     0,     0,     0,     0,            0,     0,     0,     0,     0,     0,     0,     0,     0,            0,     0,     0,     0,     0,     0,     0,     0,     0,            0);
signal d_g_values_1 : t_pulse_shape_values := ( 0,     0,   632, 11006,  4163, -1421, -3105, -3024, -2438,
       -1826, -1324,  -947,  -675,  -482,  -346,  -249,  -181,  -132,
         -97,   -72,   -54,   -40,   -30,   -23,   -17,   -13,   -10,
          -8,    -6,    -5,    -4,    -3,    -2,    -2,    -1,    -1,
          -1,     0,     0,     0,     0,     0,     0,     0,     0,
           0,     0,     0,     0,     0,     0,     0,     0,     0,
           0,     0,     0,     0,     0,     0,     0,     0,     0,
           0,     0,     0,     0,     0,     0,     0,     0,     0,
           0,     0,     0,     0,     0,     0,     0,     0,     0,
           0,     0,     0,     0,     0,     0,     0,     0,     0,
           0,     0,     0,     0,     0,     0,     0,     0,     0,
           0);



signal g_values_2 : t_pulse_shape_values := (0,     0,     0, 17696, 55590, 65422, 57429, 44903, 33378,
        24274, 17515, 12631,  9139,  6649,  4869,  3591,  2668,  1997,
         1506,  1143,   873,   672,   520,   405,   317,   249,   197,
          157,   125,   101,    81,    65,    53,    43,    35,    29,
           24,    20,    16,    13,    11,     9,     8,     6,     5,
            4,     4,     3,     3,     2,     2,     1,     1,     1,
            1,     1,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0);

signal d_g_values_2 : t_pulse_shape_values := (0,     0,     1, 10461,  6156,  -504, -2931, -3120, -2592,
        -1966, -1434, -1028,  -733,  -523,  -374,  -270,  -195,  -142,
         -105,   -77,   -58,   -43,   -32,   -25,   -19,   -14,   -11,
           -8,    -6,    -5,    -4,    -3,    -2,    -2,    -1,    -1,
           -1,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0);




signal g_values_3 : t_pulse_shape_values := ( 0,     0,     0,  7183, 47135, 65214, 60601, 48529, 36457,
        26631, 19241, 13870, 10024,  7280,  5321,  3916,  2904,  2169,
         1632,  1236,   943,   724,   559,   435,   340,   267,   211,
          167,   134,   107,    86,    70,    56,    46,    37,    31,
           25,    21,    17,    14,    12,    10,     8,     7,     6,
            5,     4,     3,     3,     2,     2,     1,     1,     1,
            1,     1,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0);

signal d_g_values_3 : t_pulse_shape_values := (0,     0,     0,  7419,  8543,   934, -2560, -3185, -2770,
        -2140, -1573, -1132,  -808,  -576,  -412,  -296,  -214,  -156,
         -114,   -84,   -63,   -47,   -35,   -27,   -20,   -15,   -12,
           -9,    -7,    -5,    -4,    -3,    -2,    -2,    -1,    -1,
           -1,    -1,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0);



signal g_values_4 : t_pulse_shape_values := (0,     0,     0,  2002, 38358, 63674, 62787, 51508, 39110,
        28699, 20768, 14971, 10810,  7840,  5722,  4204,  3112,  2320,
         1743,  1318,  1004,   770,   594,   461,   360,   282,   223,
          177,   141,   113,    91,    73,    59,    48,    39,    32,
           26,    22,    18,    15,    12,    10,     8,     7,     6,
            5,     4,     3,     3,     2,     2,     2,     1,     1,
            1,     1,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0);

signal d_g_values_4 : t_pulse_shape_values := (0,     0,     0,  3609, 10157,  2406, -2089, -3180, -2904,
        -2287, -1695, -1224,  -874,  -623,  -445,  -320,  -231,  -168,
         -123,   -90,   -67,   -50,   -38,   -28,   -22,   -16,   -13,
          -10,    -7,    -6,    -4,    -3,    -3,    -2,    -1,    -1,
           -1,    -1,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0,     0,     0,     0,     0,     0,     0,     0,     0,
            0);




signal r_OF_state : t_OF_state := waiting;          -- can be either 'waiting', 'triggered_pulse_0' or 'triggered_pulse_1'

signal pulse_0_counter : integer := 0;          -- this will start counting once the OF has found a pulse
signal pulse_1_counter : integer := 0;          -- this will count after an identified pile-up pulse. Could possibly be used to extend the algorithm to reconstruct further pile-up pulses as well.


-- These will hold the estimates of A (A) and B (A*tau):
signal SUM_A_pulse_0 : signed(50 downto 0) := (others => '0');
signal SUM_A_pulse_1 : signed(50 downto 0) := (others => '0');

signal SUM_B_pulse_0 : signed(50 downto 0) := (others => '0');
signal SUM_B_pulse_1 : signed(50 downto 0) := (others => '0');


-- Holds the reconstructed pulse parameters (g and g')
signal g_value_aligned_pulse_0 : t_g_value_aligned_pulse := (others => (others => '0'));
signal d_g_value_aligned_pulse_0 : t_g_value_aligned_pulse := (others => (others => '0'));


signal Reconstructed_0_g_part : t_Reconstructed_part := (others => (others => '0'));
signal Reconstructed_0_d_g_part : t_Reconstructed_part := (others => (others => '0'));
signal Reconstructed_0 : t_Reconstructed := (others => (others => '0'));



signal r_final_trigger : std_logic := '0';




signal r_cfd_window : t_cfd_window := waiting;

signal r_Amplitude_previous_pulse : signed(50 downto 0) := (others => '0');


signal r_reconstructed_pulse_temp : t_reconstructed_pulse := (others => 0);

begin


-- As soon as there is data from the BCFD, we need to select the correct set of OF coefficients (based on the BCFD zero-crossing interval). These are put into the FIR_coefficients_a_vector and FIR_coefficients_b_vector (for each of the two OF calculations).
process(cfd_time, FIR_coefficients_a_1, FIR_coefficients_a_2, FIR_coefficients_a_3, FIR_coefficients_a_4)
    begin
    for i in 0 to FIR_LENGTH-1 loop
        case cfd_time is
            when 1 =>
                FIR_coefficients_a_vector(i) <= std_logic_vector(to_signed(FIR_coefficients_a_1(i), 25));
            when 2 =>
                FIR_coefficients_a_vector(i) <= std_logic_vector(to_signed(FIR_coefficients_a_2(i), 25));
            when 3 =>
                FIR_coefficients_a_vector(i) <= std_logic_vector(to_signed(FIR_coefficients_a_3(i), 25));
            when 4 =>
                FIR_coefficients_a_vector(i) <= std_logic_vector(to_signed(FIR_coefficients_a_4(i), 25));
            when others =>
                FIR_coefficients_a_vector(i) <= (others => '0');
        end case;
    end loop;
end process;

process(cfd_time, FIR_coefficients_b)
    begin
    for i in 0 to FIR_LENGTH-1 loop
        case cfd_time is
            when 1 =>
                FIR_coefficients_b_vector(i) <= std_logic_vector(to_signed(FIR_coefficients_b_1(i), 25));
            when 2 =>
                FIR_coefficients_b_vector(i) <= std_logic_vector(to_signed(FIR_coefficients_b_2(i), 25));
            when 3 =>
                FIR_coefficients_b_vector(i) <= std_logic_vector(to_signed(FIR_coefficients_b_3(i), 25));
            when 4 =>
                FIR_coefficients_b_vector(i) <= std_logic_vector(to_signed(FIR_coefficients_b_4(i), 25));
            when others =>
                FIR_coefficients_b_vector(i) <= (others => '0');
        end case;
    end loop;
end process;


-- Also, put the correct raw data into the FIR_data vector, for use in the OF calculations. Note that the baseline comes from the baseline_selector, and so can include the tail from a preceeding pulse
process(data_in, baseline)
    begin
    for i in 0 to FIR_LENGTH-1 loop
        FIR_data(i) <= std_logic_vector(to_signed(to_integer(data_in(i+2)) - baseline(i+2), 16));        -- NOTE: The fact that this is 2 samples delayed is due to the latency in calculating the CFD etcetera. I.e., we need to align the FIR output with the CFD window calculation output, and there is some latency there.
    end loop;                                                                                          
end process;


-- Now, generate all the necessary multipliers with the correct inputs (corresponding to the data set above):
GENERATE_MULTIPLIERS_A:
    for i in 0 to FIR_LENGTH-1 generate
        mult_a : mult_gen_0
            PORT MAP (
            A => FIR_coefficients_a_vector(i),
            B => FIR_data(i),
            P => FIR_product_a(i)
            );
    end generate GENERATE_MULTIPLIERS_A;
    
GENERATE_MULTIPLIERS_B:
        for i in 0 to FIR_LENGTH-1 generate
            mult_b : mult_gen_0
                PORT MAP (
                A => FIR_coefficients_b_vector(i),
                B => FIR_data(i),
                P => FIR_product_b(i)
                );
        end generate GENERATE_MULTIPLIERS_B;
        


--- As soon as the OF multiplications are finished, sum them up (to give the final OF estimates for the amplitude and A*tau):
process(FIR_product_a)
    variable sum_temp : signed(50 downto 0) := (others => '0');
    begin
    
    sum_temp := (others => '0');
    
    for i in 0 to FIR_LENGTH-1 loop
        sum_temp := sum_temp + signed(FIR_product_a(i));
    end loop;
    
    SUM_A <= sum_temp;                      -- the final sum
end process;

process(FIR_product_b)
    variable sum_temp : signed(50 downto 0) := (others => '0');
    begin
    
    sum_temp := (others => '0');
    
    for i in 0 to FIR_LENGTH-1 loop
        sum_temp := sum_temp + signed(FIR_product_b(i));
    end loop;
    
    SUM_B <= sum_temp;                      -- the final sum
end process;


-- Calculate u_out and v_out, by shifting right by 11 bits (corresponds to coefficient accuracy set in Get_OF_weights.C). Note: the v_out value (i. e. A*tau) still needs to be divided by a scaling factor to get "real units" for tau in the end. This is done in the reconstruct_A_and_T.py script.
u_out <= to_integer(shift_right(SUM_A, 11));				-- shifted right by 11 bits, because that is the precision of the a coefficients (see get_OF_coefficients.py output). By dividing by 2^11, we end up with an amplitude estimate that has the "true" units.
v_out <= to_integer(shift_right(SUM_B, 11));				-- shifted right by 11 bits. Still has to be divided by the amplitude estimate, and shifted right by 9 bits (because the total scaling factor for b is 20 bits (see get_OF_coefficients.py), leaving 9 bits for the tau part) to get "true" units.




-------------------------------



process(baseline_state, cfd_time, SUM_A)

begin
    if ((baseline_state = setup) or (baseline_state = awake)) then		-- we know that there can be no pulse because the baseline has not triggered. So, initialise the OF state:
        r_OF_state <= waiting;
        r_final_trigger <= '0';

    else
        if (cfd_time > 0 and to_integer(shift_right(SUM_A, 11)) > OF_AMPLITUDE_THRESHOLD and to_integer(shift_right(SUM_A, 11)) > to_integer(shift_right(r_Amplitude_previous_pulse, OF_AMPLITUDE_THRESHOLD_FRACTION))) then            -- only accept the pulse if the amplitude (as determined by the OF) is above some threshold. In the case of a pileup pulse (arriving on tail of preceeding pulse), the amplitude of the second pulse needs to be at least a certain fraction of the first pulse.
            case r_OF_state is
                when waiting =>
                    r_OF_state <= triggered_pulse_0;
                    r_final_trigger <= '1';
	        when triggered_pulse_0 =>			-- meaning that this is now the pile-up pulse that has triggered.
                    r_OF_state <= triggered_pulse_1;
                    r_final_trigger <= '1';                   
                when others =>
                    r_OF_state <= waiting;
                    r_final_trigger <= '0';
            end case;

            case cfd_time is				-- need to know which OF coefficients to apply. Get the BCFD window.
                when 1 =>
                    r_cfd_window <= w1;
                when 2 =>
                    r_cfd_window <= w2;
                when 3 =>
                    r_cfd_window <= w3;
                when 4 =>
                    r_cfd_window <= w4;
                when others =>
                    r_cfd_window <= waiting;
            end case;
        else
            r_final_trigger <= '0';
        end if;
    end if;
end process;

final_trigger <= r_final_trigger;


OF_state <= r_OF_state;



-- Calculate the (aligned) tail template, for subtraction from the already detected pulse.
align_g : process(clk)

begin
    if rising_edge(clk) then
        if (r_OF_state = triggered_pulse_0) then
            if (pulse_0_counter = 0) then
                -- Calculate A and A*tau values to use in the reconstruction calculation:
                SUM_A_pulse_0 <= shift_right(SUM_A, 11);        -- shift by 11 since A is calculated for 11 bits (a[10] in Get_OF_weights.C)
                SUM_B_pulse_0 <= shift_right(SUM_B, 11);        -- shift by 11 since A is calculated for 11 bits. This will result in A*tau, and to get the final estimate one should first divide by the OF u estimate. The result is a number quantised in 9 bits (the value of b_scaling - a_scaling, i.e. the number of bits available to quantise tau). Get this value (9) from get_OF_coefficients.py
                
                r_Amplitude_previous_pulse <= shift_right(SUM_A, 11);
            end if;
            

	    for i in 0 to 3 loop			-- Because the OF has some latency w.r.t. the BCFD algorithm, a pulse is not fully processed by the OF until a few samples after the BCFD zero crossing. Now, if a second pulse arrives very shortly after the first one, it would still be acceptable in terms of which samples are actually used by the OF (that is, the tail could be reconstructed and the second pulse analysed). However, because of said latency we need to provide the baseline_selector with the reconstructed pulse a few samples earlier as well. It was found that by calculating four reconstructed samples simultaneously, the algorithm works within the limits of the OF (i.e. which samples are included w.r.t. the BCFD). Therefore, need to instantiate 4 sets of multipliers to do that calculation at the same time. Of course, this increases the resource requirements somewhat. Nonetheless, given the few samples FIR_LENGTH required for OF (4), the total number of multipliers needed per channel will be 4 (for the a coefficients) + 4 (for the b coefficients) + 4 (for the g reconstruction) + 4 (for the g' reconstruction) = 16. One might think of clever ways to reuse multipliers when not used for other things, or using other resources on the FPGA, or multiplexing (considering available clock resources).

                -- NOTE: the alignment (done by OF_ALIGNMENT_N_SAMPLES + pulse_0_counter + i) is NOT to align with data_in to the optimal_filter module. It is to ensure that the reconstructed baseline in baseline_selector will be aligned with the data_in to the constant fraction module.

                -- I want to align g and g' to the data, so I need to select the correct template (based on the BCFD zero-crossing interval). Do that via the r_cfd_window signal (internal to this part of the code)
                case r_cfd_window is
                    when w1 =>
                        if (pulse_0_counter < 100) then        --there are only 100 pre-calculated template values. Calculate the reconstructed pulse in that case.
                            g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(g_values_1(OF_ALIGNMENT_N_SAMPLES + pulse_0_counter + i), 18));
                            d_g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(d_g_values_1(OF_ALIGNMENT_N_SAMPLES + pulse_0_counter + i), 18));
                        else            -- otherwise, use zero.
                            g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));
                            d_g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));                        
                        end if;
                    when w2 =>
                        if (pulse_0_counter < 100) then
                            g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(g_values_2(OF_ALIGNMENT_N_SAMPLES + pulse_0_counter + i), 18));
                            d_g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(d_g_values_2(OF_ALIGNMENT_N_SAMPLES + pulse_0_counter + i), 18));
                        else
                            g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));
                            d_g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));                        
                        end if;
                    when w3 =>
                        if (pulse_0_counter < 100) then
                            g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(g_values_3(OF_ALIGNMENT_N_SAMPLES + pulse_0_counter + i), 18));
                            d_g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(d_g_values_3(OF_ALIGNMENT_N_SAMPLES + pulse_0_counter + i), 18));
                        else
                            g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));
                            d_g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));                        
                        end if;
                    when w4 =>
                        if (pulse_0_counter < 100) then
                            g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(g_values_4(OF_ALIGNMENT_N_SAMPLES + pulse_0_counter + i), 18));
                            d_g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(d_g_values_4(OF_ALIGNMENT_N_SAMPLES + pulse_0_counter + i), 18));               
                        else
                            g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));
                            d_g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));                        
                        end if;
                    when others =>
                        g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));
                        d_g_value_aligned_pulse_0(i) <= std_logic_vector(to_signed(0, 18));                                                                                           
                end case;
            end loop;

        
            pulse_0_counter <= pulse_0_counter + 1;                     -- used to count the # of samples since pulse 0 trigger, used for tail-template alignment.
            
        elsif (r_OF_state = triggered_pulse_1) then                     -- here, one could possibly implement pile-up reconstruction even for pulses after the first pile-up (but this is not done in the current implementation)
                if (pulse_1_counter = 0) then
                    SUM_A_pulse_1 <= shift_right(SUM_A, 11);        -- shift by 11 since A is calculated for 11 bits (a[10] in Get_OF_weights_NEW_CFD)
                    SUM_B_pulse_1 <= shift_right(SUM_B, 11);        -- shift by 11 since A is calculated for 11 bits. This will result in A*tau, and to get the final estimate one should first divide by the OF u estimate. The result is a number quantised in 9 bits (the value of b_scaling - a_scaling, i.e. the number of bits available to quantise tau). Get this value (9) from get_OF_coefficients.py

                    
		    r_Amplitude_previous_pulse <= shift_right(SUM_A, 11);		-- a second pulse will only be analysed if it's sufficiently large (compared to the previous pulse)
                end if;
                

    
                pulse_0_counter <= pulse_0_counter + 1;
                pulse_1_counter <= pulse_1_counter + 1;            
        else
            pulse_0_counter <= 0;
            pulse_1_counter <= 0;
            
            -- Set these to zero, which basically makes sure that no "pulse tail" is added to the baseline anymore. This is done since r_OF_state is waiting (meaning that there is no trigger from the baseline calculator)
            g_value_aligned_pulse_0 <= (others => (others => '0'));
            d_g_value_aligned_pulse_0 <= (others => (others => '0'));
            
            r_Amplitude_previous_pulse <= (others => '0');
        end if;
    end if;
end process;



-- The aligned tail template is still not scaled and shifted by A and tau. Do that using multipliers (see discussion on resource requirements above). Again, Xilinx Multiplier v12.0 LogiCORE IP, which is not included here, is used.

GENERATE_MULTIPLIERS_g_0:
    for i in 0 to 3 generate
        rec_mult_g : Reconstruction_mult_gen
            PORT MAP (
            A => std_logic_vector(SUM_A_pulse_0(19 downto 0)),          -- basically dropping bits to fit into the DSP.
            B => g_value_aligned_pulse_0(i),                          -- to align things
            P => Reconstructed_0_g_part(i)
            );
    end generate GENERATE_MULTIPLIERS_g_0;

GENERATE_MULTIPLIERS_d_g_0:
    for i in 0 to 3 generate
        rec_mult_d_g : Reconstruction_mult_gen
            PORT MAP (
            A => std_logic_vector(SUM_B_pulse_0(19 downto 0)),          -- basically dropping bits to fit into the DSP
            B => d_g_value_aligned_pulse_0(i),                        -- to align things. 
            P => Reconstructed_0_d_g_part(i)
            );
    end generate GENERATE_MULTIPLIERS_d_g_0;



-- In order to keep as much precision as possible, do this:
-- (above, the precision of A_SUM is determined in the correct units - ADC channels (done by shifting by 11). The precision of B_SUM is 9 additional bits -> precision of tau)
-- Shift Reconstructed_g_part *left* by 9 (i.e. multiply by 2^9) (precision of B) (not shown here) - to get first part to same number of bits as second part
-- Shift Reconstructed_g_part *right* by 16 (because this is the precision of g[]). This and the prev. operation correspond to shifting Reconstructed_g_part *right* by 7
-- Shift Reconstructed_d_g_part right by 14 (precision of d_g[]). Additional shift not needed because the g_part has been shifted *left* by 9 to align with this one
-- Finally, shift EVERYTHING right by 9 bits (to get 'true' amplitude units).

-- NOTE: largest uncertainty in reconstructed pulse appears when tau is small. Then the second part will be 0 during shift operations.
-- To fix this, one could maybe increase the precision in tau... Although the b coefficients for the OF are already quite high precision.

-- On each clock cycle, I reconstruct four samples worth of data. Needed to "catch up" with the raw data that should be compensated for (there is some latency in the CFD algorithm etc)
Reconstructed_0(0) <= shift_right(shift_right(signed(Reconstructed_0_g_part(3)), 7) - shift_right(signed(Reconstructed_0_d_g_part(3)), 14), 9);      
Reconstructed_0(1) <= shift_right(shift_right(signed(Reconstructed_0_g_part(2)), 7) - shift_right(signed(Reconstructed_0_d_g_part(2)), 14), 9);
Reconstructed_0(2) <= shift_right(shift_right(signed(Reconstructed_0_g_part(1)), 7) - shift_right(signed(Reconstructed_0_d_g_part(1)), 14), 9);
Reconstructed_0(3) <= shift_right(shift_right(signed(Reconstructed_0_g_part(0)), 7) - shift_right(signed(Reconstructed_0_d_g_part(0)), 14), 9);



-- In order to use fewer multipliers, I do like this:
-- Every time the Reconstructed_0 vector changes, update the r_reconstructed_pulse_temp vector. The elements already there are pushed back, and 4 new elements are pushed into it from the Reconstructed_0 vector. Note that this will run every time the Reconstructed_0 multipliers give something, so relies on the timing of those.
reconstruct_g : process(Reconstructed_0)
begin
    r_reconstructed_pulse_temp(8) <= r_reconstructed_pulse_temp(7);
    r_reconstructed_pulse_temp(7) <= r_reconstructed_pulse_temp(6);
    r_reconstructed_pulse_temp(6) <= r_reconstructed_pulse_temp(5);
    r_reconstructed_pulse_temp(5) <= r_reconstructed_pulse_temp(4);
    r_reconstructed_pulse_temp(4) <= r_reconstructed_pulse_temp(3);
    
    r_reconstructed_pulse_temp(3) <= to_integer(Reconstructed_0(3));
    r_reconstructed_pulse_temp(2) <= to_integer(Reconstructed_0(2));
    r_reconstructed_pulse_temp(1) <= to_integer(Reconstructed_0(1));
    r_reconstructed_pulse_temp(0) <= to_integer(Reconstructed_0(0));
    
    

end process;

-- These are the actual data on the reconstructed tail that are sent out and used by the baseline selector.
reconstructed_pulse_0(8) <= r_reconstructed_pulse_temp(8);
reconstructed_pulse_0(7) <= r_reconstructed_pulse_temp(7);
reconstructed_pulse_0(6) <= r_reconstructed_pulse_temp(6);
reconstructed_pulse_0(5) <= r_reconstructed_pulse_temp(5);
reconstructed_pulse_0(4) <= r_reconstructed_pulse_temp(4);
reconstructed_pulse_0(3) <= r_reconstructed_pulse_temp(3);
reconstructed_pulse_0(2) <= r_reconstructed_pulse_temp(2);
reconstructed_pulse_0(1) <= r_reconstructed_pulse_temp(1);
reconstructed_pulse_0(0) <= r_reconstructed_pulse_temp(0);






end Behavioral;
