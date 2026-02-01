clc;
clear;
close all;

% DEFINE MATERIAL PARAMETERS
face_brick.R = 0.090/1.31; % thickness/k
face_brick.Cp = 921;
face_brick.rho = 2083;

drywall.R = 0.0125/0.16;
drywall.Cp = 840;
drywall.rho = 950;

insulation.R = 0.090/0.035;
insulation.Cp = 840;
insulation.rho = 12;

double_pane.U = 2.8;

air.h = 15;
air.Cp = 1005;
air.rho = 1.225;

indoor_concrete.R = 0.1524/1.13;
indoor_concrete.Cp = 1000;
indoor_concrete.rho = 2000;

% SIMULATION LOCATION (Austin TX)
location.longitude = -97.743; %[deg]
location.latitude = 30.2672; %[deg]
location.altitude = 185; % [m]
location.temperature.low = [5, 8, 11, 15, 19, 23, 24, 25, 22, 16, 10, 7];
location.temperature.high = [17, 19, 24, 27, 31, 35, 36, 38, 34, 29, 22, 18];

% SIMULATION LOCATION (ANCHORAGE AK)
% location.longitude = -149.8631; %[deg]
% location.latitude = 61.2173; %[deg]
% location.altitude = 31; % [m]

% DEFINE SIMULATION CONDITIONS
L = 60; W = 24; H = 6.6; % Building dimensions
V = L*W*H; % Volume of building
A_s = 2 * (L * H + W * H) + L * W; % Surface area of whole building (neglect floor)
% Calculate the specific area of the South Wall
A_NS_Wall = L * H; 
A_EW_Wall = W * H;

% DEFINE WINDOWS AND EXTERIOR WALLS

% [Surface Area(m^2_, Phi Angle(deg east of north), # of windows on face]
windows = [
    0.45*A_NS_Wall, 180, 36; % South Window
    0.30*A_NS_Wall, 0  , 36;   % North Window
    0.30*A_EW_Wall, 90 , 12;  % East  Window
    0.30*A_EW_Wall, 270, 12; % West  Window
];

% Calculate OPAQUE Area (Total Wall - Window Area)
% [Area, Angle]
opaque_walls = [
    (A_NS_Wall - windows(1,1)), 180; % South Wall
    (A_NS_Wall - windows(2,1)), 0;   % North Wall
    (A_EW_Wall - windows(3,1)), 90;  % East Wall
    (A_EW_Wall - windows(4,1)), 270; % West Wall
];

A_window_total = sum(windows(:,1));

A_wall_total = A_s - A_window_total;

% DEFINE NODES (Capacitors)
% [ID, Interior Solar Absorption %, Exterior Solar Absorption %, Capacitance
nodes = [
    1, 0  , 0.7, face_brick.Cp*face_brick.rho*A_wall_total*0.090; % C = Cp * Density * Surface Area * Thickness
    2, 0  , 0  , insulation.Cp*insulation.rho*A_wall_total*0.090;
    3, 0  , 0  , drywall.Cp*drywall.rho*A_wall_total*0.0125;
    4, 0.8, 0  , indoor_concrete.Cp*indoor_concrete.rho*L*W*0.1524;
    5, 0.2, 0  , air.Cp*V*air.rho; % Indoor Air
    6, 0  , 0  , inf % Outdoor air (infinite Capacitance = heat reservoir)
];
n = size(nodes, 1);

% DEFINE RESISTORS
% pre-calculate (R_absolute = R_value / Area)
R_brick_abs = face_brick.R / A_wall_total;
R_ins_abs   = insulation.R / A_wall_total;
R_dry_abs   = drywall.R / A_wall_total;
R_conc_abs  = indoor_concrete.R / (L*W);
R_conv      = 1 / (air.h * A_wall_total);

resistors = [
    % 1. Outside Air (5) -> Face Brick Center (1)
    % Resistance = Convection + Half Brick
    n, 1, R_conv + (R_brick_abs / 2);

    % 2. Face Brick Center (1) -> Insulation Center (2)
    % Resistance = Half Brick + Half Insulation
    1, 2, (R_brick_abs / 2) + (R_ins_abs / 2);

    % 3. Insulation Center (2) -> Drywall Center (3)
    % Resistance = Half Insulation + Half Drywall
    2, 3, (R_ins_abs / 2) + (R_dry_abs / 2);

    % 4. Drywall Center (3) -> Inside Air (n-1)
    % Resistance = Half Drywall + Convection
    3, n-1, (R_dry_abs / 2) + R_conv;

    % 5. Concrete Center (4) -> Inside Air (n-1)
    % Resistance = Half Concrete + Convection
    4, n-1, (R_conc_abs / 2) + R_conv;
    
    % 6. Window (Outside Air to Inside Air)
    n, n-1, 1 / (double_pane.U * A_window_total);
];

% CREATE R MATRIX
R = zeros(n, n);
for i = 1:size(resistors,1)
    node1 = resistors(i, 1);
    node2 = resistors(i, 2);
    r_val = resistors(i, 3);
    
    % Make Matrix Symmetric (Heat flows both ways)
    R(node1, node2) = r_val;
    R(node2, node1) = r_val; 
end

disp(R)

% CREATE C VECTOR
C = zeros(n, 1);
for i = 1:n
    id = nodes(i, 1);
    C(id) = nodes(i, 4);
end


% Time Set Up
dt = 60; % Time step (seconds).
t_end = 15 * 24 * 3600;
time_vec = 0:dt:t_end;
num_steps = length(time_vec);

% Generate dates for the whole year
start_date = datetime(2026, 1, 23, 0, 0, 0);
date_list = start_date + seconds(time_vec);
months = month(date_list);

% Pre-Calculate Temperatures for the year
lows = interp1(1:12, location.temperature.low, months, 'linear', 'extrap');
highs = interp1(1:12, location.temperature.high, months, 'linear', 'extrap');
amps = (highs - lows) / 2;
T_outside_vec = lows + amps + amps .* cos(2*pi * (time_vec - 15*3600) / (24*3600)) + 273.15;

% SIMULATION
T = 20 * ones(n, 1) + 273.15; % Initial Temp Vector
energy_inputs = zeros(num_steps, 1);
timeZone = -6;

tic; % Start timer
for z = 1:num_steps
    % Update Outside Air Temp
    T(n) = T_outside_vec(z);
    
    % Calculate Sun Position
    [y, m, d] = ymd(date_list(z));
    [h, mn, s] = hms(date_list(z));
    timeStruct.year=y; timeStruct.month=m; timeStruct.day=d;
    timeStruct.hour=h; timeStruct.min=mn; timeStruct.sec=s;
    timeStruct.UTC=timeZone;
    
    sun = sun_position(timeStruct, location);
    % sun.azimuth_rad = deg2rad(sun.azimuth);
    % sun.altitude_rad = deg2rad(90 - sun.zenith);

    dT = zeros(n, 1);

    Q_sol_win = 0;
    % Calculate heat through windows from sun.
    for y = 1:size(windows,1)
        if y == 1 % Temporarily only apply louvers to south windows
            % Effective surface area with louver shading: # of windows * effective of one window
            A_s_eff = windows(y,3) * louver_sunlit_area(sun, windows(y,2), (3/5)*2.87, 2.87, 0.5, 0.5, 25);
            Q_sol_win = Q_sol_win + solar_sim(sun, windows(y,2), A_s_eff);
        else 
            Q_sol_win = Q_sol_win + solar_sim(sun, windows(y,2), windows(y,1));
        end
    end

    Q_sol_wall = 0;
    % Calculate heating of exterior surface from sun.
    for y = 1:size(windows,1)
        Q_sol_wall = Q_sol_wall + solar_sim(sun, opaque_walls(y,2), opaque_walls(y,1));
    end


    for k = 1:n
        
        % Calculate NET flow using neighbor nodes
        if C(k) ~= inf % Don't calculate for infinite reservoirs
            for i = 1:n
                if R(i, k) ~= 0 % Check if there is a resistor there
                    % Ohm's Law for Heat: (T_neighbor - T_node) / R
                    flow = (T(i) - T(k)) / R(i, k);
                    dT(k) = dT(k) + flow;
                end
            end
            % Update Temp Change: (Net Heat Flow * dt) / Capacitance
            dT(k) = (dT(k) + Q_sol_win*nodes(k, 2) + Q_sol_wall*nodes(k,3)) * dt / C(k);
        end
    end
    
    % Update temperatures
    T = T + dT;

    % Calculate energy required to heat/cool
    energy_inputs(z) =  -1 * nodes(n-1,4) * (dT(n-1)/dt);

    T(n-1) = 293.15;
end

% PLOT RESULT
figure;
%scatter(mod(time_vec, 24*3600)/3600, energy_inputs/1000, '.');
scatter(time_vec/3600, energy_inputs/1000, '.');
hold on;
xlabel('Time (hours)');
ylabel('Load (kW)');
title('Active Heating/Cooling Requirements');
grid on;