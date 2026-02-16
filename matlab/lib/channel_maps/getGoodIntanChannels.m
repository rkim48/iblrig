function [good_intan_channels,good_depth_idx, good_impedances] =  getGoodIntanChannels(animalID)
addpath '\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\ImpedanceAnalysis'
if ~exist('animalID','var')
    [file,path] = uigetfile('\\10.129.151.108\xieluanlabs\xl_stimulation\*.csv;*.txt','Please select impedance file');
    impedance_file = fullfile(path,file);
else
    d = dir(fullfile('\\10.129.151.108\xieluanlabs\xl_stimulation\',animalID,'Impedance/'));
    d = d(~ismember({d.name},{'.','..'})); % exclude specific folders
    datetime_strs = cellfun(@(x) datetime(extractBefore(x,'.csv'),'InputFormat','M-dd-yy'), {d.name}); % extract datetime strings
    [~,sort_idx] = sort(datetime_strs);
    d = d(sort_idx,:); % sort by date
    impedance_file = fullfile(d(1).folder,d(1).name); % get last file
end

%% Read intan impedances
map_data = load('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\channel_maps\32OmneticsChMap');
map = map_data.channel_map(:,2)+1;
T = readmatrix(impedance_file);    
unordered_impedances = T(:,5);   
impedances = unordered_impedances(map);

%% Find channels whose impedances are under 1 MOhm 
good_depth_idx = find(impedances < 1e6);
intan_channels = map_data.channel_map(:,2);
good_intan_channels = intan_channels(good_depth_idx);
good_impedances = impedances(good_depth_idx);
% good_impedances = convert2Ohm(good_impedances);

end