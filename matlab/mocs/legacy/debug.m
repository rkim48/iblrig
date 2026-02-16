%% Run method of constant stimuli
blockNumber = 1
stepFactor = 2
fprintf('\n\tBlock %d\n----------------\n\n',blockNumber)
if size(blocks,1) > 1
    block = blocks{blockNumber};
else
    block = blocks;
end

a = datetime;
time_str = strcat('H',num2str(a.Hour),'M',num2str(a.Minute));
baseName = fullfile(subFolder,strcat('D',num2str(sessionDepthIndex),'_block',num2str(blockNumber)));

struct_name = [baseName '_' time_str '_behavior.mat'];

ephysFileName = strcat(baseName,'_',time_str,'_ephys');
fprintf('Struct name: %s\nEphys file name: %s\n',struct_name, ephysFileName);

currents = block{:,1};
stimParams = block{:,2};
totalTrials = length(currents);
trialData = zeros(totalTrials,6);
responseArr = zeros(size(currentArr));
catchTrialResponses = 0;
catchTrialCounter = 0;
totalTrialTypeArr = zeros(size(currentArr));

for i = 1:totalTrials

    current = currents(i);
    stimParam = stimParams(i);

    stimParamIdx = find(paramVec == stimParam);
    currentIdx = find(currentArr(stimParamIdx,:) == current);
    totalTrialTypeArr(stimParamIdx,currentIdx) = totalTrialTypeArr(stimParamIdx,currentIdx) + 1;
    if strcmp(expParam,'Frequency'); frequency = stimParam; else; pulseWidth = stimParam; end
    
    % Define Ripple stimulation cmd
    phaseLen = round(pulseWidth/33.33);
    pulsePeriod = 30000/frequency;
    currentSteps = current * stepFactor; 
    IPILen = expStruct.IPILen;

    cmd = struct('elec',sessionRippleCh,'period',pulsePeriod,...
    'repeats',trialLength*frequency);
    cmd.seq(1) = struct('length', phaseLen, 'ampl', currentSteps, 'pol', 0, ...
                             'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);
    cmd.seq(2) = struct('length', IPILen, 'ampl', 0, 'pol', 0, 'fs', 0, ...
                            'enable', 0, 'delay', 0, 'ampSelect', 1);
    cmd.seq(3) = struct('length', phaseLen, 'ampl', currentSteps, 'pol', 1, ...
                             'fs', 0, 'enable', 1, 'delay', 0, 'ampSelect', 1);  
    fprintf('Trial %d with current %d uA at %d %s\n',i, current, stimParam, unitStr);
  

    response = binornd(1,0.5);
    trialTime = 0.5;
    
    if current > 0    
        tic
        stimLatency = toc;
        fprintf('Stimulating...\n')  
    else
        % send 10 ms digital output pulse to tell bpod not to reward during catch trial 
        fprintf('Catch trial...\n')
        % xippmex('digout', 1, 1); pause(0.001); xippmex('digout', 1, 0);
    end
    tic
   
    if response
        if current == 0
            catchTrialResponses = catchTrialResponses + 1;
            catchTrialCounter = catchTrialCounter + 1;
            fprintf('Turn detected! False alarm!\n\n')    
        else         
            responseArr(stimParamIdx,currentIdx) = responseArr(stimParamIdx,currentIdx) + 1;
            fprintf('Turn detected!\n\n')    
        end
        response = 1;  
    elseif trialTime > trialLength * 1.2
        fprintf('Misalignment detected! Ending experiment.\n');
        continue;
    else
        if current == 0
            catchTrialResponses = catchTrialResponses + 1;
        end
        response = 0;
        fprintf('No turn detected!\n\n') 
    end  

    printTrialResponseRate(responseArr,totalTrialTypeArr,currentArr,...
        catchTrialResponses,catchTrialCounter,expParam,paramVec);
    
    % Record data in trial data array
    trialData(i,1) = i;
    trialData(i,2) = current;
    trialData(i,3) = response;  
    trialData(i,4) = trialTime;
    trialData(i,5) = frequency;
    trialData(i,6) = pulseWidth;

end

expStruct.trialData = trialData;

pause(2);
save(struct_name,'expStruct');
fprintf('Experiment done!\n')
% sound(y);