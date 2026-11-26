function resultFolder = run_final_evaluation(smokeTest)
% Compare frozen DT, RED R10, and PA-AQM P02 settings.
% Default smoke uses seed 2001, not a held-out seed.
if nargin < 1, smokeTest = true; end
assert(islogical(smokeTest) && isscalar(smokeTest));
[name, folder] = uigetfile('*.mat', ...
    'Select saved final-study plan or original run_settings.mat');
if isequal(name,0), resultFolder = ""; return; end
S = load(fullfile(folder,name),'plan');
assert(isfield(S,'plan'), 'Selected MAT file must contain plan.');
plan = S.plan;
required = {'baseCfg','trafficRegimes','testLoads','testPd', ...
    'testPf','testTraffic','testSeeds','tuningSeeds', ...
    'overloadLoadThreshold','numTestRegimes','screeningDt_s'};
assert(all(isfield(plan,required)), 'Saved plan lacks required fields.');
assert(isempty(intersect(plan.tuningSeeds,plan.testSeeds)));
assert(isequal(plan.testSeeds(:),(3001:3020)'));
assert(abs(plan.baseCfg.dt - plan.screeningDt_s) < 1e-12);
assert(abs(plan.baseCfg.simTime - 300) < 1e-12);
assert(exist('build_final_inputs','file') == 2);
assert(exist('run_final_case','file') == 2);
% Candidate IDs preserve their tuning identities; DT thresholds are unused.
catalog = table(["droptail";"tuned_red";"tuned_paaqm"], ...
    ["DT";"R10";"P02"], ["droptail";"red";"paaqm"], ...
    [plan.baseCfg.redMinFraction;0.50;0.30], ...
    [plan.baseCfg.redMaxFraction;0.85;0.60], [0;0;0], ...
    [false;false;true], [false;false;true], ...
    'VariableNames',{'MethodID','CandidateID','Controller','Alpha', ...
    'Beta','RecoveryDuration_s','FreezeAverage','SuspendEarlyDrop'});
% Build all held-out conditions from the saved traffic definitions.
rows = cell(plan.numTestRegimes,1); k = 0;
for loadValue = plan.testLoads(:)'
    for pdValue = plan.testPd(:)'
        for pfValue = plan.testPf(:)'
            for traffic = string(plan.testTraffic(:))'
                tr = plan.trafficRegimes( ...
                    string(plan.trafficRegimes.TrafficRegime)==traffic,:);
                assert(height(tr)==1, 'Missing or duplicate traffic definition.');
                k = k+1;
                q.RegimeID = string(sprintf('TEST_%03d',k));
                q.Split = "test";
                q.IsOverload = loadValue > plan.overloadLoadThreshold;
                q.OfferedLoad = loadValue;
                q.Pd = pdValue; q.Pf = pfValue;
                q.TrafficRegime = traffic;
                q.ArrivalMode = string(tr.ArrivalMode);
                q.TrafficOnFraction = tr.OnFraction;
                q.TrafficMeanOn_s = tr.MeanOn_s;
                if q.ArrivalMode == "onoff"
                    q.TrafficMeanOff_s = q.TrafficMeanOn_s * ...
                        (1-q.TrafficOnFraction)/q.TrafficOnFraction;
                else
                    q.TrafficMeanOff_s = NaN;
                end
                rows{k}=q;
            end
        end
    end
end
assert(k==plan.numTestRegimes && k==96);
allTestRegimes = struct2table(vertcat(rows{:}));
if smokeTest
    % Cover each traffic generator without drawing any held-out seed.
    [~,idx] = unique(allTestRegimes.TrafficRegime,'stable');
    regimes = allTestRegimes(sort(idx),:);
    regimes.RegimeID = compose("SMOKE_%03d",(1:height(regimes))');
    regimes.Split(:) = "smoke";
    seeds = plan.tuningSeeds(1);
    duration = 30;
    prefix = 'final_evaluation_SMOKE_';
else
    % Require a completed matching smoke run before a full evaluation.
    [passName,passFolder] = uigetfile('smoke_pass.mat', ...
        'Select smoke_pass.mat from the verified evaluation smoke folder');
    assert(~isequal(passName,0), 'Full evaluation cancelled.');
    V = load(fullfile(passFolder,passName),'smokePassed','smokePlan','smokeCatalog');
    assert(V.smokePassed && isequaln(V.smokePlan,plan) && ...
        isequaln(V.smokeCatalog,catalog), ...
        'Smoke settings do not match this evaluation.');
    answer = questdlg(['Run frozen methods on all held-out conditions? ' ...
        'Do not retune after inspecting results.'], ...
        'Start held-out evaluation','Run','Cancel','Cancel');
    assert(strcmp(answer,'Run'), 'Full evaluation cancelled.');
    regimes = allTestRegimes;
    seeds = plan.testSeeds;
    duration = plan.baseCfg.simTime;
    prefix = 'final_evaluation_FULL_';
end
assert(smokeTest || isempty(intersect(seeds,plan.tuningSeeds)));
assert(~smokeTest || isempty(intersect(seeds,plan.testSeeds)));
expectedRuns = height(regimes)*numel(seeds)*height(catalog);
root = fullfile(pwd,'results');
if ~isfolder(root), mkdir(root); end
resultFolder = tempname(root);
[~,uniqueName] = fileparts(resultFolder);
resultFolder = fullfile(root,[prefix uniqueName]);
mkdir(resultFolder);
save(fullfile(resultFolder,'run_settings.mat'), 'plan','catalog', ...
    'regimes','allTestRegimes','seeds','duration','smokeTest');
writetable(catalog,fullfile(resultFolder,'frozen_methods.csv'));
writetable(regimes,fullfile(resultFolder,'regimes.csv'));
fprintf('Smoke test: %d\n',smokeTest);
fprintf('Regimes: %d; seeds: %d; methods: %d\n', ...
    height(regimes),numel(seeds),height(catalog));
fprintf('Duration: %.0f s; expected runs: %d\n',duration,expectedRuns);
fprintf('Output: %s\n',resultFolder);
records = cell(expectedRuns,1); n = 0;
for s = 1:numel(seeds)
    for r = 1:height(regimes)
        regime = regimes(r,:);
        cfg = plan.baseCfg;
        cfg.seed = seeds(s); cfg.simTime = duration;
        cfg.offeredLoad = regime.OfferedLoad;
        cfg.Pd = regime.Pd; cfg.Pf = regime.Pf;
        cfg.arrivalMode = regime.ArrivalMode;
        if cfg.arrivalMode == "onoff"
            cfg.trafficOnFraction = regime.TrafficOnFraction;
            cfg.trafficMeanOn_s = regime.TrafficMeanOn_s;
        end
        [cfg,traces] = build_final_inputs(cfg);
        firstRecord = [];
        for m = 1:height(catalog)
            c = cfg;
            c.controller = catalog.Controller(m);
            c.redMinFraction = catalog.Alpha(m);
            c.redMaxFraction = catalog.Beta(m);
            c.paMode = "fixed";
            c.paRecovery_s = catalog.RecoveryDuration_s(m);
            c.paFreezeAverage = catalog.FreezeAverage(m);
            c.paSuspendEarlyDrop = catalog.SuspendEarlyDrop(m);
            rec = run_final_case(c,traces,regime, ...
                catalog.MethodID(m),catalog.CandidateID(m));
            rec.SmokeTest = smokeTest;
            assert(rec.MaxAbsPacketBalanceError==0);
            assert(rec.BlockedAttemptPackets==0);
            assert(rec.MaxServiceBudgetExcess==0);
            assert(rec.MaxQueueCapacityExcess==0);
            assert(rec.MinRecordedQueue>=0);
            assert(rec.GeneratedPackets == rec.DeliveredPackets + ...
                rec.TotalDrops + rec.FinalQueue_packets);
            assert(abs(rec.SimulatedTime_s-duration)<1e-10);
            if m==1
                firstRecord = rec;
            else
                assert(rec.GeneratedPackets==firstRecord.GeneratedPackets);
                assert(rec.ObservedPUDutyCycle==firstRecord.ObservedPUDutyCycle);
            end
            n=n+1; records{n}=rec;
        end
        T = struct2table(vertcat(records{1:n}));
        writetable(T,fullfile(resultFolder,'evaluation_checkpoint.csv'));
        fprintf('Seed %d; %s: completed %d/%d runs.\n', ...
            seeds(s),char(regime.RegimeID),n,expectedRuns);
    end
end
assert(n==expectedRuns);
assert(height(unique(T(:,{'CandidateID','RegimeID','Seed'}),'rows'))==n);
writetable(T,fullfile(resultFolder,'evaluation_runs.csv'));
if smokeTest
    smokePassed=true; smokePlan=plan; smokeCatalog=catalog;
    save(fullfile(resultFolder,'smoke_pass.mat'), ...
        'smokePassed','smokePlan','smokeCatalog');
    fprintf('PASS: evaluation smoke test verified (%d runs).\n',n);
else
    fprintf('PASS: held-out evaluation completed (%d runs).\n',n);
end
fprintf('Results: %s\n',resultFolder);
end
