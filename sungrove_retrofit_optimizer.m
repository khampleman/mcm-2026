clc;
clear;
close all;

% --- 1. SETUP & CONSTANTS ---
% Material Parameters
face_brick.R = 0.090/1.31; face_brick.Cp = 921; face_brick.rho = 2083;
drywall.R = 0.0125/0.16;   drywall.Cp = 840;    drywall.rho = 950;
insulation.R = 0.090/0.035;insulation.Cp = 840; insulation.rho = 12;
double_pane.U = 2.8;
air.h = 15; air.Cp = 1005; air.rho = 1.225;
indoor_concrete.R = 0.1524/1.13; indoor_concrete.Cp = 1000; indoor_concrete.rho = 2000;

% Solar Absorptivity
alpha_wall = 0.7; 
alpha_roof = 0.2; 

% Location (Austin TX)
location.longitude = -97.743; 
location.latitude = 30.2672; 
location.altitude = 185; 
location.temperature.low = [5, 8, 11, 15, 19, 23, 24, 25, 22, 16, 10, 7];
location.temperature.high = [17, 19, 24, 27, 31, 35, 36, 38, 34, 29, 22, 18];

% Geometry
L = 60; W = 24; H = 6.6; 
V = L*W*H; 
A_roof = L * W; 
A_vertical_gross = 2 * (L * H + W * H); 
A_total_shell_gross = A_roof + A_vertical_gross; 
A_NS_Wall = L * H; 
A_EW_Wall = W * H;

% BASE WINDOW CONFIGURATION (Indices 6,7,8 are placeholders for optimization)
% [Area, Phi, Count, W, H, Pv, Ph, theta, H_spac]
windows_base = [
    0.45*A_NS_Wall, 180, 36, 1.723, 2.872, 0, 0, 0, 1.525; % South (Index 1)
    0.30*A_NS_Wall, 0  , 36, 1.407, 2.345, 0, 0, 0, 1.824; % North (Index 2)
    0.30*A_EW_Wall, 90 , 14, 1.427, 2.378, 0, 0, 0, 1.751; % East  (Index 3)
    0.30*A_EW_Wall, 270, 14, 1.427, 2.378, 0, 0, 0, 1.751; % West  (Index 4)
];

A_window_total = sum(windows_base(:,1));
A_opaque_total = A_total_shell_gross - A_window_total;

opaque_walls = [
    (A_NS_Wall - windows_base(1,1)), 180;
    (A_NS_Wall - windows_base(2,1)), 0;
    (A_EW_Wall - windows_base(3,1)), 90;
    (A_EW_Wall - windows_base(4,1)), 270;
];

% --- 2. THERMAL NETWORK PRE-CALC ---
nodes = [
    1, 0, 1.0, face_brick.Cp*face_brick.rho*A_opaque_total*0.090;
    2, 0, 0  , insulation.Cp*insulation.rho*A_opaque_total*0.090;
    3, 0, 0  , drywall.Cp*drywall.rho*A_opaque_total*0.0125;
    4, 0.8, 0, indoor_concrete.Cp*indoor_concrete.rho*L*W*0.1524;
    5, 0.2, 0, air.Cp*V*air.rho; 
    6, 0, 0  , inf 
];
n_nodes = size(nodes, 1);

R_brick_abs = face_brick.R / A_opaque_total;
R_ins_abs   = insulation.R / A_opaque_total;
R_dry_abs   = drywall.R / A_opaque_total;
R_conc_abs  = indoor_concrete.R / (L*W);
R_conv      = 1 / (air.h * A_opaque_total);

resistors = [
    n_nodes, 1, R_conv + (R_brick_abs / 2);
    1, 2, (R_brick_abs / 2) + (R_ins_abs / 2);
    2, 3, (R_ins_abs / 2) + (R_dry_abs / 2);
    3, n_nodes-1, (R_dry_abs / 2) + R_conv;
    4, n_nodes-1, (R_conc_abs / 2) + R_conv;
    n_nodes, n_nodes-1, 1 / (double_pane.U * A_window_total);
];

R_mat = zeros(n_nodes, n_nodes);
for i = 1:size(resistors,1)
    n1 = resistors(i, 1); n2 = resistors(i, 2); val = resistors(i, 3);
    R_mat(n1, n2) = val; R_mat(n2, n1) = val; 
end
C_vec = nodes(:, 4); 

% --- 3. WEATHER & SUN PRE-CALCULATION (SPEED BOOST) ---
% We calculate this ONCE before the loop to save massive time.
fprintf('Pre-calculating annual weather and solar positions...\n');
dt = 600; 
t_end = 365 * 24 * 3600;
time_vec = 0:dt:t_end; 
num_steps = length(time_vec);

start_date = datetime(2026, 1, 1, 0, 0, 0);
date_list = start_date + seconds(time_vec);

% Weather Interpolation
month_centers = 15:30:365; 
day_of_year_vec = days(date_list - datetime(2026,1,1,0,0,0)) + 1;
monthly_lows_wrap = [location.temperature.low(12), location.temperature.low, location.temperature.low(1)];
monthly_highs_wrap = [location.temperature.high(12), location.temperature.high, location.temperature.high(1)];
month_centers_wrap = [-15, month_centers, 380];
lows = interp1(month_centers_wrap, monthly_lows_wrap, day_of_year_vec, 'pchip');
highs = interp1(month_centers_wrap, monthly_highs_wrap, day_of_year_vec, 'pchip');
amps = (highs - lows) / 2;
T_outside_data = lows + amps + amps .* cos(2*pi * (time_vec - 15*3600) / (24*3600)) + 273.15;

% Solar Position Arrays
sun_azimuths = zeros(1, num_steps);
sun_zeniths = zeros(1, num_steps);
timeZone = -6;

for z = 1:num_steps
    [y, m, d] = ymd(date_list(z));
    [h, mn, s] = hms(date_list(z));
    timeStruct.year=y; timeStruct.month=m; timeStruct.day=d;
    timeStruct.hour=h; timeStruct.min=mn; timeStruct.sec=s;
    timeStruct.UTC=timeZone;
    sun = sun_position(timeStruct, location);
    sun_azimuths(z) = sun.azimuth;
    sun_zeniths(z) = sun.zenith;
end

% --- 4. OPTIMIZATION LOOP ---
num_iterations = 999999; % Number of random attempts
best_energy = inf;
best_params = [];

% Set RNG seed for randomness
rng('shuffle');

% Run BASELINE First (No Louvers)
% This ensures we have a real "worst case" to compare against
fprintf('Running Baseline (No Louvers)...\n');
windows_trial = windows_base; % Zeros for louvers
baseline_energy = run_simulation(windows_trial, opaque_walls, nodes, R_mat, C_vec, T_outside_data, sun_azimuths, sun_zeniths, alpha_wall, alpha_roof, A_roof, dt, n_nodes);
best_energy = baseline_energy;
best_params = zeros(1, 9); % Zeros
fprintf('Baseline Energy: %.2f kWh\n', best_energy);
fprintf('--------------------------------------------------\n');

fprintf('Starting Optimization (%d Iterations)...\n', num_iterations);
tic;

for iter = 1:num_iterations
    
    % A. Generate Random Parameters
    % Constraints: 0 < Pv, Ph < 1.0  |  -45 < theta < 45
    
    % South (Index 1)
    Pv_S = rand * 1.0; 
    Ph_S = rand * 1.0;
    Th_S = (rand * 90) - 45;
    
    % East (Index 3)
    Pv_E = rand * 1.0; 
    Ph_E = rand * 1.0;
    Th_E = (rand * 90) - 45;
    
    % West (Index 4)
    Pv_W = rand * 1.0; 
    Ph_W = rand * 1.0;
    Th_W = (rand * 90) - 45;
    
    % Apply to Trial Matrix
    windows_trial = windows_base;
    windows_trial(1, 6:8) = [Pv_S, Ph_S, Th_S];
    windows_trial(3, 6:8) = [Pv_E, Ph_E, Th_E];
    windows_trial(4, 6:8) = [Pv_W, Ph_W, Th_W];
    
    % B. Run Simulation
    energy_kWh = run_simulation(windows_trial, opaque_walls, nodes, R_mat, C_vec, T_outside_data, sun_azimuths, sun_zeniths, alpha_wall, alpha_roof, A_roof, dt, n_nodes);
    
    % C. Compare
    if energy_kWh < best_energy
        best_energy = energy_kWh;
        best_params = [Pv_S, Ph_S, Th_S, Pv_E, Ph_E, Th_E, Pv_W, Ph_W, Th_W];
        
        % PRINT UPDATE IMMEDIATELY
        fprintf('Iter %d: NEW BEST! %.2f kWh (Saved: %.2f kWh)\n', iter, best_energy, (baseline_energy - best_energy));
        fprintf('   SOUTH: Pv=%.2f, Ph=%.2f, Th=%.2f\n', Pv_S, Ph_S, Th_S);
        fprintf('   EAST : Pv=%.2f, Ph=%.2f, Th=%.2f\n', Pv_E, Ph_E, Th_E);
        fprintf('   WEST : Pv=%.2f, Ph=%.2f, Th=%.2f\n', Pv_W, Ph_W, Th_W);
        fprintf('--------------------------------------------------\n');
    end
end
sim_time = toc;

% --- 5. RESULTS ---
fprintf('\n=========================================\n');
fprintf('OPTIMIZATION COMPLETE in %.2f seconds\n', sim_time);
fprintf('Best Annual Load: %.2f kWh\n', best_energy);
fprintf('=========================================\n');
fprintf('OPTIMAL PARAMETERS:\n');
fprintf('SOUTH: Pv=%.2fm, Ph=%.2fm, Theta=%.2f deg\n', best_params(1), best_params(2), best_params(3));
fprintf('EAST:  Pv=%.2fm, Ph=%.2fm, Theta=%.2f deg\n', best_params(4), best_params(5), best_params(6));
fprintf('WEST:  Pv=%.2fm, Ph=%.2fm, Theta=%.2f deg\n', best_params(7), best_params(8), best_params(9));


% --- HELPER FUNCTION: RUN SIMULATION ---
% Defined locally to keep the loop clean
function total_kWh = run_simulation(windows, opaque_walls, nodes, R_mat, C_vec, T_outside, sun_az, sun_zen, alpha_wall, alpha_roof, A_roof, dt, n_nodes)
    
    T = 20 * ones(n_nodes, 1) + 273.15; 
    total_joules = 0;
    num_steps = length(T_outside);
    
    for z = 1:num_steps
        T(n_nodes) = T_outside(z);
        
        % Build temp struct
        sun.azimuth = sun_az(z);
        sun.zenith = sun_zen(z);
        
        dT = zeros(n_nodes, 1);
        Q_sol_win = 0;
        Q_wall_loss = 0;
        
        % Windows
        for y = 1:size(windows, 1)
            % Check if louver params exist (cols 6,7 > 0) OR if it's North (idx 2)
            if windows(y, 6) > 0 || windows(y, 7) > 0 || windows(y, 8) ~= 0
                 [A_win_sl, A_wall_sl] = louver_sunlit_area(sun, windows(y,2), windows(y,4), windows(y,5), windows(y,6), windows(y,7), windows(y,8), windows(y,9));
                 
                 % Window Gain
                 Q_sol_win = Q_sol_win + solar_sim(sun, windows(y,2), A_win_sl * windows(y,3));
                 
                 % Wall Shadow Loss
                 Gap_Area = windows(y,5) * windows(y,9);
                 Gap_Shaded = Gap_Area - A_wall_sl;
                 if Gap_Shaded > 0
                     Q_wall_loss = Q_wall_loss + solar_sim(sun, windows(y,2), Gap_Shaded * windows(y,3));
                 end
            else
                 % No Louver (North or Base Case)
                 Q_sol_win = Q_sol_win + solar_sim(sun, windows(y,2), windows(y,1));
            end
        end
        
        % Opaque Walls & Roof
        Q_absorbed = 0;
        for w = 1:size(opaque_walls, 1)
            Q_inc = solar_sim(sun, opaque_walls(w,2), opaque_walls(w,1));
            Q_absorbed = Q_absorbed + (Q_inc * alpha_wall);
        end
        Q_absorbed = Q_absorbed - (Q_wall_loss * alpha_wall);
        
        if (90 - sun.zenith) > 0
            zenith_rad = deg2rad(sun.zenith);
            AM = 1/cos(zenith_rad);
            DNI = 1353 * (0.7 ^ AM) ^ 0.678;
            Q_roof = DNI * cos(zenith_rad) * A_roof;
        else
            Q_roof = 0;
        end
        Q_absorbed = Q_absorbed + (Q_roof * alpha_roof);
        
        % Solver
        for k = 1:n_nodes
            if C_vec(k) ~= inf
                for i = 1:n_nodes
                    if R_mat(i, k) ~= 0
                        dT(k) = dT(k) + (T(i) - T(k)) / R_mat(i, k);
                    end
                end
                if k == 1
                    dT(k) = (dT(k) + Q_absorbed) * dt / C_vec(k);
                else
                    dT(k) = (dT(k) + Q_sol_win*nodes(k, 2)) * dt / C_vec(k);
                end
            end
        end
        
        T = T + dT;
        
        % Energy Integration
        load_watts = -1 * nodes(5,4) * (dT(5)/dt);
        total_joules = total_joules + abs(load_watts) * dt; 
        
        T(5) = 293.15; 
    end
    total_kWh = total_joules / 3.6e6;
end