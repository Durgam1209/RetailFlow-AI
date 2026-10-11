# Daily insights setup and troubleshooting

## Set up Supabase

Run `sql/setup_daily_insights_table.sql` in the Supabase SQL Editor. It creates `public.daily_insights`, enables row-level security, and grants the public `anon` role read access to insights. The pipeline's nightly GitHub Actions job writes using the `SUPABASE_SERVICE_ROLE_KEY` Actions Secret, which bypasses RLS as a privileged backend credential. Never put that key in `ml_pipeline/.env`, Flutter configuration, or committed files.

The pipeline's local `.env` uses `SUPABASE_URL` and `SUPABASE_KEY` (publishable or legacy anon key), plus optional `WEATHER_KEY`. Copy `ml_pipeline/.env.example` as a starting point. Local writes remain subject to RLS. To run a privileged publish, use the GitHub Actions **Nightly ML retrain** workflow and its repository secrets.

Required GitHub Actions secrets for nightly runs:

- `SUPABASE_URL`
- `SUPABASE_KEY` (publishable or legacy anon key, used to fetch data)
- `SUPABASE_SERVICE_ROLE_KEY` (backend insert credential)
- `WEATHER_KEY` (optional)

`ALERT_SLACK_WEBHOOK_URL` is optional; add it to enable Slack failure notifications.

## Verify insights

After dispatching **Nightly ML retrain** from the GitHub Actions tab, check the job log and the `daily_insights` table. The Flutter app reads that table with its publishable key. The JSON payload must satisfy [the versioned schema](ml_pipeline/schemas/daily_insights.schema.json); the current version is `1.0`.

## Troubleshooting

### The app says “No AI insights available yet”

The table may be empty or the app may be querying the wrong project. Check that the workflow completed, that a recent row exists in `daily_insights`, and that the Flutter URL and publishable key match that Supabase project.

### Flutter reports an RLS error when reading insights

Confirm `daily_insights` has RLS enabled, an `anon` SELECT policy, and a SELECT grant. The setup script creates the intended read policy for this non-customer-facing recommendation data. Do not use the public policy as a template for raw sales tables.

### The nightly job reports an insert/RLS error

Check that the repository's `SUPABASE_SERVICE_ROLE_KEY` Actions Secret contains the current service role key, and that the retrain workflow maps it to the same environment variable. Rerun the workflow after correcting it. Do not fix this by adding the service key to a local env file or by making the sales tables publicly writable.

### Weather advice is missing or stale

Weather is optional. Check that `WEATHER_KEY` is configured and that the API is reachable. The pipeline uses a recent cached forecast when possible and warns when usable weather data is unavailable; forecasting can continue without it.

## Reading forecast metrics

The per-item holdout compares Prophet with a naive forecast that repeats sales from the same weekday in the previous week. The last seven chronological days are held out from Prophet fitting. MAE is the average absolute miss in kilograms; RMSE is also in kilograms and gives larger misses more weight. WAPE is the share of actual sales represented by total absolute error (lower is better and it works when some days have zero sales). Bias is the average `forecast - actual` in kilograms: a positive value indicates over-forecasting; a negative value indicates under-forecasting. `beats_baseline` means Prophet had lower MAE than the naive forecast on that holdout.

Current limits: the 7-day moving-average baseline and per-item production fallback selection are not implemented. Per-item metrics are nested in the history record rather than one CSV row per SKU. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full record shape and known gaps.

## Run locally

From the repository root, install dependencies and run:

```sh
python -m pip install -r ml_pipeline/requirements-dev.txt
python -m pytest ml_pipeline/tests -q
python -m ruff check ml_pipeline
python ml_pipeline/enrich_data.py
python ml_pipeline/main.py
```

Or build and run the same pipeline container:

```sh
docker build -f ml_pipeline/Dockerfile -t retailflow-ml .
docker run --rm --env-file ml_pipeline/.env retailflow-ml
```

The local env file must contain no service role key.
