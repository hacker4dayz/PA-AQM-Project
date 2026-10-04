function puActual = generate_pu_trace(cfg)

rng(cfg.seed + 10);

N = cfg.numSteps;
puActual = false(N, 1);

if cfg.puDutyCycle <= 0
    return;
end

if lower(string(cfg.puMode)) == "periodic"
    t = (0:N-1)' * cfg.dt;
    phase = mod(t, cfg.puPeriod_s);
    puActual = phase < cfg.puDutyCycle * cfg.puPeriod_s;
    return;
end

meanOn = cfg.puMeanOn_s;
meanOff = meanOn * (1 - cfg.puDutyCycle) / cfg.puDutyCycle;

stateOn = false;
stepIndex = 1;

while stepIndex <= N
    if stateOn
        duration_s = exponential_random(meanOn);
    else
        duration_s = exponential_random(meanOff);
    end

    durationSteps = max(1, round(duration_s / cfg.dt));
    lastStep = min(N, stepIndex + durationSteps - 1);

    puActual(stepIndex:lastStep) = stateOn;

    stepIndex = lastStep + 1;
    stateOn = ~stateOn;
end

end

function x = exponential_random(meanValue)
x = -meanValue * log(max(rand, realmin));
end