addpath(genpath('C:\iblrigv8\matlab\util\'));
addpath('C:\iblrigv8\matlab\lib\xippmex\');
load('beep.mat','y');

%% Trek Hardware Initialization (takes a minute)
ripple;
%% Stim parameters
current = 7; % uA 
pulse_width = 167; % us
interphase_interval = 67;
stim_freq = 100; % Hz

max_go_trial_s = 3; % s
max_no_go_trial_s = 3; % s

p_go = 0.5;
total_trials = 1000;
ripple_ch_GO = 122;
ripple_ch_NOGO = 27;
%CNL23 Go 91 Nogo17/Go 53 Nogo 110/9 119/ 41 107/ 47 103 (47 118) 89 113
%106 118
%CNL29 Go 73 Nogo19/Go 41 Nogo 102 works/Go53 Mogo 40 works New go9 nogo105
%( 19 100 11 26 11 21
%CNL34 Go 95 Nogo93/85 91    47 102 37 97
% xippmex('digout', 4, 1); % go19 nogo115  11 66 15 12 9 39 9 30 33 30
%CNL41 40 115 124 27
% Write stim trials to CSV
write_trials_to_csv(p_go, total_trials, ripple_ch_GO, ripple_ch_NOGO);
trial_table = readtable('C:/Users/xiela/OneDrive/Desktop/precomputed_trials.csv');

%% Start experiment

for i = 1:total_trials

    % Define Ripple stimulation cmd
    phase_len = round(pulse_width/33.33);
    pulse_period = 30000/stim_freq;
    current_steps = current * step_factor; 
    ipi_len = round(interphase_interval/33.33);
    stim_channel = trial_table.stim_channel(i);
    trial_type = trial_table.trial_type(i);

    cmd = struct('elec',stim_channel,'period',pulse_period,...
    'repeats',max_go_trial_s * stim_freq);
    cmd.seq(1) = struct('length', phase_len, 'ampl', current_steps, 'pol', 0, ...
                             'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);
    cmd.seq(2) = struct('length', ipi_len, 'ampl', 0, 'pol', 0, 'fs', 0, ...
                            'enable', 0, 'delay', 0, 'ampSelect', 1);
    cmd.seq(3) = struct('length', phase_len, 'ampl', current_steps, 'pol', 1, ...
                             'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);

    fprintf('Trial %d with current %d uA at channel %d\n', i, current, stim_channel);

    % Stimulate when trigger pulse received from BPod 
    fprintf('Waiting for trigger pulse...\n');
    xippmex('digin');
    count = 0;
    while count == 0
       % events
       [count, timestamps, events] = xippmex('digin');
    end
    fprintf('Sending stim\n');
    % Stimulate
    tic;
    xippmex('stimseq', cmd); 
    stim_latency = toc;
    tic;
    
    xippmex('digin');
    count = 0;
    while count == 0 
        [count, timestamps, events] = xippmex('digin');
    end
    trial_time = toc;
    % End stimulation 
    xippmex('stim', 'enable', 0);
    pause(0.5) % important!
    xippmex('stim', 'enable', 1);
    if strcmp(trial_type, 'go')
        max_trial_s = max_go_trial_s;
    elseif strcmp(trial_type, 'no-go')
        max_trial_s = max_no_go_trial_s;
    end

    if trial_time < 0.95*(max_trial_s - stim_latency)
        fprintf('Turn detected!\n\n')    
        response = 1;  
    elseif trial_time > max_trial_s * 1.2
        fprintf('Misalignment detected! Ending experiment.\n');
        beep();
        break;
    else
        response = 0;
        fprintf('No turn detected!\n\n') 
    end  
    
end