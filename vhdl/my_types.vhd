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


-- The data types defined here are used in the main code. Normally the types define arrays (i. e. buffers of integers or data), or state variables. Please see the other .vhd files for reference to usage.

package my_types is

type t_sample_buffer is array (16 downto 0) of unsigned(15 downto 0);


---------

type t_baseline_buffer is array (20 downto 0) of integer;
type t_baseline_state is (setup, awake, sleeping);

---------

type t_cfd_buffer is array (1 downto 0) of integer;
type t_cfd_state is (waiting, triggered);
type t_cfd_window is (waiting, w1, w2, w3, w4);

---------

type t_fir_coefficients is array (3 downto 0) of integer;
type t_fir_coefficients_vector is array (3 downto 0) of std_logic_vector(24 downto 0);

type t_fir_data is array (3 downto 0) of std_logic_vector(15 downto 0);

type t_fir_product is array (3 downto 0) of std_logic_vector(40 downto 0);

type t_u_buffer is array (3 downto 0) of integer;

--------------

type t_OF_state is (waiting, triggered_pulse_0, triggered_pulse_1, triggered_pulse_2);              -- Note: 'triggered_pulse_2' is NOT used in the current version.


type t_g_value_aligned_pulse is array(0 to 3) of STD_LOGIC_VECTOR(17 DOWNTO 0);
type t_d_g_value_aligned_pulse is array(0 to 3) of STD_LOGIC_VECTOR(17 DOWNTO 0);



type t_pulse_shape_values is array (0 to 99) of integer;
type t_reconstructed_pulse is array (8 downto 0) of integer;

type t_Reconstructed_part is array(3 downto 0) of STD_LOGIC_VECTOR(37 DOWNTO 0);
type t_Reconstructed is array(3 downto 0) of signed(37 DOWNTO 0);

------------
-- For baseline selector:

type t_baseline_sel_buffer is array (8 downto 0) of integer; 



 

   
end package my_types;
 
-- Package Body Section
package body my_types is

 
end package body my_types;
