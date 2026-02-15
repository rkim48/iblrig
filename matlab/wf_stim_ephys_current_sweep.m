% Get the directory of the current script
base_path = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(base_path, 'util')));
addpath(fullfile(base_path, 'lib', 'xippmex'));
load(fullfile(base_path, 'util', 'beep.mat'),'y');

%% Trek Hardware Initialization (takes a minute)
ripple;

%% ---------------- Ripple: verify + set stim resolution ----------------
status = xippmex;
if status ~= 1
    error('Xippmex Did Not Initialize');
end
pause(0.5);

elecs = xippmex('elec','micro');          % electrode list
xippmex('stim','enable',0);
xippmex('stim','res', elecs, 1);          % 1 uA resolution (important for amplitude mapping)
xippmex('stim','enable',1);

%% ---------------- Create save folder + start ephys recording ----------------
% Default to a data folder in the repository root if it exists, otherwise use home directory
repo_root = fileparts(base_path);
if exist(fullfile(repo_root, 'data'), 'dir')
    parent_dir = fullfile(repo_root, 'data');
else
    parent_dir = fullfile(char(java.lang.System.getProperty('user.home')), 'Documents', 'iblrig_data');
end
animal_dir = uigetdir(parent_dir,'Select animal folder');
date_str   = datestr(now, 'yyyy-mm-dd');
save_path  = fullfile(animal_dir, date_str, 'WF_StimSurvey');

if ~exist(save_path, 'dir')
    mkdir(save_path);
end
fprintf('Data will be saved in %s\n', save_path);

time_str = datestr(datetime, 'HHMMSS');
ephys_filename = fullfile(save_path, ['ephys_' time_str]);   % Trellis will add extensions as needed
fprintf('Ephys file name: %s\n', ephys_filename);

xippmex('trial','recording', ephys_filename);
pause(1);
fprintf('Recording started.\n');

%% ---------------- Fixed stim waveform parameters ----------------
pulse_width        = 167;   % us (per phase)
interphase_interval= 67;    % us
stim_freq          = 50;    % Hz
stim_duration_s    = 0.5;   % seconds of stimulation per trial

%% ---------------- Trial list parameters (vary by trial) ----------------
currents_uA = [0 2 3 4 5 7];
channels    = [4 16 18 38 52 63 75 114 117 122];
num_trials_per_parameter = 30;


% Save CSV into same save_path for recordkeeping
base_name = 'wf_stim_trials';

[csv_path, trial_table] = write_trials_to_csv_wf_stim( ...
    currents_uA, channels, num_trials_per_parameter, save_path, base_name);

fprintf('Using trial CSV:\n%s\n\n', csv_path);

total_trials = height(trial_table);

%% ---------------- Run stimulation trials ----------------
% Log a few extra things for debugging/alignment
stim_call_time = nan(total_trials,1);
trial_wallclock = strings(total_trials,1);

try
    for i = 1:total_trials

        stim_channel = trial_table.stim_channel(i);
        current_uA   = trial_table.current_uA(i);

        % --- Convert into Ripple units (30 kHz clock => 33.33 us/tick) ---
        phase_len     = round(pulse_width / 33.33);           % ticks
        ipi_len       = round(interphase_interval / 33.33);   % ticks
        pulse_period  = 30000 / stim_freq;                    % ticks

        % If ripple.m defines step_factor, use it; otherwise assume 1 uA/step after stim res=1
        if exist('step_factor','var')
            current_steps = current_uA * step_factor;
        else
            current_steps = current_uA;  % with xippmex stim res = 1 uA, this is typically correct
        end

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
                i, total_trials, current_uA, stim_freq, stim_channel, stim_duration_s);

        % --- Optional external trigger (keep if BPod/camera triggers trials) ---
        fprintf('Waiting for trigger pulse...\n');
        xippmex('digin');
        count = 0;
        while count == 0
            [count, ~, ~] = xippmex('digin');
        end

        % --- Send stim ---
        fprintf('Sending stim\n');
        t_start = tic;
        xippmex('stimseq', cmd);
        stim_call_time(i) = toc(t_start);
        trial_wallclock(i) = string(datetime('now'));

        xippmex('digin');
        count = 0;
        while count == 0 
            [count, timestamps, events] = xippmex('digin');
        end

        % --- Reset stim hardware between trials (kept from your original code) ---
        xippmex('stim', 'enable', 0);
        pause(0.5);
        xippmex('stim', 'enable', 1);

        fprintf('stimseq call returned in %.4f s\n\n', stim_call_time(i));
    end

catch ME
    fprintf('\nERROR/STOP: %s\n', ME.message);
    beep();
end

%% ---------------- Stop recording + save logs ----------------
pause(0.5);
xippmex('trial','stopped', ephys_filename);
fprintf('Recording stopped.\n');

RunLog.csv_path        = csv_path;
RunLog.ephys_filename  = ephys_filename;
RunLog.stim_call_time  = stim_call_time;
RunLog.trial_wallclock = trial_wallclock;
RunLog.stim_freq       = stim_freq;
RunLog.stim_duration_s = stim_duration_s;
RunLog.pulse_width_us  = pulse_width;
RunLog.interphase_us   = interphase_interval;

save(fullfile(save_path, ['runlog_' time_str '.mat']), 'RunLog');

fprintf('Done. Saved run log to %s\n', save_path);
