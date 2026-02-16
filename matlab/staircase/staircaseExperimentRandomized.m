%%
addpath('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\2Pimaging\xippmex');
cd('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\Behavioral\Staircase');
addpath('\\10.129.151.108\xieluanlabs\xl_stimulation\Robin\ImpedanceAnalysis');
staircase = staircaseParams();
unpackStruct = @(s) cellfun(@(name) assignin('base',name,getfield(s,name)),fieldnames(s));
unpackStruct(staircase);
unpackStruct(stim_params);
%% NIP Hardware Initialization 
disp('Initializing Ripple Neural Interface Processor...'); fprintf('\n');
% Initialize xippmex
status = xippmex;
if status ~= 1; error('Xippmex Did Not Initialize'); end
% Give the NIP some time to process any commands we have sent
pause(0.5)
elecs = xippmex('elec', 'pico');
% xippmex('signal', elecs(1), 'lfp', 0) 
% fprintf('LFP data stream disabled...\n');
xippmex('signal', elecs, 'spk', 0);
fprintf('Spike data stream disabled...\n');
xippmex('signal', elecs(1), 'raw', 1)
fprintf('Raw data stream enabled...\n\n');
%% Important!!! Set correct stim step size. For 0.5 uA step size, resolution must be index 5. 
xippmex('stim', 'enable', 0); % Enable 0 to start impedances 
disp("Running pre-stimulation impedance test..."); fprintf('\n');
prestim_impedances = xippmex('impedance', elecs(1:32));
xippmex('stim', 'res', elecs, 1);
xippmex('stim', 'enable', 1);

save(fullfile(save_dir,'prestim_impedances.mat'),'prestim_impedances'); % save locally 
save(fullfile(server_impedance_path,strcat(date,'.mat')),'prestim_impedances'); % save in server 
generateImpedancePlot2P(fullfile(server_impedance_path,strcat(date,'.mat')),save_dir)
fprintf('Impedance test complete!\n')

disp("Pre-stimulation impedance test complete!"); fprintf('\n');
%%
nCH = numel(Ripple_stim_channel);
ch_vec = 1:nCH;
ch_vec_rnd = randperm(length(ch_vec));
channels_done = [];

file_name = 'staircase_ephys_recording';
xippmex('trial', 'recording', fullfile(save_dir,file_name)); 
figure;
for i = 1:nCH
ch_idx = ch_vec_rnd(i);
nexttile
hold on
reversal = false;
current = init_current;
results = zeros(max_trials,5); % trial, current, hit/miss, reversal, response time
stim_channel = Ripple_stim_channel(ch_idx);
Intan_stim_channel_name = Intan_stim_channel(ch_idx);
last_response = 0;
reversal_count = 0;

for trial_i = 1:max_trials
    
    fprintf('\nIntan channel %d/Ripple channel %d: Trial %d\n', Intan_stim_channel_name,...
        stim_channel, trial_i);
    % Change stimulation parameters
    cmd = struct('elec',stim_channel,'period',stim_duration_NIP_clock,'repeats',trial_length*stim_freq); 
    cmd.seq(1) = struct('length', phase_len, 'ampl', current, 'pol', 0, ...
                             'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);
    cmd.seq(2) = struct('length', IPI_len, 'ampl', 0, 'pol', 0, 'fs', 0, ...
                            'enable', 0, 'delay', 0, 'ampSelect', 1);
    cmd.seq(3) = struct('length', phase_len, 'ampl', current, 'pol', 1, ...
                             'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1); 
    % Stimulate when trigger pulse received from BPod 
    fprintf('Current is %d uA. Waiting for trigger pulse...\n',current);
    xippmex('digin');
    count = 0;
    while count == 0
       [count, timestamps, events] = xippmex('digin');
    end
    % Stimulate
    if current ~= 0 
        xippmex('stimseq', cmd);
    end
    tic;
    pause(0.01)
    fprintf('Stimulating...\n')

    xippmex('digin');
    count = 0;
    while count == 0 
        [count, timestamps, events] = xippmex('digin');
    end
    trial_time = toc;
    % End stimulation 
    xippmex('stim', 'enable', 0);
    pause(0.5) % important!
    xippmex('stim', 'enable', 1);
    % Evaluate response to stimulus
    if trial_time < trial_length
        response = 1;
        fprintf('Hit!\n')    
    else
        response = 0;
        fprintf('Miss!\n') 
    end
    % Change step direction based on response since 1 Up/1 Down staircase
    if response 
        step_direction = -1;
    else 
        step_direction = 1;
    end
 
    if last_response ~= response && trial_i > 1
        reversal = true;
        reversal_count = reversal_count + 1;
        fprintf('Reversal #%d!\n',reversal_count);
    else
        reversal = false;    
    end
    
    % Record data in results array
    results(trial_i,1) = trial_i;
    results(trial_i,2) = current;
    results(trial_i,3) = response;  
    results(trial_i,4) = reversal == 1;  
    results(trial_i,5) = trial_time;
    
    hits = find(results(1:trial_i,3) == 1);
    misses = find(results(1:trial_i,3) == 0);
    
    % Plot in real time
    colors = [[1 1 1];[0 0 0]];
    color = colors(response+1,:);
    p = plot(results(1:trial_i,1),results(1:trial_i,2),'k');
    sctr = scatter(results(trial_i,1),results(trial_i,2),50,'s','filled',...
        'MarkerEdgeColor',[0 0 0],'MarkerFaceColor',color);
    uistack(p,'bottom')
    hold on;
    
    % Stop condition
    ceiling_cond = 0;
    if trial_i > 10 && all(results(trial_i-3:trial_i-1,2) == max_current)
        ceiling_cond = 1;
    end
    if reversal_count == reversals || trial_i == max_trials || ceiling_cond 
        fprintf('Channel test complete!\n\n')
        break
    end
        
    if trial_i == 1 || reversal_count < 3
        step_size = init_step;
    else
        step_size = step;
    end
    fprintf('Step size is %d uA.\n\n',step_size);
    % Next trial current
    current = max(min(current + step_size * step_direction, max_current),0); 
    last_response = response; 
end

channels_done = [channels_done Intan_stim_channel_name];
reversal_col = results(:,4);
current_col = results(reversal_col == 1,2);
try
    reversal_mean = round(mean(current_col(end-avg_n_last_reversals+1:end)),2);
catch
    reversal_mean = round(mean(current_col),2);
end
if ceiling_cond 
    reversal_mean = NaN;
    title(strcat('Ch.',string(Intan_stim_channel_name),' threshold: nan'));
else
    title(strcat('Ch.',string(Intan_stim_channel_name),' threshold: ',{' '},string(reversal_mean),'uA'));
end

staircase.results{ch_idx} = results;
staircase.thresholds{ch_idx} = reversal_mean;
end
xippmex('trial', 'stopped', fullfile(save_dir,file_name));

xippmex('stim', 'enable', 0); % Enable 0 to start impedances 
disp("Running post-stimulation impedance test..."); fprintf('\n');
poststim_impedances = xippmex('impedance', elecs(1:32));
xippmex('stim', 'enable', 1);
save(fullfile(save_dir,'poststim_impedances'),'poststim_impedances');
%

struct_name = [fullfile(save_dir,date) '_staircase.mat'];
save(struct_name,'staircase');

sgtitle(strcat(animalID,{' '}, date, {' '}, 'staircase method results'))
saveas(gcf,[fullfile(save_dir,date) '_staircase.png'])
fprintf('Experiment done!\n')
