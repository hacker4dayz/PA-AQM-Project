function [sensed, sensingSlot] = ...
    generate_sensed_pu_trace(puActual, cfg)

assert(cfg.dt > 0 && cfg.sensePeriod_s > 0, ...
    'Invalid sensing period or dt.');

assert(cfg.senseTime_s >= 0 && ...
       cfg.senseTime_s < cfg.sensePeriod_s, ...
    'Require 0 <= sensing duration < sensing period.');

assert(cfg.Pd >= 0 && cfg.Pd <= 1 && ...
       cfg.Pf >= 0 && cfg.Pf <= 1, ...
    'Pd and Pf must lie in [0,1].');

periodRatio = cfg.sensePeriod_s / cfg.dt;
durationRatio = cfg.senseTime_s / cfg.dt;

assert(abs(periodRatio - round(periodRatio)) < 1e-9 && ...
       abs(durationRatio - round(durationRatio)) < 1e-9, ...
    ['Sensing period and duration must be integer ' ...
     'multiples of cfg.dt.']);

Ts = round(periodRatio);
tau = round(durationRatio);

assert(Ts >= 1, ...
    'Sensing period must be at least one simulation step.');

rng(cfg.seed + 30);

puActual = logical(puActual(:));
N = numel(puActual);

sensed = false(N, 1);
sensingSlot = false(N, 1);

current = false;

for k = 1:N

    phase = mod(k - 1, Ts);

    if phase == 0

        if puActual(k)
            current = rand < cfg.Pd;
        else
            current = rand < cfg.Pf;
        end

    end

    sensed(k) = current;
    sensingSlot(k) = phase < tau;

end

end
