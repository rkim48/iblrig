function intan_channels = depth2intan(depth_indices)

% Assume 32 channel Omnetics mapping
% fprintf('Loading 32OmneticsChMap\n');
% 
load('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\channel_maps\32OmneticsChMap.mat','channel_map');

% More intuitive to have depth of 1 as most shallow channel 
intan_channels = channel_map(depth_indices,2);

% Test
% depth_indices = [1,2,31,32]
% Expected Intan channels: [31,8,6,17];