function [record, out] = run_final_case( ...
    cfg, traces, regime, methodID, candidateID)
% Run one controller using existing shared input traces.
% No input traces are regenerated here.

assert(istable(regime) && height(regime) == 1, ...
    'Provide exactly one regime-table row.');

assert(abs(cfg.offeredLoad - regime.OfferedLoad) < 1e-12 && ...
       abs(cfg.Pd - regime.Pd) < 1e-12 && ...
       abs(cfg.Pf - regime.Pf) < 1e-12, ...
    'Configuration does not match the regime.');

assert(string(cfg.arrivalMode) == string(regime.ArrivalMode), ...
    'Traffic mode does not match the regime.');

if string(cfg.arrivalMode) == "onoff"
    assert(abs(cfg.trafficOnFraction - ...
               regime.TrafficOnFraction) < 1e-12 && ...
           abs(cfg.trafficMeanOn_s - ...
               regime.TrafficMeanOn_s) < 1e-12, ...
        'Burst settings do not match the regime.');
end

% Recalculate thresholds for this particular candidate.
cfg.redMinTh = cfg.redMinFraction * cfg.queueCapacity;
cfg.redMaxTh = cfg.redMaxFraction * cfg.queueCapacity;

out = simulate_crn(cfg, traces);

% Checks applying to every controller.
blocked = out.sensed | out.sensingSlot;

assert(all(out.attempted(blocked) == 0), ...
    'Blocked-step transmission detected.');

assert(all(out.packetBalanceTrace == 0), ...
    'Packet conservation failed.');

assert(numel(out.deliveredDelay_s) == out.deliveredPackets, ...
    'Delivered-packet and delay counts disagree.');

% Suspension is checked only when enabled.
if string(cfg.controller) == "paaqm"
    holdMask = out.paStateTrace == 2;

    if cfg.paSuspendEarlyDrop
        assert(all(out.earlyDropsTrace(holdMask) == 0), ...
            'Early dropping during suspended HOLD.');
    end

    if cfg.paFreezeAverage
        previousAverage = [0; out.avgQueue(1:end-1)];

        assert(all(abs(out.avgQueue(holdMask) - ...
                       previousAverage(holdMask)) < 1e-12), ...
            'Queue average changed during frozen HOLD.');
    end
end

% Experiment identifiers.
record.RegimeID = string(regime.RegimeID);
record.Split = string(regime.Split);
record.Seed = cfg.seed;
record.MethodID = string(methodID);
record.CandidateID = string(candidateID);
record.Controller = string(cfg.controller);
record.IsOverload = logical(regime.IsOverload);

% Input and operating settings.
record.OfferedLoad = cfg.offeredLoad;
record.TrafficRegime = string(regime.TrafficRegime);
record.ArrivalMode = string(cfg.arrivalMode);
record.TrafficOnFraction = regime.TrafficOnFraction;
record.TrafficMeanOn_s = regime.TrafficMeanOn_s;
record.TrafficMeanOff_s = regime.TrafficMeanOff_s;

record.QueueCapacity_packets = cfg.queueCapacity;
record.ConfiguredPUDutyCycle = cfg.puDutyCycle;
record.ObservedPUDutyCycle = mean(out.puActual);
record.PUMeanOn_s = cfg.puMeanOn_s;
record.Pd = cfg.Pd;
record.Pf = cfg.Pf;
record.SensingPeriod_s = cfg.sensePeriod_s;
record.SensingDuration_s = cfg.senseTime_s;
record.TimeStep_s = cfg.dt;
record.SimulatedTime_s = out.simulatedTime;

% Controller parameters.
record.Alpha = cfg.redMinFraction;
record.Beta = cfg.redMaxFraction;
record.REDMinThreshold = cfg.redMinTh;
record.REDMaxThreshold = cfg.redMaxTh;
record.REDMaxP = cfg.redMaxP;
record.REDWeight = cfg.redWeight;
record.PAMode = string(cfg.paMode);
record.RecoveryDuration_s = cfg.paRecovery_s;
record.FreezeAverage = logical(cfg.paFreezeAverage);
record.SuspendEarlyDrop = logical(cfg.paSuspendEarlyDrop);

% Performance metrics.
record.GeneratedPackets = out.generatedPackets;
record.DeliveredPackets = out.deliveredPackets;
record.AttemptedPackets = sum(out.attempted);
record.EarlyDrops = out.earlyDrops;
record.OverflowDrops = out.overflowDrops;
record.CollisionLosses = out.collisionLosses;
record.TotalDrops = out.totalDrops;
record.FinalQueue_packets = out.finalQueue;
record.PDR = out.pdr;
record.TotalLossFraction = out.lossRatio;
record.FinalUndeliveredFraction = ...
    out.finalUndeliveredFraction;
record.Throughput_kbps = out.throughput_bps / 1000;
record.MeanQueue_packets = out.avgQueueLength;
record.MeanDeliveredDelay_ms = ...
    1000 * out.meanDeliveredDelay_s;
record.P95DeliveredDelay_ms = ...
    1000 * out.p95DeliveredDelay_s;
record.PUTransmitOverlapFrac = out.puTransmitOverlapFrac;
record.RealizedArrivalRate_pps = ...
    out.generatedPackets / out.simulatedTime;

if record.AttemptedPackets > 0
    record.CollisionAttemptFraction = ...
        out.collisionLosses / record.AttemptedPackets;
else
    record.CollisionAttemptFraction = NaN;
end

% Validation diagnostics.
record.BlockedAttemptPackets = out.blockedAttemptPackets;
record.MaxAbsPacketBalanceError = ...
    out.maxAbsPacketBalanceError;
record.MaxServiceBudgetExcess = out.maxServiceBudgetExcess;
record.MaxQueueCapacityExcess = out.maxQueueCapacityExcess;
record.MinRecordedQueue = out.minRecordedQueue;
end