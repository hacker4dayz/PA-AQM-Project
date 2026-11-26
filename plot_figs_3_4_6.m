% Figures 3, 4 and 6 from the held-out results (evaluation_runs.csv).
clear; clc; close all;

[f, p] = uigetfile('evaluation_runs.csv', 'Select evaluation_runs.csv');
assert(~isequal(f,0), 'No file selected.');
H = readtable(fullfile(p, f), 'TextType', 'string');
H.IsOverload = logical(H.IsOverload);

methods = ["DT","R10","P02"];
mLabel  = ["Drop-tail","RED (R10)","PA-AQM (P02)"];
mColor  = [0.12 0.47 0.71; 0.85 0.37 0.01; 0.48 0.20 0.58];
types   = ["poisson","short_bursts","long_bursts"];
tLabel  = ["Poisson","Short bursts","Long bursts"];
tcrit   = 2.0930;                        % t value, 95%, 19 degrees of freedom
fontName = 'Times New Roman';

%% Figure 3: delay and PDR vs offered load
S = groupsummary(H, {'Seed','TrafficRegime','OfferedLoad','CandidateID'}, ...
    'mean', {'MeanDeliveredDelay_ms','PDR'});
loads = unique(H.OfferedLoad)';
fields = {'mean_MeanDeliveredDelay_ms','mean_PDR'};
yLab   = {'Mean delivered delay (ms)','Packet delivery ratio'};

fig3 = figure('Color','w','Position',[100 100 1250 650]);
tl = tiledlayout(fig3, 2, 3, 'TileSpacing','compact','Padding','compact');
ax3 = gobjects(2,3);
for i = 1:2
    for j = 1:3
        ax3(i,j) = nexttile(tl); hold(ax3(i,j),'on'); box(ax3(i,j),'on'); grid(ax3(i,j),'on');
        for m = 1:3
            mu = zeros(size(loads)); er = zeros(size(loads));
            for q = 1:numel(loads)
                idx = S.TrafficRegime==types(j) & S.CandidateID==methods(m) & S.OfferedLoad==loads(q);
                v = S.(fields{i})(idx);
                mu(q) = mean(v); er(q) = tcrit*std(v)/sqrt(numel(v));
            end
            errorbar(ax3(i,j), loads, mu, er, '-o', 'Color', mColor(m,:), ...
                'MarkerFaceColor', mColor(m,:), 'MarkerSize', 5, 'LineWidth', 1.2, ...
                'CapSize', 4, 'DisplayName', mLabel(m));
        end
        xticks(ax3(i,j), loads);
        if i == 1, title(ax3(i,j), tLabel(j)); end
        if i == 2, xlabel(ax3(i,j), 'Nominal offered-load ratio'); end
        if j == 1, ylabel(ax3(i,j), yLab{i}); end
    end
end
legend(ax3(1,1), 'Location','northwest');
set(ax3(:), 'FontName', fontName, 'FontSize', 11);
exportgraphics(fig3, 'fig3_delay_pdr_vs_load_matlab.png', 'Resolution', 300, 'BackgroundColor', 'white');

%% Figure 4: feasibility map for PA-AQM
regs = unique(H.RegimeID, 'stable');
pds = [0.70 0.85 0.95 1.00];  lds = [0.4 0.7 1.0 1.3];
cls = zeros(numel(regs),1);            % 1 valid, 2 infeasible (guard violated), 3 no delay gain
info = table(regs, 'VariableNames', {'RegimeID'});
info.Load = zeros(numel(regs),1); info.Pd = info.Load; info.Pf = info.Load;
info.Traffic = strings(numel(regs),1);
for r = 1:numel(regs)
    row = H(find(H.RegimeID==regs(r),1),:);
    info.Load(r) = row.OfferedLoad; info.Pd(r) = row.Pd; info.Pf(r) = row.Pf;
    info.Traffic(r) = row.TrafficRegime;
    g = @(m,v) getv(H, regs(r), m, v);
    [~, hiDelay]   = tci(g("P02",'MeanDeliveredDelay_ms') - g("DT",'MeanDeliveredDelay_ms'), tcrit);
    [loPDR, ~]     = tci(g("P02",'PDR') - g("DT",'PDR'), tcrit);
    [~, hiQueue]   = tci(g("P02",'MeanQueue_packets') - 1.05*g("R10",'MeanQueue_packets'), tcrit);
    [~, hiOverlap] = tci(g("P02",'PUTransmitOverlapFrac') - g("R10",'PUTransmitOverlapFrac'), tcrit);
    feasible = loPDR >= -0.01 && hiQueue <= 0 && hiOverlap <= 0.001;
    if row.IsOverload
        [loOver, ~] = tci(g("P02",'PDR') - g("R10",'PDR'), tcrit);
        feasible = feasible && loOver >= -0.01;
    end
    gain = hiDelay < 0;
    if gain && feasible, cls(r) = 1; elseif gain, cls(r) = 2; else, cls(r) = 3; end
end
fprintf('Fig. 4 counts: valid %d, infeasible %d, no delay gain %d\n', ...
    sum(cls==1), sum(cls==2), sum(cls==3));
cMap = [0.17 0.63 0.17; 0.84 0.15 0.16; 0.74 0.74 0.74];
cName = ["Valid delay claim","Infeasible (guard violated)","Feasible, no delay gain"];

fig4 = figure('Color','w','Position',[100 100 1250 720]);
tl4 = tiledlayout(fig4, 2, 3, 'TileSpacing','compact','Padding','compact');
pfs = [0 0.1];
for i = 1:2
    for j = 1:3
        ax = nexttile(tl4); hold(ax,'on'); box(ax,'on');
        sel = find(info.Traffic==types(j) & abs(info.Pf-pfs(i))<1e-9);
        for s = sel'
            x = find(abs(pds-info.Pd(s))<1e-9);  y = find(abs(lds-info.Load(s))<1e-9);
            rectangle(ax, 'Position',[x-0.45 y-0.45 0.9 0.9], ...
                'FaceColor', cMap(cls(s),:), 'EdgeColor','none');
        end
        xlim(ax,[0.5 4.5]); ylim(ax,[0.5 4.5]);
        xticks(ax,1:4); xticklabels(ax, string(pds));
        yticks(ax,1:4); yticklabels(ax, string(lds));
        xlabel(ax,'Detection probability P_d'); ylabel(ax,'Offered load');
        title(ax, sprintf('%s, P_f = %g', tLabel(j), pfs(i)));
        set(ax,'FontName',fontName,'FontSize',11,'Layer','top');
        if i == 1 && j == 1
            hp = gobjects(1,3);
            for c = 1:3, hp(c) = patch(ax, NaN, NaN, cMap(c,:)); end
            lgd = legend(ax, hp, cName, 'Orientation','horizontal');
            lgd.Layout.Tile = 'south';
        end
    end
end
exportgraphics(fig4, 'fig4_feasibility_map_matlab.png', 'Resolution', 300, 'BackgroundColor', 'white');

%% Figure 6: loss composition at load 1.3
H13 = H(H.OfferedLoad == 1.3,:);
parts = zeros(3,3);                    % rows: methods, columns: early, overflow, collision
for m = 1:3
    rr = H13(H13.CandidateID==methods(m),:);
    gen = sum(rr.GeneratedPackets);
    parts(m,:) = 100*[sum(rr.EarlyDrops) sum(rr.OverflowDrops) sum(rr.CollisionLosses)]/gen;
end
fig6 = figure('Color','w','Position',[100 100 600 480]);
ax6 = axes(fig6); hold(ax6,'on'); box(ax6,'on');
b = bar(ax6, categorical(mLabel, mLabel), parts, 'stacked');
b(1).FaceColor = [0.30 0.47 0.65]; b(2).FaceColor = [0.96 0.52 0.09]; b(3).FaceColor = [0.70 0.13 0.13];
tot = sum(parts,2);
cum = cumsum(parts,2);                     % top edge of each segment
bottoms = [zeros(3,1) cum(:,1:2)];         % bottom edge of each segment
for m = 1:3
    for k = 1:3
        val = parts(m,k);
        if val < 0.05, continue; end       % skip empty segments
        yMid = bottoms(m,k) + val/2;
        if val >= 4
            text(ax6, m, yMid, sprintf('%.1f%%', val), 'HorizontalAlignment','center', ...
                'VerticalAlignment','middle','Color','w','FontWeight','bold', ...
                'FontName',fontName,'FontSize',10);
        else
            text(ax6, m+0.30, yMid, sprintf('%.1f%%', val), 'HorizontalAlignment','left', ...
                'VerticalAlignment','middle','Color','k','FontName',fontName,'FontSize',10);
        end
    end
    text(ax6, m, tot(m)+1.5, sprintf('Total %.1f%%', tot(m)), ...
        'HorizontalAlignment','center','FontName',fontName,'FontWeight','bold');
end
ylabel(ax6,'Generated packets lost (%)'); ylim(ax6,[0 90]);
legend(ax6, {'Early drops','Overflow drops','Collision losses'}, 'Location','southeast');
set(ax6,'FontName',fontName,'FontSize',11);
exportgraphics(fig6, 'fig6_overload_loss_matlab.png', 'Resolution', 300, 'BackgroundColor', 'white');

%% Local functions
function v = getv(H, id, method, field)
    r = H(H.RegimeID==id & H.CandidateID==method, :);
    [~, ix] = sort(r.Seed);
    v = r.(field)(ix);
end

function [lo, hi] = tci(d, tcrit)
    assert(numel(d) == 20, 'Expected 20 paired seeds.');
    m = mean(d);  h = tcrit*std(d)/sqrt(numel(d));
    lo = m - h;  hi = m + h;
end
