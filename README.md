# PU-Aware Adaptive Queue Management (PA-AQM)

MATLAB project comparing **PA-AQM**, drop-tail, and simplified RED in a cognitive-radio relay network.

**Team:** Leroy Malcolm, Selam Kelil, and Nakira Oglesby  
**Course:** EE 6760 — Applied Communication Systems  
**Instructor:** Dr. Sumit Chakravarty

## Project Goal

Primary-user activity interrupts relay transmissions while packets continue arriving. PA-AQM uses the sensed primary-user state to adjust packet admission and investigate the tradeoff between packet delivery and queueing delay.

## How PA-AQM Works

- **NORMAL:** Apply simplified RED.
- **HOLD:** When sensing reports an active primary user, freeze the average queue and suspend early dropping.
- **Overflow protection:** Remains active in every state.
- **Optional RECOVERY:** Gradually restore RED after HOLD.

The main evaluated configuration uses zero recovery duration, returning directly from HOLD to NORMAL.

## Main Files

| File | Purpose |
|---|---|
| `config_default.m` | Default parameters |
| `generate_arrivals.m` | Packet arrivals |
| `generate_pu_trace.m` | Actual primary-user activity |
| `generate_sensed_pu_trace.m` | Sensing decisions and reserved sensing slots |
| `queue_droptail.m` | Drop-tail admission |
| `queue_red.m` | Simplified RED admission |
| `queue_paaqm.m` | PA-AQM admission |
| `simulate_crn.m` | Queue, transmission, loss, and delay simulation |
| `run_paaqm_batch.m` | Batch experiments and result export |
| `plot_paaqm_scenario.m` | Controller comparison plots |
| `test_paaqm.m` | Controller and service checks |
| `test_paaqm_adaptive.m` | Additional transition and FIFO-delay checks |

## How to Run

Place the MATLAB files in the same folder and make it the current MATLAB folder.

First run:

```matlab
test_paaqm
test_paaqm_adaptive
```

Then open `run_paaqm_batch.m` and start with:

```matlab
smokeTest = true;
```

Run:

```matlab
run_paaqm_batch
```

For the complete 20-seed experiment, change:

```matlab
smokeTest = false;
experimentMode = "full";
plannedSeeds = 1001:1020;
```

## Experiment Settings

| Parameter | Values |
|---|---|
| Duration / time step | 300 s / 1 ms |
| Link rate / packet size | 1 Mbps / 1,000 bytes |
| Buffer capacity | 25, 50, 100 packets |
| Offered-load ratio | 0.40, 0.70, 1.00, 1.30 |
| PU duty cycle | 0%, 10%, 30%, 50% |
| Detection probability | 0.70, 0.85, 0.95, 1.00 |
| False-alarm probability | 0, 0.05, 0.10, 0.20 |
| Reference sensing period / duration | 20 ms / 5 ms |
| Sensing-period sweep | 20, 50, 100, 500 ms |
| Repetitions | 20 seeds per configuration |

Controllers share the input traces within each comparison. The full batch contains 46,260 controller runs.

## Results

Start with these files:

- `all_runs_with_metadata.csv` — individual runs and settings.
- `summary_across_seeds.csv` — averages and confidence intervals.
- `sensing_period_summary.csv` — sensing-period comparison.

The results include throughput, packet delivery ratio, early drops, overflow drops, collision losses, queue occupancy, and delivered-packet delay.

Preliminary findings show a tradeoff: PA-AQM improves delivery relative to RED in examined reference cases. Under high-load reference conditions, it matches drop-tail delivery while reducing mean delivered delay. It does not outperform both baselines on every metric.

## Validation and Limitations

All uploaded runs passed spreadsheet packet-conservation checks. MATLAB test results should also be retained.

The model uses one source, one relay, fixed-rate Poisson traffic, and statistical sensing, not a waveform detector. Delay includes successfully delivered packets only and must be interpreted alongside delivery and loss.

## Reproducibility

Retain the source version, `experiment_plan.mat`, exported figures, and test log associated with the paper.
