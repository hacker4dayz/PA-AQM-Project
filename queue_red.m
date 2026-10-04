function [admitted, earlyDrops, overflowDrops, avgQueue, dropProb] = ...
    queue_red(arrivals, queueLength, queueCapacity, avgQueue, cfg)

% Update RED exponentially weighted moving average.
avgQueue = (1 - cfg.redWeight) * avgQueue + ...
    cfg.redWeight * queueLength;

% Determine RED early-drop probability.
if avgQueue < cfg.redMinTh
    dropProb = 0;

elseif avgQueue < cfg.redMaxTh
    dropProb = cfg.redMaxP * ...
        (avgQueue - cfg.redMinTh) / ...
        (cfg.redMaxTh - cfg.redMinTh);

else
    dropProb = 1;
end

% Apply probabilistic early dropping to each arriving packet.
earlyDrops = 0;
admitted = 0;

for packet = 1:arrivals
    if rand < dropProb
        earlyDrops = earlyDrops + 1;
    else
        admitted = admitted + 1;
    end
end

% Apply finite-buffer protection after RED early dropping.
availableSlots = max(0, queueCapacity - queueLength);

overflowDrops = max(0, admitted - availableSlots);
admitted = min(admitted, availableSlots);

end