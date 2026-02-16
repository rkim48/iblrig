%% Stimulate for 2P laser power tuning 
test_length = 2;
ch_idx = 1;
stim_channel = rippleChannels(ch_idx);
current = 4;

phaseLen = 5;
IPI_len = 2;
pulsePeriod = 30000/frequency;
currentSteps = current * stepFactor;
cmd = struct('elec',stim_channel,'period',pulsePeriod,'repeats',test_length*frequency); 
cmd.seq(1) = struct('length', phaseLen, 'ampl', currentSteps, 'pol', 0, ...
                         'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);
cmd.seq(2) = struct('length', IPI_len, 'ampl', 0, 'pol', 0, 'fs', 0, ...
                        'enable', 0, 'delay', 0, 'ampSelect', 1);
cmd.seq(3) = struct('length', phaseLen, 'ampl', currentSteps, 'pol', 1, ...
                         'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1); 
fprintf('Starting test stimulation...\n');
xippmex('stimseq', cmd);