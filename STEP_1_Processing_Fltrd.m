%% This script will calculate 8 measures for all files in the folder: filepathName
% All files fcn*.m contain Matlab functions used in calculating measures.

%% Add path to use EEGLAB Matlab functions; Change path to your local copy of EEGLab
addpath(genpath('D:\Dropbox\119 FRACTAL ANALYSIS\119 CODE\119 MATLAB\eeglab14_1_1b'));

%% Change to filepath with files on local disk
filepathName = 'D:\\Dropbox\\119 FRACTAL ANALYSIS\\119 CODE\\119 MATLAB\\';

%% Get file(s)
myFolderInfo = dir([filepathName, '*.RAW']); 
myFolderInfo = myFolderInfo(~cellfun('isempty', {myFolderInfo.date}));

%% Iterate through available files in the folder
for iFile = 1:size(myFolderInfo,1)
    disp([' File: ', num2str(iFile), ' ', myFolderInfo(iFile).name])   % File for processing
    
    %% Read binary simple Netstation file
    filename = myFolderInfo(iFile).name; 
    EEG = pop_readegi(filename, [],[],'auto');

    %% Correct delay 
    EEG = correctDelay(EEG,25);

    %% Edit channel locations 
    myChanLocs = 'GSN-HydroCel-129.sfp';
    EEG = pop_chanedit(EEG, 'load',{myChanLocs 'filetype' 'autodetect'},'setref',{'4:128' 'Cz'},'changefield',{132 'datachan' 0});

    %% Re-reference and add 'Cz' back to the data
    EEG = pop_reref( EEG, [],'refloc',struct('labels',{'Cz'},'Y',{0},'X',{5.4492e-16},'Z',{8.8992},'sph_theta',{0},'sph_phi',{90},'sph_radius',{8.8992},'theta',{0},'radius',{0},'type',{''},'ref',{'Cz'},'urchan',{132},'datachan',{0}));

    %% Filter the data; 0.1 for low and 50 for high
    EEG = pop_eegfiltnew(EEG, 0.1,50,33000,0,[],1);

    %% Correct DINs
    EEG.event = cleanTriggers(EEG.event);

    %% Plot for checking
    %pop_eegplot( EEG, 1, 1, 1);

    %% Run ICA
    EEG = pop_runica(EEG, 'extended',1,'interupt','on');

    %% Use for checking consistency of dataset
    EEG = eeg_checkset(EEG);

    %% Save dataset; 
    EEG = pop_saveset( EEG, 'filename',strrep(filename,'.RAW','Fltrd.set'),'filepath',filepathName);

    %% Calculate fractal dimensions and save the output to Excel spreadsheet
    % Prepare table for output; allocate memory
    tableOutput = struct2table(EEG.event);
    for jChan=1:size(EEG.chanlocs,2)
        tableOutput(1, strcat(EEG.chanlocs(jChan).labels,'_CD')) = {0}; 
        tableOutput(1, strcat(EEG.chanlocs(jChan).labels,'_PK')) = {0}; 
        tableOutput(1, strcat(EEG.chanlocs(jChan).labels,'_FNN')) = {0}; 
        tableOutput(1, strcat(EEG.chanlocs(jChan).labels,'_LE')) = {0}; 
        tableOutput(1, strcat(EEG.chanlocs(jChan).labels,'_HFD')) = {0}; 
        tableOutput(1, strcat(EEG.chanlocs(jChan).labels,'_MSE')) = {0}; 
        tableOutput(1, strcat(EEG.chanlocs(jChan).labels,'_DFA')) = {0}; 
        tableOutput(1, strcat(EEG.chanlocs(jChan).labels,'_LZ')) = {0}; 
    end

    %% Check type of file and then process it accordingly
    % Check if RMET and then iterate through DIN8 events [DIN8 DIN8]
    % Check if BCST and then iterate through [DIN1 DIN4(8)+100]
    % Check if EOEC and then iterate through [DIN0+x DIN1-x], [DIN1-y, DIN1+y], [DIN1+z DIN0-z]
    
    % Initialise vector with events for processing
    eventVec = []; 

    % RMET
    if size(tableOutput,1)==sum(arrayfun(@(x) strcmp(x.type, 'DIN0') + strcmp(x.type, 'DIN8'), EEG.event))
        eventVec = find(arrayfun(@(x) strcmp(x.type, 'DIN8'), EEG.event));
    end

    % BCST
    if size(tableOutput,1)>=10 && sum(arrayfun(@(x) strcmp(x.type, 'DIN1') + strcmp(x.type, 'DIN4'), EEG.event))>=1
        eventVec = find(arrayfun(@(x) strcmp(x.type, 'DIN1'), EEG.event));
    end

    % EOEC; used for benchmarking; 5 sec epoch
    if size(tableOutput,1)<=5 
        eventVec = find(arrayfun(@(x) strcmp(x.type, 'DIN1') || strcmp(x.type, 'DIN0'), EEG.event));
    end

    %% Iterate through events
    for iEvent = eventVec
         % Extract epochs
            % RMET
            if size(tableOutput,1)==sum(arrayfun(@(x) strcmp(x.type, 'DIN0') + strcmp(x.type, 'DIN8'), EEG.event))
               tempDataAll = EEG.data(:, EEG.event(iEvent).latency:EEG.event(iEvent + 1).latency);
            end
            % BCST
            if size(tableOutput,1)>=10 && sum(arrayfun(@(x) strcmp(x.type, 'DIN1') + strcmp(x.type, 'DIN4'), EEG.event))>=1
                tempDataAll = EEG.data(:, EEG.event(iEvent).latency:EEG.event(iEvent + 1).latency+100);
            end
            % EOEC
            if size(tableOutput,1)<=5 
                switch iEvent
                    case 1
                         tempDataAll = EEG.data(:, EEG.event(iEvent).latency + 10000:EEG.event(iEvent).latency + 15000);
                    case 2
                         tempDataAll = EEG.data(:, EEG.event(iEvent).latency - 2500:EEG.event(iEvent).latency + 2500);
                    case 3
                         tempDataAll = EEG.data(:, EEG.event(iEvent-1).latency + 10000:EEG.event(iEvent-1).latency + 15000);
                end
            end

            % Store results in this matrix for parallel processing purposes
            resultMat = zeros(size(EEG.chanlocs,2),8);

        parfor jChan = 1:size(EEG.chanlocs,2)
            tic;
            % Correlation dimension, PK
            d = 10; 
            [CD, PK, ~] = fcnCD_PK(tempDataAll(jChan,:),d);  

            % False nearest neighbors
            tao = 10;
            mmax = 10;
            rtol = 10;
            atol = 2;
            thresh = 0.5;
            FNN = find(fcnFNN(tempDataAll(jChan,:),tao,mmax,rtol,atol) < thresh,1);
            if isempty(FNN)
                FNN = nan;
            end

            % Lyapunov Spectrum
            LE = fcnLE(tempDataAll(jChan,:)',1);

            % Higuchi FD
            kmax = 5;
            HFD = fcnHFD(tempDataAll(jChan,:), kmax);

            % MSE
            [MSE, ~, ~] = fcnSE(tempDataAll(jChan,:));

            % DFA
            [DFA, ~] = fcnDFA(tempDataAll(jChan,:));

            % LZ
            LZ = fcnLZ(tempDataAll(jChan,:) >= median(tempDataAll(jChan,:)));

            % Store results
            resultMat(jChan,:) = [CD,PK,FNN,LE,HFD,MSE,DFA,LZ];

            % Show progress
            if rem(jChan, 10)==0
                disp([' Channel: ', num2str(jChan)])
            end
            toc
        end
        % Save output to a table
        resultMatT = resultMat';
        tableOutput{iEvent, 4:4 + 129*8 - 1} = resultMatT(:)'; 

        % Save length of epoch
        tableOutput(iEvent, 'Epoch_length') = {size(tempDataAll,2)}; 
        disp([' Event: ', num2str(iEvent)])
        toc;
    end % loop for events

    %% Save output to Excel spreadsheet for checking and futher processing
    writetable(tableOutput,strrep(filename,'.RAW','.Fltrd.xlsx'),'Sheet',1,'Range','A1')

end % loop for files









