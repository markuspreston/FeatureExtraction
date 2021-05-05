import numpy as np
import matplotlib.pyplot as plt

MC_truth_data = np.genfromtxt('../data/MC_truth_data.csv', delimiter=',')               ## the data we want to compare with (the amplitudes and times of the pulses originally generated)
VHDL_output_data = np.genfromtxt('../data/output_data.csv', delimiter=',', dtype='int') ## what has now been output from the VHDL simulation

## Header data read from the MC truth file
N_EMPTY_WAVEFORMS = int(MC_truth_data[0,0])
N_REAL_WAVEFORMS = int(MC_truth_data[0,1])
N_SAMPLES_PER_WAVEFORM = int(MC_truth_data[0,2])

## These values have been copied/pasted from the output of get_OF_coefficients.py. For each BCFD window, this value is the average time difference between the BCFD zero crossing time and the assumed T_0 (i.e. the T_0 of the lognormal in the current implementation). The tau value calculated by the OF will be a small deviation in time from that assumed T_0 (which in itself has an accuracy of ~1/4 samples because we use four BCFD windows).
delta_BCFD_window_mean = [3.46268184, 3.47873633, 3.42513086, 3.47061768]

N_WF_TO_PROCESS = N_REAL_WAVEFORMS                 ## the number of waveforms to process in this script. Set equal to N_REAL_WAVEFORMS to process all data.


delta_A_0 = np.zeros(N_WF_TO_PROCESS)           ### difference between reconstructed and true amplitude for the first pulse in each waveform
delta_A_1 = np.zeros(N_WF_TO_PROCESS)           ### The same for the second pulse in each waveform

delta_T_0 = np.zeros(N_WF_TO_PROCESS)           ### difference between reconstructed and true time for the first pulse in each waveform
delta_T_1 = np.zeros(N_WF_TO_PROCESS)           ### The same for the second pulse in each waveform


for waveform_index in range(N_EMPTY_WAVEFORMS, N_EMPTY_WAVEFORMS + N_WF_TO_PROCESS):         ## start after the empty waveform(s)
    print('Processing waveform ' + str(waveform_index))

    MC_truth_data_for_wf = MC_truth_data[1+waveform_index]      ## skip the header row

    VHDL_data_for_wf = VHDL_output_data[waveform_index*N_SAMPLES_PER_WAVEFORM:(waveform_index+1)*N_SAMPLES_PER_WAVEFORM]                ## Get the VHDL output for the current waveform.

    ## the structure of the VHDL_data_for_wf vector will be determined by the output from the VHDL simulation. This is described in the main_tb.vhd file:
    # Column 0: the clock cycle number
    # Column 1: the raw input data
    # Column 2: the 2-sample MA (used to issue the baseline trigger)
    # Column 3: the calculated baseline (note: the output data is not necessarily correctly shifted in time, but this is handled internally in the VHDL code. Outputs such as this was just included for debugging)
    # Column 4: the baseline trigger (if the 2-sample MA goes above some threshold)
    # Column 5: the CFD signal
    # Column 6: the BCFD window found
    # Column 7: OF u (the first result of the OF: u = A)
    # Column 8: OF v (the second result of the OF: v = A*tau)
    # Column 9: the 'final trigger' - signals that readout should take place since a signal has been identified

    pulse_no = 0                ## keep track of whether first or second pulse (in each waveform) is analysed

    for sample_no in range(0, N_SAMPLES_PER_WAVEFORM):
        final_trigger = VHDL_data_for_wf[sample_no,9]
        if (final_trigger == 1):                                ## read out the data when we see the final trigger
            VHDL_sample_no = VHDL_data_for_wf[sample_no,0]
            BCFD_window = VHDL_data_for_wf[sample_no,6]
            OF_u = VHDL_data_for_wf[sample_no,7]
            OF_v = VHDL_data_for_wf[sample_no,8]

            OF_tau = (OF_v/OF_u)/512.              ## divide by 512 (= 2^9), because b_scaling - a_scaling = 20 - 11 (that is, after dividing OF_v by OF_u we have a number scaled up by (20-11) = 9 bits). Need to scale the quantised value down to a fraction of a sample. The required scaling here should correspond to what was done in get_OF_coefficients.py.

            T_0_BCFD = 0.125 + 0.25*(BCFD_window - 1)                           ## we define four BCFD windows. For each, the best estimate of the zero crossing time is the midpoint of that window (so 0.125, 0.375, 0.625 and 0.875).
            T_0_assumed = T_0_BCFD - delta_BCFD_window_mean[BCFD_window - 1]    ## T_0_assumed is the best guess on the lognormal T_0 *given* the BCFD window.


            Reconstructed_A = OF_u
            Reconstructed_T = VHDL_sample_no + T_0_assumed + OF_tau             ## To finally get the time, add VHDL_sample_no (for global time synchronisation, this would have to come from some external source such as readout in real life), the assumed T_0 (resolution ~1/4 sample due to BCFD algorithm) and the OF tau (the small shift in time from T_0_assumed to get best fit of lognormal to data)

            ## store reconstructed data in arrays:
            if (pulse_no == 0):
                True_A = MC_truth_data_for_wf[0]
                True_T = waveform_index*N_SAMPLES_PER_WAVEFORM + MC_truth_data_for_wf[1]
            elif (pulse_no == 1):
                True_A = MC_truth_data_for_wf[2]
                True_T = waveform_index*N_SAMPLES_PER_WAVEFORM + MC_truth_data_for_wf[3]
            else:
                print('Something went wrong (only 2 pulses allowed per wf)!')
                exit()

            ## Calculate some metrics: for time, just the difference of the reconstructed w.r.t. the true. For amplitude, the relative difference of the reconstructed from the true (because we generate pulses with many different amplitudes)
            if (pulse_no == 0):
                delta_A_0[waveform_index - N_EMPTY_WAVEFORMS] = (Reconstructed_A - True_A)/True_A
                delta_T_0[waveform_index - N_EMPTY_WAVEFORMS] = Reconstructed_T - True_T
            elif (pulse_no == 1):
                delta_A_1[waveform_index - N_EMPTY_WAVEFORMS] = (Reconstructed_A - True_A)/True_A
                delta_T_1[waveform_index - N_EMPTY_WAVEFORMS] = Reconstructed_T - True_T


            pulse_no += 1



## plot the results:
fig, ax = plt.subplots(2, 1, sharex=True)
n, bins, patches = ax[0].hist(delta_T_0, bins=1000, range=(3, 5), facecolor='g', alpha=0.75)
n, bins, patches = ax[1].hist(delta_T_1, bins=1000, range=(3, 5), facecolor='r', alpha=0.75)
plt.xlabel(r'Reconstructed $T_0$ - True $T_0$ [samples]')
ax[1].set_xlim(3, 5)
ax[0].set_yscale('log')
ax[1].set_yscale('log')

ax[0].text(0.55, 0.8, 'First pulse', horizontalalignment='left', verticalalignment='center', weight='bold', transform = ax[0].transAxes)
ax[0].text(0.55, 0.7, 'Distribution mean: ' + "{:.3f}".format(np.mean(delta_T_0)) + ' ns', horizontalalignment='left', verticalalignment='center', transform = ax[0].transAxes)
ax[0].text(0.55, 0.6, 'Distribution std dev: ' + "{:.3f}".format(np.std(delta_T_0)) + ' ns', horizontalalignment='left', verticalalignment='center', transform = ax[0].transAxes)
ax[1].text(0.55, 0.8, 'Second pulse (pile-up)', horizontalalignment='left', verticalalignment='center', transform = ax[1].transAxes)
ax[1].text(0.55, 0.7, 'Distribution mean: ' + "{:.3f}".format(np.mean(delta_T_1)) + ' ns', horizontalalignment='left', verticalalignment='center', transform = ax[1].transAxes)
ax[1].text(0.55, 0.6, 'Distribution std dev: ' + "{:.3f}".format(np.std(delta_T_1)) + ' ns', horizontalalignment='left', verticalalignment='center', transform = ax[1].transAxes)



fig, ax = plt.subplots(2, 1, sharex=True)
n, bins, patches = ax[0].hist(delta_A_0, bins=500, range=(0, 1), facecolor='g', alpha=0.75)
n, bins, patches = ax[1].hist(delta_A_1, bins=500, range=(0, 1), facecolor='r', alpha=0.75)
plt.xlabel(r'(Reconstructed $A$ - True $A$)/(True $A$)')
ax[1].set_xlim(0, 0.5)
ax[0].set_yscale('log')
ax[1].set_yscale('log')

ax[0].text(0.55, 0.8, 'First pulse', horizontalalignment='left', verticalalignment='center', weight='bold', transform = ax[0].transAxes)
ax[0].text(0.55, 0.7, 'Distribution mean: ' + "{:.3f}".format(np.mean(delta_A_0)), horizontalalignment='left', verticalalignment='center', transform = ax[0].transAxes)
ax[0].text(0.55, 0.6, 'Distribution std dev: ' + "{:.3f}".format(np.std(delta_A_0)), horizontalalignment='left', verticalalignment='center', transform = ax[0].transAxes)
ax[1].text(0.55, 0.8, 'Second pulse (pile-up)', horizontalalignment='left', verticalalignment='center', transform = ax[1].transAxes)
ax[1].text(0.55, 0.7, 'Distribution mean: ' + "{:.3f}".format(np.mean(delta_A_1)), horizontalalignment='left', verticalalignment='center', transform = ax[1].transAxes)
ax[1].text(0.55, 0.6, 'Distribution std dev: ' + "{:.3f}".format(np.std(delta_A_1)), horizontalalignment='left', verticalalignment='center', transform = ax[1].transAxes)




plt.show()
