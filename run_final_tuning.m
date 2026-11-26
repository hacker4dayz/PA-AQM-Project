function resultFolder = run_final_tuning(smokeTest)
% Evaluate threshold/recovery candidates on tuning data only.
% Default: short smoke test.

if nargin < 1
    smokeTest = true;
end

assert(islogical(smokeTest) && isscalar(smokeTest), ...
    'smokeTest must be true or false.');

S = load('final_study_plan.mat', ...
    'plan', 'tuningRegimes');

plan = S.plan;
regimes = S.tuningRegimes;
seeds = plan.tuningSeeds;

assert(isempty(intersect( ...
    plan.tuningSeeds, plan.testSeeds)), ...
    'Tuning and test seeds overlap.');

if ~smokeTest
    assert(plan.readyToRun, ...
        ['Full tuning is not enabled yet. ' ...
         'Complete the smoke test and review first.']);
end

%% Build the controller/candidate catalog
nRed = height(plan.redCandidates);
nPA = height(plan.paCandidates);

methodIDs = [ ...
    "droptail"; ...
    repmat("red_candidate", nRed, 1); ...
    repmat("paaqm_candidate", nPA, 1)];

candidateIDs = [ ...
    "DT"; ...
    compose("R%02d", (1:nRed)'); ...
    compose("P%02d", (1:nPA)')];

controllers = [ ...
    "droptail"; ...
    repmat("red", nRed, 1); ...
    repmat("paaqm", nPA, 1)];

alphas = [ ...
    plan.originalAlpha; ...
    plan.redCandidates.Alpha; ...
    plan.paCandidates.Alpha];

betas = [ ...
    plan.originalBeta; ...
    plan.redCandidates.Beta; ...
    plan.paCandidates.Beta];

recoveries = [ ...
    0; ...
    zeros(nRed, 1); ...
    plan.paCandidates.RecoveryDuration_s];

catalog = table( ...
    methodIDs, candidateIDs, controllers, ...
    alphas, betas, recoveries, ...
    'VariableNames', { ...
        'MethodID', 'CandidateID', 'Controller', ...
        'Alpha', 'Beta', 'RecoveryDuration_s'});

%% Smoke-test overrides
simulationTime_s = plan.baseCfg.simTime;

if smokeTest
    % First two regimes: Poisson and short bursts.
    regimes = regimes(1:2, :);
    seeds = seeds(1);
    simulationTime_s = 30;
end

assert(all(regimes.Split == "tuning"), ...
    'The tuning runner must not use test regimes.');

%% Output folder
stamp = datestr(now, 'yyyymmdd_HHMMSS');

if smokeTest
    prefix = 'final_tuning_SMOKE_';
else
    prefix = 'final_tuning_FULL_';
end

resultFolder = fullfile('results', [prefix stamp]);

if ~exist(resultFolder, 'dir')
    mkdir(resultFolder);
end

save(fullfile(resultFolder, 'run_settings.mat'), ...
    'plan', 'regimes', 'seeds', 'catalog', ...
    'smokeTest', 'simulationTime_s');

writetable(catalog, ...
    fullfile(resultFolder, 'candidate_catalog.csv'));

writetable(regimes, ...
    fullfile(resultFolder, 'regimes.csv'));

expectedRuns = ...
    height(regimes) * numel(seeds) * height(catalog);

fprintf('Smoke test: %d\n', smokeTest);
fprintf('Regimes: %d\n', height(regimes));
fprintf('Seeds: %d\n', numel(seeds));
fprintf('Controller configurations: %d\n', height(catalog));
fprintf('Expected simulations: %d\n', expectedRuns);

%% Run paired candidate comparisons
records = cell(expectedRuns, 1);
recordIndex = 0;

for s = 1:numel(seeds)
    for r = 1:height(regimes)
        regime = regimes(r, :);

        cfg = plan.baseCfg;
        cfg.seed = seeds(s);
        cfg.simTime = simulationTime_s;

        cfg.offeredLoad = regime.OfferedLoad;
        cfg.Pd = regime.Pd;
        cfg.Pf = regime.Pf;
        cfg.arrivalMode = regime.ArrivalMode;

        if cfg.arrivalMode == "onoff"
            cfg.trafficOnFraction = regime.TrafficOnFraction;
            cfg.trafficMeanOn_s = regime.TrafficMeanOn_s;
        end

        % Generate inputs once, outside the candidate loop.
        [cfg, traces] = build_final_inputs(cfg);

        fprintf('\nSeed %d; %s; %s\n', ...
            cfg.seed, char(regime.RegimeID), ...
            char(regime.TrafficRegime));

        for c = 1:height(catalog)
            runCfg = cfg;

            runCfg.controller = catalog.Controller(c);
            runCfg.redMinFraction = catalog.Alpha(c);
            runCfg.redMaxFraction = catalog.Beta(c);
            runCfg.paRecovery_s = ...
                catalog.RecoveryDuration_s(c);
            runCfg.paMode = "fixed";

            % Full PA-AQM mechanisms for parameter tuning.
            % Mechanism ablations will be a separate study.
            isPA = runCfg.controller == "paaqm";
            runCfg.paFreezeAverage = isPA;
            runCfg.paSuspendEarlyDrop = isPA;

            record = run_final_case( ...
                runCfg, traces, regime, ...
                catalog.MethodID(c), ...
                catalog.CandidateID(c));

            record.SmokeTest = smokeTest;

            record.IsReferenceSetting = ...
                abs(catalog.Alpha(c) - ...
                    plan.originalAlpha) < 1e-12 && ...
                abs(catalog.Beta(c) - ...
                    plan.originalBeta) < 1e-12 && ...
                abs(catalog.RecoveryDuration_s(c) - ...
                    plan.originalRecovery_s) < 1e-12;

            recordIndex = recordIndex + 1;
            records{recordIndex} = record;
        end

        % Checkpoint after each regime/seed group.
        checkpoint = struct2table( ...
            vertcat(records{1:recordIndex}));

        writetable(checkpoint, ...
            fullfile(resultFolder, 'tuning_checkpoint.csv'));

        fprintf('Completed %d of %d simulations.\n', ...
            recordIndex, expectedRuns);
    end
end

%% Final outputs
results = struct2table( ...
    vertcat(records{1:recordIndex}));

assert(height(results) == expectedRuns, ...
    'Unexpected number of completed simulations.');

assert(all(ismember(results.Seed, plan.tuningSeeds)), ...
    'Unexpected seed in tuning results.');

assert(~any(ismember(results.Seed, plan.testSeeds)), ...
    'Held-out test seeds were used during tuning.');

writetable(results, ...
    fullfile(resultFolder, 'tuning_runs.csv'));

fprintf('\nCompleted. Results folder:\n%s\n', resultFolder);

if smokeTest
    fprintf(['SMOKE TEST ONLY: do not use these results ' ...
        'to select final parameters.\n']);
end
end