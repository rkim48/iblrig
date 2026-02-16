function staircase = staircaseParams()
% STAIRCASEPARAMS - Configuration for staircase paradigm
% Refactored for iblrig v8 integration

%% Get current project structure
this_dir = fileparts(mfilename('fullpath'));
staircase_root = this_dir;
matlab_root = fileparts(staircase_root);
lib_dir = fullfile(matlab_root, 'lib');
channel_maps_dir = fullfile(lib_dir, 'channel_maps');

% Add channel maps to path
addpath(channel_maps_dir);

% Load 32LinearChMap.mat
c = load(fullfile(channel_maps_dir, '32LinearChMap.mat'));
channel_map = c.channel_map; clear c;

% for nCH stimulation channels, assume staircase params are constant
% store results array for each stimulation channel in parent results array
staircase.init_step = 3;
staircase.step = 1;
staircase.reversals = 9;
staircase.avg_n_last_reversals = 4;
staircase.n_up = 1;
staircase.n_down = 1;
staircase.max_trials = 25;
staircase.min_current = 1;
staircase.max_current = 20; %30
staircase.init_current = 10; %10

% Stim parameters
staircase.stim_params.phase_len = 5; % cathodic/anodic length in 33.3 us steps
staircase.stim_params.IPI_len = 2; % interphase interval
staircase.stim_params.trial_length = 0.95; % seconds
staircase.stim_params.stim_freq = 100; % Frequency within train 
staircase.stim_params.stim_duration_NIP_clock = 30000/staircase.stim_params.stim_freq;
add_str = ''; % useful if more than 1 session in one day, else leave empty

% Select animal folder (local preferred in v8)
animal_dir = uigetdir('C:/data/ICMS', 'Select animal folder');
if isequal(animal_dir, 0)
    error('Selection cancelled.');
end
[~, animalID, ~] = fileparts(animal_dir);
fprintf('Animal ID is %s.\n', animalID);

% Paths
server_impedance_path = fullfile(matlab_root, 'data', 'Impedances', animalID);
if ~isfolder(server_impedance_path)
    mkdir(server_impedance_path)
end

staircase.server_impedance_path = server_impedance_path;
staircase.date = date;

% Use all channels with good voltage transient measures
switch animalID 
    case 'ICMS24'
        Intan_stim_ch = [14 5 15 4 20 31 21 22 29 23 18 26 27]; % Intan channels
    case 'ICMS25'
        Intan_stim_ch = 4;
    case 'ICMS37'
        Intan_stim_ch = [12 11 0 10 1 2 13 14 15];
    case 'ICMS42'
        Intan_stim_ch = [21 22 29 23 28 19 24 18 26 27];
    case 'ICMS44'
        Intan_stim_ch = [16 17 20 21 22 23 24 25 26 29 30 31];
    case 'ICMS39'
        Intan_stim_ch = [25 28 31 29 27 26];
    case 'ICMS49'
        Intan_stim_ch = [7,13,6,14,5,15,4,20,31,21,22,19,18,25,16];
    case 'ICMS52'
        Intan_stim_ch = [10 9 8 12 13 14 15 20 21 22 23 19 24 25 26 27];
    case 'test'
        Intan_stim_ch = [1 2 3];
    otherwise
        warning('Unknown animalID! Using default map [1, 2, 3].');
        Intan_stim_ch = [1 2 3];
end

stim_channels = zeros(numel(Intan_stim_ch),1);
for ch = 1:numel(Intan_stim_ch)
    idx = channel_map(:,2)==Intan_stim_ch(ch);
    if any(idx)
        stim_channels(ch) = channel_map(idx, 3);
    else
        warning('Intan channel %d not found in channel map.', Intan_stim_ch(ch));
    end
end

staircase.animalID = animalID;
staircase.Intan_stim_channel = Intan_stim_ch;
staircase.Ripple_stim_channel = stim_channels;
staircase.results = cell(numel(Intan_stim_ch),1);
staircase.thresholds = cell(numel(Intan_stim_ch),1);

save_dir = fullfile(animal_dir, [date add_str]);
if ~isfolder(save_dir)
    mkdir(save_dir)
end
staircase.save_dir = save_dir;

fprintf('Staircase parameters for %s loaded!\n', animalID)
end
