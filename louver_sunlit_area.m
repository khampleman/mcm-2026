function A_SL = louver_sunlit_area(location, currentTime, timeZone, psi, W, H, Pv, Ph, theta)

% location: struct
%   ex:
%       location.longitude = -97.743; [deg]
%       location.latitude = 30.2672; [deg]
%       location.altitude = 185; % [m]

% currentTime: ex - datetime(2026, 1, 30, 0, 0, 0);

% timeZone: deviance from UTC (ex: -6 for central time)

% psi: [deg] Angle of window East of North
psi = deg2rad(psi);

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

% If the angle of incidence is > 90 degrees, the window is in self-shadow
if cos(gamma) <= 0
    A_SL = 0;
    return;
end

tanOmega = tan(sun.altitude)/cos(gamma); % Tangent of profile angle

% Calculate sunlit area of window
% 1. Vertical Shadow (from horizontal louver)
% Shadow length = Ph * tanOmega
% Sunlit Height = Window Height - Shadow Length
% Logic: max(0, ...) prevents negative values
h_sunlit = max(0, H - (Ph * tanOmega));

% 2. Horizontal Shadow (from vertical louvers)
% We calculate the shadow width projected onto the glass
shadow_width = Pv * (abs(sin(gamma - theta)) / (cos(theta) * cos(gamma)));

% Sunlit Width = Window Width - Shadow Width
w_sunlit = max(0, W - shadow_width);

% Final Area Calculation
A_SL = w_sunlit * h_sunlit;

end