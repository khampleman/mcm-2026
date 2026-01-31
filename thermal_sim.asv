clc;
clear;
close all;

% DEFINE MATERIAL PARAMETERS

% !!!!!!! THESE VALUES NEED TO BE MORE PRECISELY CHOSEN !!!!!!!!!!!
% These are random values I got from Gemini, we will choose these from
% research sources

concrete.R_val = 2.29; % (Thermal Resistance [m^2K/W])
concrete.C_val = 20000; 
air.h_val = 3.9; 
window.U_val = 2.8;

% SIMULATION LOCATION (Austin TX)
location.longitude = -97.743; %[deg]
location.latitude = 30.2672; %[deg]
location.altitude = 185; % [m]

% DEFINE SIMULATION CONDITIONS
L = 60; W = 24; H = 6.6; % Building dimensions
V = L*W*H; % Volume of building
A_s = 2 * (L * H + W * H) + L * W; % Surface area of whole building (neglect floor)
% Calculate the specific area of the South Wall
A_South_Wall = L * H; 

% Set window as a percentage of THAT wall (e.g., 40%)
Window_Ratio = 0.45;
A_w = Window_Ratio * A_South_Wall; 

% The remaining South wall is concrete
A_opaque_south = A_South_Wall - A_w;

% The other walls (North, East, West) + Roof
A_other_walls = A_s - A_South_Wall; 

% Total Opaque Area (Concrete)
A_concrete_total = A_other_walls + A_opaque_south;

% Window angle east of north [deg]
phi = 180;

% DEFINE NODES (Capacitors)
nodes = [
  1, 0, 1.225 * V * 1006;         % Indoor Air
  2, 1, (concrete.C_val/2) * A_concrete_total; % Interior Wall Mass
  3, 0, (concrete.C_val/2) * A_concrete_total; % Exterior Wall Mass
  4, 0, inf;                      % Outside Air
];
n = size(nodes, 1);

% DEFINE RESISTORS
resistors = [
  % 1. Concrete Path (Outside -> Ext -> Int -> Inside)
  4, 3, 1 / (air.h_val * A_concrete_total); 
  3, 2, concrete.R_val / A_concrete_total; 
  2, 1, 1 / (air.h_val * A_concrete_total);
  
  % 2. Window Path
  % Connect Outside (4) DIRECTLY to Inside (1))
  4, 1, 1 / (window.U_val * A_w);
];

% DEFINE TIME PARAMETERS
currentTime = datetime(2026, 7, 15, 0, 0, 0);
timeZone = -6; % UTC-6 is Central Time
dt = 10;
t_end = 7 * 24 * 3600;
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
    C(id) = nodes(i, 3);
end

% SIMULATION
results = zeros(size(time)); 
T = [20, 20, 20, 30]; 
T = T + 273.15; % Convert to Kelvin
results(1) = T(1);

for z = 2:length(time)
    % High: 35
    % Low: 23

    T(4) = 23 + (35-23)*sin(2*pi/(24*3600)*time(z));
    

    dT = zeros(1, n);

    Q_net_sol = solar_sim(location, currentTime, timeZone, phi, A_w);
    
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
            dT(k) = (dT(k) + Q_net_sol*nodes(k, 2)) * dt / C(k);
        end
    end
    
    % Update temperatures
    T = T + dT;
    results(z) = T(1);
    
    % Increment time
    currentTime = currentTime + seconds(dt);
end

% PLOT RESULTS
figure;
plot(time/3600, results-273.15, 'LineWidth', 2);
xlabel('Time (hours)');
ylabel('Temperature (°C)');
title('Indoor Temperature Response');
grid on;