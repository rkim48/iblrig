% SESSIONHELPER - Configure stimulus blocks for the current session
% Refactored for iblrig v8 integration

% Default experiment parameters if not set by main.m
if ~exist('expType', 'var'); expType = 'Planar'; end
if ~exist('expParam', 'var'); expParam = 'Channel'; end
if ~exist('ch_idx', 'var'); ch_idx = 1; end % Default to first channel in map

% Configure trial counts based on experiment type
if strcmp(expType, 'Volumetric')
    trialsPerCurrent = 40;
elseif strcmp(expType, 'Planar')
    trialsPerCurrent = 10;
else
    trialsPerCurrent = 5;
end

% Map metadata from expStruct
expStruct.experimentType = expType;
expStruct.experimentParam = expParam;
intanChannels = expStruct.intanChannels;
rippleChannels = expStruct.rippleChannels;
depthIndices = expStruct.depthIndices;

% Safety check for channel index
if ch_idx > length(intanChannels)
    ch_idx = 1;
    fprintf('Warning: ch_idx out of range. Defaulting to 1.\n');
end

expStruct.channelIndex = ch_idx;
sessionIntanCh = intanChannels(ch_idx);
sessionRippleCh = rippleChannels(ch_idx);
sessionDepthIndex = depthIndices(ch_idx);

% Configure parameters for specific experiment modes
if strcmp(expParam, 'Channel')
    paramVec = rippleChannels; 
    expStruct.stimPulseWidthsArr = 167;
    expStruct.stimFreqArr = 100;
    % Load default currents or use sessionParameters values if they exist
    if exist('ch_c', 'var')
        c = ch_c;
    else
        c = repmat([5, 7, 9], length(paramVec), 1); % Default currents
    end
    ch_idx_list = 1:numel(paramVec);
elseif strcmp(expParam, 'Frequency') 
    paramVec = expStruct.stimFreqArr; 
    expStruct.stimPulseWidthsArr = 167;
    if exist('fpw_c', 'var')
        c = fpw_c;
    else
        c = repmat([5, 7, 9], length(paramVec), 1);
    end
elseif strcmp(expParam, 'PulseWidth')
    paramVec = expStruct.stimPulseWidthsArr;  
    expStruct.stimFreqArr = 100;
    if exist('fpw_c', 'var')
        c = fpw_c;
    else
        c = repmat([5, 7, 9], length(paramVec), 1);
    end
end

expStruct.currentArr = c;
expStruct.trialsPerCurrent = trialsPerCurrent;

% Total trials includes catch trials (current = 0)
expStruct.totalTrials = trialsPerCurrent * numel(expStruct.currentArr) + trialsPerCurrent;

% Generate stimulus blocks using getStimBlocks function
blocks = getStimBlocks(expStruct);
expStruct.blocks = blocks;

% Log session info
fprintf(['\nSession Configuration:\n' ...
    'Animal: %s\n' ...
    'Experiment: %s (%s)\n' ...
    'Total Trials: %d\n'], ...
    expStruct.animalID, expType, expParam, expStruct.totalTrials);
