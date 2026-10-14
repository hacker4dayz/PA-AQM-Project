function cfg = config_default()

cfg.seed = 1001;

% Simulation timing
cfg.dt = 0.01;
cfg.simTime = 300;
cfg.numSteps = round(cfg.simTime / cfg.dt);

% Link and buffer
cfg.packetBits = 1000 * 8;
cfg.linkRate_bps = 1e6;
cfg.queueCapacity = 50;

% Stationary Poisson traffic
cfg.offeredLoad = 0.70;
cfg.arrivalRate_pps = ...
    cfg.offeredLoad * cfg.linkRate_bps / cfg.packetBits;

% PU activity
cfg.puDutyCycle = 0.00;
cfg.puMeanOn_s = 2.0;
cfg.puMeanOff_s = 8.0;

cfg.puMode = "random";
cfg.puPeriod_s = 0.040;

% Sensing accuracy
cfg.Pd = 1.00;
cfg.Pf = 0.00;

% Sensing timing
cfg.sensePeriod_s = cfg.dt;
cfg.senseTime_s = 0;

% Controller
cfg.controller = "droptail";

% Simplified RED parameters
cfg.redMinTh = 15;
cfg.redMaxTh = 35;
cfg.redMaxP = 0.10;
cfg.redWeight = 0.002;

% PA-AQM parameter: initial trial value, not an optimized value
cfg.paRecovery_s = 0.50;

end
