function [sensed, sensingSlot] = generate_sensed_pu_trace(puActual, cfg)

rng(cfg.seed + 30);

N = numel(puActual);
Ts = max(1, round(cfg.sensePeriod_s / cfg.dt));
tau = round(cfg.senseTime_s / cfg.dt);

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