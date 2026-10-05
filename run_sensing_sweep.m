clear; clc; close all;

Ts_list = [0.02 0.05 0.10 0.50];
nRuns = numel(Ts_list);

thr = zeros(nRuns,1);
pdr = zeros(nRuns,1);
overhead = zeros(nRuns,1);
collisionFrac = zeros(nRuns,1);
collisionLoss = zeros(nRuns,1);
overflow = zeros(nRuns,1);
balanceErr = zeros(nRuns,1);

for i = 1:nRuns
    cfg = config_default();

    cfg.dt = 0.001;
    cfg.simTime = 100;
    cfg.numSteps = round(cfg.simTime / cfg.dt);

    cfg.controller = "droptail";
    cfg.offeredLoad = 0.50;
    cfg.arrivalRate_pps = cfg.offeredLoad * cfg.linkRate_bps / cfg.packetBits;

    cfg.puDutyCycle = 0.30;
    cfg.puMeanOn_s = 2.0;
    cfg.puMeanOff_s = 4.67;

    cfg.Pd = 1.0;
    cfg.Pf = 0.0;

    cfg.sensePeriod_s = Ts_list(i);
    cfg.senseTime_s = 0.005;

    out = simulate_crn(cfg);

    thr(i) = out.throughput_bps / 1e3;
    pdr(i) = out.pdr;
    overhead(i) = out.sensingOverhead;
    collisionFrac(i) = out.collisionTimeFrac;
    collisionLoss(i) = out.collisionLosses;
    overflow(i) = out.overflowDrops;
    balanceErr(i) = out.packetBalanceError;
end

results = table(Ts_list'*1e3, thr, pdr, overhead, collisionFrac, ...
    collisionLoss, overflow, balanceErr, ...
    'VariableNames', {'Ts_ms','Throughput_kbps','PDR','SensingOverhead', ...
    'CollisionTimeFrac','CollisionLosses','OverflowDrops','BalanceError'});

disp(results);
writetable(results, 'sensing_sweep_results.csv');

figure;
subplot(1,3,1);
plot(Ts_list*1e3, thr, '-o', 'LineWidth', 1.2);
xlabel('Sensing period T_s (ms)'); ylabel('Throughput (kbps)');
grid on; title('Throughput');

subplot(1,3,2);
plot(Ts_list*1e3, overhead, '-o', 'LineWidth', 1.2);
xlabel('Sensing period T_s (ms)'); ylabel('Sensing overhead (fraction)');
grid on; title('Sensing overhead');

subplot(1,3,3);
plot(Ts_list*1e3, collisionFrac, '-o', 'LineWidth', 1.2);
xlabel('Sensing period T_s (ms)'); ylabel('Collision time (fraction)');
grid on; title('Collision time');
