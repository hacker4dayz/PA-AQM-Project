function out = simulate_crn(cfg, traces)

N = cfg.numSteps;
dt = cfg.dt;
B = cfg.queueCapacity;

assert(N >= 1 && N == floor(N) && dt > 0, ...
    'Invalid simulation grid.');

assert(B >= 1 && B == floor(B), ...
    'Queue capacity must be a positive integer.');

assert(cfg.packetBits > 0 && cfg.linkRate_bps >= 0, ...
    'Invalid link parameters.');

assert(cfg.redMaxTh > cfg.redMinTh && ...
       cfg.redWeight >= 0 && cfg.redWeight <= 1 && ...
       cfg.redMaxP >= 0 && cfg.redMaxP <= 1, ...
    'Invalid RED parameters.');

if ~isfield(cfg, 'paRecovery_s')
    cfg.paRecovery_s = 0.50;
end

if ~isfield(cfg, 'paMode')
    cfg.paMode = "fixed";
end

assert(cfg.paRecovery_s >= 0, ...
    'Recovery duration must be nonnegative.');

% Generate inputs unless explicitly supplied.
if nargin < 2

    rng(cfg.seed);

    traces.puActual = generate_pu_trace(cfg);

    [traces.sensed, traces.sensingSlot] = ...
        generate_sensed_pu_trace(traces.puActual, cfg);

    traces.arrivals = generate_arrivals(cfg);

end

puActual = logical(traces.puActual(:));
sensed = logical(traces.sensed(:));
sensingSlot = logical(traces.sensingSlot(:));
arrivals = traces.arrivals(:);

assert(numel(puActual) == N && ...
       numel(sensed) == N && ...
       numel(sensingSlot) == N && ...
       numel(arrivals) == N, ...
    'Input trace length mismatch.');

assert(all(isfinite(arrivals) & ...
           arrivals >= 0 & ...
           arrivals == floor(arrivals)), ...
    'Arrivals must be nonnegative integers.');

% Shared packet-level admission randomness.
admissionStream = RandStream( ...
    'mt19937ar', 'Seed', cfg.seed + 90);

queueLength = 0;
avgQueue = 0;
serviceCredit = 0;
paState = [];

packetsPerEligibleStep = ...
    cfg.linkRate_bps * dt / cfg.packetBits;

% FIFO timestamp ring buffer.
packetArrivalTime = zeros(B, 1);
head = 1;
tail = 1;

% Maximum possible number of delivered packets.
deliveryDelays = zeros(sum(arrivals), 1);
delayCount = 0;

% Traces.
queueTrace = zeros(N, 1);
avgQueueTrace = zeros(N, 1);
deliveredTrace = zeros(N, 1);
overflowDropTrace = zeros(N, 1);
earlyDropTrace = zeros(N, 1);

attemptedTrace = zeros(N, 1);
collisionLossTrace = zeros(N, 1);
serviceCreditTrace = zeros(N, 1);
serviceBudgetTrace = zeros(N, 1);
packetBalanceTrace = zeros(N, 1);

paStateTrace = nan(N, 1);
dropProbabilityTrace = zeros(N, 1);
paRecoveryFactorTrace = nan(N, 1);
paDrainRateTrace = nan(N, 1);

generatedPackets = 0;
deliveredPackets = 0;
overflowDrops = 0;
earlyDrops = 0;
collisionLosses = 0;
collisionSteps = 0;

for k = 1:N

    timeStart = (k - 1) * dt;
    timeEnd = k * dt;

    newPackets = arrivals(k);
    generatedPackets = generatedPackets + newPackets;

    draws = rand(admissionStream, newPackets, 1);
    dropProb = 0;

    % Admission uses occupancy before this step's arrivals.
    switch lower(string(cfg.controller))

        case "droptail"

            [admitted, overflowDropsNow] = ...
                queue_droptail( ...
                newPackets, queueLength, B);

            earlyDropsNow = 0;
            avgQueue = queueLength;

        case "red"

            [admitted, earlyDropsNow, overflowDropsNow, ...
                avgQueue, dropProb] = queue_red( ...
                newPackets, queueLength, B, ...
                avgQueue, cfg, draws);

        case "paaqm"

            [admitted, earlyDropsNow, overflowDropsNow, ...
                avgQueue, paState, dropProb, factor] = ...
                queue_paaqm( ...
                newPackets, queueLength, B, avgQueue, ...
                sensed(k), timeStart, paState, cfg, draws);

            paStateTrace(k) = paState.mode;
            paRecoveryFactorTrace(k) = factor;

            if isfield(paState, 'lastDrainRate_pps')
                paDrainRateTrace(k) = paState.lastDrainRate_pps;
            end

        otherwise

            error('Unknown controller: %s', cfg.controller);

    end

    % Append admitted packet timestamps in FIFO order.
    if admitted > 0

        enqueueIndex = mod( ...
            (tail - 1) + (0:admitted-1), B) + 1;

        packetArrivalTime(enqueueIndex) = timeStart;
        tail = mod(tail - 1 + admitted, B) + 1;

    end

    queueLength = queueLength + admitted;

    overflowDrops = overflowDrops + overflowDropsNow;
    earlyDrops = earlyDrops + earlyDropsNow;

    overflowDropTrace(k) = overflowDropsNow;
    earlyDropTrace(k) = earlyDropsNow;
    dropProbabilityTrace(k) = dropProb;

    % Service budget.
    canTransmit = ~sensed(k) && ~sensingSlot(k);

    sentNow = 0;
    wholeBudget = 0;

    if canTransmit

        budget = serviceCredit + packetsPerEligibleStep;

        tol = 1e-12 * max(1, abs(budget));
        wholeBudget = floor(budget + tol);

        serviceCredit = max(0, budget - wholeBudget);

        sentNow = min(queueLength, wholeBudget);

    end

    % Read and remove the oldest attempted packets.
    attemptedArrivalTimes = zeros(0, 1);

    if sentNow > 0

        dequeueIndex = mod( ...
            (head - 1) + (0:sentNow-1), B) + 1;

        attemptedArrivalTimes = ...
            packetArrivalTime(dequeueIndex);

        attemptedArrivalTimes = attemptedArrivalTimes(:);

        head = mod(head - 1 + sentNow, B) + 1;

    end

    queueLength = queueLength - sentNow;

    % Channel outcomes.
    deliveredNow = 0;
    collisionNow = 0;

    if canTransmit

        if puActual(k)

            collisionNow = sentNow;
            collisionSteps = collisionSteps + 1;

        else

            deliveredNow = sentNow;

            if deliveredNow > 0

                theseDelays = ...
                    timeEnd - attemptedArrivalTimes;

                assert(all(theseDelays >= 0), ...
                    'Negative packet delay at step %d.', k);

                destinationIndex = ...
                    delayCount + (1:deliveredNow);

                deliveryDelays(destinationIndex) = theseDelays;

                delayCount = delayCount + deliveredNow;

            end

        end

    end

    deliveredPackets = deliveredPackets + deliveredNow;
    collisionLosses = collisionLosses + collisionNow;

    % Logging.
    deliveredTrace(k) = deliveredNow;
    attemptedTrace(k) = sentNow;
    collisionLossTrace(k) = collisionNow;

    queueTrace(k) = queueLength;
    avgQueueTrace(k) = avgQueue;
    serviceCreditTrace(k) = serviceCredit;
    serviceBudgetTrace(k) = wholeBudget;

    % Validation.
    assert(queueLength >= 0 && queueLength <= B, ...
        'Queue-capacity violation at step %d.', k);

    assert(serviceCredit >= 0 && serviceCredit < 1, ...
        'Fractional-credit violation at step %d.', k);

    assert(sentNow <= wholeBudget && ...
           (canTransmit || sentNow == 0), ...
        'Service-budget violation at step %d.', k);

    packetBalanceTrace(k) = generatedPackets ...
        - deliveredPackets ...
        - overflowDrops ...
        - earlyDrops ...
        - collisionLosses ...
        - queueLength;

    assert(packetBalanceTrace(k) == 0, ...
        'Packet-conservation failure at step %d.', k);

end

assert(delayCount == deliveredPackets, ...
    'Delivered-packet and delay counts disagree.');

deliveryDelays = deliveryDelays(1:delayCount);

% Nearest-rank 95th percentile; no toolbox required.
if isempty(deliveryDelays)

    meanDelay = NaN;
    p95Delay = NaN;
    maximumDelay = NaN;

else

    sortedDelays = sort(deliveryDelays);
    percentileIndex = max(1, ceil(0.95 * delayCount));

    meanDelay = mean(deliveryDelays);
    p95Delay = sortedDelays(percentileIndex);
    maximumDelay = sortedDelays(end);

end

totalDrops = overflowDrops + earlyDrops + collisionLosses;

out.cfg = cfg;
out.time = (0:N-1)' * dt;
out.simulatedTime = N * dt;

out.puActual = puActual;
out.sensed = sensed;
out.sensingSlot = sensingSlot;

out.puStarts = find(diff([false; puActual]) == 1);
out.puEnds = find(diff([false; puActual]) == -1);

out.arrivals = arrivals;
out.delivered = deliveredTrace;
out.queue = queueTrace;
out.avgQueue = avgQueueTrace;

out.overflowDropsTrace = overflowDropTrace;
out.earlyDropsTrace = earlyDropTrace;
out.attempted = attemptedTrace;
out.collisionLossesTrace = collisionLossTrace;

out.serviceCreditTrace = serviceCreditTrace;
out.serviceBudgetTrace = serviceBudgetTrace;
out.packetBalanceTrace = packetBalanceTrace;
out.finalServiceCredit = serviceCredit;

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

out.throughput_bps = ...
    deliveredPackets * cfg.packetBits / out.simulatedTime;

out.pdr = deliveredPackets / max(generatedPackets, 1);
out.lossRatio = totalDrops / max(generatedPackets, 1);
out.avgQueueLength = mean(queueTrace);
out.packetBalanceError = packetBalanceTrace(end);

out.paStateTrace = paStateTrace;
out.paDropProbabilityTrace = dropProbabilityTrace;
out.paRecoveryFactorTrace = paRecoveryFactorTrace;
out.paDrainRateTrace = paDrainRateTrace;

% Delay is conditional on successful delivery.
out.deliveredDelay_s = deliveryDelays;
out.meanDeliveredDelay_s = meanDelay;
out.p95DeliveredDelay_s = p95Delay;
out.maxDeliveredDelay_s = maximumDelay;

end
