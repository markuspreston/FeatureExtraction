import numpy as np
import matplotlib.pyplot as plt

input_data = np.genfromtxt('../data/input_data.csv', delimiter=',', dtype='int')            ## the generated data
MC_truth_data = np.genfromtxt('../data/MC_truth_data.csv', delimiter=',')                   ## needed to know the number of waveforms in the data
VHDL_output_data = np.genfromtxt('../data/output_data.csv', delimiter=',', dtype='int')     ## the output from the VHDL simulation

## Read some file-structure data:
N_EMPTY_WAVEFORMS = int(MC_truth_data[0,0])
N_REAL_WAVEFORMS = int(MC_truth_data[0,1])
N_SAMPLES_PER_WAVEFORM = int(MC_truth_data[0,2])

# This will hold the (global) time, and is used for plotting only:
t_pulse_train = np.linspace(1, (N_EMPTY_WAVEFORMS + N_REAL_WAVEFORMS)*N_SAMPLES_PER_WAVEFORM, (N_EMPTY_WAVEFORMS + N_REAL_WAVEFORMS)*N_SAMPLES_PER_WAVEFORM)

## Reading some outputs from the VHDL simulation:
CFD_signal = VHDL_output_data[:,5]
OF_u = VHDL_output_data[:,7]


# plot everything:
fig, ax = plt.subplots(3, 1, sharex=True)
ax[0].plot(t_pulse_train, input_data, color='darkorange')
ax[1].plot(t_pulse_train, CFD_signal, color='navy')
ax[2].plot(t_pulse_train, OF_u, color='maroon')

ax[0].set_title('Input data')
ax[1].set_title('CFD signal (from VHDL simulation)')
ax[2].set_title('OF amplitude estimate (from VHDL simulation)')


plt.xlim(0, t_pulse_train[-1])
ax[2].set_xlabel('Sample number')

fig.set_size_inches(6, 9)

plt.show()
