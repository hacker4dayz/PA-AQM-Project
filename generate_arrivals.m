function arrivals = generate_arrivals(cfg)

rng(cfg.seed + 20);

lambdaPerStep = cfg.arrivalRate_pps * cfg.dt;

arrivals = zeros(cfg.numSteps, 1);

for k = 1:cfg.numSteps
    arrivals(k) = poisson_random(lambdaPerStep);
end

end

function x = poisson_random(lambda)

if lambda <= 0
    x = 0;
    return;
end

L = exp(-lambda);
x = 0;
p = 1;

while p > L
    x = x + 1;
    p = p * rand;
end

x = x - 1;

end