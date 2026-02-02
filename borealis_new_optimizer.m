clc;
clear;
close all;
addpath('./tools/');

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
triple_pane.U = 1/1.7; % ~0.588
air.h = 15;
air.Cp = 1005;
air.rho = 1.225;
concrete.R = 0.1524/1.13;
concrete.Cp = 1000;
concrete.rho = 2000;
% Solar Absorptivity
alpha_wall = 0.7; % Standard Brick
alpha_roof = 0.2; % White Roof
% Trombe Wall Parameters
alpha_trombe = 0.95; % Black painted mass wall
tau_trombe_glass = 0.75; % Transmissivity of triple pane glass

% SIMULATION LOCATION (Yellowknife, NT, Canada)
location.longitude = -114.370; %[deg]
location.latitude = 62.4536; %[deg]
location.altitude = 206; % [m]
location.temperature.low = [-29, -27, -21, -10, 1, 9, 13, 11, 5, -4, -18, -26];
location.temperature.high = [-21, -18, -10, 1, 11, 18, 21, 18, 11, 1, -11, -19];

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

num_iterations = 999999;
best_params = [0, 0];
best_energy = inf;
for iter = 1:num_iterations
    % GLOBAL SOUTH OVERHANG
    % This applies to both the Windows and the Trombe Wall on the South Face
    south_overhang_depth = 10*rand; % [m]
    
    % TROMBE WALL CONFIGURATION (PERCENTAGE)
    % Specify the % of available opaque wall to convert to Trombe Wall (0.0 to 1.0)
    % Order: [South, North, East, West]
    trombe_wall_percent = [rand, 0, 0, 0]; 
    
    % Black curtain Short Wave Radiant Fraction(SWRF)
    curtain.SWRF = 0.8;
    
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
    % ... Vertical Projection, Horizontal Projection, louver angle, Horiz Spacing]
    windows = [
        % SOUTH WINDOW: Uses south_overhang_depth
        0.45*A_NS_Wall, 180, 36, 1.723, 2.872, south_overhang_depth, south_overhang_depth, 0, 1.525; % South
        0.30*A_NS_Wall, 0  , 36, 1.407, 2.345, 0, 0, 0, 1.824; % North
        0.30*A_EW_Wall, 90 , 14, 1.427, 2.378, 0, 0, 0, 1.751; % East
        0.30*A_EW_Wall, 270, 14, 1.427, 2.378, 0, 0, 0, 1.751; % West
    ];
    A_window_total = sum(windows(:,1));
    
    % Define curtain parameters
    % [SWRF, Surface Area]
    curtains = [
        curtain.SWRF, windows(1,4)*2.03; % South
        curtain.SWRF, 0                ; % North
        curtain.SWRF, windows(3,4)*2.03; % East
        curtain.SWRF, windows(4,4)*2.03; % West
    ];
    % Calculate effective SWRF values
    effective_SWRF_vec = curtains(:,1).*curtains(:,2)./(windows(:,4).*windows(:,5));
    % Take weighted average to calculate total effective
    total_curtain_SA = sum(curtains(:,2));
    effective_SWRF = sum(effective_SWRF_vec.*curtains(:,2))/total_curtain_SA;
    
    % Trombe wall setup
    trombe_air_thickness  = 0.1;
    trombe_mass_thickness = 0.5;
    
    % DYNAMICALLY ASSIGN TROMBE VS OPAQUE WALLS (PERCENTAGE BASED)
    % We loop through the 4 faces (South, North, East, West)
    % Total Wall Areas for each face
    A_faces_total = [A_NS_Wall, A_NS_Wall, A_EW_Wall, A_EW_Wall];
    Angles = [180, 0, 90, 270];
    
    % Initialize Arrays [Area, Angle]
    trombe_walls = zeros(4, 2);
    opaque_walls = zeros(4, 2);
    
    for i = 1:4
        % Calculate remaining available area on this face (Total - Window)
        A_avail = A_faces_total(i) - windows(i, 1);
        
        % Determine split based on percentage
        pct = trombe_wall_percent(i);
        
        % Ensure pct is between 0 and 1
        pct = max(0, min(1, pct));
        
        A_t = A_avail * pct;      % Area converted to Trombe
        A_o = A_avail * (1 - pct);% Area remaining as Opaque
        
        trombe_walls(i, :) = [A_t, Angles(i)];
        opaque_walls(i, :) = [A_o, Angles(i)];
    end
    
    A_trombe_total = sum(trombe_walls(:,1));
    V_trombe_mass = A_trombe_total * trombe_mass_thickness;
    
    % Total Opaque Area (Vertical Walls + Roof) for Mass/Resistance calculations
    A_opaque_total = A_total_shell_gross - A_window_total - A_trombe_total;
    
    % DEFINE NODES (Capacitors)
    % [ID, Interior Solar Absorption %, Exterior Solar Absorption %, Capacitance
    % Note: Node 5 (Trombe Air) removed to prevent instability.
    %       New Order: 5=Mass, 6=Indoor, 7=Outdoor
    nodes = [
        1, 0               , 1.0, face_brick.Cp*face_brick.rho*A_opaque_total*0.090; % C = Cp * Density * Surface Area * Thickness
        2, 0               , 0  , insulation.Cp*insulation.rho*A_opaque_total*0.090;
        3, 0               , 0  , drywall.Cp*drywall.rho*A_opaque_total*0.0125;
        4, 1-effective_SWRF, 0  , concrete.Cp*concrete.rho*L*W*0.1524; % Concrete floor
        5, 1.0             , 0  , concrete.Cp*concrete.rho*V_trombe_mass; % Trombe Mass (Receives Solar)
        6, effective_SWRF  , 0  , air.Cp*V*air.rho; % Indoor Air
        7, 0               , 0  , inf % Outdoor air (infinite Capacitance = heat reservoir)
    ];
    n = size(nodes, 1);
    
    % DEFINE RESISTORS
    % pre-calculate (R_absolute = R_value / Area)
    R_brick_abs   = face_brick.R / A_opaque_total;
    R_ins_abs     = insulation.R / A_opaque_total;
    R_dry_abs     = drywall.R / A_opaque_total;
    R_conc_abs    = concrete.R / (L*W);
    R_trombe_abs  = concrete.R / (A_trombe_total);
    R_conv        = 1 / (air.h * A_opaque_total);
    R_trombe_conv = 1 / (air.h * A_trombe_total);
    if A_trombe_total == 0
        R_trombe_abs = 0;
        R_trombe_conv = 0;
    end
    resistors = [
        % Outside Air (n) -> Face Brick Center (1)
        % Resistance = Convection + Half Brick
        n, 1, R_conv + (R_brick_abs / 2);
        % Face Brick Center (1) -> Insulation Center (2)
        % Resistance = Half Brick + Half Insulation
        1, 2, (R_brick_abs / 2) + (R_ins_abs / 2);
        % Insulation Center (2) -> Drywall Center (3)
        % Resistance = Half Insulation + Half Drywall
        2, 3, (R_ins_abs / 2) + (R_dry_abs / 2);
        % Drywall Center (3) -> Inside Air (n-1)
        % Resistance = Half Drywall + Convection
        3, n-1, (R_dry_abs / 2) + R_conv;
        
        % Concrete Center (4) -> Inside Air (n-1)
        % Resistance = Half Concrete + Convection
        4, n-1, (R_conc_abs / 2) + R_conv;
        
        % Outside Air to Trombe Mass Center (Through Glass + Air Gap)
        % Resistance = (1/U_glass) + Convection + Half Mass
        n, 5, (1 / (triple_pane.U * A_trombe_total)) + R_trombe_conv + (R_trombe_abs / 2);
        
        % Trombe Mass Center to Inside Air (n-1)
        % Resistance = Half Mass + Convection
        5, n-1, (R_trombe_abs / 2) + R_trombe_conv;
        
        % Window (Outside Air to Inside Air)
        n, n-1, 1 / (triple_pane.U * A_window_total);
    ];
    if A_trombe_total == 0
        resistors(6,3) = 0;
    end
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
    % CREATE C VECTOR
    C = zeros(n, 1);
    for i = 1:n
        id = nodes(i, 1);
        C(id) = nodes(i, 4);
    end
    
    % SIMULATION
    T = 20 * ones(n, 1) + 273.15; % Initial Temp Vector
    energy_inputs = zeros(num_steps, 1);
    timeZone = -7; % MST for Yellowknife
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
        Q_wall_shaded_loss = 0; % Track how much energy is blocked by shadows on the wall
        
        % Calculate heat through windows from sun AND shadow on walls.
        for y = 1:size(windows,1)
            % Effective surface area with louver shading
            % Note: South windows now have the 'south_overhang_depth' applied from matrix init
            [A_win_sl_one, A_wall_sl_one] = louver_sunlit_area(sun, windows(y,2), windows(y,4), windows(y,5), windows(y,6), windows(y,7), windows(y,8), windows(y,9));
            
            % 1. Add Window Solar Gain
            % Area effective = Sunlit Area * Number of Windows
            A_win_total_eff = A_win_sl_one * windows(y,3);
            Q_sol_win = Q_sol_win + solar_sim(sun, windows(y,2), A_win_total_eff);
            
            % 2. Calculate Shadow Loss on Wall Gap
            % Total Area of the Gap = H_win * H_spac
            Area_Gap_One = windows(y,5) * windows(y,9);
            % Shaded Area = Total Gap - Sunlit Gap (from helper function)
            Area_Gap_Shaded_One = Area_Gap_One - A_wall_sl_one;
            
            % If there is shadow, subtract that energy from the wall calculation
            if Area_Gap_Shaded_One > 0
                % Total Shaded Gap Area = Shaded One * Count
                Q_blocked = solar_sim(sun, windows(y,2), Area_Gap_Shaded_One * windows(y,3));
                Q_wall_shaded_loss = Q_wall_shaded_loss + Q_blocked;
            end
        end
        
        % Calculate TROMBE WALL Solar Gain
        % Sum up solar gain for ALL active Trombe faces
        Q_inc_trombe_total = 0;
        for y = 1:size(trombe_walls, 1)
            if trombe_walls(y, 1) > 0 % If this face has a Trombe wall
                
                % If it is the SOUTH face (Index 1), apply the Overhang
                if y == 1
                    % Calculate Dimensions for Shading (H=Building H, W=Area/H)
                    H_t = H; 
                    W_t = trombe_walls(y,1) / H_t;
                    [A_t_sunlit, ~] = louver_sunlit_area(sun, 180, W_t, H_t, 0, south_overhang_depth, 0, 0);
                    Q_inc_trombe_total = Q_inc_trombe_total + solar_sim(sun, 180, A_t_sunlit);
                else
                    % Other faces (North/East/West) - No overhang logic applied
                    Q_inc_trombe_total = Q_inc_trombe_total + solar_sim(sun, trombe_walls(y,2), trombe_walls(y,1));
                end
            end
        end
        
        % Energy absorbed by the concrete mass (Node 5)
        Q_absorbed_trombe = Q_inc_trombe_total * tau_trombe_glass * alpha_trombe;
        
        % Calculate heating of exterior surface from sun.
        Q_absorbed_shell = 0;
        
        % 1. Vertical Opaque Walls (70% Absorption)
        for y = 1:size(opaque_walls,1)
            if opaque_walls(y,1) > 0 % Only if area exists
                Q_incident = solar_sim(sun, opaque_walls(y,2), opaque_walls(y,1));
                Q_absorbed_shell = Q_absorbed_shell + (Q_incident * alpha_wall);
            end
        end
        
        % Subtract the energy blocked by shadows (account for absorptivity)
        Q_absorbed_shell = Q_absorbed_shell - (Q_wall_shaded_loss * alpha_wall);
        
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
            % [FIX] Added check for C > 100 to prevent divide-by-zero on Node 5 when Trombe Area = 0
            if C(k) ~= inf && C(k) > 100
                for i = 1:n
                    if R(i, k) ~= 0 % Check if there is a resistor there
                        % Ohm's Law for Heat: (T_neighbor - T_node) / R
                        flow = (T(i) - T(k)) / R(i, k);
                        dT(k) = dT(k) + flow;
                    end
                end
                
                % Update Temp Change: (Net Heat Flow * dt) / Capacitance
                
                % APPLY SOURCES
                if k == 1
                    % Exterior Shell (Brick)
                    dT(k) = (dT(k) + Q_absorbed_shell) * dt / C(k);
                elseif k == 5
                    % Trombe Mass (Receives Solar thru glass)
                    dT(k) = (dT(k) + Q_absorbed_trombe) * dt / C(k);
                elseif nodes(k, 2) > 0
                    % Interior Nodes (Floor & Air) receiving Window Solar
                    dT(k) = (dT(k) + Q_sol_win*nodes(k, 2)) * dt / C(k);
                else
                    % Nodes with no direct solar (Insulation, Drywall, etc.)
                    dT(k) = dT(k) * dt / C(k);
                end
            end
        end
        
        % Update temperatures
        T = T + dT;
        % Calculate energy required to heat/cool
        energy_inputs(z) =  -1 * nodes(n-1,4) * (dT(n-1)/dt);
        T(n-1) = 293.15;
    end
    % TOTAL ENERGY CALCULATION
    % Separate Heating (Positive) and Cooling (Negative)
    heating_power = max(0, energy_inputs); % zeros out negative values
    cooling_power = abs(min(0, energy_inputs)); % zeros out positive values & makes cooling positive
    % Integrate Power over Time to get Energy (Joules)
    total_heating_joules = sum(heating_power) * dt;
    total_cooling_joules = sum(cooling_power) * dt;
    % Convert Joules to kWh
    % 1 kWh = 3,600,000 Joules
    total_heating_kWh = total_heating_joules / 3.6e6;
    total_cooling_kWh = total_cooling_joules / 3.6e6;
    total_kWh = total_heating_kWh + total_cooling_kWh;
    % % Display Annual Totals
    % fprintf('\n--------------------------------------\n');
    % fprintf('ANNUAL ENERGY SIMULATION RESULTS\n');
    % fprintf('--------------------------------------\n');
    % fprintf('Total Heating Load: %.2f kWh\n', total_heating_kWh);
    % fprintf('Total Cooling Load: %.2f kWh\n', total_cooling_kWh);
    % fprintf('Total System Load:  %.2f kWh\n', total_heating_kWh + total_cooling_kWh);
    if total_kWh < best_energy
        best_energy = total_kWh;
        best_params = [south_overhang_depth, trombe_wall_percent(1)];
        fprintf('--------------------------------------\n');
        fprintf('New Best (Iter %.0f)  %.2f kWh\nParams:\nOverhang = %.2f\nTrombe Percent = %.2f\n', iter, total_kWh, south_overhang_depth, trombe_wall_percent(1));
        fprintf('--------------------------------------\n');
    end
end
disp("DONE")