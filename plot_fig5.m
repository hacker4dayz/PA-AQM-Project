% Figure 5: regime-level guard margins for PA-AQM (held-out results).
clear; clc; close all;
[f, p] = uigetfile('evaluation_runs.csv', 'Select evaluation_runs.csv');
assert(~isequal(f,0), 'No file selected.');
H = readtable(fullfile(p, f), 'TextType', 'string');
G = groupsummary(H, {'RegimeID','CandidateID','TrafficRegime'}, 'mean', ...
    {'PDR','MeanDeliveredDelay_ms','MeanQueue_packets'});

reg = unique(G.RegimeID, 'stable');
n = numel(reg);
dPDR = zeros(n,1); dDelayDT = zeros(n,1);
qContrast = zeros(n,1); dDelayRED = zeros(n,1);
traffic = strings(n,1);

for i = 1:n
    r = G.RegimeID == reg(i);
    get = @(m, v) G.(v)(r & G.CandidateID == m);
    traffic(i) = G.TrafficRegime(find(r,1));
    dPDR(i)      = 100*(get("P02",'mean_PDR') - get("DT",'mean_PDR'));
    dDelayDT(i)  = get("P02",'mean_MeanDeliveredDelay_ms') - get("DT",'mean_MeanDeliveredDelay_ms');
    qContrast(i) = get("P02",'mean_MeanQueue_packets') - 1.05*get("R10",'mean_MeanQueue_packets');
    dDelayRED(i) = get("P02",'mean_MeanDeliveredDelay_ms') - get("R10",'mean_MeanDeliveredDelay_ms');
end

types   = ["poisson","short_bursts","long_bursts"];
labels  = ["Poisson","Short bursts","Long bursts"];
markers = ['o','s','^'];
colors  = [0.12 0.47 0.71; 0.85 0.37 0.01; 0.17 0.63 0.17];

fig = figure('Color','w','Position',[100 100 1200 520]);
tl = tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');

ax1 = nexttile(tl); hold(ax1,'on'); box(ax1,'on'); grid(ax1,'on');
ax2 = nexttile(tl); hold(ax2,'on'); box(ax2,'on'); grid(ax2,'on');
for k = 1:3
    m = traffic == types(k);
    scatter(ax1, dPDR(m), dDelayDT(m), 40, colors(k,:), markers(k), ...
        'filled','MarkerFaceAlpha',0.8,'MarkerEdgeColor','k','DisplayName',labels(k));
    scatter(ax2, qContrast(m), dDelayRED(m), 40, colors(k,:), markers(k), ...
        'filled','MarkerFaceAlpha',0.8,'MarkerEdgeColor','k');
end
xline(ax1,-1,'r--'); yline(ax1,0,'k-');
xline(ax2, 0,'r--'); yline(ax2,0,'k-');
xlabel(ax1,'PDR(PA-AQM) - PDR(drop-tail) (percentage points)');
ylabel(ax1,'Delay change vs drop-tail (ms)'); title(ax1,'(a) Delivery guard');
xlabel(ax2,'Queue(PA-AQM) - 1.05 Queue(RED) (packets)');
ylabel(ax2,'Delay change vs RED (ms)'); title(ax2,'(b) Queue guard');
legend(ax1,'Location','southeast');
set([ax1 ax2],'FontName','Times New Roman','FontSize',11);

exportgraphics(fig,'fig5_guard_scatter_matlab.png','Resolution',300,'BackgroundColor','white');
