% This script is used to automate the ICMS + imaging channel survey procedure 
% for the Ripple Neural Interface Processor. 

%% PulsePal 
disp('Please disconnect BNC cable from Bpod and connect to PulsePal!')
addpath(genpath('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\lib\PulsePal-master\'))
clear PulsePalSystem
PulsePal('COM8') % If error, go to Device Manager and find COM port for Arduino Due
load ParameterMatrix_Example.mat; % Loads the default parameter matrix
ProgramPulsePal(ParameterMatrix);

Voltages = 5;
PulseTimes = 0.01; % Start first stim pulse batch after delay of 0.01 seconds

% Output channel 1 controls the imaging 
SendCustomPulseTrain(1, PulseTimes, Voltages); % Uploads our train in slot 1 of 2
ProgramPulsePalParam(1, 14, 1); % Sets output channel 1 to use custom train 1
ProgramPulsePalParam(1, 4, 0.01); % Sets output channel 1 to use 100 ms pulses
%% Create directory to save data

subFolder = fullfile(parentFolder,'imageSurvey');
if ~isfolder(subFolder); mkdir(subFolder); end

fprintf('Data will be saved in %s\n',subFolder);

%% Stimulation parameters
% Time between start of scan and start of next scan should be
% stim_and_wait_time
% If you want N seconds between end of stim and start of baseline,
% stim_and_wait_time - stim_time needs to be N

stim_time = 2.3; % Stim time, also the imaging time, 2.3 for 300 um, 2s for 250 um, 1.7s for 200 um, 
stim_and_wait_time = 5.5; % Includes stim_time 5.5s for 300 um stack, 4.5s for 250 um, 4s for 200 um


%% SURVEY CODE STARTS HERE

ch_idx = 3; % iterate through 1 to 3
frequency = 100; % iterate through 20, 50, 100 Hz
phaseLen = 5; % iterate through 3, 5, 6 steps (100, 167, 200 us)
current = 7 ; % iterate through 3,5,7 uA
currentStr = strrep(num2str(current),'.','_');

sessionIntanCh = intanChannels(ch_idx);
sessionRippleCh = rippleChannels(ch_idx);
sessionDepthIndex = depthIndices(ch_idx);

clock_freq = 30000/frequency;
interpulse_interval = 1/frequency;
train_freq = 1; % Frequency of train; 
train_period = 1/train_freq;
duty_cycle = 1; % Percentage of period burst occurs 
stim_duration_NIP_clock = 30000/frequency;
nTrials = 20;

replicate = generateReplicate(sessionRippleCh,current,nTrials);

fileName = fullfile(subFolder,strcat('D',num2str(sessionDepthIndex), '_', currentStr, 'uA'));
% fileName = fullfile(subFolder,strcat('D',num2str(sessionDepthIndex), '_', num2str(frequency), 'Hz_', currentStr, 'uA'));
% fileName = fullfile(subFolder,strcat('D',num2str(sessionDepthIndex), '_', num2str(round(phaseLen*33.33)), 'us_', currentStr, 'uA'));
fprintf('File name: %s\n',fileName);
xippmex('stim', 'enable', 0);
xippmex('stim', 'res', elecs, 1);
xippmex('stim', 'enable', 1);
%% Run this after imaging

xippmex('trial', 'recording', fileName); % enable recording
pause(1); 
for i = 1:nTrials
    
    stim_ch = replicate{i,1};
    stim_current = replicate{i,2};

    if stim_ch == 0
        baseline_tic = tic;
        fprintf('Depth index %d, scan %d / %d at baseline\n',sessionDepthIndex,i,nTrials)
        TriggerPulsePal(1); % PulsePal will trigger stim and image scan simulateneously
        pause(stim_and_wait_time); % baseline time
        toc(baseline_tic)
    else 
        stim_tic = tic;
        fprintf('Depth index %d, scan %d / %d at stim current %d uA\n',...
            sessionDepthIndex,i,nTrials,current)
        current_steps = stim_current; % HAVE TO MULTIPLY BY 2 FOR 0.5 uA STEP!!!
        cmd = struct('elec',stim_ch,'period',stim_duration_NIP_clock,'repeats',stim_time*frequency);
        
        % first phase
        cmd.seq(1) = struct('length', phaseLen, 'ampl', current_steps, 'pol', 0, ...
                                 'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);
        % interphase interval
        cmd.seq(2) = struct('length', 2, 'ampl', 0, 'pol', 0, 'fs', 0, ...
                                'enable', 0, 'delay', 0, 'ampSelect', 1);
        % second phase 
        cmd.seq(3) = struct('length', phaseLen, 'ampl', current_steps, 'pol', 1, ...
                                 'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);
        TriggerPulsePal(1); % PulsePal will trigger stim and image scan simulateneously
        % 100% duty cycle
        xippmex('stimseq', cmd);
        pause(stim_and_wait_time);
        toc(stim_tic)
    end
end
pause(0.2)
xippmex('trial', 'stopped', fileName);
fprintf('Survey complete!\n')

% %% Post-stimulate impedances 
% xippmex('stim', 'enable', 0); % Enable 0 to start impedances 
% disp("Running post-stimulation impedance test..."); fprintf('\n');
% poststim_impedances = xippmex('impedance', elecs(1:32));
% save(fullfile(subFolder,'poststim_impedances'),'poststim_impedances');

%%
function replicate = generateReplicate(channel,current,trials)
    try 
        assert(mod(trials,2) == 0);
    catch
        error('Trials (%d) is not an even number.',trials);
    end
    
    replicate = cell(trials,2);
    for i = 1:trials
        replicate{i,1} = channel;    
        if mod(i,2) == 0
           replicate{i,1} = channel;
           replicate{i,2} = current; 
        else
           replicate{i,1} = 0;
           replicate{i,2} = 0;
        end
    end
end