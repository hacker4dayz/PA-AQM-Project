function plot_paaqm_scenario( ...
    outputs, outputFolder, showFigures, ...
    zoomWindow_s, useTransparency)

colors = [ ...
    0.000 0.447 0.741; ...
    0.850 0.325 0.098; ...
    0.494 0.184 0.556];

styles = {'-', '--', '-.'};
names = {'Drop-tail', 'RED', 'PA-AQM'};

if showFigures
    visibility = 'on';
else
    visibility = 'off';
end

cfg = outputs{1}.cfg;
time = outputs{1}.time;

scenarioTitle = sprintf( ...
    'Load %.2f, Configured PU Duty %.0f%%', ...
    cfg.offeredLoad, 100 * cfg.puDutyCycle);

%% Full-run queue comparison

fig = figure('Visible', visibility, 'Color', 'w');
ax = axes('Parent', fig);
hold(ax, 'on');

for j = 1:3

    drawQueue(ax, time, outputs{j}.queue, ...
        colors(j, :), styles{j}, useTransparency);

end

grid(ax, 'on');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Relay queue length (packets)');
ylim(ax, [0 cfg.queueCapacity]);

title(ax, ['Queue Occupancy: ' scenarioTitle]);
legend(ax, names, 'Location', 'best');

savePlot(fig, outputFolder, ...
    'queue_comparison_full', showFigures);

%% Short-window queue comparison

mask = time >= zoomWindow_s(1) & ...
       time <= zoomWindow_s(2);

if nnz(mask) >= 2

    fig = figure('Visible', visibility, 'Color', 'w');
    ax = axes('Parent', fig);
    hold(ax, 'on');

    for j = 1:3

        drawQueue(ax, time(mask), outputs{j}.queue(mask), ...
            colors(j, :), styles{j}, useTransparency);

    end

    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Relay queue length (packets)');

    xlim(ax, zoomWindow_s);
    ylim(ax, [0 cfg.queueCapacity]);

    title(ax, ['Queue Occupancy, Short Window: ' scenarioTitle]);

    legend(ax, names, 'Location', 'best');

    savePlot(fig, outputFolder, ...
        'queue_comparison_zoom', showFigures);

end

%% Average queue: RED and PA-AQM only

fig = figure('Visible', visibility, 'Color', 'w');
hold on;

plot(time, outputs{2}.avgQueue, ...
    'Color', colors(2, :), ...
    'LineStyle', styles{2}, ...
    'LineWidth', 1.2);

plot(time, outputs{3}.avgQueue, ...
    'Color', colors(3, :), ...
    'LineStyle', styles{3}, ...
    'LineWidth', 1.2);

grid on;
xlabel('Time (s)');
ylabel('Smoothed queue (packets)');
ylim([0 cfg.queueCapacity]);

title(['Smoothed Queue: ' scenarioTitle]);
legend({'RED', 'PA-AQM'}, 'Location', 'best');

savePlot(fig, outputFolder, ...
    'smoothed_queue_comparison', showFigures);

%% Delivered-delay cumulative distributions

fig = figure('Visible', visibility, 'Color', 'w');
hold on;

handles = gobjects(0);
delayNames = {};

for j = 1:3

    delays = outputs{j}.deliveredDelay_s;

    if isempty(delays)
        continue;
    end

    delays_ms = sort(delays(:) * 1000);

    % Exact empirical cumulative distribution at distinct delays.
    [uniqueDelay, ~, group] = unique(delays_ms);
    counts = accumarray(group, 1);
    cumulativeFraction = cumsum(counts) / numel(delays_ms);

    h = stairs(uniqueDelay, cumulativeFraction, ...
        'Color', colors(j, :), ...
        'LineStyle', styles{j}, ...
        'LineWidth', 1.5);

    handles(end+1) = h;
    delayNames{end+1} = names{j};

end

grid on;
xlabel('Delivered-packet relay delay (ms)');
ylabel('Cumulative fraction');
ylim([0 1]);

title(['Delivered-Delay Distribution: ' scenarioTitle]);

if ~isempty(handles)
    legend(handles, delayNames, 'Location', 'best');
end

savePlot(fig, outputFolder, ...
    'delivered_delay_cdf', showFigures);

%% PA-AQM states remain separate

pa = outputs{3};

fig = figure('Visible', visibility, 'Color', 'w');

stairs(time, pa.paStateTrace, ...
    'Color', colors(3, :), ...
    'LineWidth', 1.2);

grid on;
xlabel('Time (s)');
ylabel('PA-AQM state');

yticks([1 2 3]);
yticklabels({'NORMAL', 'HOLD', 'RECOVERY'});
ylim([0.8 3.2]);

title(['PA-AQM State: ' scenarioTitle]);

savePlot(fig, outputFolder, ...
    'paaqm_state', showFigures);

end

%% Local plotting helpers

function drawQueue(ax, time, queue, color, style, useTransparency)

if useTransparency

    % Two identical rows form a zero-width surface.
    % Its row edges provide translucent traces.
    x = time(:)';
    y = queue(:)';

    surface(ax, ...
        [x; x], ...
        [y; y], ...
        zeros(2, numel(x)), ...
        'FaceColor', 'none', ...
        'EdgeColor', color, ...
        'EdgeAlpha', 0.55, ...
        'MeshStyle', 'row', ...
        'LineStyle', style, ...
        'LineWidth', 1.0);

    view(ax, 2);

else

    plot(ax, time, queue, ...
        'Color', color, ...
        'LineStyle', style, ...
        'LineWidth', 1.0);

end

end

function savePlot(fig, folder, name, keepOpen)

drawnow;

savefig(fig, fullfile(folder, [name '.fig']));

print(fig, fullfile(folder, [name '.png']), ...
    '-dpng', '-r200');

if ~keepOpen
    close(fig);
end

end