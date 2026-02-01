function A_SL = louver_sunlit_area(sun, psi, W, H, Pv, Ph, theta)

% sun: [struct]
% ---- zenith  [deg]
% ---- azimuth [deg]

% psi: [deg] Angle of window East of North
psi = deg2rad(psi);

% W: [m] Width of window
% H: [m] Height of window

% Pv: [m] Vertical projection - length of vertical louvers
% Ph: [m] Horizontal projection - length of top horizontal louver

% theta: [deg] Vertical louver angle
theta = deg2rad(theta);

% SIMULATION

% Convert sun data to radians
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