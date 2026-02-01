function A_SL = louver_sunlit_area(location, currentTime, timeZone, psi, W, H, Pv, Ph, theta)

% location: struct
%   ex:
%       location.longitude = -97.743; [deg]
%       location.latitude = 30.2672; [deg]
%       location.altitude = 185; % [m]

% currentTime: ex - datetime(2026, 1, 30, 0, 0, 0);

% timeZone: deviance from UTC (ex: -6 for central time)

% psi: [deg] Angle of window East of North

% W: [m] Width of window
% H: [m] Height of window

% Pv: [m] Vertical projection - length of vertical louvers
% Ph: [m] Horizontal projection - length of top horizontal louver

% theta: [deg] Vertical louver angle
theta = deg2rad(theta);

% SIMULATION

dv = datevec(currentTime);

% Create the time struct
timeStruct.year = dv(1);
timeStruct.month = dv(2);
timeStruct.day = dv(3);
timeStruct.hour = dv(4);
timeStruct.min = dv(5);
timeStruct.sec = dv(6);
timeStruct.UTC = timeZone;

% Get sun position
sun = sun_position(timeStruct, location);
sun.azimuth = deg2rad(sun.azimuth);
sun.altitude = deg2rad(90 - sun.zenith);

% Compute necessary values
gamma = sun.azimuth - psi; % Surface solar azimuth
tanOmega = tan(sun.altitude)/cos(gamma); % Tangent of profile angle

% Calculate sunlit area of window
A_SL = ( W - Pv * ( abs( sin( gamma - theta ) ) / ( cos( theta ) * cos( gamma ) ) ) ) * ( H - Ph * tanOmega );

end