import numpy as np
import matplotlib.pyplot as plt

## The lognormal function. Assumed to be the shape of the raw detector pulses in this example case.
def generate_lognormal_signal(t, A, T0, mu, sigma, N_SAMPLES):

    signal = np.zeros(N_SAMPLES)                                                    ## will contain the actual signal (i. e. not including the baseline and baseline noise)

    for sample_no in range(N_SAMPLES):
        if (t[sample_no] > T0):
            signal[sample_no] = A*np.exp(mu - np.power(sigma, 2)/2.)*(1./(t[sample_no]-T0))*np.exp(-np.power(np.log(t[sample_no]-T0)-mu, 2)/(2.*sigma*sigma))
        else:
            signal[sample_no] = 0.

    return signal



N_SAMPLES_PER_WAVEFORM = 100                 ## each waveform should be 100 samples
N_EMPTY_WAVEFORMS = 1                       ## because the VHDL algorithm needs some time for initialisation, the first waveforms (i. e. the first 100 samples are "empty", so just baseline and no signal). This will allow the VHDL algorithm to find an accurate baseline.
N_REAL_WAVEFORMS = 10000               ## how many waveforms (with signals) to generate

## Set the properties of the baseline. Here, assumed to be a constant value with a Gaussian noise (with sigma = baseline_gen_sigma)
baseline_gen_mu = 1000.
baseline_gen_sigma = 2.


## For each waveform (that is, each 100 samples), generate two pulses. This is done to test the pile-up reconstruction capabilities of the algorithm. Also, we want both the amplitude A and start time T0 of each of the two pulses to be generated randomly (within some ranges). This is done to get a good distribution with respect to the sampling clock (i.e. the algorithm should work independently of the phase of the pulse w.r.t. the sampling clock)

## Specify the limits in amplitude:
A_min = 50.
A_max = 1000.

# Generate amplitudes for the N_REAL_WAVEFORMS waveforms, one for each of the two signals per waveform:
A_0_gen = np.random.uniform(A_min, A_max, N_REAL_WAVEFORMS)          ## the first of the two pulses
A_1_gen = np.random.uniform(A_min, A_max, N_REAL_WAVEFORMS)          ## the second of the two pulses

## Specify the limits in T0 for the *first* pulse (note: the time units here are *samples*, and one should convert to nanoseconds or similar when analysing the data in the end).
T0_0_min = 5.
T0_0_max = 20.

# Generate T0 for the N_REAL_WAVEFORMS waveforms, first for the first of the two signals per waveform:
T0_0_gen = np.random.uniform(T0_0_min, T0_0_max, N_REAL_WAVEFORMS)

# The second pulse should arrive a time Delta_T0 after the first pulse (here, one can change the range to test the performance under different degrees of pile-up). Specify the possible range of Delta_T0:
Delta_T0_min = 5.
Delta_T0_max = 50.

# Generate Delta_T0 for the N_REAL_WAVEFORMS waveforms. In the end, the second pulse will have a T0 of T0_0 + Delta_T0 
Delta_T0_gen = np.random.uniform(Delta_T0_min, Delta_T0_max, N_REAL_WAVEFORMS)                 ## for each waveform, generate a certain Delta_T0 (how far second pulse is to come after first), to get good distribution of pulse phase w.r.t. sampling


## These parameters determine the shape of the LogNormal. They were determined by fitting to simulated waveforms from a Geant4 simulation. Here, they are kept fixed to generate waveforms according to the LogNormal, just to demonstrate the principle of the algorithm.
mu = 1.47515
sigma = 0.610874


## samples run between 1, 2, 3, ..., N_SAMPLES_PER_WAVEFORM. Produce a vector of these values denoting the times in each waveform.
t_waveform = np.linspace(1, N_SAMPLES_PER_WAVEFORM, N_SAMPLES_PER_WAVEFORM)

# This will hold the generated data:
pulse_train = np.zeros((N_EMPTY_WAVEFORMS + N_REAL_WAVEFORMS)*N_SAMPLES_PER_WAVEFORM)

# This will hold the generated data (with no pile-up pulses, used for fitting in get_OF_coefficients.py):
pulse_train_no_pileup = np.zeros((N_EMPTY_WAVEFORMS + N_REAL_WAVEFORMS)*N_SAMPLES_PER_WAVEFORM)

# This will hold the (global) time, and is used for plotting only:
t_pulse_train = np.linspace(1, (N_EMPTY_WAVEFORMS + N_REAL_WAVEFORMS)*N_SAMPLES_PER_WAVEFORM, (N_EMPTY_WAVEFORMS + N_REAL_WAVEFORMS)*N_SAMPLES_PER_WAVEFORM)

# Simple data structure to hold the data that will be exported to a text file. These data will be used as Monte Carlo truth values when analysing the output of the VHDL simulation
MC_truth_data = np.zeros(shape=(1+N_EMPTY_WAVEFORMS+N_REAL_WAVEFORMS, 4))           ## row 1: header, stores the number of empty waveforms, the number of real waveforms and the number of samples per waveform. The remaining rows store the following data: [A_0, T_0_0, A_1, T_0_1].

## Set the header of the MC truth file:
MC_truth_data[0,0] = N_EMPTY_WAVEFORMS
MC_truth_data[0,1] = N_REAL_WAVEFORMS
MC_truth_data[0,2] = N_SAMPLES_PER_WAVEFORM
MC_truth_data[0, 3] = -1            ## means no data
for i in range(N_EMPTY_WAVEFORMS):
    MC_truth_data[1+i,:] = -1               ## the rows where no pulses generated should be filled with -1.

## fill with truth data:
MC_truth_data[1+N_EMPTY_WAVEFORMS:,0] = A_0_gen
MC_truth_data[1+N_EMPTY_WAVEFORMS:,1] = T0_0_gen
MC_truth_data[1+N_EMPTY_WAVEFORMS:,2] = A_1_gen
MC_truth_data[1+N_EMPTY_WAVEFORMS:,3] = T0_0_gen + Delta_T0_gen

## Now, start generating waveforms:
for waveform_index in range(N_EMPTY_WAVEFORMS + N_REAL_WAVEFORMS):
    if (waveform_index % 500 == 0):
        print('Waveform ' + str(waveform_index))

    baseline = np.random.normal(baseline_gen_mu, baseline_gen_sigma, N_SAMPLES_PER_WAVEFORM)            ## the baseline is generated for every waveform (also the empty ones), by generating gaussian noise with a certain mean and std dev.


    if (waveform_index >= N_EMPTY_WAVEFORMS):           ## get the signal data from lognormal functions with the appropriate amplitudes and start times:
        signal_0 = generate_lognormal_signal(t_waveform, A_0_gen[waveform_index - N_EMPTY_WAVEFORMS], T0_0_gen[waveform_index - N_EMPTY_WAVEFORMS], mu, sigma, N_SAMPLES_PER_WAVEFORM)
        signal_1 = generate_lognormal_signal(t_waveform, A_1_gen[waveform_index - N_EMPTY_WAVEFORMS], T0_0_gen[waveform_index - N_EMPTY_WAVEFORMS]+Delta_T0_gen[waveform_index - N_EMPTY_WAVEFORMS], mu, sigma, N_SAMPLES_PER_WAVEFORM)
    else:               ## empty waveform, so both signal 0 and 1 = zero:
        signal_0 = np.zeros(N_SAMPLES_PER_WAVEFORM)
        signal_1 = np.zeros(N_SAMPLES_PER_WAVEFORM)


    ## Now, everything in place to produce the waveform. The waveform is the sum of the baseline (including noise) and the two signal shapes. Note that the data is rounded and converted to integer (to emulate dititisation in an ADC)
    pulse_train[waveform_index*N_SAMPLES_PER_WAVEFORM:(waveform_index+1)*N_SAMPLES_PER_WAVEFORM] = np.round(baseline + signal_0 + signal_1).astype(int)

    ## In the get_OF_coefficients.py script, you want to fit to well-isolated pulses to determine the parameters of the OF filter. In reality, you would select well-isolated pulses acquired with a detector for that. Here, we simply generate waveforms definitely pile-up free (so only signal 0 is stored for these data):
    pulse_train_no_pileup[waveform_index*N_SAMPLES_PER_WAVEFORM:(waveform_index+1)*N_SAMPLES_PER_WAVEFORM] = np.round(baseline + signal_0).astype(int)



## Save the 'input_data.csv' file. This will be the input to the VHDL simulation
np.savetxt("../data/input_data.csv", pulse_train, fmt='%i')

## Save the 'input_data_no_pileup.csv' file. This will be the input to the get_OF_coefficients.py script
np.savetxt("../data/input_data_no_pileup.csv", pulse_train_no_pileup, fmt='%i')

## Save the 'MC_truth_data.csv' file. This will be used when analysing the output from the VHDL simulation.
np.savetxt("../data/MC_truth_data.csv", MC_truth_data, fmt='%f', delimiter=',')

## For visualisation purposes, plot the entire pulse train:
plt.plot(t_pulse_train, pulse_train)
plt.show()
