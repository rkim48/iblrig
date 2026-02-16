function depth_indices = intan2depth(intan_channels)

% Assume 32 channel Omnetics mapping
% fprintf('Loading 32OmneticsChMap\n');

load('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\channel_maps\32OmneticsChMap.mat','channel_map');

% More intuitive to have depth of 1 as most shallow channel 
[~, depth_indices] = ismember(intan_channels, channel_map(:,2));
% Test
% intan_channels = [31,8,6,17];
% Expected depth indices: [1,2,31,32]

