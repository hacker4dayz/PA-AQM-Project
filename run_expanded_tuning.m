function resultFolder = run_expanded_tuning(smokeTest)
% Run only the added v2 candidates. No held-out seeds are used.
% Smoke mode: one regime, one seed, full duration, plus a baseline check.
if nargin < 1
    smokeTest = true;
end
assert(islogical(smokeTest) && isscalar(smokeTest));
[fileName, planFolder] = uigetfile('*.mat', ...
    'Select expanded_tuning_plan.mat inside expanded_plan_v2');
if isequal(fileName, 0)
    resultFolder = ""; return;
end
S = load(fullfile(planFolder, fileName), ...
    'plan', 'tuningRegimes', 'extraRED', 'extraPA');
plan = S.plan;
regimes = S.tuningRegimes;
seeds = plan.tuningSeeds;
assert(isempty(intersect(seeds, plan.testSeeds)));
assert(plan.originalRedCandidateCount == 9 && ...
       plan.originalPACandidateCount == 27);
assert(height(S.extraRED) == 3 && height(S.extraPA) == 9);
if ~smokeTest
    assert(plan.readyToRun, ...
        'Expanded full tuning is not enabled. Complete the smoke check first.');
end
% The expansion directory is inside the original full-tuning directory.
selectedPlanFile = fullfile(planFolder, fileName);
expansionFolder = fileparts(selectedPlanFile);
sourceFolder = fileparts(expansionFolder);

assert(isfile(fullfile(sourceFolder, 'tuning_runs.csv')), ...
    'Original tuning_runs.csv was not found in: %s', sourceFolder);
original = readtable(fullfile(sourceFolder, 'tuning_runs.csv'), ...
    'TextType', 'string');
assert(height(original) == 4440 && all(original.SmokeTest == 0), ...
    'Expected the original completed full-tuning CSV.');
originalDT = original(original.CandidateID == "DT", :);
nR = height(S.extraRED);
nP = height(S.extraPA);
catalog = table( ...
    [repmat("red_candidate", nR, 1); repmat("paaqm_candidate", nP, 1)], ...
    [compose("R%02d", (plan.originalRedCandidateCount + (1:nR))'); ...
     compose("P%02d", (plan.originalPACandidateCount + (1:nP))')], ...
    [repmat("red", nR, 1); repmat("paaqm", nP, 1)], ...
    [S.extraRED.Alpha; S.extraPA.Alpha], ...
    [S.extraRED.Beta; S.extraPA.Beta], ...
    [zeros(nR, 1); S.extraPA.RecoveryDuration_s], ...
    'VariableNames', {'MethodID', 'CandidateID', 'Controller', ...
        'Alpha', 'Beta', 'RecoveryDuration_s'});
assert(~any(ismember(catalog.CandidateID, original.CandidateID)), ...
    'Added candidate IDs collide with original results.');
if smokeTest
    regimes = regimes(1, :);
    seeds = seeds(1);
end
simulationTime_s = plan.baseCfg.simTime;
expectedRuns = height(regimes) * numel(seeds) * height(catalog);
stamp = datestr(now, 'yyyymmdd_HHMMSS');
if smokeTest
    prefix = 'expanded_tuning_SMOKE_';
else
    prefix = 'expanded_tuning_FULL_';
end
resultFolder = fullfile(sourceFolder, [prefix stamp]);
mkdir(resultFolder);
save(fullfile(resultFolder, 'run_settings.mat'), ...
    'plan', 'regimes', 'seeds', 'catalog', 'smokeTest', ...
    'simulationTime_s', 'sourceFolder');
writetable(catalog, fullfile(resultFolder, 'candidate_catalog.csv'));
writetable(regimes, fullfile(resultFolder, 'regimes.csv'));
fprintf('Smoke test: %d\n', smokeTest);
fprintf('Additional candidates: %d\n', height(catalog));
fprintf('Simulation duration: %.0f s\n', simulationTime_s);
fprintf('Expected candidate simulations: %d\n', expectedRuns);
records = cell(expectedRuns, 1);
recordIndex = 0;
baselineRecords = cell(numel(seeds) * height(regimes), 1);
baselineIndex = 0;
for s = 1:numel(seeds)
    for r = 1:height(regimes)
        regime = regimes(r, :);
        cfg = plan.baseCfg;
        cfg.seed = seeds(s);
        cfg.offeredLoad = regime.OfferedLoad;
        cfg.Pd = regime.Pd;
        cfg.Pf = regime.Pf;
        cfg.arrivalMode = regime.ArrivalMode;
        if cfg.arrivalMode == "onoff"
            cfg.trafficOnFraction = regime.TrafficOnFraction;
            cfg.trafficMeanOn_s = regime.TrafficMeanOn_s;
        end
        [cfg, traces] = build_final_inputs(cfg);
        reference = originalDT(originalDT.RegimeID == regime.RegimeID & ...
            originalDT.Seed == cfg.seed, :);
        assert(height(reference) == 1);
        assert(reference.GeneratedPackets == sum(traces.arrivals), ...
            'Regenerated arrival total differs from the original run.');
        assert(abs(reference.ObservedPUDutyCycle - ...
            mean(traces.puActual)) < 1e-12, ...
            'Regenerated PU duty differs from the original run.');
        % Independently rerun DT to verify compatibility with saved results.
        baselineCfg = cfg;
        baselineCfg.controller = "droptail";
        baselineCfg.paMode = "fixed";
        baselineCfg.paRecovery_s = 0;
        baselineCfg.paFreezeAverage = false;
        baselineCfg.paSuspendEarlyDrop = false;
        baseline = run_final_case(baselineCfg, traces, regime, ...
            "droptail", "DT");
        compareFields = {'GeneratedPackets', 'DeliveredPackets', ...
            'AttemptedPackets', 'CollisionLosses', 'FinalQueue_packets', ...
            'MeanQueue_packets', 'MeanDeliveredDelay_ms', ...
            'PUTransmitOverlapFrac'};
        for f = 1:numel(compareFields)
            name = compareFields{f};
            x = baseline.(name); y = reference.(name);
            assert((isnan(x) && isnan(y)) || ...
                abs(x - y) <= 1e-10 * max(1, abs(y)), ...
                'Original DT reproduction failed for %s.', name);
        end
        baselineIndex = baselineIndex + 1;
        baseline.SmokeTest = smokeTest;
        baselineRecords{baselineIndex} = baseline;
        writetable(struct2table(vertcat(baselineRecords{1:baselineIndex})), ...
            fullfile(resultFolder, 'baseline_reproduction_checks.csv'));
        fprintf('\nSeed %d; %s: DT reproduction passed.\n', ...
            cfg.seed, char(regime.RegimeID));
        for c = 1:height(catalog)
            runCfg = cfg;
            runCfg.controller = catalog.Controller(c);
            runCfg.redMinFraction = catalog.Alpha(c);
            runCfg.redMaxFraction = catalog.Beta(c);
            runCfg.paRecovery_s = catalog.RecoveryDuration_s(c);
            runCfg.paMode = "fixed";
            isPA = runCfg.controller == "paaqm";
            runCfg.paFreezeAverage = isPA;
            runCfg.paSuspendEarlyDrop = isPA;
            record = run_final_case(runCfg, traces, regime, ...
                catalog.MethodID(c), catalog.CandidateID(c));
            record.SmokeTest = smokeTest;
            record.IsReferenceSetting = false;
            recordIndex = recordIndex + 1;
            records{recordIndex} = record;
        end
        writetable(struct2table(vertcat(records{1:recordIndex})), ...
            fullfile(resultFolder, 'expanded_checkpoint.csv'));
        fprintf('Completed %d of %d candidate simulations.\n', ...
            recordIndex, expectedRuns);
    end
end
results = struct2table(vertcat(records{1:recordIndex}));
assert(height(results) == expectedRuns);
assert(all(ismember(results.Seed, plan.tuningSeeds)));
assert(~any(ismember(results.Seed, plan.testSeeds)));
writetable(results, fullfile(resultFolder, 'expanded_tuning_runs.csv'));
fprintf('\nCompleted. Output folder:\n%s\n', resultFolder);
if smokeTest
    fprintf('SMOKE TEST ONLY. Do not include these rows in final selection.\n');
end
end
