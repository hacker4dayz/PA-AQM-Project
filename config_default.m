function cfg = config_default()

cfg.seed = 1001;

cfg.dt = 0.01;
cfg.simTime = 300;
cfg.numSteps = round(cfg.simTime / cfg.dt);

cfg.packetBits = 1000 * 8;
cfg.linkRate_bps = 1e6;
cfg.queueCapacity = 50;

cfg.offeredLoad = 0.70;
cfg.arrivalRate_pps = ...
    cfg.offeredLoad * cfg.linkRate_bps / cfg.packetBits;

cfg.puDutyCycle = 0.00;
cfg.puMeanOn_s = 2.0;
cfg.puMeanOff_s = 8.0;

cfg.Pd = 1.00;
cfg.Pf = 0.00;

cfg.controller = "droptail";

% PU timing
cfg.puMode = "random";        % "random" or "periodic"
cfg.puPeriod_s = 0.040;       % used only in periodic mode

% Sensing timing
cfg.sensePeriod_s = cfg.dt;   % T_s: how often the SU checks
cfg.senseTime_s = 0;          % tau_s: time spent sensing each period

% RED parameters
cfg.redMinTh = 15;
cfg.redMaxTh = 35;
cfg.redMaxP = 0.10;
cfg.redWeight = 0.002;

end