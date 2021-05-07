# A feature-extraction and pile-up reconstruction algorithm for the forward-spectrometer EMC of the PANDA experiment
This is an algorithm for real-time reconstruction of pulses from a detector (in our case an electromagnetic calorimeter) in real time using an FPGA. The algorithm has been developed to handle pile-up of signals, such as in a high-radiation environment. The algorithm combines a digital implementation of the constant fraction discriminator algorithm and the optimal filter [1] algorithm to determine pulse amplitude and timing and to reconstruct the pulse tail. In the current implementation, the method allows reconstruction of two pulses superimposed on one another (that is, the 'first pulse' and the 'pile-up pulse'). Nonetheless, this could probably be extended should sufficient resources be available in the target device.

The algorithm has been documented elsewhere, and therefore this readme file is rather short. The main references would be [2] and [3]. However, a few lines about the structure of the repository and how to run the code is appropriate. First, some initial remarks:
- For this repository, I have opted to include only synthetic data generated using an assumed pulse shape (described by a log-normal function).
- In reality, the algorithm was tested using both simulated data from a Geant4 simulation and experimental data.
- The code in this repository assumes that the pulse shape has already been determined (for example by fitting a fixed pulse shape to a large number of simulated or experimental pulses). With pulse *shape* I mean that the only parameters that are free to vary is the amplitude and the time of the pulse (and the baseline, if applicable).
- The generated pulses are used as inputs to the VHDL simulation, where the amplitudes and times of the pulses are determined.
- Finally, the output of the VHDL simulation is compared to the "truth data" (i. e. the amplitudes and times of the originally generated pulses). Because the data here consists of pulses generated from the *known* log-normal shape, the results do not account for detector resolution and other effects. The only difference between the determined amplitude and time is due to the algorithm itself (meaning that there will be a good agreement, because the uncertainties only come from quantisation errors and uncertainties in the constant fraction or OF algorithms).

## Code structure
The repository is divided into three directories: data, scripts and vhdl. To run the code, proceed in the following order:
1. scripts/generate_pulse_data.py (to generate the actual input data and the truth data). Example data are provided in the data directory.
2. scripts/get_OF_coefficients.py (to *fit* the input data, determining the average difference between the (B)CFD time estimate and the log-normal fit, calculating the OF coefficients for all four BCFD windows). From the output of this run, you'll need to copy some things.
3. vhdl/optimal_filter.vhd (copy the FIR_coefficients_a, FIR_coefficients_b, g_values and d_g_values from the output of get_OF_coefficients.py into this code).
4. Run the VHDL simulation. The code has been developed for a Xilinx Kintex-7 FPGA, and was developed and tested using Xilinx Vivado v2018.1. Because the design uses some multiplier IPs, you'll need to place the vhd files in your design and connect to multipliers where needed. The VHDL code should be well-documented. For a general overview of how the different parts of the code interact, see Fig. 11.6 in [2].
5. The data directory contains an example output file output_data.csv, which was generated from the VHDL simulation when using input_data.csv as input.
6. scripts/visualise_data.py (visualise the input data, the CFD signal and the amplitudes determined by the OF. Quite a lot of pile-up cases can be investigated)
7. scripts/reconstruct_A_and_T.py (to compare the VHDL output to the input (i.e. the truth data). In the example case (provided), two pulses per waveform have been generated, resulting in some pile-up. This script shows the performance in reconstructing the amplitude and time for all pulses, including the pile-up).

It is again worth to emphasise that the example cases provided do *not* come from experiment or detector simulation. They have been generated using a log-normal function that was found to describe our pulses well. Therefore, the example case does not account for detector resolution and so on. You should replace the generate_pulse_data.py with some other source of signals (simulation or experiment) to test the performance under more realistic conditions (which was also done in [2, 3]).

## Licensing
The Python scripts in the scripts directory are provided under the MIT license. The VHDL code is provided under the weakly reciprocal CERN-OHL-W v2 license. Please see the LICENSE files in the "scripts" and "vhdl" directories for the details.

## Contact
Markus Preston, markus.preston@physics.uu.se

## References
[1] W. E. Cleland and E. G. Stern, "Signal processing considerations for liquid ionization calorimeters in a high rate environment", Nucl. Instrum. Methods Phys. Res. A 338(2-3), pp. 467-497, 1993. (https://doi.org/10.1016/0168-9002(94)91332-3)

[2] M. Preston, "Developments for the FPGA-Based Digitiser in the PANDA Electromagnetic Calorimeters", PhD thesis, Stockholm University, Stockholm, Sweden, 2020. (http://urn.kb.se/resolve?urn=urn%3Anbn%3Ase%3Asu%3Adiva-179733)

[3] M. Preston et al, "A feature-extraction and pile-up reconstruction algorithm for the forward-spectrometer EMC of the PANDA experiment", to be published, 2021.
