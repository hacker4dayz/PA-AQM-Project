# PA-AQM: PU-Aware Adaptive Queue Management for Cognitive Radio Relays

MATLAB simulator, scripts and results for the paper *PU-Aware Adaptive Queue Management for Cognitive Radio Networks Under Imperfect Spectrum Sensing*.

**Team:** Leroy Malcolm, Selam Kelil, and Nakira Oglesby  
**Course:** EE 6760 — Applied Communication Systems, Kennesaw State University  
**Instructor:** Dr. Sumit Chakravarty

## Overview

PA-AQM extends simplified Random Early Detection (RED) at a finite-buffer secondary-user relay. While sensing reports an active primary user (PU), it freezes the smoothed queue estimate and suspends early dropping. Overflow protection stays active in every state. Thresholds and recovery duration are chosen by a constrained selection procedure on tuning data, then evaluated with frozen settings on held-out regimes.

## Main result

On 96 held-out load, sensing-error and burst regimes (20 seeds each):

| Method | Mean delay (ms) | PDR | Mean queue (packets) |
|---|---:|---:|---:|
| Drop-tail | 541.6 | 0.4460 | 26.65 |
| Tuned RED (R10: alpha 0.50, beta 0.85) | 517.3 | 0.4445 | 24.99 |
| PA-AQM (P02: alpha 0.30, beta 0.60, recovery 0 s) | 493.8 | 0.4427 | 23.42 |

A delay claim meets every guard in 77 of 96 regimes, is infeasible (a guard is violated) in 10 Poisson regimes, and shows no significant delay gain in 9 regimes. The gain is concentrated in Poisson traffic. The PU-overlap measure is a simulation proxy, not measured PU interference.

## Repository contents

### Simulator and controllers

| File | Purpose |
|---|---|
| `simulate_crn.m` | Queue, transmission, loss and delay simulation |
| `queue_droptail.m`, `queue_red.m`, `queue_paaqm.m` | Drop-tail, simplified RED and PA-AQM admission |
| `generate_arrivals.m` | Poisson and ON/OFF packet arrivals |
| `generate_pu_trace.m` | Actual PU activity |
| `generate_sensed_pu_trace.m` | Sensing decisions and reserved sensing slots |
| `config_default.m` | Default parameters (also called by `config_final.m`) |
| `config_final.m` | Final-study settings |

### Final study (run in this order)

| Step | File | Purpose |
|---|---|---|
| 1 | `make_final_plan.m` | Saves `final_study_plan.mat` (parameters, regimes, seeds, guards) |
| 2 | `run_final_tuning.m` | Runs the 37 original settings on the 12 tuning regimes |
| 3 | `screen_red_tuning.m` | Screens RED candidates against the guards (no simulations) |
| 4 | `make_expanded_tuning_plan.m`, `run_expanded_tuning.m` | Adds and runs 12 extra candidates after no original RED candidate was feasible |
| 5 | `run_final_evaluation.m` | Runs drop-tail, R10 and P02 on the 96 held-out regimes |
| 6 | `run_sensitivity_checks.m` | Time-step convergence and mechanism ablation |

Helpers: `build_final_inputs.m` (derived settings and shared input traces) and `run_final_case.m` (one controller run with validation checks).

### Plots and figures

`plot_fig5.m` and `plot_figs_3_4_6.m` draw Figs. 3 to 6 from `evaluation_runs.csv`. Each asks you to select that file and saves PNG files to the current folder. The figures used in the paper are in `Figures/`.

### Tests

`test_paaqm.m` and `test_paaqm_adaptive.m` check controller transitions, blocked service, packet conservation, nominal capacity, collision accounting and sensing-grid validation. Run them before the experiments.

### Exploratory earlier batch

A first batch with a single reference configuration and untuned parameters (771 settings, 46,260 runs). It is not used for the reported results: `run_paaqm_batch.m`, `run_pilot.m`, `run_sensing_sweep.m`, `plot_paaqm_scenario.m`, `experiment_plan.mat`, `all_runs_with_metadata.csv`, `summary_across_seeds.csv`, `sensing_period_summary.csv`.

## Requirements

MATLAB R2024b. Keep all `.m` files and `final_study_plan.mat` in one folder and make it the current MATLAB folder. The scripts load the plan by name and write their output to a `results/` folder.

## Study design

- Link 1 Mb/s, 1,000-byte packets, buffer B = 50, 300 s runs, 1 ms step.
- PU activity: random ON/OFF, 30% duty cycle, 2 s mean ON time.
- Sensing: 20 ms period, 5 ms reserved sensing duration.
- RED thresholds are fractions of the buffer: q_min = alpha B, q_max = beta B.
- Tuning: seeds 2001-2010; loads 0.55, 0.85, 1.20; Pd 0.85, 1.00; Pf 0.10; Poisson and short bursts (12 regimes).
- Held-out: seeds 3001-3020; loads 0.40, 0.70, 1.00, 1.30; Pd 0.70-1.00; Pf 0, 0.10; Poisson, short and long bursts (96 regimes).
- Sensitivity checks: seeds 4001-4010; 12 held-out regimes; no retuning.
- No original RED candidate satisfied every guard, so the search was extended once during tuning (candidates R10-R12 and P28-P36) before any held-out run.

## Reproducing the results

Run each script with `true` first (smoke test), then with `false` (full run).

```matlab
test_paaqm
test_paaqm_adaptive
make_final_plan
run_final_tuning(false)
screen_red_tuning                 % select the FULL tuning_runs.csv
make_expanded_tuning_plan
run_expanded_tuning(false)
run_final_evaluation(false)
run_sensitivity_checks(false)
plot_fig5
plot_figs_3_4_6
```

Smoke-test output must not be used in results. Held-out seeds must not be used for retuning.

## Results

`results_gh/runs/` holds the committed full runs with their settings:

| Folder | Content |
|---|---|
| `final_tuning_FULL_20261124_155348` | 37 original settings x 12 regimes x 10 seeds (4,440 runs); RED screening evidence (`red_screening_summary.csv`, `red_paired_guard_details.csv`, `red_selection_status.csv`); the nested expanded plan and expanded tuning run (12 added candidates, 1,440 runs, with drop-tail reproduction checks) |
| `final_evaluation_FULL_*` | Drop-tail, R10 and P02 on 96 regimes x 20 seeds (5,760 runs) and the frozen settings |
| `sensitivity_FULL_*` | Time-step convergence and mechanism ablation (1,080 runs) |

The CSV files directly in `results_gh/` are copies of the run files. Each run row records the regime, seed, controller, parameters, packet counts, PDR, delay, queue, overlap proxy and validation diagnostics.

## Validation

Each run asserts packet conservation, queue bounds, service-budget compliance and zero transmissions in sensing or sensed-busy steps. All diagnostics are zero in every tuning, held-out and sensitivity run.

## Limitations

One relay, a single flow, one buffer size (B = 50), one PU duty cycle and sensing period, and statistical sensing errors. The PU-overlap measure depends on the time step and does not measure RF interference. Delay covers delivered packets only.

## Citation

L. Malcolm, S. Kelil and N. Oglesby, PA-AQM project repository, 2026. https://github.com/hacker4dayz/PA-AQM-Project
