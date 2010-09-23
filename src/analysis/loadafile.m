function [F, t, Ts, params] = loadafile( fname )
%[F, t, Ts, params] = loadafile( fname )
%
% fname is a string of the complete file path; if it is not given, then a
% GUI "find file" dialog is opened.
%
% Let N be the number of microphone channels, and let K be the number of
% samples per channel. Then
%
%   F - an K x N matrix of mic array data. Note that it is not scaled, so
%       e.g. for 10 bit data, it would be an unsigned integer with possible
%       values from 0 to 1023.
%
%   t - time vector, size K x 1; time is measured with respect to trigger
%
%   Ts - sample period.
%
%   params - a structure containing anything else read from the array data
%   file; contents depend on the format version. Confer the BatStack
%   reference manual for details.
%
% On (most) errors, empty matrices are returned.
%
% The sister m-function to this script is genafile.m
%
%
% Scott Livingston  <slivingston@caltech.edu>
% June 2010.


% Run-time config (not accessible as function argument)
BUFFER_SIZE = 2^20; % For buffering array data matrix.

F = [];
t = [];
Ts = [];
params = [];

if nargin < 1
    [fname, pathname] = uigetfile( '*.bin', 'Select raw array data file.' );
    if isequal(fname,0)
        return
    end
    fname = [pathname fname];
end

% Attempt to open file and read header data
fd = fopen(fname,'r');
if fd == -1
    error( 'Failed to open file %s', fname );
end

params.ver_num = fread(fd,1,'uint8');
fprintf( 'Reading file %s, detected version %d...\n', fname, params.ver_num );

% At the time of writing, there is only one file format version, so we do
% not use any conditional switching here. Future editions will need to add
% such version-specific routines.
%
% Version 1

% Date
rec_date_raw = fread(fd, 2, 'uint8');
rec_date_v = [0 0 0 0 0 0];
rec_date_v(3) = bitand(rec_date_raw(1), hex2dec('1F') );
rec_date_v(2) = bitshift( bitand( rec_date_raw(1), hex2dec('E0') ), -5 );
rec_date_v(2) = bitor( rec_date_v(2), bitshift( bitand(rec_date_raw(2),1), 3 ) );
rec_date_v(1) = bitshift( bitand( rec_date_raw(2), hex2dec('FE') ), -1 ) + 1970;

if nnz(rec_date_v) == 0
    params.recording_date = '';
else
    params.recording_date = datestr(rec_date_v);
end

% Trial number
params.trial_number = fread(fd, 1, 'uint8' );

% Num channels
params.num_channels = fread(fd, 1, 'uint8' );

% Sample period
Ts_raw = fread(fd, 2, 'uint8' );
params.sample_period = (Ts_raw(1) + bitshift( Ts_raw(2), 8 ))*1e-8; % Now in units of seconds
Ts = params.sample_period; % Echoed as a return value.

% Post-trigger length
ptl_raw = fread(fd, 4, 'uint8' );
params.post_trigger_samps = ptl_raw(1) + bitshift( ptl_raw(2), 8 ) + ...
                            bitshift( ptl_raw(3), 16 ) + bitshift( ptl_raw(4), 24 );

% Notes string
notes_raw = fread(fd, 128, 'char' );
params.notes = char( [notes_raw(1:max(find(notes_raw ~= 0)))]' );

% Read the actual data
% F = zeros(BUFFER_SIZE, params.num_channels);
% rows_written = 0;
% while ~feof(fd)
    
%     if rem(size(F,1),BUFFER_SIZE) && rows_written > 0 % Time to grow F buffer?
%         tmp_F = F;
%         F = zeros(size(tmp_F,1)+BUFFER_SIZE, params.num_channels);
%         F(1:size(tmp_F,1),:) = tmp_F;
%         clear tmp_F;
%     end
%     
%     for k = 1:params.num_channels
%         tmp_dat = fread(fd, 2, 'uint8' );
%         F(rows_written+1,k) = tmp_dat(1) + bitshift(tmp_dat(2),8);
%     end
%     
%     rows_written = rows_written + 1;    
% end
% fclose(fd);
% 
% if size(F,1) > rows_written % Trim unused rows
%     F = F(1:rows_written,:);
% end

% We hope that the native machine is little-endian; otherwise, doing this
% by hand (a la splitting each sample into two separate bytes) requires an
% ungodly amount of time in Matlab.
F = fread(fd, 'uint16' );
fclose(fd);
F = reshape( F, params.num_channels, floor(length(F)/params.num_channels) );
F = F';

% Finally, construct time vector
t = (1:size(F,1))*Ts;
t = t - t(end-params.post_trigger_samps);