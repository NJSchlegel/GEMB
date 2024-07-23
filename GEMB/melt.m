function [sumM, Msurf, Rsum, Fsum, T, d, dz, W, mAdd, dz_add, a, adiff, re, gdn, gsp] = ...
    melt(T, d, dz, W, Ra, a, adiff, dzMin, zMax, zMin, zTop, zY, re, gdn, gsp, dIce)
% melt computes the quantity of meltwater due to snow temperature in excess 
% of 0 deg C, determines pore water content and adjusts grid spacing
%
%% Syntax 
% 
% 
%
%% Description
% 
% 
% 
%% Inputs
% 
% 
% 
%% Outputs
% 
% 
%% Documentation
% 
% For complete documentation, see: https://github.com/alex-s-gardner/GEMB 
% 
%% References 
% If you use GEMB, please cite the following: 
% 
% Gardner, A. S., Schlegel, N.-J., and Larour, E.: Glacier Energy and Mass 
% Balance (GEMB): a model of firn processes for cryosphere research, Geosci. 
% Model Dev., 16, 2277–2302, https://doi.org/10.5194/gmd-16-2277-2023, 2023.

%% INITIALIZATION

Ttol = 1e-10;
Dtol = 1e-11;
Wtol = 1e-13;

ER    = 0;
sumM  = 0;
sumER = 0;
addE  = 0;
mSum0 = 0;
sumE0 = 0;
mSum1 = 0;
sumE1 = 0;
dE    = 0;
dm    = 0;
X     = 0;
Wi    = 0;

% Specify constants:
CtoK = 273.15;   % Celsius to Kelvin conversion
CI   = 2102;     % specific heat capacity of snow/ice (J kg-1 K-1)
LF   = 0.3345E6; % latent heat of fusion (J kg-1)
dPHC = 830.0;    % pore hole close off density [kg m-3]

n    = length(T);
M    = zeros(n,1);
maxF = zeros(n,1);
dW   = zeros(n,1);

% store initial mass [kg] and energy [J]
m  = dz .* d;                  % grid cell mass [kg]
EI = m .* T * CI;              % initial enegy of snow/ice
EW = W .* (LF + CtoK * CI);    % initial enegy of water

mSum0 = sum(W) + sum(m);       % total mass [kg]
sumE0 = sum(EI) + sum(EW);     % total energy [J]

% initialize melt and runoff scalars
R      = 0;   % runoff [kg]
Rsum   = 0;   % sum runoff [kg]
Fsum   = 0;   % sum refreeze [kg]
sumM   = 0;   % total melt [kg]
mAdd   = 0;   % mass added/removed to/from base of model [kg]
addE   = 0;   % energy added/removed to/from base of model [J]
dz_add = 0;   % thickness of the layer added/removed to/from base of model [m]
Msurf  = 0;   % surface layer melt

% output
surplusE = 0;

% calculate temperature excess above 0 degC
exsT = max(0, T - CtoK);        % [K] to [degC]

% new grid point center temperature, T [K]
T = min(T,CtoK);

% specify irreducible water content saturation [fraction]
Swi = 0.07;                     % assumed constant after Colbeck, 1974

%% REFREEZE PORE WATER
% check if any pore water
if sum(W) > 0+Wtol
    % disp('PORE WATER REFREEZE')
    % calculate maximum freeze amount, maxF [kg]
    maxF = max(0, -((T - CtoK) .* m * CI) / LF);
    
    % freeze pore water and change snow/ice properties
    dW = min(maxF, W);                              % freeze mass [kg]   
    W = W - dW;                                     % pore water mass [kg]
    m = m + dW;                                     % new mass [kg]
    d = m ./ dz;                                    % density [kg m-3]   
    T = T + double(m>Wtol).*(dW.*(LF+(CtoK - T)*CI)./(m.*CI)); % temperature [K]
    
    % if pore water froze in ice then adjust d and dz thickness
    d(d > dIce-Dtol) = dIce;
    dz = m ./ d;  

end

% squeeze water from snow pack
Wi = (dIce - d) .* Swi .* (m ./ d);     % irreducible water content [kg]
exsW = max(0, W - Wi);                  % water "squeezed" from snow [kg]

%% MELT, PERCOLATION AND REFREEZE
F=zeros(n,1);

% Add previous refreeze to F and reset dW
F = F + dW;
dW(:) = 0;

% run melt algorithm if there is melt water or excess pore water
if (sum(exsT) > 0.0+Ttol) || (sum(exsW) > 0.0+Wtol)
    % disp ('MELT OCCURS')
    % check to see if thermal energy exceeds energy to melt entire cell
    % if so redistribute temperature to lower cells (temperature surplus)
    % (maximum T of snow before entire grid cell melts is a constant
    % LF/CI = 159.1342)
    surpT = max(0, exsT - LF/CI);

    if sum(surpT) > 0.0+Ttol % bug fixed 21/07/2016
        
        % calculate surplus energy
        surpE = surpT .* CI .* m;
        i = 1;

        while sum(surpE) > 0.0+Ttol && i<n+1

            if i<n 
                % use surplus energy to increase the temperature of lower cell
                T(i+1) = surpE(i) / m(i+1) / CI + T(i+1);
                
                exsT(i+1) = max(0, T(i+1) - CtoK) + exsT(i+1);
                T(i+1) = min(CtoK, T(i+1));
                
                surpT(i+1) = max(0, exsT(i+1) - LF/CI);
                surpE(i+1) = surpT(i+1) * CI * m(i+1);
            else
                surplusE=surpE(i);
                display([' WARNING: surplus energy at the base of GEMB column' newline])
            end
            
            % adjust current cell properties (again 159.1342 is the max T)
            exsT(i) = LF/CI;
            surpE(i) = 0;   
            i = i + 1;

        end
    end

    % convert temperature excess to melt [kg]
    Mmax  = exsT .* d .* dz * CI / LF;  
    M     = min(Mmax, m);               % melt
    Msurf = M(1);
    sumM  = max(0,sum(M)-Ra);           % total melt [kg] minus the liquid rain that had been added 
    
    % calculate maximum refreeze amount, maxF [kg]
    maxF = max(0, -((T - CtoK) .* d .* dz * CI)/ LF);
 
    % initialize refreeze, runoff, flxDn and dW vectors [kg]
    R = zeros(n,1);
    flxDn = [R; 0];
    
    % determine the deepest grid cell where melt/pore water is generated
    X = find((M > 0.0+Wtol | exsW > 0.0+Wtol), 1, 'last');
    X(isempty(X)) = 1;
        
    Xi=1;
    n=length(T);

    %% meltwater percolation
    for i = 1:n
        % calculate total melt water entering cell
        inM = M(i)+ flxDn(i);

        depthice=0;
        if d(i) >= dPHC-Dtol
            for l=i:n
                if d(l)>=dPHC-Dtol
                    depthice = depthice+dz(l); 
                else 
                    break
                end
            end
        end
 
        % break loop if there is no meltwater and if depth is > mw_depth
        if abs(inM) < Wtol && i > X
            break
 
        % if reaches impermeable ice layer all liquid water runs off (R)
        elseif d(i) >= dIce-Dtol || (d(i) >= dPHC-Dtol && depthice>0.1+Dtol)  % dPHC = pore hole close off [kg m-3]
            % disp('ICE LAYER')
            % no water freezes in this cell
            % no water percolates to lower cell
            % cell ice temperature & density do not change
            
            m(i) = m(i) - M(i);                       % mass after melt
            Wi = (dIce-d(i)) * Swi * (m(i)/d(i));     % irreducible water
            dW(i) = max(min(inM, Wi - W(i)),-1*W(i)); % change in pore water
            R(i) = max(0.0, inM - dW(i));             % runoff

        % check if no energy to refreeze meltwater     
        elseif abs(maxF(i)) < Dtol
            % disp('REFREEZE == 0')
            % no water freezes in this cell
            % cell ice temperature & density do not change
            
            m(i) = m(i) - M(i);                       % mass after melt
            Wi = (dIce-d(i)) * Swi * (m(i)/d(i));     % irreducible water
            dW(i) = max(min(inM, Wi - W(i)),-1*W(i)); % change in pore water
            flxDn(i+1) = max(0.0, inM - dW(i));       % meltwater out
            R(i) = 0;
 
            % some or all meltwater refreezes
        else
            % change in density and temperature
            % disp('MELT REFREEZE')
            %-----------------------melt water-----------------------------
            m(i) = m(i) - M(i);
            dz_0 = m(i)/d(i);          
            dMax = (dIce - d(i))*dz_0;              % d max = dIce
            F1   = min(min(inM,dMax),maxF(i));      % maximum refreeze
            m(i) = m(i) + F1;                       % mass after refreeze
            d(i) = m(i)/dz_0;
            
            %-----------------------pore water-----------------------------
            Wi = (dIce-d(i))* Swi * dz_0;                % irreducible water
            dW(i) = max(min(inM - F1, Wi-W(i)),-1*W(i)); % change in pore water
            F2 = 0;
            
            %% ---------------- THIS HAS NOT BEEN CHECKED-----------------_
            if dW(i) < 0.0-Wtol                     % excess pore water
                dMax  = (dIce - d(i))*dz_0;         % maximum refreeze                                             
                maxF2 = min(dMax, maxF(i)-F1);      % maximum refreeze
                F2    = min(-1.0*dW(i), maxF2);     % pore water refreeze
                m(i)  = m(i) + F2;                  % mass after refreeze
                d(i)  = m(i)/dz_0;
            end
            % -------------------------------------------------------------
            
            F(i) = F(i) + F1 + F2;

            flxDn(i+1) = max(0.0,inM - F1 - dW(i)); % meltwater out
            if m(i)>Wtol
                T(i) = T(i) + ...                       % change in temperature
                    ((F1+F2)*(LF+(CtoK - T(i))*CI)./(m(i).*CI));
            end
            
            % check if an ice layer forms 
            if abs(d(i) - dIce) < Dtol
                % disp('ICE LAYER FORMS')
                % excess water runs off
                R(i) = flxDn(i+1);

                % no water percolates to lower cell
                flxDn(i+1) = 0;
            end
        end
        
        Xi=Xi+1;
    end

    %% GRID CELL SPACING AND MODEL DEPTH

    if any(W < 0.0-Wtol)
        error('Negative pore water generated in melt equations.')
    end

    % delete all cells with zero mass
    % adjust pore water
    W = W + dW;   

    % calculate Rsum:
    Rsum=sum(R) + flxDn(Xi);
    
    % delete all cells with zero mass
    D = (m <= 0+Wtol); 
    m(D)     = []; 
    W(D)     = []; 
    d(D)     = []; 
    T(D)     = []; 
    a(D)     = []; 
    re(D)    = []; 
    gdn(D)   = []; 
    gsp(D)   = []; 
    adiff(D) = []; 
    EI(D)    = []; 
    EW(D)    = [];
 
    % calculate new grid lengths
    dz = m ./ d;
end
 
Fsum = sum(F);

% Manage the layering to match the user defined requirements
[d, T, dz, W, mAdd, dz_add, addE, a, adiff, m, EI, EW, re, gdn, gsp] = ...
    managelayers(T, d, dz, W, a, adiff, m, EI, EW, dzMin, zMax, zMin, re, gdn, gsp, zTop, zY, CI, LF, CtoK);

%% CHECK FOR MASS AND ENERGY CONSERVATION

% Calculate final mass [kg] and energy [J]
sumER = Rsum * (LF + CtoK * CI);
EI    = m .* T * CI;
EW    = W .* (LF + CtoK * CI);

mSum1 = sum(W) + sum(m) + Rsum;
sumE1 = sum(EI) + sum(EW);

dm = round((mSum0 - mSum1 + mAdd)*100)/100.;
dE = round(sumE0 - sumE1 - sumER + addE - surplusE);

if dm ~= 0 || dE ~= 0
    error(['Mass and energy are not conserved in melt equations:' newline ' dm: ' ...
        num2str(dm) ' dE: ' num2str(dE) newline])
end

if any(W < 0.0-Wtol)
    error('Negative pore water generated in melt equations.')
end

