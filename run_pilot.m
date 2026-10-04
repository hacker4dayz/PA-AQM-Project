clear; clc; close all;

cfg = config_default();

cfg.controller = "red";

cfg.offeredLoad = 0.7; % 0.4(40%), 0.70(70%), 1.0(100%), 1.3(130% congestion)
cfg.arrivalRate_pps = cfg.offeredLoad * cfg.linkRate_bps / cfg.packetBits;

cfg.puDutyCycle = 0.30; % 0.00(0%), 0.1(10%), 0.3(30%), 0.5(50%)
cfg.puMeanOn_s = 2.0;
cfg.puMeanOff_s = 4.67;

cfg.Pd = 1.00;
cfg.Pf = 0.00;

out = simulate_crn(cfg);

if cfg.controller == "droptail"
    fprintf("Pilot: Drop-tail with PU ON/OFF interruptions\n");
elseif cfg.controller == "red"
    fprintf("Pilot: RED with PU ON/OFF interruptions\n");
end
fprintf("Offered load: %.2f of nominal link capacity\n",cfg.offeredLoad);
fprintf("Generated packets: %d\n", out.generatedPackets);
fprintf("Delivered packets: %d\n", out.deliveredPackets);
fprintf("Early drops: %d\n", out.earlyDrops);
fprintf("Overflow drops: %d\n", out.overflowDrops);
fprintf("Total drops: %d\n", out.totalDrops);
fprintf("Throughput: %.2f kbps\n", out.throughput_bps / 1e3);
fprintf("PDR: %.4f\n", out.pdr);
fprintf("Loss ratio: %.4f\n", out.lossRatio);
fprintf("Average queue: %.6f packets\n", out.avgQueueLength);
fprintf("Maximum queue: %d packets\n", max(out.queue));
fprintf("Final queue: %d packets\n", out.finalQueue);
fprintf("Packet-balance error: %d packets\n", out.packetBalanceError);
actualDutyCycle = mean(out.puActual);
fprintf("Configured PU duty cycle: %.2f\n", cfg.puDutyCycle);
fprintf("Observed PU duty cycle: %.4f\n", actualDutyCycle);
fprintf("PU active time: %.2f s\n", sum(out.puActual) * cfg.dt);
fprintf("Collision losses: %d\n", out.collisionLosses);
fprintf("Sensing period: %.0f ms, sensing time: %.0f ms\n", ...
    cfg.sensePeriod_s*1e3, cfg.senseTime_s*1e3);
fprintf("Sensing overhead (time fraction): %.4f\n", out.sensingOverhead);
fprintf("Collision time fraction: %.4f\n", out.collisionTimeFrac);
fprintf("Missed-opportunity fraction: %.4f\n", out.missedOpportunityFrac);

kappa = cfg.arrivalRate_pps * cfg.puMeanOn_s / cfg.queueCapacity;
fprintf("Outage-to-buffer ratio kappa: %.2f\n", kappa);

figure;
plot(out.time, out.queue, "LineWidth", 1.2);
grid on;
xlabel("Time (s)");
ylabel("Relay queue length (packets)");
title("Relay Queue During PU ON/OFF Interruptions");

figure;
stairs(out.time, out.puActual, "LineWidth", 1.2);
grid on;
xlabel("Time (s)");
ylabel("PU state");
ylim([-0.1 1.1]);
yticks([0 1]);
yticklabels({"Idle", "Active"});
title("Primary-User Activity Trace");