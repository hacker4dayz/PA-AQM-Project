clear;
clc;
close all;

%% Experiment controls

experimentMode = "full";   % "staged" or "full"
smokeTest = false;             % Set false after checking the trial run.

plannedSeeds = 1001:1020;

% Avoid saving large packet traces for every simulation.
% Configurations and numerical metrics are always saved.
saveSelectedTrace = true;
makeSelectedPlots = true;

% Existing plot_paaqm_scenario.m is needed only for selected plots.
zoomWindow_s = [0, 20];
useTransparency = true;

%% Planned values

bufferSizes = [25, 50, 100];
offeredLoads = [0.40, 0.70, 1.00, 1.30];
dutyCycles = [0, 0.10, 0.30, 0.50];

PdValues = [0.70, 0.85, 0.95, 1.00];
PfValues = [0, 0.05, 0.10, 0.20];

% Explicit sensing-period sweep.
sensingPeriods_s = [0.020, 0.050, 0.100, 0.500];
sensingDuration_s = 0.005;

controllers = ["droptail", "red", "paaqm"];

%% Common configuration

baseCfg = config_default();

baseCfg.simTime = 300;
baseCfg.dt = 0.001;
baseCfg.numSteps = round(baseCfg.simTime / baseCfg.dt);

baseCfg.puMode = "random";
baseCfg.puMeanOn_s = 2.0;

baseCfg.paMode = "fixed";
baseCfg.paRecovery_s = 0;

% Same RED averaging time scale for all controllers.
referenceDt = 0.01;
referenceWeight = 0.002;

baseCfg.redWeight = 1 - ...
    (1 - referenceWeight)^(baseCfg.dt / referenceDt);

%% Build configuration matrix
% Columns:
% Buffer, Load, Duty, Pd, Pf, SensingPeriod_s, SensingDuration_s

design = zeros(0, 7);

if experimentMode == "full"

    % Every combination in the attached parameter plan.
    for B = bufferSizes
        for loadValue = offeredLoads
            for duty = dutyCycles
                for Pd = PdValues
                    for Pf = PfValues

                        design(end+1, :) = [ ...
                            B, loadValue, duty, Pd, Pf, ...
                            0.020, sensingDuration_s];

                    end
                end
            end
        end
    end

elseif experimentMode == "staged"

    % Study 1: all buffers, loads, and duty cycles.
    % Reference sensing probabilities.
    for B = bufferSizes
        for loadValue = offeredLoads
            for duty = dutyCycles

                design(end+1, :) = [ ...
                    B, loadValue, duty, 1.00, 0, ...
                    0.020, sensingDuration_s];

            end
        end
    end

    % Study 2: all Pd/Pf combinations at one reference scenario.
    for Pd = PdValues
        for Pf = PfValues

            design(end+1, :) = [ ...
                50, 0.70, 0.30, Pd, Pf, ...
                0.020, sensingDuration_s];

        end
    end

else

    error('experimentMode must be staged or full.');

end

% Study 3: sensing-period sweep for all three controllers.
% Keep other conditions fixed.
for Ts = sensingPeriods_s

    design(end+1, :) = [ ...
        50, 0.70, 0.30, 1.00, 0, ...
        Ts, sensingDuration_s];

end

% Remove configurations repeated across the studies.
design = unique(design, 'rows', 'stable');

%% Small initial verification run

if smokeTest

    design = [ ...
        50, 0.70, 0.30, 1.00, 0.00, 0.020, 0.005; ...
        50, 0.70, 0.30, 0.85, 0.10, 0.020, 0.005; ...
        50, 0.70, 0.30, 1.00, 0.00, 0.100, 0.005];

    seeds = plannedSeeds(1);

else

    seeds = plannedSeeds;

end

%% Output folder

runStamp = datestr(now, 'yyyymmdd_HHMMSS');

rootFolder = fullfile( ...
    'results', ['paaqm_final_batch_' runStamp]);

if ~exist(rootFolder, 'dir')
    mkdir(rootFolder);
end

save(fullfile(rootFolder, 'experiment_plan.mat'), ...
    'baseCfg', 'design', 'seeds', ...
    'experimentMode', 'smokeTest', ...
    'referenceDt', 'referenceWeight');

fprintf('Configurations: %d\n', size(design, 1));
fprintf('Seeds: %d\n', numel(seeds));

fprintf('Controller simulations: %d\n', ...
    size(design, 1) * numel(seeds) * numel(controllers));

%% Run experiments

records = struct([]);
recordIndex = 0;
selectedSaved = false;

for seedIndex = 1:numel(seeds)

    seed = seeds(seedIndex);

    % Reuse a generated PU trace when duty cycle is unchanged.
    puCache = containers.Map( ...
        'KeyType', 'char', 'ValueType', 'any');

    % Reuse arrivals when offered load is unchanged.
    arrivalCache = containers.Map( ...
        'KeyType', 'char', 'ValueType', 'any');

    for scenarioIndex = 1:size(design, 1)

        cfg = baseCfg;
        cfg.seed = seed;

        cfg.queueCapacity = design(scenarioIndex, 1);
        cfg.offeredLoad = design(scenarioIndex, 2);
        cfg.puDutyCycle = design(scenarioIndex, 3);
        cfg.Pd = design(scenarioIndex, 4);
        cfg.Pf = design(scenarioIndex, 5);
        cfg.sensePeriod_s = design(scenarioIndex, 6);
        cfg.senseTime_s = design(scenarioIndex, 7);

        cfg.arrivalRate_pps = ...
            cfg.offeredLoad * ...
            cfg.linkRate_bps / cfg.packetBits;

        if cfg.puDutyCycle == 0

            cfg.puMeanOff_s = Inf;

        else

            cfg.puMeanOff_s = cfg.puMeanOn_s * ...
                (1 - cfg.puDutyCycle) / cfg.puDutyCycle;

        end

        scenarioID = sprintf('S%04d', scenarioIndex);

        %% Shared PU input

        puKey = sprintf('duty_%.6f', cfg.puDutyCycle);

        if isKey(puCache, puKey)

            puActual = puCache(puKey);

        else

            if cfg.puDutyCycle == 0

                puActual = false(cfg.numSteps, 1);

            else

                rng(seed);
                puActual = generate_pu_trace(cfg);
                puActual = logical(puActual(:));

            end

            puCache(puKey) = puActual;

        end

        %% Shared arrivals

        arrivalKey = sprintf('load_%.6f', cfg.offeredLoad);

        if isKey(arrivalCache, arrivalKey)

            arrivals = arrivalCache(arrivalKey);

        else

            rng(seed);
            arrivals = generate_arrivals(cfg);
            arrivals = arrivals(:);

            arrivalCache(arrivalKey) = arrivals;

        end

        %% Shared sensing input

        [sensed, sensingSlot] = ...
            generate_sensed_pu_trace(puActual, cfg);

        traces.puActual = puActual;
        traces.sensed = sensed;
        traces.sensingSlot = sensingSlot;
        traces.arrivals = arrivals;

        if cfg.puDutyCycle == 0

            kappa = NaN;

        else

            kappa = cfg.arrivalRate_pps * ...
                cfg.puMeanOn_s / cfg.queueCapacity;

        end

        outputs = cell(3, 1);

        fprintf( ...
    ['\nSeed %d; %s; B=%d; load=%.2f; duty=%.0f%%; ' ...
     'Pd=%.2f; Pf=%.2f; Ts=%.0f ms\n'], ...
    seed, scenarioID, cfg.queueCapacity, ...
    cfg.offeredLoad, 100 * cfg.puDutyCycle, ...
    cfg.Pd, cfg.Pf, 1000 * cfg.sensePeriod_s);

        for controllerIndex = 1:3

            controllerCfg = cfg;

            controllerCfg.controller = ...
                controllers(controllerIndex);

            out = simulate_crn(controllerCfg, traces);
            outputs{controllerIndex} = out;

            %% Checks

            blocked = out.sensed | out.sensingSlot;

            assert(all(out.attempted(blocked) == 0), ...
                'Blocked-step transmission detected.');

            assert(all(out.packetBalanceTrace == 0), ...
                'Packet conservation failed.');

            assert(numel(out.deliveredDelay_s) == ...
                   out.deliveredPackets, ...
                'Delay count mismatch.');

            if controllerCfg.controller == "paaqm"

                holdMask = out.paStateTrace == 2;

                assert(all( ...
                    out.earlyDropsTrace(holdMask) == 0), ...
                    'PA-AQM early dropping during HOLD.');

            end

            %% Requested fields and identifying metadata

            recordIndex = recordIndex + 1;

            testID = sprintf('%s_seed%d_%s', ...
                scenarioID, seed, ...
                char(controllers(controllerIndex)));

            records(recordIndex).Test = string(testID);
            records(recordIndex).Scenario = string(scenarioID);
            records(recordIndex).Seed = seed;

            records(recordIndex).Controller = ...
                controllers(controllerIndex);

            records(recordIndex).OfferedLoad = cfg.offeredLoad;

            records(recordIndex).ObservedPUDutyCycle_pct = ...
                100 * mean(out.puActual);

            records(recordIndex).Throughput_kbps = ...
                out.throughput_bps / 1000;

            records(recordIndex).PDR = out.pdr;

            records(recordIndex).EarlyDrops = ...
                out.earlyDrops;

            records(recordIndex).OverflowDrops = ...
                out.overflowDrops;

            records(recordIndex).AverageQueue_packets = ...
                out.avgQueueLength;

            records(recordIndex).FinalQueue_packets = ...
                out.finalQueue;

            records(recordIndex).Kappa = kappa;

            % Metadata prevents different experiments being confused.
            records(recordIndex).QueueCapacity_packets = ...
                cfg.queueCapacity;

            records(recordIndex).ConfiguredPUDutyCycle_pct = ...
                100 * cfg.puDutyCycle;

            records(recordIndex).Pd = cfg.Pd;
            records(recordIndex).Pf = cfg.Pf;

            records(recordIndex).SensingPeriod_ms = ...
                1000 * cfg.sensePeriod_s;

            records(recordIndex).SensingDuration_ms = ...
                1000 * cfg.senseTime_s;

            records(recordIndex).SensingOverhead = ...
                out.sensingOverhead;

            records(recordIndex).CollisionTimeFraction = ...
                out.collisionTimeFrac;

            records(recordIndex).CollisionLosses = ...
                out.collisionLosses;

            records(recordIndex).TotalDrops = ...
                out.totalDrops;

            records(recordIndex).GeneratedPackets = ...
                out.generatedPackets;

            records(recordIndex).DeliveredPackets = ...
                out.deliveredPackets;

            records(recordIndex).MeanDeliveredDelay_ms = ...
                1000 * out.meanDeliveredDelay_s;

            records(recordIndex).P95DeliveredDelay_ms = ...
                1000 * out.p95DeliveredDelay_s;

            records(recordIndex).BalanceError = ...
                out.packetBalanceError;

        end

        %% Display requested table

        theseRows = struct2table( ...
            records(recordIndex-2:recordIndex));

        requestedColumns = { ...
            'Test', ...
            'Controller', ...
            'OfferedLoad', ...
            'ObservedPUDutyCycle_pct', ...
            'Throughput_kbps', ...
            'PDR', ...
            'EarlyDrops', ...
            'OverflowDrops', ...
            'AverageQueue_packets', ...
            'FinalQueue_packets', ...
            'Kappa'};

        disp(theseRows(:, requestedColumns));

        %% Save one representative detailed scenario

        isSelected = ...
            cfg.queueCapacity == 50 && ...
            abs(cfg.offeredLoad - 0.70) < 1e-12 && ...
            abs(cfg.puDutyCycle - 0.30) < 1e-12 && ...
            cfg.Pd == 1 && cfg.Pf == 0 && ...
            abs(cfg.sensePeriod_s - 0.020) < 1e-12;

        if seedIndex == 1 && isSelected && ~selectedSaved

            selectedFolder = fullfile(rootFolder, ...
                'selected_scenario');

            if ~exist(selectedFolder, 'dir')
                mkdir(selectedFolder);
            end

            if saveSelectedTrace

                save(fullfile(selectedFolder, 'scenario.mat'), ...
                    'cfg', 'traces', 'outputs', '-v7.3');

            end

            if makeSelectedPlots

                assert(exist('plot_paaqm_scenario', 'file') == 2, ...
                    'plot_paaqm_scenario.m is missing.');

                plot_paaqm_scenario( ...
                    outputs, selectedFolder, true, ...
                    zoomWindow_s, useTransparency);

            end

            selectedSaved = true;

        end

    end

    % Checkpoint after each seed.
    checkpointTable = struct2table(records);

    writetable(checkpointTable, ...
        fullfile(rootFolder, 'all_runs_checkpoint.csv'));

end

%% Final per-run outputs

allRuns = struct2table(records);

writetable(allRuns, ...
    fullfile(rootFolder, 'all_runs_with_metadata.csv'));

requestedTable = allRuns(:, requestedColumns);

writetable(requestedTable, ...
    fullfile(rootFolder, 'requested_results_per_run.csv'));

% Test IDs join this metadata to the requested table.
metadataColumns = { ...
    'Test', 'Scenario', 'Seed', ...
    'QueueCapacity_packets', ...
    'ConfiguredPUDutyCycle_pct', ...
    'Pd', 'Pf', ...
    'SensingPeriod_ms', 'SensingDuration_ms'};

writetable(allRuns(:, metadataColumns), ...
    fullfile(rootFolder, 'test_metadata.csv'));

%% Mean results and uncertainty across seeds

summary = summarizeFinalBatch(allRuns);

writetable(summary, ...
    fullfile(rootFolder, 'summary_across_seeds.csv'));

%% Separate sensing-period results

sensingMask = ...
    allRuns.QueueCapacity_packets == 50 & ...
    abs(allRuns.OfferedLoad - 0.70) < 1e-12 & ...
    abs(allRuns.ConfiguredPUDutyCycle_pct - 30) < 1e-12 & ...
    allRuns.Pd == 1 & allRuns.Pf == 0;

sensingRuns = allRuns(sensingMask, :);

writetable(sensingRuns, ...
    fullfile(rootFolder, 'sensing_period_runs.csv'));

sensingSummaryMask = ...
    summary.QueueCapacity_packets == 50 & ...
    abs(summary.OfferedLoad - 0.70) < 1e-12 & ...
    abs(summary.ConfiguredPUDutyCycle_pct - 30) < 1e-12 & ...
    summary.Pd == 1 & summary.Pf == 0;

sensingSummary = summary(sensingSummaryMask, :);

sensingSummary = sortrows(sensingSummary, ...
    {'Controller', 'SensingPeriod_ms'});

writetable(sensingSummary, ...
    fullfile(rootFolder, 'sensing_period_summary.csv'));

plotSensingSummary(sensingSummary, rootFolder);

fprintf('\nCompleted. Output folder:\n%s\n', rootFolder);

if smokeTest
    fprintf('SMOKE TEST ONLY: the full planned grid was not run.\n');
end

%% Local functions

function summary = summarizeFinalBatch(T)

scenarioIDs = unique(T.Scenario, 'stable');
controllerNames = ["droptail", "red", "paaqm"];

metrics = { ...
    'ObservedPUDutyCycle_pct', ...
    'Throughput_kbps', ...
    'PDR', ...
    'EarlyDrops', ...
    'OverflowDrops', ...
    'AverageQueue_packets', ...
    'FinalQueue_packets', ...
    'CollisionLosses', ...
    'TotalDrops', ...
    'MeanDeliveredDelay_ms', ...
    'P95DeliveredDelay_ms', ...
    'SensingOverhead', ...
    'CollisionTimeFraction'};

summaryRows = struct([]);
index = 0;

for s = 1:numel(scenarioIDs)

    for c = 1:numel(controllerNames)

        mask = ...
            T.Scenario == scenarioIDs(s) & ...
            T.Controller == controllerNames(c);

        group = T(mask, :);

        if isempty(group)
            continue;
        end

        index = index + 1;

        summaryRows(index).Test = scenarioIDs(s);
        summaryRows(index).Controller = controllerNames(c);
        summaryRows(index).Repetitions = height(group);

        summaryRows(index).QueueCapacity_packets = ...
            group.QueueCapacity_packets(1);

        summaryRows(index).OfferedLoad = group.OfferedLoad(1);

        summaryRows(index).ConfiguredPUDutyCycle_pct = ...
            group.ConfiguredPUDutyCycle_pct(1);

        summaryRows(index).Pd = group.Pd(1);
        summaryRows(index).Pf = group.Pf(1);

        summaryRows(index).SensingPeriod_ms = ...
            group.SensingPeriod_ms(1);

        summaryRows(index).SensingDuration_ms = ...
            group.SensingDuration_ms(1);

        summaryRows(index).Kappa = group.Kappa(1);

        for m = 1:numel(metrics)

            metric = metrics{m};
            values = group.(metric);
            values = values(isfinite(values));

            n = numel(values);

            if n == 0

                average = NaN;
                halfWidth = NaN;

            else

                average = mean(values);
                halfWidth = NaN;

                if n >= 2

                    halfWidth = critical95(n - 1) * ...
                        std(values, 0) / sqrt(n);

                end

            end

            summaryRows(index).([metric '_Mean']) = average;
            summaryRows(index).([metric '_CI95HalfWidth']) = ...
                halfWidth;

        end

    end

end

summary = struct2table(summaryRows);

end

function value = critical95(df)

critical = [ ...
    12.706, 4.303, 3.182, 2.776, 2.571, ...
    2.447, 2.365, 2.306, 2.262, 2.228, ...
    2.201, 2.179, 2.160, 2.145, 2.131, ...
    2.120, 2.110, 2.101, 2.093, 2.086, ...
    2.080, 2.074, 2.069, 2.064, 2.060, ...
    2.056, 2.052, 2.048, 2.045, 2.042];

if df <= 30
    value = critical(df);
else
    value = critical(30);
end

end

function plotSensingSummary(T, folder)

controllerNames = ["droptail", "red", "paaqm"];
displayNames = {'Drop-tail', 'RED', 'PA-AQM'};

colors = [ ...
    0.000 0.447 0.741; ...
    0.850 0.325 0.098; ...
    0.494 0.184 0.556];

styles = {'-', '--', '-.'};
markers = {'o', 's', '^'};

metrics = { ...
    'Throughput_kbps', ...
    'PDR', ...
    'SensingOverhead', ...
    'CollisionTimeFraction', ...
    'CollisionLosses'};

labels = { ...
    'Delivered throughput (kbps)', ...
    'Packet delivery ratio', ...
    'Sensing overhead fraction', ...
    'Eligible PU-overlap fraction', ...
    'Collision-lost packets'};

for m = 1:numel(metrics)

    fig = figure('Color', 'w');
    hold on;

    for c = 1:numel(controllerNames)

        group = T(T.Controller == controllerNames(c), :);
        group = sortrows(group, 'SensingPeriod_ms');

        x = group.SensingPeriod_ms;
        y = group.([metrics{m} '_Mean']);
        e = group.([metrics{m} '_CI95HalfWidth']);

        if all(isfinite(e))

            errorbar(x, y, e, ...
                'Color', colors(c, :), ...
                'LineStyle', styles{c}, ...
                'Marker', markers{c}, ...
                'LineWidth', 1.3);

        else

            plot(x, y, ...
                'Color', colors(c, :), ...
                'LineStyle', styles{c}, ...
                'Marker', markers{c}, ...
                'LineWidth', 1.3);

        end

    end

    grid on;
    xlabel('Sensing period (ms)');
    ylabel(labels{m});

    title(sprintf( ...
        'Sensing-Period Sweep: Load 0.70, Duty 30%%, %s', ...
        labels{m}));

    legend(displayNames, 'Location', 'best');

    savefig(fig, fullfile(folder, ...
        ['sensing_' metrics{m} '.fig']));

    print(fig, fullfile(folder, ...
        ['sensing_' metrics{m} '.png']), ...
        '-dpng', '-r200');

end

end