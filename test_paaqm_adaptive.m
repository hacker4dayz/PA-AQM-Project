function test_paaqm_adaptive()

cfg = config_default();

cfg.paMode = "adaptive";
cfg.paRecovery_s = 0.75;
cfg.paTrendWindow_s = 0.10;
cfg.paLowQueue = 15;
cfg.paHighQueue = 40;
cfg.paMinDrain_pps = 0;

%% Test 1: High queue that does not drain ends recovery.

state = [];

[~, ~, ~, q, state, p, ~] = queue_paaqm( ...
    0, 50, 50, 40, true, 0, state, cfg, []);

assert(state.mode == 2 && q == 40 && p == 0);

[~, ~, ~, q, state, p, ~] = queue_paaqm( ...
    0, 50, 50, q, false, 0.01, state, cfg, []);

assert(state.mode == 3 && p == 0);

[~, ~, ~, ~, state, ~, ~] = queue_paaqm( ...
    0, 50, 50, q, false, 0.11, state, cfg, []);

assert(state.mode == 1, ...
    'High non-draining backlog did not end recovery.');

fprintf('PASS: high non-draining backlog ends recovery.\n');

%% Test 2: A draining high queue remains in recovery.

state = [];

[~, ~, ~, q, state, ~, ~] = queue_paaqm( ...
    0, 50, 50, 40, true, 0, state, cfg, []);

[~, ~, ~, q, state, ~, ~] = queue_paaqm( ...
    0, 50, 50, q, false, 0.01, state, cfg, []);

[~, ~, ~, ~, state, ~, factor] = queue_paaqm( ...
    0, 49, 50, q, false, 0.11, state, cfg, []);

assert(state.mode == 3);
assert(state.lastDrainRate_pps > 0);
assert(factor > 0 && factor < 1);

fprintf('PASS: draining backlog retains temporary recovery.\n');

%% Test 3: Low physical and averaged queues end recovery.

state = [];

[~, ~, ~, q, state, ~, ~] = queue_paaqm( ...
    0, 10, 50, 10, true, 0, state, cfg, []);

[~, ~, ~, ~, state, ~, ~] = queue_paaqm( ...
    0, 10, 50, q, false, 0.01, state, cfg, []);

assert(state.mode == 1);

fprintf('PASS: low backlog ends recovery.\n');

%% Test 4: New sensed activity immediately enters HOLD.

[~, ~, ~, ~, state, p, factor] = queue_paaqm( ...
    0, 50, 50, 40, true, 0.02, state, cfg, []);

assert(state.mode == 2);
assert(p == 0 && factor == 0);

fprintf('PASS: new interruption enters HOLD.\n');

%% Test 5: FIFO timestamps include same-step service.

cfg.controller = "droptail";
cfg.dt = 0.01;
cfg.numSteps = 4;
cfg.simTime = 0.04;

traces.puActual = false(4, 1);
traces.sensed = false(4, 1);
traces.sensingSlot = false(4, 1);
traces.arrivals = [1; 0; 0; 0];

out = simulate_crn(cfg, traces);

assert(out.deliveredPackets == 1);

assert(abs(out.deliveredDelay_s(1) - cfg.dt) < 1e-12);

assert(out.packetBalanceError == 0);

fprintf('PASS: same-step delay accounting.\n');

%% Test 6: Blocking preserves a packet's original timestamp.

traces.sensed = [true; false; false; false];

out = simulate_crn(cfg, traces);

assert(out.deliveredPackets == 1);

assert(abs(out.deliveredDelay_s(1) - 2 * cfg.dt) < 1e-12);

fprintf('PASS: blocked packet retains its arrival timestamp.\n');

%% Test 7: Collision removal does not corrupt FIFO delay.

traces.puActual = [true; false; false; false];
traces.sensed = false(4, 1);
traces.arrivals = [1; 1; 0; 0];

out = simulate_crn(cfg, traces);

assert(out.collisionLosses == 1);
assert(out.deliveredPackets == 1);
assert(numel(out.deliveredDelay_s) == 1);

assert(abs(out.deliveredDelay_s(1) - cfg.dt) < 1e-12);

assert(all(out.packetBalanceTrace == 0));

fprintf('PASS: collision removal and FIFO delay.\n');

%% Test 8: Timestamp ring wraps without corrupting order.

cfg.numSteps = 400;
cfg.simTime = cfg.numSteps * cfg.dt;

traces.puActual = false(cfg.numSteps, 1);
traces.sensed = false(cfg.numSteps, 1);
traces.sensingSlot = false(cfg.numSteps, 1);
traces.arrivals = ones(cfg.numSteps, 1);

out = simulate_crn(cfg, traces);

assert(out.deliveredPackets == cfg.numSteps);

assert(all(abs(out.deliveredDelay_s - cfg.dt) < 1e-10));

assert(all(out.packetBalanceTrace == 0));

fprintf('PASS: FIFO ring-buffer wraparound.\n');
fprintf('All included adaptive-controller tests passed.\n');

end