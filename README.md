
```markdown
# RetailFlow AI 🚀

An end-to-end, production-grade MLOps retail intelligence platform designed for hyperlocal supply chains and perishable goods micro-retail operations. 

RetailFlow AI transforms manual storefront operations into a data-driven ecosystem. It combines an offline-first Flutter web/mobile application with an automated serverless Python machine learning pipeline that ingests live transactional data, applies environmental and contextual feature engineering, and streams actionable business intelligence straight to the shop floor to systematically mitigate inventory wastage and maximize revenue margins.

---

## 🔗 Production Deployments & Actions
- **Live Production Web Application:** [https://retail-flow-ai-fb-hosting66.web.app/](https://retail-flow-ai-fb-hosting66.web.app/)
- **Automated MLOps Pipeline Status:** ![ML Pipeline](https://github.com/Durgam1209/RetailFlow-AI/actions/workflows/main.yml/badge.svg)

---

## 📸 Production Application Showroom

### 1. Storefront Point-of-Sale (POS) Engine
The frontend client architecture enforces a strict **Offline-First transactional queue pattern**. POS tasks capture weight adjustments dynamically, caching data inside local NoSQL structures to protect system availability against unstable network conditions on the shop floor.

| POS Product Catalog Matrix | Micro-Reactive Billing | Dynamic Checkout Verification |
| :---: | :---: | :---: |
<img src="https://raw.githubusercontent.com/Durgam1209/RetailFlow-AI/main/murali_fruits_ml/assets/images/pos_catalog.png" width="230" alt="POS Catalog Grid"/>
| *NoSQL-backed local cache rendering real-time stock matrix grids.* | *Safer transactional confirmation layout preventing rounding errors.* | *Incremental precision scaling matching standard micro-retail increments.* |

---

### 2. Live Sales Performance Analytics Dashboards
To optimize system execution speeds, the client layer bypasses heavy client-side computation. It taps directly into pre-aggregated database views via `fl_chart`, executing animated, real-time telemetry rendering with automated peak-performance threshold tracking.

| Financial Revenue Vectors | Running Daily Checkout Volume | Historical Log Ingestions |
| :---: | :---: | :---: |
https://raw.githubusercontent.com/Durgam1209/RetailFlow-AI/main/murali_fruits_ml/assets/images/analytics_revenue.png
| *Weekly income trends highlighting peak revenue days via green thresholds.* | *Granular transactional volume tracking detailing traffic rhythms.* | *Comprehensive historical audits pulled directly from local storage collections.* |

---

### 3. AI Predictive Insights & Spatial Merchandising
Complex mathematical data structures from the MLOps pipeline are simplified into straightforward visual cues. The platform displays real-time weather adjustments, holiday warnings, and cross-purchasing affinity patterns mapped onto a spatial storefront matrix layout to guide daily inventory decisions.

| Pipeline Predictions Dashboard | Spatial Merchandising Map | Affinity Basket Recommendations |
| :---: | :---: | :---: |
| <img src="https://github.com/Durgam1209/RetailFlow-AI/raw/main/murali_fruits_ml/assets/images/ai_predictions.png" width="230" alt="Predictive Analytics Feed"/> | <img src="https://github.com/Durgam1209/RetailFlow-AI/raw/main/murali_fruits_ml/assets/images/shop_layout.png" width="230" alt="AI Shop Layout Overlay"/> | <img src="https://github.com/Durgam1209/RetailFlow-AI/raw/main/murali_fruits_ml/assets/images/ai_bundles.png" width="230" alt="Market Basket Affinities"/> |
| *7-day advanced stock plans generated via Prophet time-series data calculations.* | *Zone-based layout engine overlaying placement cues on store floorplans.* | *Item bundling pairings derived dynamically from Apriori rules mining.* |

---

### 4. Cloud MLOps Infrastructure Logs
The end-to-end telemetry system is orchestrated entirely in the cloud. Scheduled GitHub Actions workflows track model drift by writing performance evaluations directly back to Supabase PostgreSQL, ensuring the system requires zero developer maintenance.

#### Nightly Automation Workflow Performance Tracking (GitHub Actions Console)
![GitHub Actions Workflow Run](https://github.com/Durgam1209/RetailFlow-AI/raw/main/murali_fruits_ml/assets/images/mlops_pipeline_log.png?raw=1)
*Automated background runner script provisioning isolated runtime layers, executing Python feature engineering tasks, and checking for data drift.*

#### Core Database Schema Analytics & Relational Collections View (Supabase Management Layer)
![Supabase Database Tables Dashboard](https://github.com/Durgam1209/RetailFlow-AI/raw/main/murali_fruits_ml/assets/images/supabase_dashboard.png)
*Serverless storage configuration mapping secure row-level security parameters, database index clusters, and highly performant analytical compute scripts.*

---

## 🛠️ Tech Stack & Architecture

### Frontend Ecosystem (Client Layer)
- **Framework:** Flutter (Web & Mobile Engine)
- **Local Persistence:** Hive Storage (NoSQL local-first database caching)
- **State Management & UI Elements:** Dynamic data tracking streams paired with micro-reactive animations
- **Data Visualizations:** `fl_chart` (Advanced real-time, animated revenue & checkout volume metrics charts)
- **Hosting Engine:** Firebase Hosting (CDN cached edge delivery)

### Backend & Core Infrastructure (Data Layer)
- **Cloud Backend:** Supabase (Serverless PostgreSQL Database infrastructure)
- **Data Pipeline Engine:** Python with Pandas & NumPy numerical vectors
- **Time-Series Forecaster:** Facebook Prophet Engine (7-day ahead regional demand & revenue volume regressions)
- **Association Rule Miner:** `mlxtend` (Apriori algorithm for real-time market-basket purchasing affinity extraction)
- **Contextual Feature Engineering:** External national Indian holiday calendars (`holidays`) & OpenWeather API connections

### MLOps & Orchestration (Automation Layer)
- **CI/CD Pipeline Platform:** GitHub Actions
- **Workflow Automations:** Nightly cron execution loops managing secure virtual machine provisioning, continuous data enrichment pipelines, automated model retraining, and live build updates.

---

## 🔄 End-to-End Data Value Chain

The entire architecture functions as a self-sustaining data loop requiring zero manual technical maintenance:

```text
 [ Storefront Counter ] ──> Local Hive NoSQL Cache (Offline-First)
                                    │
                                    ▼ (Automatic Sync on Connection)
 [ Supabase PostgreSQL ] ──> Ingests Raw Transactional Log Tables
                                    │
                                    ▼ (Nightly GitHub Actions Cron Trigger)
 [ Python ETL Engine ]  ──> Fetches Weather API Signals & Indian Holiday Vectors
                                    │
                                    ▼ (Asynchronous Model Training)
 [ ML Inference Loops ] ──> Runs Prophet Time-Series & Apriori Market-Basket rules
                                    │
                                    ▼ (Pre-computed Database View Writing)
 [ Actionable Signals ] ──> Streams Low-Latency Insights to Live Dashboard UI

```

1. **Ingestion:** Transactions are logged securely via the Flutter UI. If network drops occur, transactions are securely cached locally using Hive NoSQL boxes and seamlessly bulk-synced to Supabase PostgreSQL when internet connectivity returns.
2. **Serverless Enrichment:** Every night, GitHub Actions provisions a clean environment, extracts the latest sales logs, and joins the transaction stream with live OpenWeather API data and localized holiday calendars.
3. **Inference & Logging:** The machine learning scripts retrain the Prophet and Apriori models, output fresh 7-day safety buffers and bundle recommendations, compute model error percentages (MAE/RMSE) to track data drift, and write records to a `daily_insights` repository table.
4. **Delivery:** The live production app reads the single latest insight vector and populates interactive dashboard graphs, event-driven warning badges, and zone-based merchandising suggestions directly on the shop floor layout map.

---

## 🗄️ Repository Structure

```text
RetailFlowAI/
├── .github/workflows/               # CI/CD Infrastructure Automations
│   ├── main.yml                     # Main Scheduled Nightly MLOps Compute Loop
│   ├── firebase-hosting-merge.yml   # Production CD Deployment to Firebase Web
│   └── firebase-hosting-pull-request.yml
├── ml_pipeline/                     # Machine Learning Pipeline Core
│   ├── data/processed/              # Localized/Sanitized Model Training Datasets
│   ├── logs/
│   │   └── performance_history.csv  # Historic Pipeline Regression Metric Checks (MAE/RMSE)
│   ├── models/
│   │   ├── basket_analyzer.py       # Apriori Association Rules Compiler
│   │   └── demand_forecaster.py     # Facebook Prophet Core Engine 
│   ├── enrich_data.py               # Weather & Calendar Feature Engineering Pipeline
│   ├── main.py                      # Main Python Orchestrator Execution Script
│   └── requirements.txt             # Backend Dependency Vectors
├── murali_fruits_ml/                # Cross-Platform Flutter Interface
│   ├── assets/images/               # UI Visual Merchandising Shop Assets
│   ├── lib/
│   │   ├── data/                    # Hive Caching & Supabase Sync Services
│   │   ├── models/                  # Strictly Typed Dart Object Definitions
│   │   └── widgets/                 # Insight Dashboards, Analytics Screens, & Tiles
│   └── pubspec.yaml                 # Flutter App Core Configurations
└── sql/                             # Database Structure & Aggregation Blueprints
    ├── setup_daily_insights_table.sql
    └── supabase_sales_log.sql       # Relational Schema Design & View Functions

```

---

## 🚀 Setting Up the Project

### 1. Database View & Schema Construction

Log in to your Supabase Console, navigate to the **SQL Editor**, and execute the scripts located in the `/sql` repository path to configure your tables, relationships, and specialized analytical views.

### 2. Python ML Pipeline Configuration

Navigate to the ML directory and install the required dependencies:

```bash
cd ml_pipeline
python -m pip install -r requirements.txt

```

Construct a localized configuration environment profile (`.env`) in the root of your `ml_pipeline/` directory:

```env
SUPABASE_URL="[https://your-project-id.supabase.co](https://your-project-id.supabase.co)"
SUPABASE_SERVICE_ROLE_KEY="your-high-privilege-service-role-key"

```

### 3. Flutter Client App Compilation

To execute the frontend locally or prepare web build distribution packages, inject the environment endpoints securely using compilation definitions:

```bash
cd murali_fruits_ml
flutter run --dart-define=SUPABASE_URL="[https://your-project-id.supabase.co](https://your-project-id.supabase.co)" --dart-define=SUPABASE_ANON_KEY="your-public-anon-key"

```

### 4. Running Production Web Build and Deployments Manually

If you choose to bypass the GitHub Actions workflow and deploy directly from your local terminal configuration:

```bash
flutter build web --release --dart-define=SUPABASE_URL="YOUR_URL" --dart-define=SUPABASE_ANON_KEY="YOUR_KEY"
firebase deploy --only hosting

```

---

## 📊 Real-World Production Optimizations Enforced

* **Database-Side Compute Aggregations:** Leverages custom PostgreSQL aggregation views to process running transactional totals on the cloud, reducing mobile client memory footprints and maximizing network load efficiency.
* **Drift-Aware Monitoring:** Automatically prints and logs performance validation history logs (`performance_history.csv`) during every retraining cycle to prevent time-series forecast drift on noisy real-world data arrays.
* **Resilient Data Sanitation Fallbacks:** Outfitted with robust fallback model syntax parsing rules (`??` operator filters) inside your Dart serializers (`fruit_item.dart` / `transaction_item.dart`), seamlessly protecting your application from schema evolution crashes when reading historical data records.
* **Enterprise-Grade Client Persistence:** Built on an offline-first architecture utilizing strict transactional queues, providing business continuity under unstable connectivity conditions on the shop floor.
