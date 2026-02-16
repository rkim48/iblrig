function printTrialResponseRate(responseArr,totalTrialTypeArr,currentArr,catchTrialResponses,catchTrialCounter,expParam,paramVec,depthIndices)

% Initialize a cell array to store row and column labels
numColumns = size(currentArr,2);  % Number of columns
colNames = cell(1, numColumns);  % Initialize cell array
for i = 1:numColumns
    colNames{i} = sprintf('Current %d', i);  % Create column names
end

numRows = length(paramVec);  % Number of columns
rowNames = cell(numRows,1);  % Initialize cell array
for i = 1:numRows
    if strcmp(expParam, 'Channel')
        rowNames{i} = sprintf('D%d', depthIndices(i));  % Create column names
    elseif strcmp(expParam, 'Frequency')
        rowNames{i} = sprintf('%d Hz', paramVec(i));  % Create column names
    elseif strcmp(expParam, 'PulseWidth')
        rowNames{i} = sprintf('%d us', paramVec(i));  % Create column names
    end   
end

% Display the header
fprintf('Response rates:\n');
fprintf('%-20s', '');  % Left-align header

for i = 1:numColumns
    fprintf('%-20s', colNames{i});  % Left-align column names
end
fprintf('\n');

% Display the table content
for i = 1:numRows
    fprintf('%-20s', rowNames{i});  % Left-align row names
    for j = 1:numColumns
        success_rate_str = sprintf('%d uA: %d/%d, %.0f%%', currentArr(i,j), ...
            responseArr(i, j), totalTrialTypeArr(i, j), 100 * responseArr(i, j) / totalTrialTypeArr(i, j));
        fprintf('%-20s', success_rate_str);  % Left-align table entries
    end
    fprintf('\n');
end

fprintf('\nFalse alarm rate:\n');
fprintf('%s', '');  % Left-align header
fa_rate_str = sprintf('%.0f/%.0f: %.0f%%', catchTrialCounter, catchTrialResponses, 100 * catchTrialCounter / catchTrialResponses);
fprintf('%s\n\n', fa_rate_str);  % Left-align table entries

end