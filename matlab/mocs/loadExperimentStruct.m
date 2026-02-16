function expStruct = loadExperimentStruct(animalID)
% LOADEXPERIMENTSTRUCT - Load animal-specific stimulation parameters
% Refactored for iblrig v8 integration

%% Get the directory of the current script
this_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(this_dir);

% Add utility paths
addpath(fullfile(matlab_root, 'util'));

expStruct.animalID = animalID;
expStruct.sessionDate = datetime("today");
expStruct.stimFreqArr = [20, 50, 100];
expStruct.stimPulseWidthsArr = [100, 167, 200];
expStruct.IPILen = 2; % 33 us steps 

% Trial parameter defaults
expStruct.trialLength = 0.7; % seconds

% Animal-specific channel maps (Selection)
switch animalID 
    case 'ICMS83'
        intanChannels = [10, 27, 12];
    case 'ICMS92'
        intanChannels = [1, 3, 20];
    case 'ICMS93'
        intanChannels = [1, 3, 20];
    case 'ICMS98'
        intanChannels = [10, 27, 12];
    case 'ICMS100'
        intanChannels = [29, 27, 12];
    case 'ICMS101'
        intanChannels = [23, 3, 20];
    case 'test'
        intanChannels = [1, 2, 3];
    otherwise
        warning('Unknown animalID! Using default map [1, 2, 3].');
        intanChannels = [1, 2, 3];
end

% Convert Intan to Ripple and depth indices using localized utilities
% (Assumes intan2ripple and intan2depth are in matlab/util/)
rippleChannels = intan2ripple(intanChannels);
depthIndices = intan2depth(intanChannels);

expStruct.intanChannels = intanChannels;
expStruct.rippleChannels = rippleChannels;
expStruct.depthIndices = depthIndices;

fprintf('Stimulation parameters for %s loaded successfully.\n', animalID)
end
