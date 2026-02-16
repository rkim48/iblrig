function ripple_channels = depth2ripple(depth_indices)

% Assume 32 channel Omnetics mapping
% fprintf('Loading 32OmneticsChMap\n');

load('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\channel_maps\32OmneticsChMap.mat','channel_map');

% More intuitive to have depth of 1 as most shallow channel 
ripple_channels = channel_map(depth_indices,3);

% Test
% depth_indices = [1,2,31,32]
% Expected Ripple channels: [32,15,19,4]