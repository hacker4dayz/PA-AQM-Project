function [admitted, earlyDrops, overflowDrops, avgQueue, state, ...
    dropProb, recoveryFactor] = queue_paaqm( ...
    arrivals, queueLength, queueCapacity, avgQueue, ...
    sensedBusy, time_s, state, cfg, draws)

if nargin < 9
    draws = rand(arrivals, 1);
end

% Preserve compatibility with earlier configurations.
if ~isfield(cfg, 'paMode')
    cfg.paMode = "fixed";
end

mode = lower(string(cfg.paMode));

assert(any(mode == ["fixed", "adaptive"]), ...
    'paMode must be fixed or adaptive.');

assert(cfg.paRecovery_s >= 0, ...
    'Recovery duration must be nonnegative.');

if mode == "adaptive"

    assert(cfg.paTrendWindow_s > 0, ...
        'Trend observation window must be positive.');

    assert(cfg.paLowQueue >= 0 && ...
           cfg.paLowQueue < cfg.paHighQueue && ...
           cfg.paHighQueue <= queueCapacity, ...
        'Invalid adaptive queue thresholds.');

    assert(cfg.paMinDrain_pps >= 0, ...
        'Minimum drain rate must be nonnegative.');

end

% State codes: 1=NORMAL, 2=HOLD, 3=RECOVERY.
if isempty(state)

    state.mode = 1;
    state.recoveryStart_s = NaN;
    state.windowStart_s = NaN;
    state.windowStartQueue = NaN;
    state.lastDrainRate_pps = NaN;

end

% State transitions from sensed PU activity.
if sensedBusy

    state.mode = 2;
    state.recoveryStart_s = NaN;
    state.windowStart_s = NaN;
    state.windowStartQueue = NaN;
    state.lastDrainRate_pps = NaN;

elseif state.mode == 2

    state.mode = 3;
    state.recoveryStart_s = time_s;
    state.windowStart_s = time_s;
    state.windowStartQueue = queueLength;
    state.lastDrainRate_pps = NaN;

end

% Recovery termination.
if state.mode == 3

    elapsedRecovery = time_s - state.recoveryStart_s;

    finishRecovery = ...
        cfg.paRecovery_s == 0 || ...
        elapsedRecovery >= cfg.paRecovery_s - 1e-12;

    if mode == "adaptive" && ~finishRecovery

        % End protection once both queues have become small.
        lowBacklog = ...
            queueLength <= cfg.paLowQueue && ...
            avgQueue <= cfg.paLowQueue;

        if lowBacklog

            finishRecovery = true;

        else

            elapsedWindow = time_s - state.windowStart_s;

            if elapsedWindow >= cfg.paTrendWindow_s - 1e-12

                % Positive value means the sampled queue has drained.
                state.lastDrainRate_pps = ...
                    (state.windowStartQueue - queueLength) / ...
                    elapsedWindow;

                highBacklog = queueLength >= cfg.paHighQueue;

                insufficientDrain = ...
                    state.lastDrainRate_pps <= cfg.paMinDrain_pps;

                if highBacklog && insufficientDrain
                    finishRecovery = true;
                end

                % Begin the next non-overlapping trend window.
                state.windowStart_s = time_s;
                state.windowStartQueue = queueLength;

            end

        end

    end

    if finishRecovery

        state.mode = 1;
        state.recoveryStart_s = NaN;
        state.windowStart_s = NaN;
        state.windowStartQueue = NaN;

    end

end

% Average and effective early-drop probability.
if state.mode == 2

    % HOLD: preserve avgQueue.
    dropProb = 0;
    recoveryFactor = 0;

else

    avgQueue = (1 - cfg.redWeight) * avgQueue + ...
        cfg.redWeight * queueLength;

    if avgQueue < cfg.redMinTh

        baseProb = 0;

    elseif avgQueue < cfg.redMaxTh

        baseProb = cfg.redMaxP * ...
            (avgQueue - cfg.redMinTh) / ...
            (cfg.redMaxTh - cfg.redMinTh);

    else

        baseProb = 1;

    end

    recoveryFactor = 1;

    if state.mode == 3

        recoveryFactor = min(1, max(0, ...
            (time_s - state.recoveryStart_s) / ...
            cfg.paRecovery_s));

    end

    dropProb = baseProb * recoveryFactor;

end

assert(numel(draws) == arrivals, ...
    'One admission draw is required per generated packet.');

% Early dropping.
earlyDrops = sum(draws(:) < dropProb);
candidates = arrivals - earlyDrops;

% Overflow protection applies in every state.
availableSlots = max(0, queueCapacity - queueLength);

overflowDrops = max(0, candidates - availableSlots);
admitted = min(candidates, availableSlots);

end