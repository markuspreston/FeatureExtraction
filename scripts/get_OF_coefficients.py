import numpy as np
from numpy import genfromtxt
import matplotlib.pyplot as plt
from scipy.optimize import curve_fit

## Define the lognormal function (for fitting to input data)
def lognormal_fcn(t, A, T0, mu, sigma, baseline):
    function = np.zeros(len(t))

    for i in range(len(t)):
        if (t[i] > T0):
            function[i] = A*np.exp(mu - np.power(sigma, 2)/2.)*(1./(t[i]-T0))*np.exp(-np.power(np.log(t[i]-T0)-mu, 2)/(2.*sigma*sigma)) + baseline
        else:
            function[i] = baseline

    return function

## Define the (time-)derivative of the lognormal function (used to produce the OF coefficients). Note that the baseline is not included, for the OF we assume that it has already been subtracted by other means
def d_lognormal_fcn(t, A, T0, mu, sigma):
    function = np.zeros(len(t))

    for i in range(len(t)):
        if (t[i] > T0):
            function[i] = A*np.exp(mu - np.power(sigma, 2)/2.)*(1./np.power(t[i]-T0, 2))*np.exp(-np.power(np.log(t[i]-T0)-mu, 2)/(2.*sigma*sigma))*((mu - np.log(t[i]-T0))/np.power(sigma, 2) - 1.)
        else:
            function[i] = 0.

    return function

## Define the constant fraction discriminator (CFD) signal corresponding to the lognormal function. The CFD signal is the sum of the delayed raw signal and an inverted and attenuated copy of that same signal.
def lognormal_fcn_CFD(t, A, T0, mu, sigma, CFD_delay, CFD_attenuation):
    CFD_function = np.zeros(len(t))

    for i in range(len(t)):
        #print(T0)
        if (t[i] > T0+CFD_delay):
            CFD_function[i] = A*np.exp(mu - np.power(sigma, 2)/2.)*(1./(t[i]-(T0+CFD_delay)))*np.exp(-np.power(np.log(t[i]-(T0+CFD_delay))-mu, 2)/(2.*sigma*sigma)) - CFD_attenuation*A*np.exp(mu - np.power(sigma, 2)/2.)*(1./(t[i]-T0))*np.exp(-np.power(np.log(t[i]-T0)-mu, 2)/(2.*sigma*sigma))
        else:
            CFD_function[i] = 0.

    return CFD_function


## Read the input data from a csv file (in this example case, the input was generated using the 'generate_pulse_data.py' script). Note: the data should contain more or less isolated pulses, to ensure that the fitting etc is not influenced by potential pile-up (or there should be a control mechanism in the code below to remove such pulses from the data). Here, we are free to generate waveforms only containing single pulses. This was done in generate_pulse_data.py
pulse_train = genfromtxt('../data/input_data_no_pileup.csv')

## You need to know some properties of the input data. That is, how many samples per waveform and how many waveforms in the pulse train?
N_SAMPLES_PER_WAVEFORM = 100                 ## each waveform should be 100 samples
N_WAVEFORMS_TO_FIT = 100                            ## how many waveforms to fit
N_EMPTY_WAVEFORMS = 1                       ## I know that the data contains one empty waveform in the beginning. This should be excluded

## These parameters determine the shape of the LogNormal. They were determined by fitting to simulated waveforms from a Geant4 simulation. Here, they are kept fixed to generate waveforms according to the LogNormal, just to demonstrate the principle of the algorithm.
mu = 1.47515
sigma = 0.610874


## Set the parameters of the constant fraction discriminator (CFD) algorithm - the delay and the attenuation.
CFD_delay = 2
CFD_attenuation = 0.5

## The CFD signal will be held in this array:
waveform_CFD = np.zeros(N_SAMPLES_PER_WAVEFORM)

### In the current implementation, four BCFD windows (i.e. subdivisions of a sample) have been used. This is more or less hard-coded here, but can of course be modified.
N_BCFD_WINDOWS = 4

delta_BCFD_window_1 = np.zeros(0)
delta_BCFD_window_2 = np.zeros(0)
delta_BCFD_window_3 = np.zeros(0)
delta_BCFD_window_4 = np.zeros(0)

## One has to specify where the OF will start and how many samples to include. In the current implementation, starting at -3 samples (relative to the CFD crossing), and using the next four samples in the OF was found to be optimal in terms of resolution and resource requirements (see Fig. 11.3 of Preston, M. (2020), "Developments for the FPGA-Based Digitiser in the PANDA Electromagnetic Calorimeters", PhD thesis, Stockholm University, http://urn.kb.se/resolve?urn=urn%3Anbn%3Ase%3Asu%3Adiva-179733 for details)
OF_START = -3
OF_LENGTH = 4

## The pulse shape template g and its derivative d_g must be quantised for the tail-reconstruction to work (in pile-up reconstruction). One needs to specify the precision for that. In the current implementation, g was quantised with a 16-bit precision and d_g with a 14-bit precision (these values were selected to fit within the DSP resources on the FPGA):
g_PRECISION = 16                ## 16-bit precision on g (g is an unsigned number in this case, the pulse template is never negative - unipolar pulse with no undershoot assumed)
d_g_PRECISION = 14              ## 14-bit precision on d_g (d_g is a signed number in this case, the derivative of the pulse template can be negative)


## samples run between 1, 2, 3, ..., N_SAMPLES_PER_WAVEFORM. Produce a vector of these values denoting the times in each waveform.
t_waveform = np.linspace(1, N_SAMPLES_PER_WAVEFORM, N_SAMPLES_PER_WAVEFORM)

g = np.zeros(shape=(N_BCFD_WINDOWS, N_SAMPLES_PER_WAVEFORM))                 ## The pulse template (needed for OF). One for each BCFD window
d_g = np.zeros(shape=(N_BCFD_WINDOWS, N_SAMPLES_PER_WAVEFORM))                 ## The derivative of the pulse template (needed for OF). One for each BCFD window

g_quantised = np.zeros(shape=(N_BCFD_WINDOWS, N_SAMPLES_PER_WAVEFORM), dtype=int)                 ## Same as above, but quantised to 16-bit precision
d_g_quantised = np.zeros(shape=(N_BCFD_WINDOWS, N_SAMPLES_PER_WAVEFORM), dtype=int)                 ## Same as above, but quantised to 14-bit precision

## a and b are the sets of coefficients used by the OF to determine A and tau. There will be OF_LENGTH coefficients per BCFD window, so store the coefficients in two N_BCFD_WINDOWS*OF_LENGTH arrays:
a = np.zeros(shape=(N_BCFD_WINDOWS, OF_LENGTH))
b = np.zeros(shape=(N_BCFD_WINDOWS, OF_LENGTH))

## Of course, these coefficients will be stored in an FPGA and should be quantised. Create similar arrays to store those values:
a_quantised = np.zeros(shape=(N_BCFD_WINDOWS, OF_LENGTH), dtype=int)
b_quantised = np.zeros(shape=(N_BCFD_WINDOWS, OF_LENGTH), dtype=int)



for waveform_index in range(N_EMPTY_WAVEFORMS, N_EMPTY_WAVEFORMS + N_WAVEFORMS_TO_FIT):
    ## Read the waveform data (to be fitted):
    waveform = pulse_train[waveform_index*N_SAMPLES_PER_WAVEFORM:(waveform_index+1)*N_SAMPLES_PER_WAVEFORM]

    ## Need an initial estimate of the baseline for the fit. Get this from the very first sample in each waveform. Note: This is not the value that will be used in the end, just a starting point for the fit.
    baseline_estimate = waveform[0]
    A_estimate = np.amax(waveform) - baseline_estimate          ## need an initial guess for the amplitude A. Get this by getting the maximum amplitude in the waveform and subtracting the baseline estimate
    T0_estimate = np.where(waveform == (A_estimate + baseline_estimate))[0][0]              ## to get an initial guess for T0, first get the sample number corresponding to A_estimate. [0][0] is to get a single scalar out (takes into account possibility for two samples having the same amplitude as the maximum)


    ## fit the current waveform with a lognormal function (note that the parameters mu and sigma are kept fixed. They were determined by fitting to signals generated from a detailed detector simulation. Here, the method is just demonstrated by generating waveforms with this shape and then fitting lognormals (with the same shape parameters mu and sigma) to the waveforms. popt contains the values of the fitted parameters [A, T0, baseline]. pcov contains the covariance matrix for these.
    popt, pcov = curve_fit(lambda t_fit, A_fit, T0_fit, baseline_fit: lognormal_fcn(t_fit, A_fit, T0_fit, mu, sigma, baseline_fit), t_waveform, waveform, p0=[A_estimate, T0_estimate, baseline_estimate])


    ## The (important) fitted parameter values:
    A_fit = popt[0]
    T0_fit = popt[1]
    baseline_fit = popt[2]


    ## Now that we have a fitted pulse, we have an estimate for the lognormal T_0 parameter for that pulse. This we now call T_0_fit. The idea is now to calculate the CFD signal corresponding to the input waveform data, extract the BCFD window (i.e. in which sub-sample window the CFD zero crossing occurs).
    pulse_start = -1
    for sample_no in range(N_SAMPLES_PER_WAVEFORM):

        if ((pulse_start == -1) and (t_waveform[sample_no] >= T0_fit)):               ## get the sample number of the first sample after the start of the pulse (determined from the fit)
            pulse_start = sample_no
    
        if (sample_no >= CFD_delay):
            waveform_CFD[sample_no] = (waveform[sample_no - CFD_delay] - baseline_fit) - CFD_attenuation*(waveform[sample_no] - baseline_fit)


    ## We know that the CFD zero crossing must occur after T_0 fit, so look in that region only.
    for sample_no in range(pulse_start, N_SAMPLES_PER_WAVEFORM):
        if ((waveform_CFD[sample_no - 1] < 0.) and (waveform_CFD[sample_no] >= 0.)):            ## when we are around the zero crossing.
            y_0 = waveform_CFD[sample_no - 1]
            y_1 = waveform_CFD[sample_no]
    
            T0_CFD = y_0/(y_0 - y_1)                    ## standard linear interpolation - we know the y values in the two samples around the zero-crossing (i.e. the sampled data). Saying that x = 0 at the first of these samples, it is then straightforward to find the value of x when y = 0 (that is, at x = T0_CFD).
    
            ## Now, interested in finding the *window* in which the zero-crossing occurs. Four BCFD windows used, so check each for the crossing:
            if (T0_CFD <= 0.25):
                T_BCFD = 0.125
                T_BCFD_window = 1
            elif (T0_CFD <= 0.50):
                T_BCFD = 0.375
                T_BCFD_window = 2
            elif (T0_CFD <= 0.75):
                T_BCFD = 0.625
                T_BCFD_window = 3
            elif (T0_CFD <= 1.):
                T_BCFD = 0.875
                T_BCFD_window = 4
    
            T_BCFD = (t_waveform[sample_no] - 1) + T_BCFD               ## the BCFD time estimate is the time of the sample before the zero crossing *plus* the "best estimate" from the BCFD window (i.e. 0.125, 0.375, 0.625 or 0.875 samples).

            ## delta is the difference between the BCFD time estimate and the T_0 of the lognormal. Calculate that here by comparing the BCFD analysis with the fitted pulse:
            delta = T_BCFD - T0_fit

            ## Append the calculated value to the correct array below:
            if (T_BCFD_window == 1):
                delta_BCFD_window_1 = np.append(delta_BCFD_window_1, delta)
            elif (T_BCFD_window == 2):
                delta_BCFD_window_2 = np.append(delta_BCFD_window_2, delta)
            elif (T_BCFD_window == 3):
                delta_BCFD_window_3 = np.append(delta_BCFD_window_3, delta)
            elif (T_BCFD_window == 4):
                delta_BCFD_window_4 = np.append(delta_BCFD_window_4, delta)

    
            break;              ## only one pulse should be analysed per waveform

## Now that the above has been done for a number of pulses, we are interested in the *average* difference between the BCFD estimate and the lognormal T_0. So, get the average differences. Note that the outputs here should be pasted into the reconstruct_A_and_T.py script (since they are needed to get back from the VHDL output to a correct estimate of T_0).
delta_BCFD_window_mean = np.array([delta_BCFD_window_1.mean(), delta_BCFD_window_2.mean(), delta_BCFD_window_3.mean(), delta_BCFD_window_4.mean()])

print(delta_BCFD_window_mean)               ## print to terminal - you should copy/paste those values to reconstruct_A_and_T.py


T0_assumed = np.zeros(N_BCFD_WINDOWS)

## Each BCFD window now has an associated delta_BCFD_window_mean value. For the OF, we instead need to find a "best guess" on T_0 (i.e. the lognormal start time). To get that, take the BCFD "best estimate" minus the delta_BCFD_window_mean values. Note that we also shift the time estimate right by 6 samples, just to get a positive T0_assumed for all BCFD windows. This shift is in that sense arbitrary, but can of course be accounted for later since it is known and fixed.
for BCFD_window in range(N_BCFD_WINDOWS):
    T0_assumed[BCFD_window] = (6. + 0.125 + BCFD_window*0.25) - delta_BCFD_window_mean[BCFD_window]


### Now, ready to calculate the OF parameters. This is done for each BCFD window. For the calculations of the actual coefficients, the methodology in Cleland & Stern (https://doi.org/10.1016/0168-9002(94)91332-3) is used.

for BCFD_window in range(N_BCFD_WINDOWS):
    print('Window ' + str(BCFD_window))
    g[BCFD_window] = lognormal_fcn(t_waveform, 1, T0_assumed[BCFD_window], mu, sigma, 0)                ## produce a lognormal function (i. e. the "pulse template" g) with T0 = T0_assumed (for this BCFD window), mu and sigma from the fixed lognormal shape and a baseline of zero (in the VHDL code, the baseline will be subtracted in a different way before applying the OF). Note also that the amplitude A is set to 1 (the amplitude is a scaling factor applied on the template in the OF algorithm)
    d_g[BCFD_window] = d_lognormal_fcn(t_waveform, 1, T0_assumed[BCFD_window], mu, sigma)                ## for the OF to work, we also need the time-derivative of the pulse template (i. e. g', or d_g as denoted here). Luckily, the derivative of the lognormal is available analytically, so we may get it directly.


    ## Calculate the quantised pulse template (and derivative). Needed for the tail reconstruction later on. Remember that the precisions on these numbers is already specified above (g_PRECISION and d_g_PRECISION)
    g_quantised[BCFD_window] = (np.power(2, g_PRECISION)*g[BCFD_window]).astype(int)
    d_g_quantised[BCFD_window] = (np.power(2, d_g_PRECISION)*d_g[BCFD_window]).astype(int)


    ## In the on-line processing of signals, the BCFD algorithm will first run to determine the BCFD window. We therefore need a way to 'align' the BCFD algorithm and the OF algorithm (the BCFD zero-crossing time is used as a reference in time). The way this is done is by looking at the timing of the first sample in the CFD data that is *above zero* (i. e. after the zero crossing). We approximate that here by looking at the CFD signal corresponding to pulse template (which should describe the data well):

    lognormal_CFD = lognormal_fcn_CFD(t_waveform, 1, T0_assumed[BCFD_window], mu, sigma, CFD_delay, CFD_attenuation)

    sample_above_zero = -1

    for sample_no in range(N_SAMPLES_PER_WAVEFORM):
        if (lognormal_CFD[sample_no] > 0.):
            sample_above_zero = sample_no                       ## sample_above_zero is now the first CFD sample above zero in the waveform.
            break

    ## ready to calculate the Q_1, Q_2 and Q_3 coefficients (see Cleland & Stern):
    Q_1 = 0.
    Q_2 = 0.
    Q_3 = 0.

    for sample_no in range((sample_above_zero + OF_START), (sample_above_zero + OF_START + OF_LENGTH)):           ## as defined in Preston, M. "Developments for the FPGA-Based Digitiser in the PANDA Electromagnetic Calorimeters", I include four samples in the OF. These are samples [-3, -2, -1, 0] relative to the first CFD sample above zero. Use those when calculating the OF coefficients.
        Q_1 += g[BCFD_window, sample_no]*g[BCFD_window, sample_no]
        Q_2 += d_g[BCFD_window, sample_no]*d_g[BCFD_window, sample_no]
        Q_3 += d_g[BCFD_window, sample_no]*g[BCFD_window, sample_no]

    Delta = Q_1*Q_2 - np.power(Q_3, 2)              # another quantity defined in Cleland/Stern

    # The following parameters are needed for the OF. Defined in Cleland and Stern Eqs. 39 and 40
    lambda_OF = Q_2/Delta
    kappa_OF = -Q_3/Delta
    mu_OF = Q_3/Delta
    rho_OF = -Q_1/Delta

    OF_index = 0            ## keep track of which of the four samples in the OF you're at

    for sample_no in range((sample_above_zero + OF_START), (sample_above_zero + OF_START + OF_LENGTH)):           ## go over the samples used in the OF, calculate the a and b coefficients (according to Eqs. 37 and 38 in Cleland/Stern):
        a[BCFD_window, OF_index] = lambda_OF*g[BCFD_window, sample_no] + kappa_OF*d_g[BCFD_window, sample_no]
        b[BCFD_window, OF_index] = mu_OF*g[BCFD_window, sample_no] + rho_OF*d_g[BCFD_window, sample_no]

        OF_index += 1





# For the VHDL implementation of the algorithm, the coefficient sets a and b must be quantised. To do that, one first has to specify the target precision (i. e. the number of bits used to represent the coefficients).

# The first step is to determine the maximum coefficient values in the sets a and b (i. e. max(abs(a_i)) and max(abs(b_i)), where i is the index of the coefficient). Note that there could be negative coefficient values, so we just want to get the maximum *absolute* coefficient value. The quantisation should be the same for all BCFD windows, so we need to find the *global* coefficient maxima:
max_abs_a_i = np.max(np.abs(a))
max_abs_b_i = np.max(np.abs(b))

## The precision on the OF reconstruction will (in part) be determined by the precision on the coefficients a and b. That is determined by the wordlength used to represent those data in the FPGA. Specify the maximum wordlengths M_a and M_a for the two coefficient sets here. NOTE: these wordlengths could probably be optimised further, but wasn't done in this work.

M_A = 12                        ## I chose to use 12-bit wordlength for the a coefficients (which are used to determine the amplitude)
M_B = M_A + 10                  ## Because the time is essentially determined by first determining A*tau and then dividing by the A estimate (from the a coefficient multiplication), higher precision is needed for the b coefficients. Here, an additional 10 bits were added to represent the fact that we need good precision on the tau estimate.

## Now for the quantisation, it is known that both a and b should be signed integers. Therefore, the maximum absolute integer value that could fit within a word of length M is 2^(M-1) - 1 ((M-1) accounts for the fact that the coefficient can be on both sides of zero, -1 at the end accounts for the maximum integer fitting in a (M-1)-bit representation is 2^(M-1) -1). Divide by the maximum value of the un-quantised coefficient values to get the scaling from maximum un-quantised to maximum quantised representation. Finally, take log2 of the result to get the number of bits needed to represent that scaling (e. g. if the maximum coefficient value is 0.6 and M = 12, (2^(M-1) - 1) = 2047 and max(abs(a)) = 0.6 => (2^(M-1) - 1)/max(abs(a)) = 3411.6667. This is the scaling at which the best precision is achieved. Take log2 of that => 11.736261. This would mean that to quantise a coefficient a, a_quant = round(a*2^11.736261). However, we should work with integers (including the scaling factor). So, the best precision can be obtained if the scaling factor = floor(11.736261) = 11 in this case. Then, any quantisation can be calculated as a_quant = round(a*2^11) (we now know that no actual coefficient value a will cause an overflow in the quantisation. Do this for our case:

a_scaling = int(np.floor(np.log2((np.power(2, M_A-1) - 1)/max_abs_a_i)))
b_scaling = int(np.floor(np.log2((np.power(2, M_B-1) - 1)/max_abs_b_i)))


## Now, to go from the OF coefficients calculated above to the quantised values, need to scale up by factors 2^a_scaling and 2^b_scaling, respectively. At a later stage, when analysing the data, these scaling factors should be kept in mind because one should scale *down* by the same factors (offline) to get back the correct units.


for BCFD_window in range(N_BCFD_WINDOWS):
    for OF_index in range(0, OF_LENGTH): 
        a_quantised[BCFD_window, OF_index] = np.round(a[BCFD_window, OF_index]*np.power(2, a_scaling))
        b_quantised[BCFD_window, OF_index] = np.round(b[BCFD_window, OF_index]*np.power(2, b_scaling))

## Print the values to terminal. These arrays should be copied/pasted into the VHDL code.
print('quantised g:')
print(repr(g_quantised))

print('quantised d_g:')
print(repr(d_g_quantised))

print('quantised a:')
print(repr(a_quantised))
print('quantised b:')
print(repr(b_quantised))

print(a_scaling)
print(b_scaling)
