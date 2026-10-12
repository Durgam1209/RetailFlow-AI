import json

import main as pipeline
import pandas as pd


class Query:
    def __init__(self, rows):
        self.rows = rows

    def select(self, _columns):
        return self

    def execute(self):
        return type("Response", (), {"data": self.rows})()


class SupabaseStub:
    def __init__(self, rows):
        self.rows = rows

    def table(self, _name):
        return Query(self.rows)


def test_excluded_outlier_dates_do_not_enter_revenue_baselines(monkeypatch):
    monkeypatch.setattr(pipeline, "FORECAST_EXCLUDED_DATES", frozenset({"2026-01-02"}))
    sales = pd.DataFrame(
        [
            {
                "created_date": day,
                "items": [{"fruitName": "Banana", "quantityKg": 1, "lineTotal": amount}],
            }
            for day, amount in (("2026-01-01", 60), ("2026-01-02", 6000))
        ]
    )

    item_sales = pipeline._item_sales_frame(sales)

    assert item_sales["date"].astype(str).tolist() == ["2026-01-01"]
    assert item_sales["revenue"].tolist() == [60]


def test_pipeline_smoke_with_fixture_csv_and_mocked_supabase(tmp_path, monkeypatch):
    items = [{"fruitName": "Banana", "quantityKg": 2.0, "unitPrice": 60}]
    row = {
        "transaction_id": "fixture-1",
        "created_at": "2026-01-01T10:00:00Z",
        "created_date": "2026-01-01",
        "total_amount": 120,
        "item_count": 1,
        "items": items,
    }
    monkeypatch.setattr(pipeline, "supabase", SupabaseStub([row]))
    monkeypatch.setattr(pipeline, "SCRIPT_DIR", tmp_path)
    processed = tmp_path / "data" / "processed"
    processed.mkdir(parents=True)
    pd.DataFrame([{**row, "items": json.dumps(items)}]).to_csv(
        processed / "master_training_data.csv", index=False
    )
    monkeypatch.setattr(pipeline, "run_basket_analysis", lambda _sales: pd.DataFrame())
    monkeypatch.setattr(
        pipeline,
        "run_demand_forecasting",
        lambda _sales: (pd.DataFrame(), {"item_metrics": {}}),
    )
    payload = {
        "schema_version": "1.0",
        "forecast_summary": "Fixture forecast",
        "suggested_bundles": [],
        "stock_advice": [],
        "festival_advice": {},
        "weather_advice": {},
        "created_at": "2026-01-01T00:00:00+00:00",
    }
    monkeypatch.setattr(pipeline, "_format_insight_payload", lambda *_args: (payload, True))
    monkeypatch.setattr(pipeline, "insert_daily_insight", lambda value: value)
    monkeypatch.setattr(pipeline, "log_performance", lambda metrics: metrics)
    assert pipeline.main() == 0
