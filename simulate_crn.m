function out = simulate_crn(cfg)

rng(cfg.seed);

N = cfg.numSteps;
dt = cfg.dt;

puActual = generate_pu_trace(cfg);
[sensed, sensingSlot] = generate_sensed_pu_trace(puActual, cfg);
arrivals = generate_arrivals(cfg);

queueLength = 0;
avgQueue = 0;
serviceCredit = 0;

queueTrace = zeros(N, 1);
avgQueueTrace = zeros(N, 1);
deliveredTrace = zeros(N, 1);
overflowDropTrace = zeros(N, 1);
earlyDropTrace = zeros(N, 1);
arrivalTrace = zeros(N, 1);

generatedPackets = 0;
deliveredPackets = 0;
overflowDrops = 0;
earlyDrops = 0;
collisionLosses = 0;
collisionSteps = 0;

for k = 1:N

    newPackets = arrivals(k);
    generatedPackets = generatedPackets + newPackets;
    arrivalTrace(k) = newPackets;

    switch lower(cfg.controller)
        case "droptail"
            [admitted, drops] = queue_droptail( ...
                newPackets, queueLength, cfg.queueCapacity);
            overflowDropsNow = drops;
            earlyDropsNow = 0;
            avgQueue = queueLength;

        case "red"
            [admitted, earlyDropsNow, overflowDropsNow, ...
                avgQueue, ~] = queue_red( ...
                newPackets, queueLength, cfg.queueCapacity, ...
                avgQueue, cfg);

        otherwise
            error("Unknown controller: %s", cfg.controller);
    end

    queueLength = queueLength + admitted;
    overflowDrops = overflowDrops + overflowDropsNow;
    earlyDrops = earlyDrops + earlyDropsNow;
    overflowDropTrace(k) = overflowDropsNow;
    earlyDropTrace(k) = earlyDropsNow;

    canTransmit = ~sensed(k) && ~sensingSlot(k);

    if canTransmit
        serviceCredit = serviceCredit + ...
            cfg.linkRate_bps * dt / cfg.packetBits;
    end

    packetsToServe = floor(serviceCredit);
    sentNow = min(queueLength, packetsToServe);

    queueLength = queueLength - sentNow;
    serviceCredit = serviceCredit - sentNow;

    if canTransmit && puActual(k)
        collisionLosses = collisionLosses + sentNow;
        collisionSteps = collisionSteps + 1;
        deliveredNow = 0;
    else
        deliveredNow = sentNow;
    end

    deliveredPackets = deliveredPackets + deliveredNow;
    deliveredTrace(k) = deliveredNow;
    queueTrace(k) = queueLength;
    avgQueueTrace(k) = avgQueue;

    if queueLength < 0 || queueLength > cfg.queueCapacity
        error("Queue-conservation failure at step %d.", k);
    end
end

totalDrops = overflowDrops + earlyDrops + collisionLosses;

out.cfg = cfg;
out.time = (0:N-1)' * dt;

out.puActual = puActual;
out.sensed = sensed;
out.sensingSlot = sensingSlot;
out.puStarts = find(diff([false; puActual]) == 1);
out.puEnds = find(diff([false; puActual]) == -1);

out.arrivals = arrivalTrace;
out.delivered = deliveredTrace;
out.queue = queueTrace;
out.avgQueue = avgQueueTrace;
out.overflowDropsTrace = overflowDropTrace;
out.earlyDropsTrace = earlyDropTrace;

out.generatedPackets = generatedPackets;
out.deliveredPackets = deliveredPackets;
out.overflowDrops = overflowDrops;
out.earlyDrops = earlyDrops;
out.collisionLosses = collisionLosses;
out.totalDrops = totalDrops;
out.finalQueue = queueLength;

out.sensingOverhead = mean(sensingSlot);
out.collisionTimeFrac = collisionSteps / N;
out.missedOpportunityFrac = mean(~puActual & sensed);

out.throughput_bps = deliveredPackets * cfg.packetBits / cfg.simTime;
out.pdr = deliveredPackets / max(generatedPackets, 1);
out.lossRatio = totalDrops / max(generatedPackets, 1);
out.avgQueueLength = mean(queueTrace);

out.packetBalanceError = generatedPackets - deliveredPackets ...
    - totalDrops - queueLength;

end