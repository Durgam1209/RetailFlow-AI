# RetailFlow AI

An end-to-end retail intelligence platform for small-scale perishable-goods retailers. It pairs an offline-first Flutter POS app with a Python ML pipeline that ingests sales data, applies weather and holiday-aware feature engineering, and generates demand forecasts and product-bundling recommendations — closing the loop between point-of-sale and inventory decisions.

**Live app:** [retail-flow-ai-fb-hosting66.web.app](https://retail-flow-ai-fb-hosting66.web.app/)
**Pipeline status:** ![ML Pipeline](https://github.com/Durgam1209/RetailFlow-AI/actions/workflows/main.yml/badge.svg)

---

## What it does

- **POS app (Flutter):** offline-first checkout that caches transactions locally (Hive) and syncs to Supabase when connectivity returns — built for shop floors with unstable internet.
- **Analytics dashboard:** real-time revenue, checkout volume, and historical sales views rendered from pre-aggregated Supabase views.
- **Demand forecasting:** 7-day ahead forecasts using Facebook Prophet, enriched with weather (OpenWeather API) and Indian holiday calendar signals, with a cold-start fallback for new items.
- **Market basket analysis:** Apriori-based association rule mining (`mlxtend`) surfaces which products are commonly bought together, shown as bundling suggestions.
- **Automated retraining:** nightly GitHub Actions job re-pulls sales data, retrains models, and logs MAE/RMSE to track forecast drift over time — no manual intervention needed.

## Screenshots

| POS Checkout | Custom price Edit | Revenue Dashboard |
|:---:|:---:|:---:|
| <img src="https://raw.githubusercontent.com/Durgam1209/RetailFlow-AI/main/murali_fruits_ml/assets/images/pos_catalog.png" width="230"/>|<img src= "https://github.com/Durgam1209/RetailFlow-AI/raw/main/murali_fruits_ml/assets/images/mlops_pipeline_log.png" width="230"/> | <img src="https://raw.githubusercontent.com/Durgam1209/RetailFlow-AI/main/murali_fruits_ml/assets/images/analytics_revenue.png" width="230"/> | 

| Demand Forecast | Shop Layout Suggestions | Basket Recommendations |
|:---:|:---:|:---:|
| <img src="https://github.com/Durgam1209/RetailFlow-AI/raw/main/murali_fruits_ml/assets/images/ai_predictions.png" width="230"/> |<img src="https://github.com/Durgam1209/RetailFlow-AI/raw/main/murali_fruits_ml/assets/images/shop_layout.png" width="230"/> | <img src="https://github.com/Durgam1209/RetailFlow-AI/raw/main/murali_fruits_ml/assets/images/ai_bundles.png" width="230"/> |

**Pipeline automation:**
![GitHub Actions Workflow Run]
*Nightly job provisioning the environment, pulling data, and checking for model drift.*

---

## Tech stack

**Frontend:** Flutter (web + mobile), Hive (local storage), `fl_chart`, Firebase Hosting
**Backend/Data:** Supabase (PostgreSQL), Python, Pandas, NumPy
**ML:** Facebook Prophet (forecasting), mlxtend (Apriori), `holidays` + OpenWeather API (feature engineering)
**Automation:** GitHub Actions (nightly cron retraining + CI/CD)

## How it fits together

```text
Storefront (Flutter) → Hive local cache (offline-first)
        │ syncs on reconnect
        ▼
Supabase PostgreSQL (raw transactions)
        │ nightly GitHub Actions trigger
        ▼
Python ETL: joins weather + holiday signals
        │
        ▼
Prophet forecast + Apriori basket rules
        │ writes to `daily_insights` table
        ▼
Dashboard reads latest insights → shop floor UI
```

---

## Repository structure

```text
RetailFlowAI/
├── .github/workflows/          # CI/CD: nightly retraining + Firebase deploy
├── ml_pipeline/
│   ├── models/
│   │   ├── basket_analyzer.py  # Apriori association rules
│   │   └── demand_forecaster.py # Prophet forecasting
│   ├── enrich_data.py          # weather + holiday feature engineering
│   ├── main.py                 # pipeline orchestrator
│   └── logs/performance_history.csv  # MAE/RMSE drift tracking
├── murali_fruits_ml/            # Flutter app
│   └── lib/{data,models,widgets}/
└── sql/                          # Supabase schema + views
```

---

## Setup

**1. Database:** run the scripts in `/sql` via the Supabase SQL Editor to create tables and views.

**2. ML pipeline:**
```bash
cd ml_pipeline
python -m pip install -r requirements.txt
```
Create a `.env` in `ml_pipeline/` with your Supabase project URL and an **anon/public key** (never commit or use the service role key here — it bypasses row-level security).

**3. Flutter app:**
```bash
cd murali_fruits_ml
flutter run --dart-define=SUPABASE_URL="https://your-project-id.supabase.co" --dart-define=SUPABASE_ANON_KEY="your-anon-key"
```

**4. Manual deploy (optional, otherwise handled by CI):**
```bash
flutter build web --release --dart-define=SUPABASE_URL="..." --dart-define=SUPABASE_ANON_KEY="..."
firebase deploy --only hosting
```

---

## Notable design decisions

- Aggregations run on the database side (Postgres views) rather than the client, keeping the mobile app lightweight.
- Every retraining run logs MAE/RMSE to `performance_history.csv` so forecast drift is visible over time, not silent.
- Dart models use fallback parsing (`??` defaults) to avoid crashes when older cached records don't match the current schema.
