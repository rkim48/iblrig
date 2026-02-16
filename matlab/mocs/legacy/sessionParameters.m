% Specify session parameters here

%

%% Survey parameters

isSingleParamVal = false; 
paramIndex = 2; 
trialsPerCurrentForSingleParam = 5;
trialsPerCurrentForMultiParam = 5;   
%% For channel

% % ICMS92
% c1 = [1 2 3]; % currents for each parameter value 
% c2 = [2 3 4];
% c3 = [3 4 5];

%ICMS93
% c1 = [5 6 7]; 
% c2 = [4 5 6];
% c3 = [5 6 7];

% % % %ICMS98
% c1 = [7 8 9]; 
% c2 = [9 10 11];
% c3 = [7 8 9];

% % %ICMS100
% c1 = [10 11 12]; 
% c2 = [5 6 7];
% c3 = [14 15 16];

% % ICMS101
c1 = [4 5 6]; 
c2 = [ 6 7 8];
c3 = [7 8 9];

ch_c = [c1;c2;c3];
%% For either frequency or pulse width

% % ICMS98 frequency
% ch_idx = 3 ;
% c1 = [9 10 11]; % currents for each parameter value 
% c2 = [8 9 10];
% c3 = [7 8 9];


% ICMS100 frequency
% ch_idx = 2; % channel index of good stimulation channels 
% c1 = [5 6 7]; % currents for each parameter value 
% c2 = [3 4 5];
% c3 = [4 5 6];

% ICMS101 pulse width
ch_idx = 3; % channel index of good stimulation channels 
c1 = [7 8 9]; 
c2 = [6 7 8];
c3 = [5 6 7];

% ch_idx = 3; % channel index of good stimulation channels 
% c1 = [10 11 12]; % currents for each parameter value 
% c2 = [8 9 10];
% c3 = [7 8 9];

fpw_c = [c1;c2;c3];
