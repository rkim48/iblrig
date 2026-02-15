addpath(genpath('C:\iblrigv8\matlab\util\'));
addpath('C:\iblrigv8\matlab\lib\xippmex\');
load('beep.mat','y');

%% Trek Hardware Initialization (takes a minute)
ripple;

%% Fixed stim waveform parameters (shared across trials)
pulse_width = 167;           % us (per phase)
interphase_interval = 67;    % us
stim_freq = 50;             % Hz
stim_duration_s = 0.5;         % seconds of stimulation per trial

%% Trial list parameters (what varies across trials)
currents_uA = [0 2];
channels    = [10 11 21 31];
num_trials_per_parameter = 1;

% Save CSV to Desktop (recommended robust way)
path = 'C:\Users\xiela\OneDrive\Desktop';
base_name = 'wf_stim';

% Generate CSV + get the trial table
[csv_path, trial_table] = write_trials_to_csv_wf_stim( ...
    currents_uA, channels, num_trials_per_parameter, path, base_name);

fprintf('Using trial CSV:\n%s\n\n', csv_path);

% Total trials comes from the table now
total_trials = height(trial_table);

%% Start experiment
for i = 1:total_trials

    % --- Pull per-trial parameters from CSV/table ---
    stim_channel = trial_table.stim_channel(i);
    current      = trial_table.current_uA(i);   % uA

    % --- Convert into Ripple units (30 kHz clock => 33.33 us per tick) ---
    phase_len     = round(pulse_width / 33.33);          % ticks
    ipi_len       = round(interphase_interval / 33.33);  % ticks
    pulse_period  = 30000 / stim_freq;                   % ticks
    current_steps = current * step_factor;               % device steps

    % --- Build stimulation command (biphasic pulse) ---
    cmd = struct('elec', stim_channel, ...
                 'period', pulse_period, ...
                 'repeats', stim_duration_s * stim_freq);

    cmd.seq(1) = struct('length', phase_len, 'ampl', current_steps, 'pol', 0, ...
                        'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);

    cmd.seq(2) = struct('length', ipi_len, 'ampl', 0, 'pol', 0, 'fs', 0, ...
                        'enable', 0, 'delay', 0, 'ampSelect', 1);

    cmd.seq(3) = struct('length', phase_len, 'ampl', current_steps, 'pol', 1, ...
                        'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);

    fprintf('Trial %d/%d: %g uA, %d Hz, ch %d, dur %.2f s\n', ...
            i, total_trials, current, stim_freq, stim_channel, stim_duration_s);

    % --- OPTIONAL: wait for external trigger (comment out if not needed) ---
    fprintf('Waiting for trigger pulse...\n');
    xippmex('digin');
    count = 0;
    while count == 0
        [count, timestamps, events] = xippmex('digin');
    end

    % --- Send stim ---
    fprintf('Sending stim\n');
    tic;
    xippmex('stimseq', cmd);
    stim_call_time = toc;   % software call overhead (not true pulse onset)

    % --- Reset stim hardware between trials ---
    xippmex('stim', 'enable', 0);
    pause(0.5);             % important!
    xippmex('stim', 'enable', 1);

    fprintf('stimseq call returned in %.4f s\n\n', stim_call_time);

end
