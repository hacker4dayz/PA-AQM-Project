function arrivals = generate_arrivals(cfg)
% Poisson or ON/OFF-modulated Poisson packet arrivals.

assert(cfg.dt > 0 && ...
       cfg.numSteps >= 1 && ...
       cfg.numSteps == floor(cfg.numSteps), ...
    'Invalid simulation grid.');

assert(isfinite(cfg.arrivalRate_pps) && ...
       cfg.arrivalRate_pps >= 0, ...
    'Arrival rate must be finite and nonnegative.');

% Preserve the original Poisson random-number sequence.
rng(cfg.seed + 20);

arrivals = zeros(cfg.numSteps, 1);

if isfield(cfg, 'arrivalMode')
    mode = lower(string(cfg.arrivalMode));
else
    mode = "poisson";
end

switch mode
    case "poisson"
        lambdaPerStep = cfg.arrivalRate_pps * cfg.dt;

        for k = 1:cfg.numSteps
            arrivals(k) = poisson_random(lambdaPerStep);
        end

    case "onoff"
        onFraction = cfg.trafficOnFraction;
        meanOn = cfg.trafficMeanOn_s;

        assert(isfinite(onFraction) && ...
               onFraction > 0 && onFraction < 1, ...
            'Traffic ON fraction must lie strictly between 0 and 1.');

        assert(isfinite(meanOn) && meanOn > 0, ...
            'Mean traffic ON duration must be positive and finite.');

        % Derive OFF duration to preserve the configured ON fraction.
        meanOff = meanOn * (1 - onFraction) / onFraction;

        % OFF-state rate is zero.
        % This ON-state rate preserves the long-run mean offered load.
        onRate = cfg.arrivalRate_pps / onFraction;

        % Separate randomness for the traffic-state process.
        stateStream = RandStream( ...
            'mt19937ar', 'Seed', cfg.seed + 21);

        % Start the traffic process in its stationary distribution.
        isOn = rand(stateStream) < onFraction;

        if isOn
            remainingDuration = exponential_duration( ...
                stateStream, meanOn);
        else
            remainingDuration = exponential_duration( ...
                stateStream, meanOff);
        end

        for k = 1:cfg.numSteps
            stepRemaining = cfg.dt;
            onTime = 0;

            % Account for state changes within this simulation step.
            while stepRemaining > 0
                segment = min(stepRemaining, remainingDuration);

                if isOn
                    onTime = onTime + segment;
                end

                stepRemaining = max(0, stepRemaining - segment);
                remainingDuration = ...
                    max(0, remainingDuration - segment);

                if remainingDuration == 0
                    isOn = ~isOn;

                    if isOn
                        remainingDuration = exponential_duration( ...
                            stateStream, meanOn);
                    else
                        remainingDuration = exponential_duration( ...
                            stateStream, meanOff);
                    end
                end
            end

            arrivals(k) = poisson_random(onRate * onTime);
        end

    otherwise
        error('Unknown arrivalMode: %s', char(mode));
end
end

function duration = exponential_duration(stream, meanDuration)
u = max(realmin, rand(stream));
duration = -meanDuration * log(u);
end

function x = poisson_random(lambda)
if lambda <= 0
    x = 0;
    return;
end

% Split large means to avoid numerical underflow.
% A sum of independent Poisson variables is Poisson.
if lambda > 20
    pieces = ceil(lambda / 20);
    x = 0;

    for j = 1:pieces
        x = x + poisson_random(lambda / pieces);
    end

    return;
end

limit = exp(-lambda);
x = 0;
product = 1;

while product > limit
    x = x + 1;
    product = product * rand;
end

x = x - 1;
end
