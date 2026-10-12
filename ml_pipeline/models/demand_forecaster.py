import ast
import json
import logging

import pandas as pd
from config import (
    FORECAST_CLOSED_DATES,
    FORECAST_EXCLUDED_DATES,
    FORECAST_HOLDOUT_DAYS,
    FORECAST_HORIZON_DAYS,
    FORECAST_INTERVAL_LOWER_FACTOR,
    FORECAST_INTERVAL_UPPER_FACTOR,
    FORECAST_MIN_ITEM_HISTORY_DAYS,
    FORECAST_MIN_ITEM_NONZERO_DAYS,
    FORECAST_MIN_TRAIN_DAYS,
    FORECAST_TREND_CAP,
    PROPHET_INTERVAL_WIDTH,
    RECENT_SALES_DAYS,
)
from prophet import Prophet

LOGGER = logging.getLogger(__name__)


def _calendar_days(start, end):
    """Calendar days are open by default; optionally omit known closed dates."""
    days = pd.date_range(start, end, freq="D")
    omitted_dates = FORECAST_CLOSED_DATES | FORECAST_EXCLUDED_DATES
    if not omitted_dates:
        return days
    return pd.DatetimeIndex(
        [day for day in days if day.strftime("%Y-%m-%d") not in omitted_dates]
    )


def _daily_demand_frame(df):
    """Build Prophet-ready daily transaction volume for the app forecast."""
    if df.empty or "created_date" not in df.columns:
        return pd.DataFrame(columns=["ds", "y"])
    demand_column = "item_count" if "item_count" in df.columns else "total_amount"
    daily = (
        df.assign(created_date=pd.to_datetime(df["created_date"], errors="coerce"))
        .dropna(subset=["created_date"])
        .loc[
            lambda rows: ~rows["created_date"]
            .dt.strftime("%Y-%m-%d")
            .isin(FORECAST_EXCLUDED_DATES)
        ]
        .groupby("created_date", as_index=False)[demand_column]
        .sum()
        .rename(columns={"created_date": "ds", demand_column: "y"})
        .sort_values("ds")
    )
    daily["y"] = pd.to_numeric(daily["y"], errors="coerce").fillna(0).clip(lower=0)
    if daily.empty:
        return daily
    calendar = _calendar_days(daily["ds"].min(), daily["ds"].max())
    return daily.set_index("ds").reindex(calendar, fill_value=0).rename_axis("ds").reset_index()


def _small_data_forecast(daily):
    if daily.empty:
        return pd.DataFrame(columns=["ds", "yhat", "yhat_upper", "yhat_lower"])
    recent = daily.tail(RECENT_SALES_DAYS).copy()
    weights = pd.Series(range(1, len(recent) + 1), dtype="float")
    baseline = float((recent["y"].reset_index(drop=True) * weights).sum() / weights.sum())
    previous_average = float(recent["y"].iloc[:-1].mean()) if len(recent) > 1 else baseline
    latest = float(recent["y"].iloc[-1])
    trend_ratio = 0 if previous_average == 0 else (latest - previous_average) / previous_average
    trend_ratio = max(min(trend_ratio, FORECAST_TREND_CAP), -FORECAST_TREND_CAP)
    dates = _calendar_days(
        daily["ds"].max() + pd.Timedelta(days=1),
        daily["ds"].max() + pd.Timedelta(days=FORECAST_HORIZON_DAYS * 2),
    )[:FORECAST_HORIZON_DAYS]
    return pd.DataFrame(
        [
            {
                "ds": day,
                "yhat": max(0, baseline * (1 + trend_ratio * i / 7)),
                "yhat_lower": max(
                    0,
                    baseline
                    * (1 + trend_ratio * i / FORECAST_HORIZON_DAYS)
                    * FORECAST_INTERVAL_LOWER_FACTOR,
                ),
                "yhat_upper": max(
                    0,
                    baseline
                    * (1 + trend_ratio * i / FORECAST_HORIZON_DAYS)
                    * FORECAST_INTERVAL_UPPER_FACTOR,
                ),
                "model_basis": "recent sales average",
            }
            for i, day in enumerate(dates, 1)
        ]
    )


def _item_daily_frames(df):
    """Extract quantity (kg) by item, filling no-sale days with zero."""
    if df.empty or "created_date" not in df or "items" not in df:
        return {}
    rows = []
    for _, sale in df[["created_date", "items"]].iterrows():
        day = pd.to_datetime(sale["created_date"], errors="coerce")
        if pd.isna(day):
            continue
        if day.strftime("%Y-%m-%d") in FORECAST_EXCLUDED_DATES:
            continue
        items = sale["items"]
        if isinstance(items, str):
            try:
                items = json.loads(items)
            except (ValueError, TypeError):
                try:
                    items = ast.literal_eval(items)
                except (ValueError, SyntaxError):
                    continue
        if not isinstance(items, list):
            continue
        for item in items:
            if not isinstance(item, dict):
                continue
            name = item.get("fruitName") or item.get("fruit_name") or item.get("name")
            try:
                quantity = float(item.get("quantityKg", 0) or 0)
            except (ValueError, TypeError):
                quantity = 0
            if name and quantity >= 0:
                rows.append({"ds": day.normalize(), "item": str(name), "y": quantity})
    if not rows:
        return {}
    transactions = pd.DataFrame(rows).groupby(["item", "ds"], as_index=False)["y"].sum()
    start, end = transactions["ds"].min(), transactions["ds"].max()
    calendar = _calendar_days(start, end)
    result = {}
    for name, group in transactions.groupby("item"):
        frame = group.set_index("ds")[["y"]].reindex(calendar, fill_value=0)
        frame.index.name = "ds"
        result[name] = frame.reset_index()
    return result


def _score(actual, predicted):
    errors = predicted - actual
    denominator = float(actual.sum())
    return {
        "mae_kg": round(float(errors.abs().mean()), 3),
        "mse_kg2": round(float(errors.pow(2).mean()), 3),
        "rmse_kg": round(float((errors.pow(2).mean()) ** 0.5), 3),
        "wape_pct": round(float(errors.abs().sum() / denominator * 100), 2)
        if denominator
        else None,
        "bias_kg": round(float(errors.mean()), 3),
        "sample_size": int(len(actual)),
        "actual_kg": round(denominator, 3),
        "absolute_error_kg": round(float(errors.abs().sum()), 3),
    }


def _newsvendor_quantile(unit_price: float, unit_cost: float) -> float:
    """Return the cost-derived service quantile used by newsvendor ordering."""
    if unit_price < 0 or unit_cost < 0:
        raise ValueError("unit_price and unit_cost must be non-negative")
    if unit_price + unit_cost == 0:
        return 0.5
    return (unit_price - unit_cost) / unit_price if unit_price > unit_cost else 0.0


def _time_holdout_split(daily: pd.DataFrame, holdout_days: int):
    """Split chronologically so the validation tail cannot enter training."""
    if holdout_days <= 0 or len(daily) <= holdout_days:
        raise ValueError("holdout_days must be positive and shorter than the series")
    return daily.iloc[:-holdout_days].copy(), daily.iloc[-holdout_days:].copy()


def _evaluate_items(item_frames):
    per_item = {}
    for name, daily in item_frames.items():
        nonzero_days = int((daily["y"] > 0).sum())
        history = {"history_days": int(len(daily)), "nonzero_days": nonzero_days}
        if (
            len(daily) < FORECAST_MIN_ITEM_HISTORY_DAYS
            or nonzero_days < FORECAST_MIN_ITEM_NONZERO_DAYS
        ):
            per_item[name] = {
                **history,
                "model_used": "cold_start_fallback",
                "cold_start": True,
            }
            continue
        if len(daily) <= FORECAST_HOLDOUT_DAYS:
            continue
        train, test = _time_holdout_split(daily, FORECAST_HOLDOUT_DAYS)
        actual = test["y"].reset_index(drop=True)
        naive = train["y"].iloc[-FORECAST_HOLDOUT_DAYS:].reset_index(drop=True)
        if len(naive) != len(test):
            continue
        prophet_prediction = None
        if len(train) >= FORECAST_MIN_TRAIN_DAYS and train["y"].sum() > 0:
            try:
                model = Prophet(
                    yearly_seasonality=False,
                    weekly_seasonality=True,
                    daily_seasonality=False,
                    interval_width=PROPHET_INTERVAL_WIDTH,
                )
                model.fit(train[["ds", "y"]])
                prophet_prediction = (
                    model.predict(test[["ds"]])["yhat"].clip(lower=0).reset_index(drop=True)
                )
            except Exception as error:
                LOGGER.warning(
                    "Holdout Prophet evaluation failed for item %s", name, exc_info=error
                )
        per_item[name] = {**history, "baseline": _score(actual, naive)}
        if prophet_prediction is not None:
            per_item[name]["prophet"] = _score(actual, prophet_prediction)
            per_item[name]["beats_baseline"] = (
                per_item[name]["prophet"]["mae_kg"] < per_item[name]["baseline"]["mae_kg"]
            )
    return per_item


def run_demand_forecasting(df: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    """Forecast aggregate demand and return per-item holdout metrics."""
    daily = _daily_demand_frame(df)
    item_metrics = _evaluate_items(_item_daily_frames(df))
    if len(daily) < FORECAST_MIN_TRAIN_DAYS:
        return _small_data_forecast(daily), {
            "item_metrics": item_metrics,
            "evaluation_days": FORECAST_HOLDOUT_DAYS,
        }
    prophet_df = daily.copy()
    prophet_df["floor"] = 0
    model = Prophet(
        yearly_seasonality=False,
        weekly_seasonality=True,
        daily_seasonality=False,
        interval_width=PROPHET_INTERVAL_WIDTH,
    )
    model.fit(prophet_df)
    future = model.make_future_dataframe(periods=FORECAST_HORIZON_DAYS * 2)
    if FORECAST_CLOSED_DATES:
        future = future[~future["ds"].dt.strftime("%Y-%m-%d").isin(FORECAST_CLOSED_DATES)]
    future["floor"] = 0
    full_forecast = model.predict(future)
    full_forecast[["yhat", "yhat_upper", "yhat_lower"]] = (
        full_forecast[["yhat", "yhat_upper", "yhat_lower"]].clip(lower=0).round(2)
    )
    forecast = full_forecast.tail(FORECAST_HORIZON_DAYS).copy()
    forecast["model_basis"] = "sales trend model"
    return forecast[["ds", "yhat", "yhat_upper", "yhat_lower", "model_basis"]], {
        "item_metrics": item_metrics,
        "evaluation_days": FORECAST_HOLDOUT_DAYS,
        "metric_unit": "kg per item",
    }
