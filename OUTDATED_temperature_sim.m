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

                            % Jan                  -                   Dec
location.temperature.low =  [5, 8, 11, 15, 19, 23, 24, 25, 22, 16, 10, 7];
location.temperature.high = [17, 19, 24, 27, 31, 35, 36, 38, 34, 29, 22, 18];

% DEFINE SIMULATION CONDITIONS
L = 60; W = 24; H = 6.6; % Building dimensions
V = L*W*H; % Volume of building
A_s = 2 * (L * H + W * H) + L * W; % Surface area of whole building (neglect floor)
% Calculate the specific area of the South Wall
A_NS_Wall = L * H; 
A_EW_Wall = W * H;

% DEFINE WINDOWS AND EXTERIOR WALLS

% [Surface Area(m^2_, Phi Angle(deg east of north)]
windows = [
    0.45*A_NS_Wall, 180; % South Window
    0.30*A_NS_Wall, 0;   % North Window
    0.30*A_EW_Wall, 90;  % East  Window
    0.30*A_EW_Wall, 270; % West  Window
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
    1, 0  , 0.0, face_brick.Cp*face_brick.rho*A_wall_total*0.090; % C = Cp * Density * Surface Area * Thickness
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

% DEFINE TIME PARAMETERS
currentTime = datetime(2026, 1, 1, 0, 0, 0);
timeZone = -6; % UTC-6 is Central Time
% timeZone = -9; % UTC-9 is Anchorage Time
dt = 60;
t_end = 5 * 24 * 3600;
time = 0:dt:t_end; 

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
C = zeros(1, n);
for i = 1:n
    id = nodes(i, 1);
    C(id) = nodes(i, 4);
end

% SIMULATION
indoor_temps = zeros(size(time)); 

T = 20 * ones(1, n); 
T = T + 273.15; % Convert to Kelvin
indoor_temps(1) = T(n-1);
outdoor_temps = zeros(size(time));
outdoor_temps(1) = T(n);

for z = 2:length(time)

    % Update outside temperature:
    low = interp1(1:12, location.temperature.low, month(currentTime), 'linear', 'extrap');
    high = interp1(1:12, location.temperature.high, month(currentTime), 'linear', 'extrap');
    amplitude = (high - low) / 2;
    Period = 24 * 3600;
    Time_of_Max = 15 * 3600;
    outsideTemp = low + amplitude + amplitude * cos(2*pi * (time(z) - Time_of_Max) / Period) + 273.15; % Convert to Kelvin
    T(n) = outsideTemp;
    outdoor_temps(z) = outsideTemp;

    dT = zeros(1, n);

    Q_sol_win = 0;
    % Calculate heat through windows from sun.
    for y = 1:size(windows,1)
        Q_sol_win = Q_sol_win + solar_sim(location, currentTime, timeZone, windows(y,2), windows(y,1));
    end

    Q_sol_wall = 0;
    % Calculate heating of exterior surface from sun.
    for y = 1:size(windows,1)
        Q_sol_wall = Q_sol_wall + solar_sim(location, currentTime, timeZone, opaque_walls(y,2), opaque_walls(y,1));
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

    % Store indoor temperature
    indoor_temps(z) = T(n-1);

    % Increment time
    currentTime = currentTime + seconds(dt);
end

% PLOT RESULTS
figure;
scatter(mod(time, 24*3600)/3600, indoor_temps-273.15, '.');
hold on;
scatter(mod(time, 24*3600)/3600, outdoor_temps-273.15, '.r');
xlabel('Time (hours)');
ylabel('Temperature (°C)');
title('Interior Air Temperature');
grid on;