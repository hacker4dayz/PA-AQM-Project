function resultFolder = run_sensitivity_checks(smokeTest)
% Supplementary checks with fresh seeds 4001-4010. No parameter is retuned.
%  (i)  time-step convergence: dt = 1 ms (reference) vs 0.5 ms
%  (ii) PA-AQM mechanism ablation at dt = 1 ms:
%       freeze+suspend (P02), freeze only, suspend only, neither
if nargin < 1, smokeTest = true; end
assert(islogical(smokeTest) && isscalar(smokeTest));
[pn, pf] = uigetfile('*.mat','Select final_study_plan.mat');
if isequal(pn,0), resultFolder = ""; return; end
S = load(fullfile(pf,pn),'plan'); plan = S.plan;
[rn, rf] = uigetfile('regimes.csv', ...
    'Select regimes.csv from the final_evaluation_FULL folder');
if isequal(rn,0), resultFolder = ""; return; end
allR = readtable(fullfile(rf,rn),'TextType','string');
assert(height(allR)==96, 'Expected the 96 held-out regimes.');
% 12 representative regimes: load {0.7,1.3} x Pd {0.7,1.0} x Pf 0.1 x 3 traffic types.
keep = ismember(allR.OfferedLoad,[0.7 1.3]) & ismember(allR.Pd,[0.7 1.0]) ...
     & abs(allR.Pf-0.1)<1e-12;
regimes = allR(keep,:);
assert(height(regimes)==12, 'Subset should contain 12 regimes.');
seeds = 4001:4010;
assert(isempty(intersect(seeds,[plan.tuningSeeds(:);plan.testSeeds(:)])));
duration = plan.baseCfg.simTime;
if smokeTest
    regimes = regimes(1,:); seeds = seeds(1); duration = 30;
end
assert(exist('build_final_inputs','file')==2 && exist('run_final_case','file')==2);
% Method table. Check: C = convergence, A = ablation. Alpha/Beta are frozen values.
M = table( ...
 ["DT";"R10";"P02";"P02_freeze_only";"P02_suspend_only";"P02_neither"], ...
 ["droptail";"red";"paaqm";"paaqm";"paaqm";"paaqm"], ...
 [0.30;0.50;0.30;0.30;0.30;0.30],[0.70;0.85;0.60;0.60;0.60;0.60], ...
 [false;false;true;true;false;false],[false;false;true;false;true;false], ...
 'VariableNames',{'ID','Controller','Alpha','Beta','Freeze','Suspend'});
dts = [0.001 0.0005];
nMethods = [height(M) 3];            % extra ablation variants only at 1 ms
expected = height(regimes)*numel(seeds)*sum(nMethods);
root = fullfile(pwd,'results'); if ~isfolder(root), mkdir(root); end
tag = ternary(smokeTest,'SMOKE','FULL');
resultFolder = tempname(root); [~,u] = fileparts(resultFolder);
resultFolder = fullfile(root,['sensitivity_' tag '_' u]); mkdir(resultFolder);
save(fullfile(resultFolder,'settings.mat'),'plan','regimes','seeds','M','dts','duration','smokeTest');
fprintf('Smoke: %d | regimes %d | seeds %d | expected runs %d | duration %.0f s\n', ...
    smokeTest,height(regimes),numel(seeds),expected,duration);
records = cell(expected,1); n = 0;
for s = 1:numel(seeds)
  for r = 1:height(regimes)
    regime = regimes(r,:);
    for k = 1:numel(dts)
      cfg = plan.baseCfg; cfg.seed = seeds(s); cfg.simTime = duration;
      cfg.dt = dts(k);
      cfg.offeredLoad = regime.OfferedLoad; cfg.Pd = regime.Pd; cfg.Pf = regime.Pf;
      cfg.arrivalMode = regime.ArrivalMode;
      if cfg.arrivalMode == "onoff"
        cfg.trafficOnFraction = regime.TrafficOnFraction;
        cfg.trafficMeanOn_s = regime.TrafficMeanOn_s;
      end
      [cfg,traces] = build_final_inputs(cfg);   % recomputes steps and RED weight
      for m = 1:nMethods(k)
        c = cfg; c.controller = M.Controller(m);
        c.redMinFraction = M.Alpha(m); c.redMaxFraction = M.Beta(m);
        c.paMode = "fixed"; c.paRecovery_s = 0;
        c.paFreezeAverage = M.Freeze(m); c.paSuspendEarlyDrop = M.Suspend(m);
        rec = run_final_case(c,traces,regime,M.ID(m),M.ID(m));
        rec.TimeStepUsed_s = dts(k); rec.SmokeTest = smokeTest;
        assert(rec.MaxAbsPacketBalanceError==0 && rec.BlockedAttemptPackets==0);
        assert(rec.MaxServiceBudgetExcess==0 && rec.MaxQueueCapacityExcess==0);
        assert(rec.GeneratedPackets==rec.DeliveredPackets+rec.TotalDrops+rec.FinalQueue_packets);
        n = n+1; records{n} = rec;
      end
    end
    T = struct2table(vertcat(records{1:n}));
    writetable(T,fullfile(resultFolder,'sensitivity_checkpoint.csv'));
    fprintf('Seed %d; %s: %d/%d runs\n',seeds(s),char(regime.RegimeID),n,expected);
  end
end
assert(n==expected);
writetable(T,fullfile(resultFolder,'sensitivity_runs.csv'));
fprintf('PASS: sensitivity run complete (%d runs).\nResults: %s\n',n,resultFolder);
end

function y = ternary(c,a,b)
if c, y = a; else, y = b; end
end
