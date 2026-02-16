function depth_indices = ripple2depth(ripple_channels)

% Assume 32 channel Omnetics mapping
load('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\channel_maps\32OmneticsChMap.mat','channel_map');

% More intuitive to have depth of 1 as most shallow channel 
[~, depth_indices] = ismember(ripple_channels, channel_map(:,3));

% Test
% ripple_channels = [32,15,19,4];
% Expected depth indices: [1,2,31,32]

