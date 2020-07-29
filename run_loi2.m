function run_loi2(TestRun, SkipSyncTests, DoEmailBackup)
% RUN_TASK  Run LOI2
%
%   USAGE: run_task([TestRun], [SkipSyncTests], [DoEmailBackup])
%
if nargin<1, TestRun       = 0; end
if nargin<2, SkipSyncTests = 1; end  % 2018-09-19 JMT Default to skipping sync tests
if nargin<3, DoEmailBackup = 1; end

cd(fileparts(mfilename('fullpath')));

%% SkipSyncTests Check
if SkipSyncTests
    Screen('Preference', 'SkipSyncTests', 1);
    fprintf('\n\t!!! WARNING !!!\n\tSkipping Sync Tests!\n\n');
end

%% Check for Psychtoolbox %%
try
    PsychtoolboxVersion;
catch
    url = 'https://psychtoolbox.org/PsychtoolboxDownload';
    fprintf('\n\t!!! WARNING !!!\n\tPsychophysics Toolbox does not appear to on your search path!\n\tSee: %s\n\n', url);
    return
end

%% Print Title %%
script_name='----------- Photo Judgment Test -----------'; boxTop(1:length(script_name))='=';
fprintf('\n%s\n%s\n%s\n',boxTop,script_name,boxTop)

%% Defaults Paramters %%
TASK_ID = 'socnsloi2';
KbName('UnifyKeyNames');
defaults = task_defaults;
trigger = KbName(defaults.trigger);

%% Load Design and Setup Seeker Variable %%
load(fullfile(defaults.path.design, 'design.mat'))
design      = alldesign{1};
blockSeeker = design.blockSeeker;
trialSeeker = design.trialSeeker;
trialSeeker(:,6:9) = 0;
nTrialsBlock    = length(unique(trialSeeker(:,2)));
BOA             = diff([blockSeeker(:,3); design.totalTime]);
maxBlockDur     = defaults.cueDur + defaults.firstISI + (nTrialsBlock*defaults.maxDur) + (nTrialsBlock-1)*defaults.ISI;
BOA             = BOA + (maxBlockDur - min(BOA));
eventTimes          = cumsum([defaults.prestartdur; BOA]);
blockSeeker(:,3)    = eventTimes(1:end-1);
numTRs              = ceil(eventTimes(end)/defaults.TR);
totalTime           = defaults.TR*numTRs;

%% Print Defaults %%
fprintf('Test Duration:         %d secs (%d TRs)', totalTime, numTRs);
fprintf('\nTrigger Key:           %s', defaults.trigger);
fprintf(['\nValid Response Keys:   %s' repmat(', %s', 1, length(defaults.valid_keys)-1)], defaults.valid_keys{:});
fprintf('\nForce Quit Key:        %s\n', defaults.escape);
fprintf('%s\n', repmat('-', 1, length(script_name)));

%% Get Subject ID %%
if ~TestRun
    subjectID = ptb_get_input_string('\nEnter Subject ID: ');
else
    subjectID = 'TestRun';
end

%% Key filenames in Conte Core BIDS-ish style
logFile = conte_fname(defaults.path.data, subjectID, TASK_ID, 'log.tsv');
resultsFile = conte_fname(defaults.path.data, subjectID, TASK_ID, 'results.mat');
edfLocalFile = conte_fname(defaults.path.data, subjectID, TASK_ID, 'gaze.edf');
edfHostFile = datestr(now, 'ddHHMMSS');

%% Ask user whether to use eyetracking
DoET = ptb_get_input_numeric('\nUse eyetracking? (0:no; 1:yes): ', [0 1]);

%% Setup Input Device(s) %%
switch upper(computer)
    case 'MACI64'
        inputDevice = ptb_get_resp_device;
    case {'PCWIN','PCWIN64'}
        % JMT:
        % Do nothing for now - return empty chosen_device
        % Windows XP merges keyboard input and will process external keyboards
        % such as the Silver Box correctly
        inputDevice = [];
    otherwise
        % Do nothing - return empty chosen_device
        inputDevice = [];
end
resp_set = ptb_response_set([defaults.valid_keys defaults.escape]); % response set

%% Initialize Screen %%
w = ptb_setup_screen(0,250,defaults.font.name,defaults.font.size1);

%% Initialize Logfile (Trialwise Data Recording) %%
fprintf('\nA running log of this session will be saved to %s\n', logFile);
fid=fopen(logFile,'w');
if fid < 1, error('could not open logfile!'); end
eventcolumns = {
    'block_num', 'trial_num', 'trial_type', ...
    'correct_response', 'stim_index', 'onset', ...
    'response_time', 'subject_response', 'offset'
    };
fprintf(fid,[repmat('%s\t',1,length(eventcolumns)) '\n'],eventcolumns{:});

%% Initialize eyetracker
if DoET
    DoET = ptb_eyelink_initialize(w.win, edfHostFile);
end

%% Make Images Into Textures %%
DrawFormattedText(w.win,sprintf('LOADING\n\n0%% complete'),'center','center',w.white,defaults.font.wrap);
Screen('Flip',w.win);
slideName = cell(length(design.qim), 1);
slideTex = slideName;
for i = 1:length(design.qim)
    slideName{i} = design.qim{i,2};
    tmp1 = imread([defaults.path.stim filesep slideName{i}]);
    slideTex{i} = Screen('MakeTexture',w.win,tmp1);
    DrawFormattedText(w.win,sprintf('LOADING\n\n%d%% complete', ceil(100*i/length(design.qim))),'center','center',w.white,defaults.font.wrap);
    Screen('Flip',w.win);
end
instructTex = Screen('MakeTexture', w.win, imread([defaults.path.stim filesep 'loi2_instruction.jpg']));
fixTex = Screen('MakeTexture', w.win, imread([defaults.path.stim filesep 'fixation.jpg']));
reminderTex = Screen('MakeTexture', w.win, imread([defaults.path.stim filesep 'motion_reminder.jpg']));

%% Get Cues %%
ordered_questions  = design.preblockcues(blockSeeker(:,4));
firstclause = {'Is the person ' 'Is the photo ' 'Is it a result of ' 'Is it going to result in '};
pbc1 = design.preblockcues;
pbc2 = pbc1;
for i = 1:length(firstclause)
    tmpidx = ~isnan(cellfun(@mean, regexp(design.preblockcues, firstclause{i})));
    pbc1(tmpidx) = cellstr(firstclause{i}(1:end-1));
    pbc2 = regexprep(pbc2, firstclause{i}, '');
end
pbc1 = strcat(pbc1, repmat('\n', 1, defaults.font.linesep));

%% Get Coordinates for Centering ISI Cues
isicues_xpos = zeros(length(design.isicues),1);
isicues_ypos = isicues_xpos;
for q = 1:length(design.isicues), [isicues_xpos(q), isicues_ypos(q)] = ptb_center_position(design.isicues{q},w.win); end

%% Test Button Box %%
if defaults.testbuttonbox, ptb_bbtester(inputDevice, w); end

%==========================================================================
%
% START TASK PRESENTATION
%
%==========================================================================

%% Present Instruction Screen %%
Screen('DrawTexture',w.win, instructTex); Screen('Flip',w.win);

%% Wait for Trigger to Start %%
KbQueueRelease()

% DisableKeysForKbCheck([]);
secs=KbTriggerWait(trigger, inputDevice);

% Mark time origin in data file
if DoET
    Eyelink('Message', 'SYNCTIME');
end

anchor=secs;
RestrictKeysForKbCheck([resp_set defaults.escape]);

%% Present Motion Reminder %%
if defaults.motionreminder
    Screen('DrawTexture',w.win,reminderTex)
    Screen('Flip',w.win);
    WaitSecs('UntilTime', anchor + blockSeeker(1,3) - 2);
end

try
    
    if TestRun, nBlocks = 1; totalTime = ceil(totalTime/(size(blockSeeker, 1))); % for test run
    else nBlocks = length(blockSeeker); end
    %======================================================================
    % BEGIN BLOCK LOOP
    %======================================================================
    for b = 1:nBlocks
        
        %% Present Fixation Screen %%
        Screen('DrawTexture',w.win, fixTex); Screen('Flip',w.win);
        
        if DoET
            Eyelink('Message', 'BLOCKID %d', b);
        end
        
        %% Get Data for This Block (While Waiting for Block Onset) %%
        tmpSeeker   = trialSeeker(trialSeeker(:,1)==b,:);
        line1       = pbc1{blockSeeker(b,4)};  % line 1 of question cue
        pbcue       = pbc2{blockSeeker(b,4)};  % line 2 of question cue
        isicue      = design.isicues{blockSeeker(b,4)};  % isi cue
        isicue_x    = isicues_xpos(blockSeeker(b,4));  % isi cue x position
        isicue_y    = isicues_ypos(blockSeeker(b,4));  % isi cue y position
        
        %% Prepare Question Cue Screen (Still Waiting) %%
        Screen('TextSize',w.win, defaults.font.size1); Screen('TextStyle', w.win, 0);
        DrawFormattedText(w.win,line1,'center','center',w.white, defaults.font.wrap);
        Screen('TextStyle',w.win, 1); Screen('TextSize', w.win, defaults.font.size2);
        DrawFormattedText(w.win,pbcue,'center','center', w.white, defaults.font.wrap);
        
        %% Present Question Screen and Prepare First ISI (Blank) Screen %%
        WaitSecs('UntilTime',anchor + blockSeeker(b,3)); Screen('Flip', w.win);
        Screen('FillRect', w.win, w.black);
        
        %% Present Blank Screen Prior to First Trial %%
        WaitSecs('UntilTime',anchor + blockSeeker(b,3) + defaults.cueDur); Screen('Flip', w.win);
        
        %==================================================================
        % BEGIN TRIAL LOOP
        %==================================================================
        for t = 1:nTrialsBlock
            
            if DoET
                Eyelink('command', 'record_status_message "BLOCK %d/%d, TRIAL %d/%d"', b, nBlocks, t, nTrialsBlock);
            end
            
            %% Prepare Screen for Current Trial %%
            Screen('DrawTexture',w.win,slideTex{tmpSeeker(t,5)})
            if t==1, WaitSecs('UntilTime',anchor + blockSeeker(b,3) + defaults.cueDur + defaults.firstISI);
            else WaitSecs('UntilTime',anchor + offset_dur + defaults.ISI); end
            
            %% Present Screen for Current Trial & Prepare ISI Screen %%
            Screen('Flip',w.win);
            
            if DoET
                Eyelink('Message', 'BLOCKID %d TRIALID %d ONSET', b,t);
            end
            
            onset = GetSecs; tmpSeeker(t,6) = onset - anchor;
            if t==nTrialsBlock % present fixation after last trial of block
                Screen('DrawTexture', w.win, fixTex);
            else % present question reminder screen between every block trial
                Screen('DrawText', w.win, isicue, isicue_x, isicue_y);
            end
            
            %% Look for Button Press %%
            [resp, rt] = ptb_get_resp_windowed_noflip(inputDevice, resp_set, defaults.maxDur, defaults.ignoreDur);
            offset_dur = GetSecs - anchor;
            
            %% Present ISI, and Look a Little Longer for a Response if None Was Registered %%
            Screen('Flip', w.win);
            
            if DoET
                Eyelink('Message', 'BLOCKID %d TRIALID %d OFFSET', b,t);
            end
            
            norespyet = isempty(resp);
            if norespyet, [resp, rt] = ptb_get_resp_windowed_noflip(inputDevice, resp_set, defaults.ISI*0.90); end
            if ~isempty(resp)
                
                if DoET
                    Eyelink('Message', 'BLOCKID %d TRIALID %d KEYPRESS', b,t);
                end
                
                if strcmpi(resp, defaults.escape)
                    
                    if DoET
                        ptb_eyelink_cleanup(edfHostFile, edfLocalFile);
                    end
                    
                    ptb_exit; % rmpath(defaults.path.utilities)
                    fprintf('\nESCAPE KEY DETECTED\n'); return
                end
                tmpSeeker(t,8) = find(strcmpi(KbName(resp_set), resp));
                tmpSeeker(t,7) = rt + (defaults.maxDur*norespyet);
            end
            tmpSeeker(t,9) = offset_dur;
            
        end % END TRIAL LOOP
        
        %% Store Block Data & Print to Logfile %%
        trialSeeker(trialSeeker(:,1)==b,:) = tmpSeeker;
        for t = 1:size(tmpSeeker,1), fprintf(fid,[repmat('%d\t',1,size(tmpSeeker,2)) '\n'],tmpSeeker(t,:)); end
        
    end % END BLOCK LOOP
    
    %% Present Fixation Screen Until End of Scan %%
    WaitSecs('UntilTime', anchor + totalTime);
    
catch
    
    if DoET
        ptb_eyelink_cleanup(edfHostFile, edfLocalFile);
    end
    
    ptb_exit;
    psychrethrow(psychlasterror);
end

%% Create Results Structure %%
result.blockSeeker  = blockSeeker;
result.trialSeeker  = trialSeeker;
result.qim          = design.qim;
result.qdata        = design.qdata;
result.preblockcues = design.preblockcues;
result.isicues      = design.isicues;

%% Save Data to Matlab Variable %%
try
    save(resultsFile, 'subjectID', 'result', 'slideName', 'defaults');
catch
    fprintf('couldn''t save %s\n saving to loi_results.mat\n', resultsFile);
    save loi_results.mat
end

%% End of Test Screen %%
DrawFormattedText(w.win,'TEST COMPLETE\n\nPlease wait for further instructions.','center','center',w.white,defaults.font.wrap);
Screen('Flip', w.win);
ptb_any_key;

%% Exit & Attempt Backup %%
if DoET
    ptb_eyelink_cleanup(edfHostFile, edfLocalFile);
end
ptb_exit;

if DoEmailBackup
    try
        disp('Backing up data... please wait.');
        if TestRun
            emailto = {'bobspunt@gmail.com'};
            emailsubject = '[TEST RUN] Conte Social/Nonsocial LOI2 Behavioral Data';
        else
            emailto = {'bobspunt@gmail.com','conte3@caltech.edu','jcrdubois@gmail.com'};
            emailsubject = 'Conte Social/Nonsocial LOI2 Behavioral Data';
        end
        files2send = {logFile, outFile, strrep(logFile,'_events.tsv','_gaze.edf')};
        keep = true(1,length(files2send));
        for i = 1:length(files2send)
            if ~exist(files2send{i},'file')
                warning('File %s not found',files2send{i});
                keep(i) = 0;
            end
        end
        bob_sendemail(emailto, emailsubject, 'See attached.',files2send(keep));
        disp('All done!');
    catch
        disp('Could not email data... internet may not be connected.');
    end
end

% ===================================== %
% END MAIN FUNCTION
% ===================================== %
end

function w = ptb_setup_screen(background_color, font_color, font_name, font_size, screen_res)
% PTB_SETUP_SCREEN Psychtoolbox utility for setting up screen
%
% USAGE: w = ptb_setup_screen(background_color,font_color,font_name,font_size,screen_res)
%
% INPUTS
%  background_color = color to setup screen with
%  font_color = default font color
%  font_name = default font name (e.g. 'Arial','Times New Roman','Courier')
%  font_size = default font size
%  screen_res = desired screen resolution (width x height)
%
% OUTPUTS
%   w = structure with the following fields:
%       win = window pointer
%       res = window resolution
%       oldres = original window resolution
%       xcenter = x center
%       ycenter = y center
%       white = white index
%       black = black index
%       gray = between white and black
%       color = background color
%       font.name = default font
%       font.color = default font color
%       font.size = default font size
%       font.wrap = default wrap for font
%

if nargin<5, screen_res = []; end
if nargin<4, display('USAGE: w = ptb_setup_screen(background_color,font_color,font_name,font_size, screen_res)'); return; end
% start
AssertOpenGL;
screenNum = max(Screen('Screens'));
oldres = Screen('Resolution',screenNum);
if ~isempty(screen_res) & ~isequal([oldres.width oldres.height], screen_res)
    Screen('Resolution',screenNum,screen_res(1),screen_res(2));
end
[w.win w.res] = Screen('OpenWindow', screenNum, background_color);
[width height] = Screen('WindowSize', w.win);
% text
Screen('TextSize', w.win, font_size);
Screen('TextFont', w.win, font_name);
Screen('TextColor', w.win, font_color);
% this bit gets the default font wrap
text = repmat('a',1000,1);
[normBoundsRect offsetBoundsRect]= Screen('TextBounds', w.win, text);
wscreen = w.res(3);
wtext = normBoundsRect(3);
wchar = floor(wtext/length(text));
% output variable
w.xcenter = width/2;
w.ycenter = height/2;
w.white = WhiteIndex(w.win);
w.black = BlackIndex(w.win);
w.gray = round(((w.white-w.black)/2));
w.color = background_color;
w.font.name = font_name;
w.font.color = font_color;
w.font.size = font_size;
w.font.wrap = floor(wscreen/wchar) - 4;
% flip up screen
HideCursor;
Screen('FillRect', w.win, background_color);
end

function chosen_device = ptb_get_resp_device(prompt)
% PTB_GET_RESPONSE Psychtoolbox utility for acquiring responses
%
% USAGE: chosen_device = ptb_get_resp_device(prompt)
%
% INPUTS
%  prompt = to display to user
%
% OUTPUTS
%  chosen_device = device number
%

if nargin<1, prompt = 'Which device?'; end
chosen_device = [];
numDevices=PsychHID('NumDevices');
devices=PsychHID('Devices');
candidate_devices = [];
boxTop(1:length(prompt))='-';
keyboard_idx = GetKeyboardIndices;
fprintf('\n%s\n%s\n%s\n',boxTop,prompt,boxTop)
if length(keyboard_idx)==1
    fprintf('Defaulting to one found keyboard: %s, %s\n',devices(keyboard_idx).usageName,devices(keyboard_idx).product)
    chosen_device = keyboard_idx;
else
    for i=1:length(keyboard_idx), n=keyboard_idx(i); fprintf('%d - %s, %s\n',i,devices(n).usageName,devices(n).product); candidate_devices = [candidate_devices i]; end
    prompt_string = sprintf('\nChoose a keyboard (%s): ',num2str(candidate_devices));
    while isempty(chosen_device)
        chosen_device = input(prompt_string);
        if isempty(chosen_device)
            fprintf('Invalid Response!\n')
            chosen_device = [];
        elseif isempty(find(candidate_devices == chosen_device))
            fprintf('Invalid Response!\n')
            chosen_device = [];
        end
    end
    chosen_device = keyboard_idx(chosen_device);
end
end

function [resp_set, old_set] = ptb_response_set(keys)
% PTB_RESPONSE_SET Psychtoolbox utility for building response set
%
% USAGE: resp_set = ptb_response_set(keys)
%
% INPUTS
%  keys = cell array of strings for key names
%
% OUTPUTS
%  resp_set = array containing key codes for key names
%

if nargin<1, disp('USAGE: resp_set = ptb_response_set(keys)'); return; end
if ischar(keys), keys = cellstr(keys); end
KbName('UnifyKeyNames');
resp_set    = cell2mat(cellfun(@KbName, keys, 'Unif', false));
old_set     = RestrictKeysForKbCheck(resp_set);
end

function [resp,rt] = ptb_get_resp_windowed_noflip(resp_device, resp_set, resp_window, ignore_dur)
% PTB_GET_RESP_WINDOWED Psychtoolbox utility for acquiring responses
%
% USAGE: [resp rt] = ptb_get_resp_windowed_noflip(resp_device, resp_set, resp_window, ignore_dur)
%
% INPUTS
%  resp_device = device #
%  resp_set = array of keycodes (from KbName) for valid keys
%  resp_window = response window (in secs)
%  ignore_dur = dur after onset in which to ignore button presses
%
% OUTPUTS
%  resp = name of key press (empty if no response)
%  rt = time of key press (in secs)
%

if nargin < 4, ignore_dur = 0; end
onset = GetSecs;
noresp = 1;
resp = [];
rt = [];
if ignore_dur, WaitSecs('UntilTime', onset + ignore_dur); end
while noresp && GetSecs - onset < resp_window
    [keyIsDown, secs ,keyCode] = KbCheck(resp_device);
    keyPressed = find(keyCode);
    if keyIsDown & ismember(keyPressed, resp_set)
        rt = secs - onset;
        resp = KbName(keyPressed);
        noresp = 0;
    end
end
end

function [resp, rt] = ptb_get_resp_windowed(resp_device, resp_set, resp_window, window, color)
% PTB_GET_RESP_WINDOWED Psychtoolbox utility for acquiring responses
%
% USAGE: [resp rt] = ptb_get_resp_windowed(resp_device,resp_set,resp_window,window,color)
%
% INPUTS
%  resp_device = device #
%  resp_set = array of keycodes (from KbName) for valid keys
%  resp_window = response window (in secs)
%  window = window to draw to
%  color = color to flip once response is collected
%
% OUTPUTS
%  resp = name of key press (empty if no response)
%  rt = time of key press (in secs)
%

if nargin<5, disp('USAGE: [resp rt] = ptb_get_resp_windowed(resp_device,resp_set,resp_window,window,color)'); return; end

onset = GetSecs;
noresp = 1;
resp = [];
rt = [];
while noresp && GetSecs - onset < resp_window
    
    [keyIsDown secs keyCode] = KbCheck(resp_device);
    keyPressed = find(keyCode);
    if keyIsDown & ismember(keyPressed, resp_set)
        
        rt = secs - onset;
        Screen('FillRect', window, color);
        Screen('Flip', window);
        resp = KbName(keyPressed);
        noresp = 0;
        
    end
    
end
WaitSecs('UntilTime', onset + resp_window)
end

function tex = ptb_im2tex(imfile, w)
% PTB_IM2TEX
%
% USAGE: tex = ptb_im2tex(imfile, w)
%
% OUTPUTS
%   im - structure with following fields
%   w - window
%   tex - pointer to image tex from Screen('MakeTexture',...)
%

if nargin < 1, disp('USAGE: tex = ptb_im2tex(imfile, w)'); return; end
if iscell(imfile), imfile = char(imfile); end
tex = Screen('MakeTexture', w, imread(imfile));
end

function doquit = ptb_get_force_quit(resp_device, resp_set, resp_window)
% PTB_GET_FORCE_QUIT
%
% USAGE: ptb_get_force_quit(resp_device, resp_set, resp_window)
%
% INPUTS
%  resp_device = device #
%  resp_set = array of keycodes (from KbName) for valid keys
%  resp_window = response window (in secs)
%

onset = GetSecs;
noresp = 1;
doquit = 0;
while noresp && GetSecs - onset < resp_window
    
    [keyIsDown, ~, keyCode] = KbCheck(resp_device);
    keyPressed = find(keyCode);
    if keyIsDown && ismember(keyPressed, resp_set)
        noresp = 0; doquit = 1;
    end
    
end
end

function [xpos, ypos] = ptb_center_position(string, window, y_offset)
% PTB_CENTER_POSITION
%
% USAGE: [xpos ypos] = ptb_center_position(string, window, y_offset)
%
% INPUTS
%  string = string being displayed
%  window = window in which it will be displayed
%  y_offset = (default = 0) offset on y-axis (pos = lower, neg = higher)
%
% OUTPUTS
%   xpos = starting x coordinate
%   ypos = starting y coordinate
%

if nargin<2, disp('USAGE: [xpos ypos] = ptb_center_position(string, window, y_offset)'); end
if nargin<3, y_offset = 0; end
text_size = Screen('TextBounds', window, string);
[width height] = Screen('WindowSize', window);
xcenter = width/2;
ycenter = height/2;
text_x = text_size(1,3);
text_y = text_size(1,4);
xpos = xcenter - (text_x/2);
ypos = ycenter - (text_y/2) + y_offset;
end

function rect = ptb_center_position_image(im, window, xy_offsets)
% PTB_CENTER_POSITION
%
% USAGE: rect = ptb_center_position_image(im, window, xy_offsets)
%
% INPUTS
%  im = image matrix to be displayed
%  window = window in which it will be displayed
%  xy_offsets = (default = [0 0]) offset on x and y-axes (pos = lower, neg = higher)
%
% OUTPUTS
%   rect = coordinates for desination rectangle
%

if nargin<2, disp('USAGE: rect = ptb_center_position_image(im, window, xy_offsets)'); return; end
if nargin<3, xy_offsets = [0 0]; end
dims = size(im);
[width height] = Screen('WindowSize', window);
rect = [0 0 0 0];
rect(1) = (width - dims(2))/2 + xy_offsets(1);
rect(2) = (height - dims(1))/2 + xy_offsets(2);
rect(3) = rect(1) + dims(2);
rect(4) = rect(2) + dims(1);
end

function out = ptb_get_input_string(prompt)
% PTB_GET_INPUT_STRING Psychtoolbox utility for getting valid user input string
%
% USAGE: out = ptb_get_input(prompt)
%
% INPUTS
%  prompt = string containing message to user
%
% OUTPUTS
%  out = input
%

if nargin<1, disp('USAGE: out = ptb_get_input(prompt)'); return; end
out = input(prompt, 's');
while isempty(out)
    disp('ERROR: You entered nothing. Try again.');
    out = input(prompt, 's');
end
end

function bob_sendemail(to,subject,message,attachment)
% BOB_SENDEMAIL  Send email from a gmail account
%
% ARGUMENTS
%   to:                the email address to send to
%   subject:        the email subject line
%   message:      the email message
%   attachment:  the file(s) to attach (can be a string or cell array of strings)
%
% Written by Bob Spunt, Februrary 22, 2013
% Based on code provided by Pradyumna
% ------------------------------------------------------------------

% ==========================
% gmail account from which to send email
% --------------------------------
email = 'neurospunt@gmail.com';
password = 'socialbrain';
% ==========================

% check arguments
if nargin == 3
    attachment = '';
end

% set up gmail SMTP service
setpref('Internet','E_mail',email);
setpref('Internet','SMTP_Server','smtp.gmail.com');
setpref('Internet','SMTP_Username',email);
setpref('Internet','SMTP_Password',password);

% gmail server
props = java.lang.System.getProperties;
props.setProperty('mail.smtp.auth','true');
props.setProperty('mail.smtp.socketFactory.class', 'javax.net.ssl.SSLSocketFactory');
props.setProperty('mail.smtp.socketFactory.port','465');

% send
if isempty(attachment)
    sendmail(to,subject,message);
else
    sendmail(to,subject,message,attachment);
end

end

function ptb_disp_message(message,w,lspacing,waitforsecs)
% PTB_DISP_MESSAGE Psychtoolbox utility for displaying a message
%
% USAGE: ptb_disp_message(message,w,lspacing)
%
% INPUTS
%  message = string to display
%  w = screen structure (from ptb_setup_screen)
%  lspacing = line spacing (default = 1)
%

if nargin<4, waitforsecs = 0; end
if nargin<3, lspacing = 1; end
if nargin<2, disp('USAGE: ptb_disp_message(message,w,lspacing)'); return; end
DrawFormattedText(w.win,message,'center','center',w.font.color,w.font.wrap,[],[],lspacing);
Screen('Flip',w.win);
if waitforsecs, WaitSecs(waitforsecs); end
end

function ptb_any_key(resp_device)

if nargin<1, resp_device = -1; end
oldkey = RestrictKeysForKbCheck([]);
KbPressWait(resp_device);
RestrictKeysForKbCheck(oldkey);
end

function ptb_disp_blank(w, waitforsecs)

if nargin<2, waitforsecs = 0.5; end
Screen('FillRect', w.win, w.color);
Screen('Flip',w.win);
if waitforsecs, WaitSecs(waitforsecs); end
end

function ptb_exit
% sca -- Execute Screen('CloseAll');
% This is just a convenience wrapper that allows you
% to save typing that long, and frequently needed,  command.
% It also unhides the cursor if hidden, and restores graphics card gamma
% tables if they've been altered.
%

% Close all open file streams
fclose('all');

% Release keys
RestrictKeysForKbCheck([]);

% Unhide the cursor if it was hidden:
ShowCursor;
for win = Screen('Windows')
    if Screen('WindowKind', win) == 1
        if Screen('GetWindowInfo', win, 4) > 0
            Screen('AsyncFlipEnd', win);
        end
    end
end

% Close all windows, release all Screen() ressources:
Screen('CloseAll');

% Restore (possibly altered) gfx-card gamma tables from backup copies:
RestoreCluts;

% Call Java cleanup routine to avoid java.lang.outOfMemory exceptions due
% to the bugs and resource leaks in Matlab's Java based GUI:
if ~IsOctave && exist('PsychJavaSwingCleanup', 'file')
    PsychJavaSwingCleanup;
end
Priority(0);
return
end

function ptb_bbtester(inputDevice,w)
intromsg = 'The following test will make sure that your fingers are still on the correct buttons.';
instruct1 = 'Please press button 1';
instruct2 = 'Please press button 2';
b1a=KbName('1');
b1b=KbName('1!');
b2a=KbName('2');
b2b=KbName('2@');
b3a=KbName('3');
b3b=KbName('3#');
b4a=KbName('4');
b4b=KbName('4$');
resp_set = [b1a b1b b2a b2b b3a b3b b4a b4b];
one_set = [b1a b1b];
two_set = [b2a b2b];
ptb_disp_message(intromsg, w, 1, 5)
ptb_disp_blank(w, 0.5)
ptb_disp_message(instruct1, w)
goodresp=0;
while goodresp==0
    [keyIsDown,secs,keyCode] = KbCheck(inputDevice);
    keyPressed = find(keyCode);
    if keyIsDown && ismember(keyPressed,resp_set)
        tmp = KbName(keyPressed);
        if ismember(keyPressed,one_set)
            ptb_disp_message('Good!', w, 1, .5);
            goodresp=1;
        else
            correct1 = sprintf('You pressed button %s, please try to find and press button 1.', tmp(1));
            ptb_disp_message(correct1, w)
        end
    end;
end;
ptb_disp_blank(w, 0.50)
ptb_disp_message(instruct2, w)
goodresp=0;
while goodresp==0
    [keyIsDown,secs,keyCode] = KbCheck(inputDevice);
    keyPressed = find(keyCode);
    if keyIsDown && ismember(keyPressed,resp_set)
        tmp = KbName(keyPressed);
        if ismember(keyPressed,two_set)
            ptb_disp_message('Good!', w, 1, .5);
            goodresp=1;
        else
            correct2 = sprintf('You pressed button %s, please try to find and press button 2.', tmp(1));
            ptb_disp_message(correct2, w)
        end
    end;
end;
ptb_disp_blank(w, 0.25)
end

function success = ptb_eyelink_initialize(w,edfFile)
dummymode = 0;
% Provide Eyelink with details about the graphics environment
% and perform some initializations. The information is returned
% in a structure that also contains useful defaults
% and control codes (e.g. tracker state bit and Eyelink key values).
el = EyelinkInitDefaults(w);
% turn off beeps!
% set the second value in each line to 0 to turn off the sound
el.cal_target_beep=[600 0 0.05];
el.drift_correction_target_beep=[600 0 0.05];
el.calibration_failed_beep=[400 0 0.25];
el.calibration_success_beep=[800 0 0.25];
el.drift_correction_failed_beep=[400 0 0.25];
el.drift_correction_success_beep=[800 0 0.25];
% colors
el.calibrationtargetcolour       = [255 255 255];
el.backgroundcolour              = [0 0 0];
el.foregroundcolour              = [255 255 255];
el.msgfontcolour                 = [255 255 255];
el.imgtitlecolour                = [255 255 255];
% you must call this function to apply the changes from above
EyelinkUpdateDefaults(el);
% Initialization of the connection with the Eyelink Gazetracker.
% exit program if this fails.
if ~EyelinkInit(dummymode, 1)
    success = 0;
%     fprintf('Eyelink Init aborted.\n');
%     Eyelink('Shutdown');
%     sca;
    return;
else
    success = 1;
end
[~,vs]=Eyelink('GetTrackerVersion');
fprintf('Running experiment on a ''%s'' tracker.\n', vs );
% Make sure that we get gaze data from the Eyelink
Eyelink('Command', 'link_sample_data = LEFT,RIGHT,GAZE,AREA');
% Open data file to record to
Eyelink('Openfile', edfFile);
% Calibrate the eye tracker
EyelinkDoTrackerSetup(el);
% do a final check of calibration using driftcorrection
EyelinkDoDriftCorrection(el);
% start recording eyetrace
Eyelink('StartRecording');
end

function ptb_eyelink_cleanup(edfFile,edfFileReceive)
% Finish up: stop recording eye-movements,
Eyelink('StopRecording');
% Close graphics window, close data file and shut down tracker
Eyelink('CloseFile');
% Download data file to stimulation PC
try
    fprintf('Receiving data file ''%s''\n', edfFile );
    status = Eyelink('ReceiveFile', edfFile, edfFileReceive);
    if status > 0
        fprintf('ReceiveFile status %d\n', status);
    end
catch rdf
    fprintf('Problem receiving data file ''%s''\n', edfFile );
    rdf;
end
Eyelink('Shutdown');
end
