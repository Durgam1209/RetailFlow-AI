# Architecture and daily insights contract

## Data flow

1. The Flutter POS records sales and can queue transactions in Hive while offline. When online, it syncs them to Supabase `sales_log`.
2. The nightly GitHub Actions workflow installs the pinned Python dependencies, runs tests/lint, then runs `ml_pipeline/enrich_data.py` and `ml_pipeline/main.py`. Supabase URL and keys come from Actions Secrets. The service role credential is used only by this backend workflow for insight writes.
3. Enrichment fetches the sales snapshot and adds Indian holiday flags. It exports the snapshot for reproducibility. Historical weather is not merged into model training. Separately, the insight formatter requests a weather forecast for advice, using cached data when available; weather unavailability is logged and can degrade the run.
4. The pipeline validates sales fields and transaction IDs, removes duplicate IDs, and excludes negative totals and negative item quantity/price lines from demand with warnings. It then runs Apriori basket analysis and aggregate demand forecasting.
5. Item metrics use a chronological last-seven-day holdout. Prophet is trained on dates before the holdout and compared with the previous week's same weekdays. Sparse items receive a cold-start label. The aggregate forecast used to format stock advice is fit on the available history; the per-item evaluation currently does not choose which model to serve.
6. The pipeline formats recommendations, validates the object against `ml_pipeline/schemas/daily_insights.schema.json`, and inserts it into Supabase `daily_insights`. Flutter reads the latest insight using the public publishable/anon key.

## `daily_insights` version 1.0

The JSON Schema is authoritative and rejects unrecognized properties. The root object requires:

| Field | Type | Purpose |
|---|---|---|
| `schema_version` | string, fixed to `1.0` | Lets clients identify the payload shape. |
| `forecast_summary` | non-empty string | Short human-readable demand summary. |
| `suggested_bundles` | array | Basket rules with item pair, confidence, lift, support counts, strength, and advice. |
| `stock_advice` | array | Daily forecast and stock suggestion, uncertainty bounds, labels, action, and optional per-fruit breakdown. |
| `festival_advice` | object | Holiday-related recommendation; may be empty. |
| `weather_advice` | object | Forecast weather context and advice; may be empty. |
| `created_at` | date-time string | UTC creation timestamp. |

Each `stock_advice` entry includes `date`, `display_date`, `predicted_demand`, `suggested_stock`, `lower_bound`, `expected_revenue`, confidence/demand/range labels, an `action`, and `top_fruits`. Per-fruit entries include the fruit name, suggested kilograms, expected revenue, festival/weather flags, and display labels. Bundle entries include `pair_1`, `pair_2`, `title`, `confidence`, `raw_confidence`, `confidence_percent`, `lift`, `pair_count`, `antecedent_count`, `strength`, and `advice`. See the schema for required types and bounds.

The contract does not currently include `recommended_order_qty` or a cost-aware quantile. Such a field must be added to the schema and the formatter before clients can rely on it.

## Forecast metric meanings

| Metric | Meaning |
|---|---|
| MAE | Average absolute forecast miss, in kilograms. |
| MSE | Average squared miss, in kg²; large errors count more. |
| RMSE | Square root of MSE, in kilograms. |
| WAPE | Sum of absolute misses divided by sum of actual sales, as a percentage. It is defined when individual days have zero sales, provided total actual sales is nonzero. |
| Bias | Mean `forecast - actual`, in kilograms. Positive is over-forecasting; negative is under-forecasting. |
| Baseline | For holdout evaluation, repeats the sales from the same weekday in the prior week. `beats_baseline` currently means Prophet's MAE is lower. |

The evaluator also has a separate recent-sales weighted-average fallback for sparse aggregate history. That fallback is not the same as the unevaluated 7-day moving-average baseline requested for per-item comparisons.

`performance_history.csv` is append-only at run granularity. New rows carry aggregate metrics and an `item_metrics` JSON string keyed by item with baseline/Prophet scores, history counts, and cold-start status where available. Older rows remain valid and can have blank cells for fields introduced later. `mae_kg`/`mse_kg2`/`rmse_kg` and WAPE/bias are averages or pooled calculations over evaluated items; the file is not one row per SKU.

## Evaluation and monitoring gaps

- The holdout is chronological and does not enter the per-item Prophet fit, but it is a fixed final seven-day split rather than rolling-origin cross-validation.
- Only the same-weekday-last-week baseline is scored. A 7-day moving-average baseline is not currently scored.
- Per-item `beats_baseline` is logged for comparison, but no per-item baseline selection is used for the production forecast.
- The regression alert currently compares aggregate MAE with the trailing run average and marks the run degraded. It does not gate publishing or preserve the previous insight for a regressed item.
- Returns and voids have no explicit schema marker. Negative totals/lines are excluded as a temporary heuristic and counted in validation warnings.
- The project targets one store and has no multi-location, ERP, or external POS integration.
