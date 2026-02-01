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
% Solar Absorptivity
alpha_wall = 0.7; % Standard Brick
alpha_roof = 0.2; % White Roof

% SIMULATION LOCATION (Austin TX)
location.longitude = -97.743; %[deg]
location.latitude = 30.2672; %[deg]
location.altitude = 185; % [m]
location.temperature.low = [5, 8, 11, 15, 19, 23, 24, 25, 22, 16, 10, 7];
location.temperature.high = [17, 19, 24, 27, 31, 35, 36, 38, 34, 29, 22, 18];

% DEFINE SIMULATION CONDITIONS
L = 60; W = 24; H = 6.6; % Building dimensions
V = L*W*H; % Volume of building

% Area Calculations (Separating Roof vs Walls)
A_roof = L * W; % Roof Area (Horizontal)
A_vertical_gross = 2 * (L * H + W * H); % Total Vertical Wall Area
A_total_shell_gross = A_roof + A_vertical_gross; % Total Exterior Area

% Calculate the specific area of the South Wall
A_NS_Wall = L * H; 
A_EW_Wall = W * H;

% DEFINE WINDOWS AND EXTERIOR WALLS
% [   Surface Area(m^2_, Phi Angle(deg east of north), 
% ... # of windows on face, Width, Height,
% ... Vertical Projection, Horizontal Projection, louver angle]
windows = [
    0.45*A_NS_Wall, 180, 36, 1.723, 2.872, 0.5, 0.5, -25; % South Window
    0.30*A_NS_Wall, 0  , 36, 1.407, 2.345, 0  , 0  , 0 ; % North Window
    0.30*A_EW_Wall, 90 , 14, 1.427, 2.378, 0.5, 0.5, -25; % East  Window
    0.30*A_EW_Wall, 270, 14, 1.427, 2.378, 0.5, 0.5, -25; % West  Window
%   1               2    3   4      5      6    7    8
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
% Total Opaque Area (Vertical Walls + Roof) for Mass/Resistance calculations
A_opaque_total = A_total_shell_gross - A_window_total;

% DEFINE NODES (Capacitors)
% [ID, Interior Solar Absorption %, Exterior Solar Absorption %, Capacitance
nodes = [
    1, 0  , 1.0, face_brick.Cp*face_brick.rho*A_opaque_total*0.090; % C = Cp * Density * Surface Area * Thickness
    2, 0  , 0  , insulation.Cp*insulation.rho*A_opaque_total*0.090;
    3, 0  , 0  , drywall.Cp*drywall.rho*A_opaque_total*0.0125;
    4, 0.8, 0  , indoor_concrete.Cp*indoor_concrete.rho*L*W*0.1524;
    5, 0.2, 0  , air.Cp*V*air.rho; % Indoor Air
    6, 0  , 0  , inf % Outdoor air (infinite Capacitance = heat reservoir)
];
n = size(nodes, 1);

% DEFINE RESISTORS
% pre-calculate (R_absolute = R_value / Area)
R_brick_abs = face_brick.R / A_opaque_total;
R_ins_abs   = insulation.R / A_opaque_total;
R_dry_abs   = drywall.R / A_opaque_total;
R_conc_abs  = indoor_concrete.R / (L*W);
R_conv      = 1 / (air.h * A_opaque_total);

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
dt = 600; % Time step (seconds).
t_end = 365 * 24 * 3600;
time_vec = 0:dt:t_end;
num_steps = length(time_vec);

% Generate dates for the whole year
start_date = datetime(2026, 1, 1, 0, 0, 0);
date_list = start_date + seconds(time_vec);
months = month(date_list);

% Pre-Calculate Temperatures for the year (Smoothed)
% Map monthly data to the middle of each month
month_centers = 15:30:365; 
day_of_year_vec = days(date_list - datetime(2026,1,1,0,0,0)) + 1;
monthly_lows_wrap = [location.temperature.low(12), location.temperature.low, location.temperature.low(1)];
monthly_highs_wrap = [location.temperature.high(12), location.temperature.high, location.temperature.high(1)];
month_centers_wrap = [-15, month_centers, 380];
lows = interp1(month_centers_wrap, monthly_lows_wrap, day_of_year_vec, 'pchip');
highs = interp1(month_centers_wrap, monthly_highs_wrap, day_of_year_vec, 'pchip');
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
    
    dT = zeros(n, 1);
    Q_sol_win = 0;
    
    % Calculate heat through windows from sun.
    for y = 1:size(windows,1)
        % Effective surface area with louver shading: # of windows * effective of one window
        A_s_eff = windows(y,3) * louver_sunlit_area(sun, windows(y,2), windows(y,4), windows(y,5), windows(y,6), windows(y,7), windows(y,8));
        Q_sol_win = Q_sol_win + solar_sim(sun, windows(y,2), A_s_eff);
    end
    
    % Calculate heating of exterior surface from sun.
    Q_absorbed_shell = 0;
    
    % 1. Vertical Walls (70% Absorption)
    for y = 1:size(opaque_walls,1)
        Q_incident = solar_sim(sun, opaque_walls(y,2), opaque_walls(y,1));
        Q_absorbed_shell = Q_absorbed_shell + (Q_incident * alpha_wall);
    end
    
    % 2. Horizontal Roof (20% Absorption)
    if (90 - sun.zenith) > 0
        zenith_rad = deg2rad(sun.zenith);
        AM = 1/cos(zenith_rad);
        DNI = 1353 * (0.7 ^ AM) ^ 0.678;
        Q_incident_roof = DNI * cos(zenith_rad) * A_roof;
    else
        Q_incident_roof = 0;
    end
    Q_absorbed_shell = Q_absorbed_shell + (Q_incident_roof * alpha_roof);

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
            % Apply Wall/Roof Solar to Node 1 (Brick) and Window Solar to Nodes 4/5
            if k == 1
                dT(k) = (dT(k) + Q_absorbed_shell) * dt / C(k);
            else
                dT(k) = (dT(k) + Q_sol_win*nodes(k, 2)) * dt / C(k);
            end
        end
    end
    
    % Update temperatures
    T = T + dT;
    % Calculate energy required to heat/cool
    energy_inputs(z) =  -1 * nodes(n-1,4) * (dT(n-1)/dt);
    T(n-1) = 293.15;
end
toc;

% PLOT RESULT
figure;
% Plot a zoomed-in week in Summer (approx 4000 hours in)
subplot(2,1,1);
zoom_start = 4000 * (3600/dt); 
zoom_end = zoom_start + 168*(3600/dt);
plot(time_vec(zoom_start:zoom_end)/3600, energy_inputs(zoom_start:zoom_end)/1000, 'LineWidth', 1.5);
xlabel('Time (hours)'); ylabel('Load (kW)'); title('Zoomed Summer Week');
grid on;

% Plot Annual
subplot(2,1,2);
scatter(time_vec/3600, energy_inputs/1000, '.');
xlabel('Time (hours)'); ylabel('Load (kW)'); title('Annual Active Heating/Cooling');
grid on;

% --- ENERGY CALCULATION ---

% 1. Separate Heating (Positive) and Cooling (Negative)
% Note: In your logic, Positive = Adding Heat (Heating), Negative = Removing Heat (Cooling)
heating_power = max(0, energy_inputs); % zeros out negative values
cooling_power = abs(min(0, energy_inputs)); % zeros out positive values & makes cooling positive

% 2. Integrate Power over Time to get Energy (Joules)
% Energy (Joules) = Power (Watts) * Time (Seconds)
total_heating_joules = sum(heating_power) * dt;
total_cooling_joules = sum(cooling_power) * dt;

% 3. Convert Joules to kWh
% 1 kWh = 3,600,000 Joules
total_heating_kWh = total_heating_joules / 3.6e6;
total_cooling_kWh = total_cooling_joules / 3.6e6;

% 4. Display Annual Totals
fprintf('\n--------------------------------------\n');
fprintf('ANNUAL ENERGY SIMULATION RESULTS\n');
fprintf('--------------------------------------\n');
fprintf('Total Heating Load: %.2f kWh\n', total_heating_kWh);
fprintf('Total Cooling Load: %.2f kWh\n', total_cooling_kWh);
fprintf('Total System Load:  %.2f kWh\n', total_heating_kWh + total_cooling_kWh);

% --- MONTHLY BREAKDOWN PLOT ---
% It is often more useful to see this per month than as one big number

% Calculate the month for every time step
step_months = month(start_date + seconds(time_vec(1:end-1))); % Exclude last point to match size

monthly_heating = zeros(1, 12);
monthly_cooling = zeros(1, 12);

for m = 1:12
    % Find indices for this month
    idx = (step_months == m);
    
    % Sum energy for this month and convert to kWh
    monthly_heating(m) = sum(heating_power(idx)) * dt / 3.6e6;
    monthly_cooling(m) = sum(cooling_power(idx)) * dt / 3.6e6;
end

figure('Name', 'Monthly Energy Usage');
b = bar(1:12, [monthly_heating; monthly_cooling]', 'stacked');
b(1).FaceColor = [0.8500 0.3250 0.0980]; % Red for Heating
b(2).FaceColor = [0.0000 0.4470 0.7410]; % Blue for Cooling
xlabel('Month');
ylabel('Energy (kWh)');
title('Monthly Heating vs. Cooling Load');
legend('Heating', 'Cooling');
xticks(1:12);
xticklabels({'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'});
grid on;