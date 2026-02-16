function blocks = getStimBlocks(expStruct)
    
    expType = expStruct.experimentType;
    expParam = expStruct.experimentParam;
 
    if strcmp(expType,'Survey')
        assert(isfield(expStruct,'surveyStruct'),...
            'No survey structure assigned as a field to the experiment structure');
        surveyStruct = expStruct.surveyStruct;
        currentArr = surveyStruct.currentArr;
        paramVec = surveyStruct.paramVec;
        trialsPerCurrent = surveyStruct.trialsPerCurrent;
        totalTrials = surveyStruct.totalTrials;
        
        currentRepMat = repmat(currentArr, trialsPerCurrent, 1);
        currentRepMat = reshape(currentRepMat.',[],1); % reshape to vector
        stimParamRepMat = repmat(paramVec', trialsPerCurrent, size(currentArr,2));
        stimParamRepMat = reshape(stimParamRepMat.',[],1); % reshape to vector
        shuffleIdx = randperm(totalTrials);
        shuffledCurrentArr = currentRepMat(shuffleIdx);
        shuffledStimParamArr = stimParamRepMat(shuffleIdx);
        blocks = {shuffledCurrentArr shuffledStimParamArr};
    else
        if strcmp(expType,'Planar')
            numBlocks = 1;
            blocks = cell(numBlocks,1);
        else
            numBlocks = 4;
            blocks = cell(numBlocks,1);
        end
        
        currentArr = expStruct.currentArr;

        if strcmp(expParam,'Channel')
            paramVec = expStruct.rippleChannels;
        elseif strcmp(expParam,'Frequency')
            paramVec = expStruct.stimFreqArr;
        elseif strcmp(expParam, 'PulseWidth')
            paramVec = expStruct.stimPulseWidthsArr;
        end

        trialsPerCurrent = expStruct.trialsPerCurrent;
        trialsPerCurrentPerBlock = trialsPerCurrent/numBlocks;
        totalTrials = expStruct.totalTrials;
        numTrialsPerBlock = totalTrials/numBlocks;
        catchTrialsPerBlock = trialsPerCurrentPerBlock;
        catchTrials = zeros(catchTrialsPerBlock,1);

        for i = 1:numBlocks
            currentRepMat = repmat(currentArr, trialsPerCurrentPerBlock, 1);
            currentRepMat = reshape(currentRepMat.',[],1); % reshape to vector
            currentRepMat = [currentRepMat; catchTrials]; % append catch trials

            stimParamRepMat = repmat(paramVec', trialsPerCurrentPerBlock, size(currentArr,2));
            stimParamRepMat = reshape(stimParamRepMat.',[],1);
            stimParamRepMat = [stimParamRepMat; catchTrials];

            shuffleIdx = randperm(numTrialsPerBlock);
            shuffledCurrentArr = currentRepMat(shuffleIdx);
            shuffledStimParamArr = stimParamRepMat(shuffleIdx);

            blocks{i} = {shuffledCurrentArr shuffledStimParamArr};
        end


%         uniqueElements = unique(shuffledStimParamArr);
%         % Count occurrences of unique elements
%         counts = histcounts(shuffledStimParamArr, [uniqueElements; max(uniqueElements)+1]);


    end

end