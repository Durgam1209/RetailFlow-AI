# RetailFlow AI

RetailFlow AI combines an offline-first Flutter point-of-sale app with a Python pipeline for sales validation, demand forecasting, basket analysis, and daily recommendations for a small fruit shop.

**Live app:** [retail-flow-ai-fb-hosting66.web.app](https://retailflow-ai-fb-hosting66.web.app/)

## What it does

- The Flutter app caches checkout transactions in Hive and syncs them to Supabase when connectivity returns.
- Supabase stores sales and serves the dashboard's aggregate views and `daily_insights` records.
- The Python pipeline enriches sales dates with Indian holiday flags, computes basket rules, evaluates item demand forecasts on a chronological holdout, and publishes a schema-validated daily insight.
- GitHub Actions runs CI, nightly retraining, and Firebase Hosting deployment in separate workflows.

## Data flow

```text
Flutter POS → local Hive queue → Supabase sales_log
                                  ↓ nightly GitHub Actions
                   validate sales + holiday context
                      ↙                     ↘
                Apriori rules        Prophet / fallback forecast
                      ↘                     ↙
                 JSON Schema validation → daily_insights
                                            ↓
                                      Flutter dashboard
```

Weather is optional. The pipeline uses a weather API forecast for weather advice when available; historical weather is not currently merged into the model's training features. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the payload contract and details.

## Setup

1. In Supabase SQL Editor, run `sql/supabase_sales_log.sql` and `sql/setup_daily_insights_table.sql`. Review `sql/harden_rls.sql` for your deployment before applying it.
2. For local Python runs, copy `ml_pipeline/.env.example` to `ml_pipeline/.env`, then set `SUPABASE_URL`, `SUPABASE_KEY` (publishable or legacy anon key), and optionally `WEATHER_KEY`. **Never place a service role key in a local env file or client build.** The nightly workflow uses the `SUPABASE_SERVICE_ROLE_KEY` GitHub Actions Secret for protected writes.
3. Configure the Flutter app with its public Supabase URL and publishable key:

   ```sh
   cd murali_fruits_ml
   flutter run --dart-define=SUPABASE_URL=https://your-project-id.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
   ```

To run the pipeline locally, from the repository root:

```sh
python -m pip install -r ml_pipeline/requirements.txt
python ml_pipeline/enrich_data.py
python ml_pipeline/main.py
```

## Forecast metrics

Forecast metrics are calculated per item using the final seven chronological days as a holdout: those dates are excluded from that item's Prophet training data. The comparison is a same-weekday-last-week naive forecast. MAE and RMSE are expressed in kilograms; RMSE penalizes larger misses more. WAPE is total absolute error divided by total actual sales, shown as a percentage; unlike MAPE, it handles zero-sale days. Bias is the average signed error (`forecast - actual`): positive means over-forecasting, negative means under-forecasting. `beats_baseline` compares Prophet and the naive forecast by MAE.

The current evaluator does not yet calculate a 7-day moving-average baseline, choose and serve a per-item baseline forecast, or write all item metrics as separate CSV rows. Item holdout metrics are nested in the run's `item_metrics` JSON field, alongside aggregate run metrics. Regression monitoring uses the configured `METRIC_REGRESSION_THRESHOLD` and the performance history. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for limitations and field definitions.

## Configuration

Copy `.env.example` as described above. Forecast history defaults are 28 calendar days and 7 non-zero days per item; sparse items use a cold-start fallback. `SHOP_CLOSED_DATES` accepts comma-separated `YYYY-MM-DD` dates. Basket defaults require 20 transactions, support count 3, and lift 1.2. `METRIC_REGRESSION_THRESHOLD` defaults to `0.25` (25%); `ML_RANDOM_SEED` defaults to `42`; `PIPELINE_LOG_LEVEL` defaults to `INFO`. Weather and Supabase timeout/retry settings are defined in `ml_pipeline/config.py`.

## Tests and lint

```sh
python -m pip install -r ml_pipeline/requirements-dev.txt
python -m pytest ml_pipeline/tests -q
python -m ruff check ml_pipeline
```

Flutter checks (with Flutter SDK installed):

```sh
cd murali_fruits_ml
flutter test
flutter analyze
```

## Docker

From the repository root, build and run with a configured local env file:

```sh
docker build -f ml_pipeline/Dockerfile -t retailflow-ml .
docker run --rm --env-file ml_pipeline/.env retailflow-ml
```

The container runs enrichment then forecasting/publishing. Keep the service role key out of `.env`; the local public key can only perform actions allowed by RLS.

## Known limitations

- The app and pipeline assume one store. Multi-location inventory and forecasting are not supported.
- There are no ERP or external POS integrations; sales enter through this app and its Supabase schema.
- The sales schema has no explicit return/void marker. Negative quantity or price lines and negative-total transactions are currently excluded from demand and logged as validation warnings; returns cannot be classified independently from voids.
- Per-item model selection and fallback serving are not implemented yet. Holdout metrics currently compare Prophet against same-weekday-last-week by MAE; they do not select the winning baseline for production forecasts.
- Weather advice depends on optional external forecast data and may be omitted or marked stale when unavailable.

## Repository map

- `murali_fruits_ml/`: Flutter POS and dashboard.
- `ml_pipeline/`: Python enrichment, validation, basket analysis, forecasts, tests, configuration, and schema.
- `sql/`: Supabase setup and security scripts.
- `.github/workflows/`: CI, nightly retraining, and deployment workflows.
- `docs/`: architecture, privacy, credentials, and security notes.
