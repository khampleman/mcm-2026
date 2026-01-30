clc;
clear;
close all;

% DEFINE CONSTANTS
h = 3.9; % heat transfer coefficient [W/(m²K)]
c_p = 1.006 * 1000; % Specific Heat at Constant Pressure [J/kg·K]
rho = 1.225; % Density of air [kg/m³]

% DEFINE SIMULATION CONDITIONS
T_outside = 35 + 273.15; % temperature of outside (assume reservoir) [K]
L = 1; % Side length of box [m]
T0 = 20 + 273.15; % initial temperature inside [K]

V = L^3; % Volume of box [m³]
A_s = 6 * L^2; % Surface area of the box [m²]

% DEFINE TIME PARAMETERS
dt = 0.01; % time step
t_end = 120; % end time
time = 0:dt:t_end; % time vector

% SIMULATION
T = zeros(size(time)); % initialize temperature array
T(1) = T0; % set initial temperature
for i = 2:length(time)

    deltaT = -h*A_s*(T(i-1) - T_outside)*dt/(rho*V*c_p);

    T(i) = T(i-1) + deltaT; % update temperature
end

% PLOT RESULTS
figure;
plot(time, T-273.15);
xlabel('Time (s)');
ylabel('Temperature (°C)');
title('Temperature Change Over Time');
grid on;