function out = GUI()
    f = figure('Position', [500 500 250 300]);
    f.NumberTitle = 'off';
    f.ToolBar = 'none';
    f.MenuBar = 'none';
    f.Name = 'Select values';
    movegui(f,'center');
    set(f, 'CloseRequestFcn', @closeFunction);
    
    d = dir('D:/ICMS');
    d = d(~contains({d.name},{'.','..','stage1Figures'})); % exclude specific folders
    d = d(contains({d.name},{'ICMS','test'})); % exclude specific folders
    
    animalIDmenu = uicontrol(f,'Style','popupmenu');
    animalIDmenu.Position = [30 165 100 100];
    animalIDmenu.String = flip({d.name});
    animalIDmenu.Value = 1; 
    defaultAnimalID = d(end).name;

%     uicontrol(f, 'Style', 'text', 'Position', [30 250 60 18], 'String', 'Animal ID');
    uicontrol(f, 'Style', 'text', 'Position', [25 265 60 18], 'String', 'Animal ID');
%     uicontrol(f, 'Style', 'text', 'Position', [10 195 120 18], 'String', 'Experiment type');
    uicontrol(f, 'Style', 'text', 'Position', [10 210 120 18], 'String', 'Experiment type');

%     uicontrol(f, 'Style', 'text', 'Position', [5 105 160 18], 'String', 'Experiment parameter');
    uicontrol(f, 'Style', 'text', 'Position', [5 120 160 18], 'String', 'Experiment parameter');

    expTypePos = [30 190 180 25];
    expTypeGroup = uibuttongroup('Parent', f, 'Position', expTypePos);
    tb1 = uicontrol(f, 'Style', 'radiobutton', 'Position', expTypePos, 'String', 'Survey');
    tb2 = uicontrol(f, 'Style', 'radiobutton', 'Position', expTypePos + [0 -20 0 0], 'String', 'Volumetric');
    tb3 = uicontrol(f, 'Style', 'radiobutton', 'Position', expTypePos + [0 -40 0 0], 'String', 'Planar');
    
    expParamPos = [30 120 180 25];
    expParamGroup = uibuttongroup('Parent', f, 'Position', expParamPos);
    tb4 = uicontrol(f, 'Style', 'radiobutton', 'Position', expParamPos + [0 -20 0 0], 'String', 'Channel');
    tb5 = uicontrol(f, 'Style', 'radiobutton', 'Position', expParamPos + [0 -40 0 0], 'String', 'Frequency');
    tb6 = uicontrol(f, 'Style', 'radiobutton', 'Position', expParamPos + [0 -60 0 0], 'String', 'PulseWidth');

    doneButton = uicontrol(f, 'Style', 'pushbutton', 'Position', [30 20 100 30], 'String', 'Done', 'Callback', @doneCallback);

    % Initialize the data struct
    updatedStimParamStruct = struct('animalID', defaultAnimalID, 'expType', [], 'expParam', []);
    data = updatedStimParamStruct;
    guidata(f, data);

    animalIDmenu.Callback = @selection;
    set([tb1, tb2, tb3], 'Callback', @toggleSelection1);
    set([tb4, tb5, tb6], 'Callback', @toggleSelection2);

    function selection(~, ~)
        data = guidata(f);
        animalID = animalIDmenu.String{animalIDmenu.Value};
        data.animalID = animalID;
        guidata(f, data);
    end
    
    function toggleSelection1(src, ~)
        data = guidata(f);
        tb = [tb1, tb2, tb3];
        set(tb(tb ~= src), 'Value', 0); % Unselect other buttons
        selectedButton = get(src, 'String');
        data.expType = selectedButton;
        guidata(f, data);
    end

    function toggleSelection2(src, ~)
        data = guidata(f);
        tb = [tb4, tb5, tb6];
        set(tb(tb ~= src), 'Value', 0); % Unselect other buttons
        selectedButton = get(src, 'String');
        data.expParam = selectedButton;
        guidata(f, data);
    end

    function doneCallback(~, ~)
        data = guidata(f);
        out = data;
        fprintf('\n');
        disp('Selected values:');
        disp(['Animal ID: ' out.animalID]);
        disp(['Experiment Parameter: ' out.expParam]);
        disp(['Experiment Type: ' out.expType]);
        fprintf('\n');
        delete(f); % Close the figure
    end
    
    function closeFunction(~, ~)
        data = guidata(f);
        out = data;
        delete(f); % Close the figure
    end

    uiwait(f);
end


% set(0,'ShowHiddenHandles','on')
% delete(get(0,'Children'))