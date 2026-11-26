function cfg = config_final()
% Final-study settings, based on the original configuration.
cfg = config_default();

% Simulation timing
cfg.dt = 0.001;
cfg.simTime = 300;
cfg.numSteps = round(cfg.simTime / cfg.dt);

% Reference link, buffer, and traffic
cfg.queueCapacity = 50;
cfg.offeredLoad = 0.70;
cfg.arrivalRate_pps = ...
    cfg.offeredLoad * cfg.linkRate_bps / cfg.packetBits;

% Traffic settings.
% Burst generation will be implemented in a later step.
cfg.arrivalMode = "poisson";
cfg.trafficOnFraction = 0.20;
cfg.trafficMeanOn_s = 0.10;
cfg.trafficMeanOff_s = ...
    cfg.trafficMeanOn_s * ...
    (1 - cfg.trafficOnFraction) / cfg.trafficOnFraction;

% Reference PU activity
cfg.puMode = "random";
cfg.puDutyCycle = 0.30;
cfg.puMeanOn_s = 2.0;
cfg.puMeanOff_s = ...
    cfg.puMeanOn_s * ...
    (1 - cfg.puDutyCycle) / cfg.puDutyCycle;

% Reference sensing
cfg.Pd = 1.00;
cfg.Pf = 0.00;
cfg.sensePeriod_s = 0.020;
cfg.senseTime_s = 0.005;

% Buffer-normalized RED thresholds
cfg.redMinFraction = 0.30;
cfg.redMaxFraction = 0.70;

cfg.redMinTh = cfg.redMinFraction * cfg.queueCapacity;
cfg.redMaxTh = cfg.redMaxFraction * cfg.queueCapacity;
cfg.redMaxP = 0.10;

% Preserve the original RED averaging time scale.
cfg.redReferenceDt = 0.01;
cfg.redReferenceWeight = 0.002;

cfg.redWeight = 1 - ...
    (1 - cfg.redReferenceWeight)^ ...
    (cfg.dt / cfg.redReferenceDt);

% Original PA-AQM reference policy
cfg.controller = "paaqm";
cfg.paMode = "fixed";
cfg.paRecovery_s = 0;

% Mechanism switches.
% Support will be added to queue_paaqm.m in a later step.
cfg.paFreezeAverage = true;
cfg.paSuspendEarlyDrop = true;
end