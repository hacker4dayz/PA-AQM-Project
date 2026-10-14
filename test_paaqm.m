function test_paaqm()

cfg = config_default();

cfg.dt = 0.01;
cfg.numSteps = 400;
cfg.simTime = 4;
cfg.paRecovery_s = 0.04;

traces.puActual = false(cfg.numSteps, 1);
traces.sensed = false(cfg.numSteps, 1);
traces.sensingSlot = false(cfg.numSteps, 1);
traces.arrivals = 2 * ones(cfg.numSteps, 1);

%% Test 1: PA-AQM equals RED with no PU activity.

cfg.controller = "red";
red = simulate_crn(cfg, traces);

cfg.controller = "paaqm";
pa = simulate_crn(cfg, traces);

fields = { ...
    'queue', ...
    'avgQueue', ...
    'delivered', ...
    'earlyDropsTrace', ...
    'overflowDropsTrace', ...
    'paDropProbabilityTrace'};

for j = 1:numel(fields)

    assert(isequal( ...
        red.(fields{j}), pa.(fields{j})), ...
        'No-PU RED equivalence failed for %s.', ...
        fields{j});

end

assert(all(pa.paStateTrace == 1));

fprintf('PASS: no-PU RED equivalence.\n');

%% Test 2: HOLD, overflow, recovery, and re-entry.

state = [];

[a, e, o, q, state, p, f] = queue_paaqm( ...
    3, 50, 50, 40, true, 0, state, cfg, ones(3, 1));

assert(state.mode == 2);
assert(q == 40);
assert(p == 0 && f == 0);
assert(a == 0 && e == 0 && o == 3);

% Repeated sensed-active sample must keep average frozen.
[~, ~, ~, q2, state, p, ~] = queue_paaqm( ...
    0, 50, 50, q, true, 0.01, state, cfg, []);

assert(state.mode == 2);
assert(q2 == q);
assert(p == 0);

% First sensed-idle sample enters RECOVERY with zero ramp.
[~, ~, ~, q, state, p, f] = queue_paaqm( ...
    0, 50, 50, q2, false, 0.02, state, cfg, []);

assert(state.mode == 3);
assert(p == 0 && f == 0);
assert(q > q2);

% Halfway through recovery, factor should equal 0.5.
[~, ~, ~, q, state, p, f] = queue_paaqm( ...
    0, 50, 50, q, false, 0.04, state, cfg, []);

assert(state.mode == 3);
assert(abs(f - 0.5) < 1e-10);
assert(abs(p - 0.5) < 1e-10);

% A new sensed-active interval interrupts recovery.
[~, ~, ~, q, state, p, ~] = queue_paaqm( ...
    0, 50, 50, q, true, 0.05, state, cfg, []);

assert(state.mode == 2);
assert(p == 0);

% Leaving the new HOLD starts a new timer.
[~, ~, ~, q, state, ~, ~] = queue_paaqm( ...
    0, 50, 50, q, false, 0.06, state, cfg, []);

assert(state.mode == 3);
assert(abs(state.recoveryStart_s - 0.06) < 1e-12);

% After recovery, full NORMAL control resumes.
[~, ~, ~, ~, state, p, f] = queue_paaqm( ...
    0, 50, 50, q, false, 0.10, state, cfg, []);

assert(state.mode == 1);
assert(p == 1 && f == 1);

fprintf( ...
    ['PASS: HOLD, overflow protection, recovery ramp, ' ...
     'and re-entry.\n']);

%% Test 3: Blocked service and conservation.

traces.puActual(50:100) = true;
traces.sensed = traces.puActual;
traces.sensingSlot(150:160) = true;

pa = simulate_crn(cfg, traces);

blocked = pa.sensed | pa.sensingSlot;

assert(all(pa.attempted(blocked) == 0));
assert(all(pa.packetBalanceTrace == 0));

assert(all( ...
    pa.earlyDropsTrace(pa.paStateTrace == 2) == 0));

assert(all( ...
    pa.serviceCreditTrace >= 0 & ...
    pa.serviceCreditTrace < 1));

assert(all( ...
    pa.attempted <= pa.serviceBudgetTrace));

fprintf( ...
    ['PASS: blocked service, fractional credit, ' ...
     'and conservation.\n']);

%% Test 4: Continuously backlogged nominal capacity.

cfg.controller = "droptail";

traces.puActual(:) = false;
traces.sensed(:) = false;
traces.sensingSlot(:) = false;
traces.arrivals(:) = 2;

dtOut = simulate_crn(cfg, traces);

assert(isequal( ...
    dtOut.attempted(1:4), [1; 1; 1; 2]));

assert(abs( ...
    dtOut.throughput_bps - cfg.linkRate_bps) < 1e-6);

%% Test 5: Empty queue does not bank whole-packet service.

traces.arrivals(:) = 0;
traces.arrivals(end) = 50;

idleOut = simulate_crn(cfg, traces);

maximumStepBudget = ceil( ...
    cfg.linkRate_bps * cfg.dt / cfg.packetBits);

assert(idleOut.attempted(end) <= maximumStepBudget);

%% Test 6: Missed detection consumes capacity as collisions.

traces.arrivals(:) = 2;
traces.puActual(:) = true;

% sensed remains idle, representing missed detections.
collisionOut = simulate_crn(cfg, traces);

assert(collisionOut.deliveredPackets == 0);

assert(collisionOut.collisionLosses == ...
    sum(collisionOut.attempted));

fprintf( ...
    ['PASS: capacity, no banked idle service, ' ...
     'and collision accounting.\n']);

%% Test 7: Reject sensing duration not aligned to the grid.

cfg.sensePeriod_s = 0.02;
cfg.senseTime_s = 0.005;

rejected = false;

try

    generate_sensed_pu_trace( ...
        false(cfg.numSteps, 1), cfg);

catch

    rejected = true;

end

assert(rejected, ...
    'Misaligned sensing duration was not rejected.');

fprintf('PASS: sensing-grid validation.\n');
fprintf('All included MATLAB tests passed.\n');

end