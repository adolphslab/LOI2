function defaults = task_defaults
% DEFAULTS  Defines defaults for RUN_TASK.m

% Screen Resolution
%==========================================================================
defaults.screenres      = [1280 800];   % recommended screen resolution (if
                                        % not supported by monitor, will
                                        % default to current resolution)

% Response Keys
%==========================================================================
defaults.trigger        = '5%'; % trigger key (to start ask)
defaults.valid_keys     = {'1!' '2@' '3#' '4$'}; % valid response keys
defaults.escape         = 'ESCAPE'; % escape key (to exit early)
defaults.testbuttonbox  = true; % set to either true or false
defaults.motionreminder = true; % set to either true or false

% Paths
%==========================================================================
defaults.path.base      = pwd;
defaults.path.stim      = fullfile(defaults.path.base, 'stimuli');
defaults.path.design    = fullfile(defaults.path.base, 'design');

% 2018-03-19 JMT Move output data directory on desktop
userDir = char(java.lang.System.getProperty('user.home'));
defaults.path.data = fullfile(userDir, 'Desktop', 'Data');
if ~exist(defaults.path.data, 'dir')
    fprintf('\nData folder does not exist at %s\nCreating it now.\n', defaults.path.data)
    try
        mkdir(defaults.path.data)
    catch
        fprintf('Problem creating data output folder! Please fix issue and re-run.\n')
    end
end

% Text
%==========================================================================
defaults.font.name      = 'Helvetica'; % default font
defaults.font.size1     = 42; % default font size (smaller)
defaults.font.size2     = 46; % default font size (bigger)
defaults.font.wrap      = 42; % default font wrapping (arg to DrawFormattedText)
defaults.font.linesep   = 3;  % spacing between first and second lines of question cue

% Timing (specify in seconds)
%==========================================================================
defaults.TR             = 0.7;    % Your TR (in secs)
defaults.cueDur         = 2.10;   % dur of question presentation
defaults.maxDur         = 1.70;   % (max) dur of trial
defaults.ISI            = 0.30;   % dur of interval between trials
defaults.firstISI       = 0.15;   % dur of interval between question and
                                  % first trial of each block
defaults.ignoreDur      = 0.20;   % dur after trial presentation in which
                                  % button presses are ignored (this is
                                  % useful when participant provides a late
                                  % response to the previous trial)
                                  % DEFAULT VALUE = 0.15
defaults.prestartdur    = 8;      % duration of fixation period after trigger
                                  % and before first block
end
