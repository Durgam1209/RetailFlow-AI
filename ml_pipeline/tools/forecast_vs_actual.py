"""Backtest the app's recent per-item revenue estimate against recorded sales.

Run from the repository root:
    python ml_pipeline/tools/forecast_vs_actual.py [path/to/sales.csv]

The app's aggregate Prophet forecast is in item counts, while its rupee estimate
is built from recent per-fruit revenue. This script backtests that rupee heuristic
without importing main.py (which initializes Supabase clients and credentials).
"""

from __future__ import annotations

import ast
import json
import os
import sys
from pathlib import Path

import pandas as pd

DEFAULT_DATA = Path(__file__).resolve().parents[1] / "data/processed/master_training_data.csv"
EXCLUDED_DATES = {
    value.strip()
    for value in os.getenv("FORECAST_EXCLUDED_DATES", "").split(",")
    if value.strip()
}


def _items(value):
    if isinstance(value, list):
        return value
    if not isinstance(value, str):
        return []
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        try:
            parsed = ast.literal_eval(value)
        except (SyntaxError, ValueError):
            return []
    return parsed if isinstance(parsed, list) else []


def _sales_by_date(path: Path) -> tuple[pd.Series, pd.DataFrame]:
    sales = pd.read_csv(path)
    sales["created_date"] = pd.to_datetime(sales["created_date"], errors="coerce").dt.strftime(
        "%Y-%m-%d"
    )
    sales = sales.dropna(subset=["created_date"])
    sales = sales[~sales["created_date"].isin(EXCLUDED_DATES)]
    actual = sales.groupby("created_date")["total_amount"].sum().astype(float)
    rows = []
    for _, sale in sales.iterrows():
        day = sale["created_date"]
        for item in _items(sale.get("items")):
            if not isinstance(item, dict):
                continue
            name = item.get("fruitName") or item.get("fruit_name") or item.get("name")
            if not name:
                continue
            try:
                revenue = float(item.get("lineTotal", 0) or 0)
            except (TypeError, ValueError):
                revenue = 0.0
            rows.append({"date": day, "item": str(name), "revenue": max(revenue, 0.0)})
    return actual, pd.DataFrame(rows, columns=["date", "item", "revenue"])


def _recent_item_forecast(item_rows: pd.DataFrame, cutoff: str) -> float:
    history = item_rows[item_rows["date"] < cutoff]
    recent_dates = sorted(history["date"].unique())[-7:]
    if not recent_dates:
        return 0.0
    recent = history[history["date"].isin(recent_dates)]
    per_item = recent.groupby("item")["revenue"].sum() / len(recent_dates)
    return float(per_item.nlargest(5).sum())


def backtest(path: Path) -> list[tuple[str, float, float | None, float]]:
    actual, item_rows = _sales_by_date(path)
    eligible_dates = [day for day in actual.index if day not in EXCLUDED_DATES]
    test_dates = eligible_dates[-7:]
    results = []
    for day in test_dates:
        forecast = _recent_item_forecast(item_rows, day)
        previous_week = (pd.Timestamp(day) - pd.Timedelta(days=7)).strftime("%Y-%m-%d")
        naive = float(actual[previous_week]) if previous_week in actual.index else None
        results.append((day, forecast, naive, float(actual[day])))
    return results


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DATA
    if not path.is_file():
        print(f"Sales CSV not found: {path}", file=sys.stderr)
        return 2
    results = backtest(path)
    print(f"{'Date':<12} {'Recent-item forecast':>21} {'Same weekday -7d':>20} {'Actual':>12}")
    print("-" * 69)
    for day, forecast, naive, actual in results:
        naive_text = f"Rs {naive:,.0f}" if naive is not None else "n/a"
        forecast_text = f"Rs {forecast:,.0f}"
        actual_text = f"Rs {actual:,.0f}"
        print(f"{day:<12} {forecast_text:>21} {naive_text:>20} {actual_text:>12}")
    if EXCLUDED_DATES:
        print("Excluded training dates:", ", ".join(sorted(EXCLUDED_DATES)))
    print("Note: n/a means that date has no recorded transaction; it is not treated as zero sales.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
