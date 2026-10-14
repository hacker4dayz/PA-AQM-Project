function [admitted, earlyDrops, overflowDrops, avgQueue, dropProb] = ...
    queue_red(arrivals, queueLength, queueCapacity, avgQueue, cfg, draws)

if nargin < 6
    draws = rand(arrivals, 1);
end

% Update the average using queue occupancy before admission.
avgQueue = (1 - cfg.redWeight) * avgQueue + ...
    cfg.redWeight * queueLength;

% Baseline RED probability.
if avgQueue < cfg.redMinTh

    dropProb = 0;

elseif avgQueue < cfg.redMaxTh

    dropProb = cfg.redMaxP * ...
        (avgQueue - cfg.redMinTh) / ...
        (cfg.redMaxTh - cfg.redMinTh);

else

    dropProb = 1;

end

assert(numel(draws) == arrivals, ...
    'One admission draw is required per arrival.');

% Apply early dropping.
earlyDrops = sum(draws(:) < dropProb);
candidates = arrivals - earlyDrops;

% Apply finite-buffer protection.
availableSlots = max(0, queueCapacity - queueLength);

overflowDrops = max(0, candidates - availableSlots);
admitted = min(candidates, availableSlots);

end
