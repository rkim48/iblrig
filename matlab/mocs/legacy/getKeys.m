%% Generate behavioral keys 

sourceDir = uigetdir('D:\ICMS','Select date folder');
s = split(sourceDir,'\');
dateFolder = s{end};

% Convert the string to datetime and check if it's a datetime object
try
    datetimeObj = datetime(dateFolder);
    assert(isa(datetimeObj, 'datetime'), 'Input is not a valid datetime');
catch
    disp('Selected folder name is not a valid datetime.');
end

d = dir(sourceDir);
d = d(~ismember({d.name},{'.','..'})); % exclude specific folders

volIdx = find(contains({d.name}, 'Volumetric')==1);
volDir = fullfile(d(volIdx).folder,d(volIdx).name);  
planarIdx = find(contains({d.name}, 'Planar')==1);
if ~isempty(planarIdx)
    planarDir = fullfile(d(planarIdx).folder,d(planarIdx).name);
else
    warning('Planar scan not found!')
end
%%
for i = 1
% for i = 1:2
    if i == 1; expTypeDir = volDir; else; expTypeDir = planarDir; end
    expTypeDirSplit = split(expTypeDir,'\');
    expTypeDirLast = expTypeDirSplit{end};
    
    pattern = 'ICMS\d+';
    matches = regexp(expTypeDir, pattern, 'match');
    animalID = matches{1};
    
    serverFolder = fullfile('\\10.129.151.108\xieluanlabs\xl_stimulation',animalID,'Keys');
    targetDir = fullfile(serverFolder,dateFolder,'FrequencyVolumetric');
    % mkdir(targetDir);

    %targetDir = pwd
    d = dir(fullfile(expTypeDir,'*behavior.mat'));
    matFiles = {d.name};
    
    getKey(expTypeDir,targetDir);
end
disp("Done!")



%%
function getKey(expTypeDir,targetDir)
    % List all files matching the pattern
    files = dir(fullfile(expTypeDir, '*block*_H*M*_behavior.mat'));
    
    % Initialize a cell array to store the latest datetimes and filenames for each block
    latestInfo = cell(4, 2); % Assuming block numbers range from 1 to 4
    
    % Iterate through the files
    for i = 1:numel(files)
        filename = files(i).name;
        
        % Extract block number and HM string
        tokens = regexp(filename, 'block(\d+)_H(\d+)M(\d+)_behavior.mat', 'tokens');
        if ~isempty(tokens)
            blockNumber = str2double(tokens{1}{1});
            hour = str2double(tokens{1}{2});
            minute = str2double(tokens{1}{3});
            
            % Create a datetime object using the hour and minute
            datetimeValue = datetime('now'); % Use the current date
            datetimeValue.Hour = hour;
            datetimeValue.Minute = minute;
            
            % Compare and update the latest datetime and filename for each block
            if isempty(latestInfo{blockNumber, 1}) || datetimeValue > latestInfo{blockNumber, 1}
                latestInfo{blockNumber, 1} = datetimeValue;
                latestInfo{blockNumber, 2} = filename;
            end
        end
    end
    
    % Display the latest datetime and filenames for each block
    fileStrings = cell(4,1);
    for blockNumber = 1:size(latestInfo, 1)
        fileStrings{blockNumber} = latestInfo{blockNumber, 2};
        disp(['Block ', num2str(blockNumber), ':']);
        disp(['Latest filename: ', fileStrings{blockNumber}]);
        disp('---');
    end
    
    for i = 1:numel(fileStrings)
        fileString = fileStrings{i};
        if isempty(fileString)
            continue;
        end
        fileString = extractBefore(char(fileString),"_behavior.mat");
        nevFile = dir(fullfile(expTypeDir,strcat(fileString,'_*.nev')));
        nevFile = nevFile.name;
        fprintf('Generating key file for %s...\n',nevFile);
        getSingleKey(expTypeDir,nevFile,fileString,targetDir);
    end
    fprintf('Done!\n')
end

function plotStimRaster(group,tsVec,trials,trialStarts,fileName)
groupPlt = 4 - group;
s=spikeRasterPlot(seconds(tsVec),trials,'GroupData', groupPlt);
s.AlignmentTimes = seconds(trialStarts);
s.XLabelText = 'Time (s)';
s.YLabelText = 'Trial';
% a = regexprep(nevFile,'_',' ','emptymatch');
a = split(fileName,'\');
a = replace(a,'_',' ');
s.TitleText = a{end};
s.LegendVisible = 'on';
s.Parent.InnerPosition = [680   257   723   721];
s.Parent.OuterPosition = [672   249   739   814];
s.LegendLabels = {'Frame timestamps','Imaging start/stop','Stim start/stop','Stim timestamps'};
saveas(gcf,strcat(fileName,'.png'));
pause(1);
close;
end

function getSingleKey(expTypeDir,nevFile,fileString,targetDir)
addpath('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\lib\neuroshare\')
addpath('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\channel_maps\'    )
[~, hFile] = ns_OpenFile(fullfile(expTypeDir,nevFile)); 
% [~, nsFileInfo] = ns_GetFileInfo(fullfile(source_dir,nevFile))

time_str = extractBetween(string(nevFile),'_','_ephys');

matfileName = [fileString,'_behavior.mat'];
matFilePath = fullfile(expTypeDir,matfileName);
load(matFilePath,'expStruct');
depth_idx = expStruct.depthIndices(expStruct.channelIndex);
intan_ch = depth2intan(double(depth_idx));
trialData = expStruct.trialData;

if isempty(hFile.FileInfo(1).MemoryMap)
    return
end

all_stim_times = double(hFile.FileInfo(1).MemoryMap.Data.TimeStamp);
packetIDs = double(hFile.FileInfo(1).MemoryMap.Data.PacketID);
classIDs = double(hFile.FileInfo(1).MemoryMap.Data.Class);
if length(unique(packetIDs)) > 2
    fprintf('Ignoring spike data...\n');
    goodidx = find(packetIDs == 0 | packetIDs > 5000);
    packetIDs = packetIDs(goodidx);
    classIDs = classIDs(goodidx);
    all_stim_times = all_stim_times(goodidx);
end
classes = unique(classIDs);
img_id = find(strcmp({hFile.Entity.Label}, 'analog 1'));
rev_id = find(strcmp({hFile.Entity.Label}, 'analog 4'));
[~, ~, imgAnalogRaw] = ns_GetAnalogData(hFile, img_id, 1, hFile.TimeSpan);
[~, ~, revAnalogRaw] = ns_GetAnalogData(hFile, rev_id, 1, hFile.TimeSpan);

init_ts = find(diff(imgAnalogRaw) > 1000); % find where derivative is greater than 1000

dt = diff(init_ts); % samples between derivative threshold crossings 
img_ts = [];
for i = 1:numel(dt)
    if dt(i) > 1000 % assume 33 ms frame period 
        img_ts = [img_ts; init_ts(i)];
    end
end

frame_freq = 1/median(diff(img_ts)/3e4); % Hz
sprintf('Frame rate: %.2f\n',frame_freq);
% Extract imaging timestamps
tsVec = [];
group = [];
for i = 1:numel(classes)
    ts_i = all_stim_times(classIDs == classes(i));
    tsVec = [tsVec; ts_i];
    group = [group; i*ones(numel(ts_i),1)];
end
% 
tsVec = [tsVec; img_ts];
group = [group; 4*ones(numel(img_ts),1)];
assert(size(group,1)==size(tsVec,1));

[~,b] = sort(tsVec); % sort by time 
tsVec = tsVec(b)/3e4;
group = group(b);

trialStarts = tsVec(group == 3); % img start stop 
trialStarts = trialStarts(1:4:end);

% calculate trials by finding tsVec between trialStart and next trialStart
trials = [];
% remove timestamps before first trial 
goodidx = find(tsVec >= trialStarts(1));
tsVec = tsVec(goodidx);
group = group(goodidx);
assert(numel(tsVec) == numel(group));

for i = 1:numel(trialStarts)
    startTs = trialStarts(i);
    if i == numel(trialStarts)
        endTs = max(tsVec) + 0.001;
    else
        endTs = trialStarts(i+1);
    end

    idx = find((tsVec >= startTs) & (tsVec < endTs));
    n = numel(idx);
    x = i * ones(n,1);
    trials = [trials; x];
end

try 
    assert(numel(trials)==numel(group));
catch
    numel(trials)
    numel(group) 
    error('Different number of trials and groups for %s: %d trials vs %d groups',nevFile, numel(trials), numel(group))
end

% Create cell array with length nTRIALS

nTRIALS = max(trialData(:,1));
dataCellArr = cell(nTRIALS,1);
trialDataStruct = struct();
for i = 1:nTRIALS

stim_ts = tsVec(trials == i & group == 1);
img_start_stop = tsVec(trials == i & group == 3);
stim_start_stop = tsVec(trials == i & group == 2);
img_ts = tsVec(trials == i & group == 4);

img_start_stop = img_start_stop(1:2:end);
img_ts = img_ts(1:end);
stim_start_stop = stim_start_stop(1:2:end);
stim_ts = stim_ts(1:end);

current = trialData(i,2);
hit = trialData(i,3);
rt = diff(stim_start_stop);
if rt >= 0.695
    rt = nan;
end

if ~isempty(stim_start_stop)
    if stim_start_stop(1) > max(img_start_stop) 
        good_trial = 0;
    else
        good_trial = 1;
    end
else
    good_trial = 0;
end

if size(trialData,2) < 7
    depthIdx = trialData(i,4);
    freq = trialData(i,5);
    pw = trialData(i,6);
else
    depthIdx = trialData(i,5);
    freq = trialData(i,6);
    pw = trialData(i,7);
end

dataCellArr{i} = {current; depthIdx; freq; pw; hit; rt; ...
    good_trial; img_start_stop;img_ts;stim_start_stop;stim_ts};
trial_i_cell = dataCellArr{i};

% save as struct with names
names = {'Current', 'Depth', 'Frequency', 'PulseWidth', 'Response',...
    'ResponseTime', 'isGoodTrial', 'ImageStartStop', 'FrameTimestamps', ...
    'StimStartStop', 'StimTimestamps'};

for j = 1:11
    trialDataStruct(i).(names{j}) = trial_i_cell{j};
end

end

% Save file
filename = fullfile(targetDir,fileString);
fileString2 = strcat(fileString, '_key.mat');
filename2 = fullfile(targetDir,fileString2);
save(filename,'dataCellArr');
save(filename2,'trialDataStruct')
plotStimRaster(group,tsVec,trials,trialStarts,filename);
end