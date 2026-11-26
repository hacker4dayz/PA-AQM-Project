%% Save the final-study parameter and screening plan.
% This script does not run simulations.

clear plan;

plan.version = "final_plan_v1";

% Primary objective: average delivered-packet delay
% across the designated tuning regimes.
plan.objective = "mean_delivered_delay";

% Initial final-study reference configuration.
plan.baseCfg = config_final();
plan.baseCfg.queueCapacity = 50;

% Finite threshold and recovery candidate sets.
plan.alphaValues = [0.20, 0.30, 0.40];
plan.betaValues = [0.60, 0.70, 0.80];
plan.recoveryValues_s = [0, 0.10, 0.50];

% Independent tuning and held-out evaluation seeds.
plan.tuningSeeds = 2001:2010;
plan.testSeeds = 3001:3020;

assert(isempty(intersect( ...
    plan.tuningSeeds, plan.testSeeds)), ...
    'Tuning and test seeds must not overlap.');

% Screening margins.
plan.deliveryMargin = 0.01;
plan.queueRelativeMargin = 0.05;
plan.overlapMargin = 0.001;
plan.overloadDeliveryMargin = 0.01;
plan.confidenceLevel = 0.95;

% The overlap margin applies at this reference resolution.
plan.screeningDt_s = 0.001;

% Reference heuristic retained alongside tuned candidates.
plan.originalAlpha = 0.30;
plan.originalBeta = 0.70;
plan.originalRecovery_s = 0;

% Build RED threshold candidates.
[a, b] = ndgrid( ...
    plan.alphaValues, plan.betaValues);

valid = a > 0 & a < b & b < 1;

plan.redCandidates = table( ...
    a(valid), b(valid), ...
    'VariableNames', {'Alpha', 'Beta'});

% Build PA-AQM threshold/recovery candidates.
[a, b, r] = ndgrid( ...
    plan.alphaValues, ...
    plan.betaValues, ...
    plan.recoveryValues_s);

valid = a > 0 & a < b & b < 1 & r >= 0;

plan.paCandidates = table( ...
    a(valid), b(valid), r(valid), ...
    'VariableNames', ...
    {'Alpha', 'Beta', 'RecoveryDuration_s'});

% Mark incomplete until traffic/regime definitions and
% the selection procedure have also been saved.
plan.readyToRun = false;

%% Traffic regimes
% OFF-state arrival rate is zero for ON/OFF traffic.
% Both burst regimes use the same ON fraction and mean load.
plan.trafficRegimes = table( ...
    ["poisson"; "short_bursts"; "long_bursts"], ...
    ["poisson"; "onoff"; "onoff"], ...
    [NaN; 0.20; 0.20], ...
    [NaN; 0.10; 0.50], ...
    'VariableNames', { ...
        'TrafficRegime', ...
        'ArrivalMode', ...
        'OnFraction', ...
        'MeanOn_s'});

%% Tuning conditions
% Select parameters on these conditions only.
% Long bursts are excluded from parameter selection.
plan.tuningLoads = [0.55, 0.85, 1.20];
plan.tuningPd = [0.85, 1.00];
plan.tuningPf = 0.10;
plan.tuningTraffic = ["poisson", "short_bursts"];

%% Held-out evaluation conditions
% Different loads and independent seeds.
% Includes the second burst-duration regime.
plan.testLoads = [0.40, 0.70, 1.00, 1.30];
plan.testPd = [0.70, 0.85, 0.95, 1.00];
plan.testPf = [0, 0.10];
plan.testTraffic = ...
    ["poisson", "short_bursts", "long_bursts"];

assert(isempty(intersect( ...
    plan.tuningLoads, plan.testLoads)), ...
    'This plan requires disjoint tuning and test loads.');

% Additional overload-delivery guard applies above nominal capacity.
plan.overloadLoadThreshold = 1.0;

%% Declare the screening comparisons
plan.deliveryComparator = "droptail";
plan.delayComparator = "droptail";
plan.queueComparator = "tuned_red";
plan.overlapComparator = "tuned_red";
plan.overloadDeliveryComparator = "tuned_red";

% Queue screening applies to every evaluated regime.
plan.queueGuardAllRegimes = true;

% Require all declared guards to pass before claiming improvement.
plan.requireJointFeasibility = true;

%% Counts
plan.numTuningRegimes = ...
    numel(plan.tuningLoads) * ...
    numel(plan.tuningPd) * ...
    numel(plan.tuningPf) * ...
    numel(plan.tuningTraffic);

plan.numTestRegimes = ...
    numel(plan.testLoads) * ...
    numel(plan.testPd) * ...
    numel(plan.testPf) * ...
    numel(plan.testTraffic);

%% Prespecified parameter-selection rules

% Select one parameter tuple per method across all tuning regimes.
% Do not select different parameters separately for each test point.
plan.selectionScope = "one_tuple_across_tuning_regimes";

% Equal weight for each tuning regime.
plan.objectiveWeighting = "equal_weight_per_regime";

% First select the RED comparator.
% Objective: minimum average delivered delay.
% Guards: delivery and overlap relative to drop-tail.
plan.redSelection.deliveryComparator = "droptail";
plan.redSelection.deliveryMargin = plan.deliveryMargin;
plan.redSelection.overlapComparator = "droptail";
plan.redSelection.overlapMargin = plan.overlapMargin;

% Next select PA-AQM against drop-tail and the locked tuned RED.
% Objective: minimum average delivered delay.
plan.paSelection.deliveryComparator = "droptail";
plan.paSelection.queueComparator = "tuned_red";
plan.paSelection.overlapComparator = "tuned_red";
plan.paSelection.overloadDeliveryComparator = "tuned_red";

% A candidate must satisfy its guards in every tuning regime.
plan.requireEveryTuningRegime = true;

% Use two-sided paired Student-t confidence intervals.
plan.intervalMethod = "paired_student_t";
plan.intervalConfidence = 0.95;

% A candidate with unresolved guards is not accepted for selection.
plan.allowInconclusiveCandidates = false;

% Do not silently substitute an infeasible candidate.
plan.noFeasibleCandidateAction = "report_no_feasible_candidate";

% Exact objective ties are resolved by candidate-table order.
plan.tieBreakRule = "first_candidate_in_saved_table";

% Missing delay estimates make a candidate ineligible.
plan.undefinedDelayAction = "candidate_ineligible";

save('final_study_plan.mat', 'plan');

fprintf('RED candidates: %d\n', ...
    height(plan.redCandidates));

fprintf('PA-AQM candidates: %d\n', ...
    height(plan.paCandidates));

fprintf('Tuning seeds: %d\n', ...
    numel(plan.tuningSeeds));

fprintf('Held-out test seeds: %d\n', ...
    numel(plan.testSeeds));

fprintf('Tuning regimes: %d\n', ...
    plan.numTuningRegimes);

fprintf('Held-out test regimes: %d\n', ...
    plan.numTestRegimes);