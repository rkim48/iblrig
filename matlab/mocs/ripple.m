% RIPPLE - Hardware Initialization and Impedance Test
% Refactored for iblrig v8 integration

%% Get the directory of the current script
this_dir = fileparts(mfilename('fullpath'));
matlab_root = fileparts(this_dir);

%% NIP Hardware Initialization 
disp('Initializing Ripple Neural Interface Processor...'); fprintf('\n');

% Initialize xippmex
status = xippmex;
if status ~= 1; error('Xippmex Did Not Initialize'); end

% Give the NIP some time to process any commands we have sent
pause(0.5)
elecs = xippmex('elec', 'pico');

% Configure data streams
xippmex('signal', elecs, 'lfp', 0);  % 0 = disable
fprintf('LFP data stream disabled...\n');
xippmex('signal', elecs, 'spk', 1);  % 1 = enable
fprintf('Spike data stream enabled...\n');
xippmex('signal', elecs, 'raw', 1);  % 1 = enable
fprintf('Raw data stream enabled...\n\n');

%% Stim resolution and impedance measurement
xippmex('stim', 'enable', 0); 
disp("Running pre-stimulation impedance test..."); fprintf('\n');

% Impedance test
prestim_impedances = xippmex('impedance', elecs(1:32));

% Configure stim resolution (1 uA)
xippmex('stim', 'res', elecs, 1); 
xippmex('stim', 'enable', 1);

% Save impedance locally
sessionDate = char(datetime('today', 'Format', 'yyyy-MM-dd'));
local_impedance_path = fullfile(matlab_root, 'data', 'Impedance');
if ~isfolder(local_impedance_path); mkdir(local_impedance_path); end
save(fullfile(local_impedance_path, [sessionDate '.mat']), 'prestim_impedances');

disp("Pre-stimulation impedance test complete!"); fprintf('\n');

% Determine step factor
if xippmex('stim', 'res', elecs) == 5
    stepFactor = 2;
    fprintf('Using step size of 0.5 uA!\n');
else
    stepFactor = 1;
    fprintf('Using step size of 1 uA!\n');
end