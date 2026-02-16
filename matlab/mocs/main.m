function main(animalID)
% MAIN - Stimulation server for MoCS paradigm
% Refactored for iblrig v8 integration

%% Get the directory of the current script
this_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(this_dir);
addpath(genpath(fullfile(matlab_root, 'util')));
addpath(fullfile(matlab_root, 'lib', 'xippmex'));
load(fullfile(matlab_root, 'util', 'beep.mat'),'y');

if nargin < 1
    animalID = input('Enter Animal ID: ', 's');
end

%% SELECT ANIMAL & LOAD METADATA
expStruct = loadExperimentStruct(animalID);
expType = 'Planar';   % Default to Planar or prompt
expParam = 'Channel'; % Default or prompt

% Local data paths
parentFolder = fullfile('C:/data/ICMS', animalID, char(datetime('today', 'Format', 'yyyy-MM-dd')));
if ~isfolder(parentFolder); mkdir(parentFolder); end

%% NIP Hardware Initialization 
ripple;

%% Session parameters 
blockNumber = 1;
sessionHelper; % This script sets up 'blocks' based on expStruct

%% Run method of constant stimuli
block = blocks{blockNumber};
fprintf('\n\tStarting Block %d\n----------------\n\n', blockNumber);

a = datetime;
time_str = strcat('H', num2str(a.Hour), 'M', num2str(a.Minute));
baseName = fullfile(parentFolder, strcat('block', num2str(blockNumber)));
struct_name = [baseName '_' time_str '_behavior.mat'];
ephysFileName = strcat(baseName, '_', time_str, '_ephys');

fprintf('Behavior log: %s\nEphys file: %s\n', struct_name, ephysFileName);

% Start Ephys
xippmex('trial', 'recording', ephysFileName); 

currents = block{:,1};
stimParams = block{:,2};
totalTrials = length(currents);
trialLength = expStruct.trialLength; % seconds
trialData = zeros(totalTrials, 7);

for i = 1:totalTrials
    current = currents(i);
    stimParam = stimParams(i);
    
    % Define stimulation (channel, freq, etc.)
    if strcmp(expParam, 'Channel')
        sessionRippleCh = stimParam;
    elseif strcmp(expParam, 'Frequency')
        frequency = stimParam; 
    else
        pulseWidth = stimParam; 
    end

    % Ripple Command Construction
    phaseLen = round(expStruct.stimPulseWidthsArr(1)/33.33); % or from stimParam
    pulsePeriod = 30000/expStruct.stimFreqArr(1);           % or from stimParam
    currentSteps = current * stepFactor; 
    IPILen = expStruct.IPILen;

    cmd = struct('elec', sessionRippleCh, 'period', pulsePeriod, 'repeats', trialLength*100); % or freq
    cmd.seq(1) = struct('length', phaseLen, 'ampl', currentSteps, 'pol', 0, 'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);
    cmd.seq(2) = struct('length', IPILen, 'ampl', 0, 'pol', 0, 'fs', 0, 'enable', 0, 'delay', 0, 'ampSelect', 1);
    cmd.seq(3) = struct('length', phaseLen, 'ampl', currentSteps, 'pol', 1, 'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);

    fprintf('Trial %d: Current %d uA at stimParam %d\n', i, current, stimParam);

    % Wait for trigger pulse from Bpod (BNC1 output in Python)
    fprintf('Waiting for Python trigger...\n');
    xippmex('digin');
    stim_trigger = false;  
    while ~stim_trigger
       [~, ~, events] = xippmex('digin');
       % sma2 corresponds to Bpod BNC1 input on Ripple
       stim_trigger = (isfield(events, 'sma2') && ~isnan(events.sma2) && events.sma2 > 0);
    end
    
    if current > 0    
        tic;
        xippmex('stimseq', cmd);   
        stimLatency = toc;
        fprintf('Stimulating...\n');
    else
        fprintf('Catch trial (no stimulation)...\n');
        stimLatency = 0;
    end

    % Wait for response or end of trial trigger
    tic;
    xippmex('digin');
    resp_trigger = false;  
    while ~resp_trigger
       [~, ~, events] = xippmex('digin');
       % Listen for SMA2 (Tup or move)
       resp_trigger = (isfield(events, 'sma2') && ~isnan(events.sma2) && events.sma2 > 0);
    end
    trialTime = toc;
    
    % Log data (simplified for this refactor)
    trialData(i,1) = i;
    trialData(i,2) = current;
    trialData(i,3) = (trialTime < (trialLength * 0.95)); % Simplified response detection
    trialData(i,4) = trialTime;
end

% Cleanup
xippmex('trial', 'stopped', ephysFileName);
save(struct_name, 'trialData', 'expStruct');
fprintf('Experiment Block %d Complete!\n', blockNumber);
sound(y);
end