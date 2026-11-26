function [summary, guards] = screen_red_tuning()
% Reproduce RED tuning screening from a completed FULL tuning folder.
% No simulations are run. No margins or saved plans are modified.
[fileName, folder] = uigetfile('*.csv', 'Select FULL tuning_runs.csv');
if isequal(fileName, 0)
    summary = table(); guards = table(); return;
end
S = load(fullfile(folder, 'run_settings.mat'), ...
    'plan', 'regimes', 'seeds', 'catalog', 'smokeTest');
p = S.plan;
assert(~S.smokeTest, 'Do not screen smoke-test results.');
assert(p.requireEveryTuningRegime && ...
       ~p.allowInconclusiveCandidates, ...
    'This script requires the saved all-regime screening protocol.');
assert(p.redSelection.deliveryComparator == "droptail" && ...
       p.redSelection.overlapComparator == "droptail", ...
    'Unexpected RED screening comparators.');
T = readtable(fullfile(folder, fileName), 'TextType', 'string');
assert(all(T.Split == "tuning") && all(T.SmokeTest == 0));
assert(all(ismember(T.Seed, S.seeds)));
assert(isempty(intersect(S.seeds, p.testSeeds)));
assert(height(T) == height(S.regimes) * numel(S.seeds) * height(S.catalog), ...
    'Incomplete or unexpected run count.');
assert(all(abs(T.TimeStep_s - p.screeningDt_s) < 1e-12));
assert(all(T.MaxAbsPacketBalanceError == 0) && ...
       all(T.BlockedAttemptPackets == 0) && ...
       all(T.MaxServiceBudgetExcess == 0) && ...
       all(T.MaxQueueCapacityExcess == 0));
redCatalog = S.catalog(S.catalog.Controller == "red", :);
dtID = string(S.catalog.CandidateID(S.catalog.Controller == "droptail"));
assert(numel(dtID) == 1);
allGuards = cell(0, 1);
summaryRecords = cell(height(redCatalog), 1);
for c = 1:height(redCatalog)
    cid = string(redCatalog.CandidateID(c));
    statuses = strings(0, 1);
    regimeDelays = nan(height(S.regimes), 1);
    for r = 1:height(S.regimes)
        rid = string(S.regimes.RegimeID(r));
        a = sortrows(T(T.CandidateID == cid & T.RegimeID == rid, :), 'Seed');
        b = sortrows(T(T.CandidateID == dtID & T.RegimeID == rid, :), 'Seed');
        assert(height(a) == numel(S.seeds) && height(b) == numel(S.seeds));
        assert(isequal(a.Seed, sort(S.seeds(:))) && isequal(a.Seed, b.Seed), ...
            'Missing, duplicate, or mismatched paired seeds.');
        assert(isequal(a.GeneratedPackets, b.GeneratedPackets), ...
            'Paired generated-packet totals differ.');
        g1 = guardRow(cid, rid, "Delivery_vs_DT", a.PDR - b.PDR, ...
            -p.redSelection.deliveryMargin, "lower", p.intervalConfidence);
        g2 = guardRow(cid, rid, "Overlap_vs_DT", ...
            a.PUTransmitOverlapFrac - b.PUTransmitOverlapFrac, ...
            p.redSelection.overlapMargin, "upper", p.intervalConfidence);
        allGuards{end+1, 1} = g1;
        allGuards{end+1, 1} = g2;
        statuses(end+1:end+2, 1) = [g1.Status; g2.Status];
        if all(isfinite(a.MeanDeliveredDelay_ms))
            regimeDelays(r) = mean(a.MeanDeliveredDelay_ms);
        end
    end
    s.CandidateID = cid;
    s.Alpha = redCatalog.Alpha(c);
    s.Beta = redCatalog.Beta(c);
    s.PassedGuards = sum(statuses == "pass");
    s.FailedGuards = sum(statuses == "fail");
    s.InconclusiveGuards = sum(statuses == "inconclusive");
    s.InvalidGuards = sum(statuses == "invalid");
    s.ObjectiveDelay_ms = mean(regimeDelays);
    s.Eligible = all(statuses == "pass") && all(isfinite(regimeDelays));
    summaryRecords{c} = s;
end
summary = struct2table(vertcat(summaryRecords{:}));
guards = struct2table(vertcat(allGuards{:}));
writetable(summary, fullfile(folder, 'red_screening_summary.csv'));
writetable(guards, fullfile(folder, 'red_paired_guard_details.csv'));
selection.Status = "no_feasible_candidate";
selection.CandidateID = "";
selection.Alpha = NaN;
selection.Beta = NaN;
selection.ObjectiveDelay_ms = NaN;
eligible = find(summary.Eligible);
if ~isempty(eligible)
    [~, j] = min(summary.ObjectiveDelay_ms(eligible));
    chosen = eligible(j);
    selection.Status = "selected";
    selection.CandidateID = summary.CandidateID(chosen);
    selection.Alpha = summary.Alpha(chosen);
    selection.Beta = summary.Beta(chosen);
    selection.ObjectiveDelay_ms = summary.ObjectiveDelay_ms(chosen);
end
save(fullfile(folder, 'red_screening_result.mat'), 'selection', 'summary', 'guards');
writetable(struct2table(selection), fullfile(folder, 'red_selection_status.csv'));
disp(summary);
fprintf('\nRED selection status: %s\n', char(selection.Status));
fprintf('No simulations were run; evidence saved in:\n%s\n', folder);
end

function g = guardRow(cid, rid, name, values, boundary, direction, confidence)
g.CandidateID = cid;
g.RegimeID = rid;
g.Guard = name;
g.Pairs = numel(values);
g.Boundary = boundary;
g.Direction = direction;
g.MeanDifference = NaN;
g.CI95Lower = NaN;
g.CI95Upper = NaN;
g.Status = "invalid";
if numel(values) < 2 || ~all(isfinite(values))
    return;
end
n = numel(values);
df = n - 1;
z = betaincinv(1 - confidence, df / 2, 0.5);
critical = sqrt(df * (1 - z) / z);
m = mean(values);
h = critical * std(values, 0) / sqrt(n);
g.MeanDifference = m;
g.CI95Lower = m - h;
g.CI95Upper = m + h;
if direction == "lower"
    pass = g.CI95Lower >= boundary;
    fail = g.CI95Upper < boundary;
else
    pass = g.CI95Upper <= boundary;
    fail = g.CI95Lower > boundary;
end
if pass
    g.Status = "pass";
elseif fail
    g.Status = "fail";
else
    g.Status = "inconclusive";
end
end
