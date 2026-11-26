%% Document a tuning-grid expansion.
% Does not run simulations or overwrite the original plan.

[fileName, sourceFolder] = uigetfile( ...
    '*.csv', ...
    'Select tuning_runs.csv from the completed FULL tuning folder');

if ~isequal(fileName, 0)
    S = load(fullfile(sourceFolder, 'run_settings.mat'), ...
        'plan', 'regimes', 'smokeTest');

    assert(~S.smokeTest, ...
        'Select the completed FULL tuning folder.');

    screening = load( ...
        fullfile(sourceFolder, 'red_screening_result.mat'), ...
        'selection');

    assert(string(screening.selection.Status) == ...
           "no_feasible_candidate", ...
        'This expansion assumes the original search found no feasible RED.');

    % Start from the exact plan saved with the completed run.
    plan = S.plan;
    tuningRegimes = S.regimes;

    originalRedCount = height(plan.redCandidates);
    originalPACount = height(plan.paCandidates);

    % Three additional threshold pairs.
    extraAlpha = [0.50; 0.60; 0.70];
    extraBeta = [0.85; 0.90; 0.95];

    extraRED = table( ...
        extraAlpha, extraBeta, ...
        'VariableNames', {'Alpha', 'Beta'});

    % Pair each added threshold setting with each recovery duration.
    recoveryValues = plan.recoveryValues_s(:);
    numberPairs = numel(extraAlpha);

    extraPA = table( ...
        repmat(extraAlpha, numel(recoveryValues), 1), ...
        repmat(extraBeta, numel(recoveryValues), 1), ...
        repelem(recoveryValues, numberPairs), ...
        'VariableNames', { ...
            'Alpha', 'Beta', 'RecoveryDuration_s'});

    plan.redCandidates = [plan.redCandidates; extraRED];
    plan.paCandidates = [plan.paCandidates; extraPA];

    assert(height(unique(plan.redCandidates, 'rows')) == ...
           height(plan.redCandidates), ...
        'Duplicate RED candidates.');

    assert(height(unique(plan.paCandidates, 'rows')) == ...
           height(plan.paCandidates), ...
        'Duplicate PA-AQM candidates.');

    % Candidate tables define the search, not their Cartesian product.
    plan.alphaValues = unique(plan.redCandidates.Alpha)';
    plan.betaValues = unique(plan.redCandidates.Beta)';
    plan.candidateConstruction = ...
        "explicit_saved_candidate_tables";

    % Record the amendment.
    plan.version = "final_plan_v2_expanded_search";
    plan.amendmentReason = ...
        "Original RED grid had no candidate passing every tuning guard.";

    plan.amendmentScope = ...
        "Expand threshold candidates only; retain margins and seed split.";

    plan.originalRedCandidateCount = originalRedCount;
    plan.originalPACandidateCount = originalPACount;
    plan.sourceTuningFolder = string(sourceFolder);

    % Keep simulations disabled until incremental runner is prepared.
    plan.readyToRun = false;

    outputFolder = fullfile(sourceFolder, 'expanded_plan_v2');

    if ~exist(outputFolder, 'dir')
        mkdir(outputFolder);
    end

    outputFile = fullfile(outputFolder, 'expanded_tuning_plan.mat');

    assert(~isfile(outputFile), ...
        'An expanded plan already exists here. Do not overwrite it.');

    save(outputFile, ...
        'plan', 'tuningRegimes', 'extraRED', 'extraPA');

    writetable(plan.redCandidates, ...
        fullfile(outputFolder, 'expanded_red_candidates.csv'));

    writetable(plan.paCandidates, ...
        fullfile(outputFolder, 'expanded_pa_candidates.csv'));

    fprintf('Original RED candidates retained: %d\n', originalRedCount);
    fprintf('Original PA-AQM candidates retained: %d\n', originalPACount);
    fprintf('Additional RED candidates: %d\n', height(extraRED));
    fprintf('Additional PA-AQM candidates: %d\n', height(extraPA));
    fprintf('PASS: separate expanded plan saved; no simulations run.\n');
end