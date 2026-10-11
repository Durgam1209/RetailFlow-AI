from __future__ import annotations

import json
import math
import pandas as pd
from typing import Any, Dict, List, Tuple


REQUIRED_BUNDLE_KEYS = {
    "pair_1",
    "pair_2",
    "title",
    "confidence",
    "raw_confidence",
    "confidence_percent",
    "lift",
    "pair_count",
    "antecedent_count",
    "strength",
    "advice",
}

SALES_REQUIRED_COLUMNS = {"transaction_id", "created_at", "created_date", "total_amount", "item_count", "items"}


def validate_sales_data(frame: pd.DataFrame, known_items=None, label="sales_log") -> tuple[pd.DataFrame, int]:
    """Validate, deduplicate and remove return/void lines from transaction demand."""
    missing = sorted(SALES_REQUIRED_COLUMNS - set(frame.columns))
    if missing:
        raise ValueError(f"{label} is missing required columns: {', '.join(missing)}")
    data = frame.copy()
    if data["transaction_id"].isna().any() or data["transaction_id"].astype(str).str.strip().eq("").any():
        raise ValueError(f"{label} contains a null or blank transaction_id")
    data["transaction_id"] = data["transaction_id"].astype(str)
    duplicates = int(data.duplicated("transaction_id", keep="first").sum())
    if duplicates:
        print(f"Validation: removed {duplicates} duplicate transaction row(s) by transaction_id")
        data = data.drop_duplicates("transaction_id", keep="first").copy()

    parsed_dates = pd.to_datetime(data["created_date"], errors="coerce", utc=True)
    if parsed_dates.isna().any():
        rows = data.index[parsed_dates.isna()].tolist()[:5]
        raise ValueError(f"{label} has invalid created_date values at row(s): {rows}")
    data["created_date"] = parsed_dates.dt.tz_convert(None).dt.normalize()
    parsed_timestamps = pd.to_datetime(data["created_at"], errors="coerce", utc=True)
    if parsed_timestamps.isna().any():
        rows = data.index[parsed_timestamps.isna()].tolist()[:5]
        raise ValueError(f"{label} has invalid created_at timestamps at row(s): {rows}")
    data["created_at"] = parsed_timestamps
    for column in ("total_amount", "item_count"):
        values = pd.to_numeric(data[column], errors="coerce")
        invalid = values.isna() | ~values.map(lambda x: math.isfinite(float(x)))
        if invalid.any():
            raise ValueError(f"{label}.{column} contains non-numeric or non-finite values")
        if column == "item_count" and (values < 0).any():
            raise ValueError(f"{label}.{column} contains negative values")
        data[column] = values
    return_line_count = 0
    negative_total = data["total_amount"] < 0
    if negative_total.any():
        return_line_count += int(negative_total.sum())
        data = data.loc[~negative_total].copy()

    known_items = set(known_items or [])
    clean_items = []
    clean_counts = []
    for row_index, value in data["items"].items():
        items = value
        if isinstance(items, str):
            try:
                items = json.loads(items)
            except (ValueError, TypeError):
                try:
                    import ast
                    items = ast.literal_eval(items)
                except (ValueError, SyntaxError):
                    raise ValueError(f"{label}.items is malformed at row {row_index}")
        if not isinstance(items, list):
            raise ValueError(f"{label}.items must be a list at row {row_index}")
        if len(items) != int(data.at[row_index, "item_count"]):
            raise ValueError(f"{label}.item_count does not match items length at row {row_index}")
        remaining = []
        for item in items:
            if not isinstance(item, dict):
                raise ValueError(f"{label}.items contains a non-object at row {row_index}")
            name = item.get("fruitName") or item.get("fruit_name") or item.get("name")
            if not isinstance(name, str) or not name.strip():
                raise ValueError(f"{label}.items has a blank item name at row {row_index}")
            if known_items and name not in known_items:
                raise ValueError(f"{label} contains unknown item name {name!r} at row {row_index}")
            try:
                if "quantityKg" not in item or "unitPrice" not in item:
                    raise ValueError("required quantityKg/unitPrice missing")
                quantity = float(item["quantityKg"])
                price = float(item["unitPrice"])
            except (TypeError, ValueError):
                raise ValueError(f"{label}.items has invalid quantity/price at row {row_index}")
            if not math.isfinite(quantity) or not math.isfinite(price):
                raise ValueError(f"{label}.items has non-finite quantity/price at row {row_index}")
            if quantity < 0 or price < 0:
                return_line_count += 1
                continue
            remaining.append(item)
        clean_items.append(remaining)
        clean_counts.append(len(remaining))
    data["items"] = clean_items
    data["item_count"] = clean_counts
    if return_line_count:
        print(f"Validation: excluded {return_line_count} negative return/void item line(s) from demand")
    return data, return_line_count


def _is_number(x: Any) -> bool:
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def coerce_int(x: Any, default: int = 0) -> int:
    try:
        if x is None:
            return default
        if isinstance(x, bool):
            return default
        return int(round(float(x)))
    except Exception:
        return default


def coerce_float(x: Any, default: float = 0.0) -> float:
    try:
        if x is None:
            return default
        if isinstance(x, bool):
            return default
        return float(x)
    except Exception:
        return default


def ensure_jsonable(value: Any) -> Any:
    """Ensure the value is JSON serializable (basic types only)."""
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, dict):
        return {str(k): ensure_jsonable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [ensure_jsonable(v) for v in value]

    # Fallback to string
    return str(value)


def validate_and_standardize_payload(payload: Dict[str, Any]) -> Tuple[Dict[str, Any], List[str]]:
    """Return (standardized_payload, errors)."""
    errors: List[str] = []

    standardized: Dict[str, Any] = dict(payload)

    # forecast_summary
    forecast_summary = standardized.get("forecast_summary")
    if not isinstance(forecast_summary, str) or not forecast_summary.strip():
        errors.append("forecast_summary must be a non-empty string")
        standardized["forecast_summary"] = "Demand is steady." 

    # suggested_bundles
    bundles = standardized.get("suggested_bundles")
    if not isinstance(bundles, list):
        errors.append("suggested_bundles must be a list")
        bundles = []

    std_bundles: List[Dict[str, Any]] = []
    for i, b in enumerate(bundles):
        if not isinstance(b, dict):
            errors.append(f"suggested_bundles[{i}] must be an object")
            continue

        missing = REQUIRED_BUNDLE_KEYS - set(b.keys())
        if missing:
            errors.append(f"suggested_bundles[{i}] missing keys: {sorted(missing)}")

        # Standardize common numeric fields
        std_b = {
            "pair_1": str(b.get("pair_1", "Item")),
            "pair_2": str(b.get("pair_2", "Item")),
            "title": str(b.get("title", f"{b.get('pair_1','Item')} + {b.get('pair_2','Item')}")),
            "confidence": coerce_float(b.get("confidence", b.get("confidence_percent", 0.0)) / (100.0 if _is_number(b.get("confidence", None)) and b.get("confidence", 0) > 1 else 1), default=0.0),
            "raw_confidence": coerce_float(b.get("raw_confidence", 0.0), default=0.0),
            "confidence_percent": coerce_int(b.get("confidence_percent", 0), default=0),
            "lift": coerce_float(b.get("lift", 0.0), default=0.0),
            "pair_count": coerce_int(b.get("pair_count", 0), default=0),
            "antecedent_count": coerce_int(b.get("antecedent_count", b.get("antecedent_count", 0)), default=0),
            "strength": str(b.get("strength", "Worth testing")),
            "advice": str(b.get(
                "advice",
                "Place these items together to make the basket easier to build.",
            )),
        }

        std_bundles.append(std_b)

    standardized["suggested_bundles"] = std_bundles

    # stock_advice
    stock_advice = standardized.get("stock_advice")
    if not isinstance(stock_advice, list):
        errors.append("stock_advice must be a list")
        stock_advice = []

    std_stock: List[Dict[str, Any]] = []
    for i, d in enumerate(stock_advice):
        if not isinstance(d, dict):
            errors.append(f"stock_advice[{i}] must be an object")
            continue

        date = d.get("date")
        display_date = d.get("display_date")
        if display_date is None and date is not None:
            display_date = str(date)

        top_fruits = d.get("top_fruits")
        if not isinstance(top_fruits, list):
            top_fruits = []

        std_top_fruits: List[Dict[str, Any]] = []
        for j, tf in enumerate(top_fruits):
            if not isinstance(tf, dict):
                continue
            std_top_fruits.append(
                {
                    "fruit_name": str(tf.get("fruit_name", "Fruit")),
                    "suggested_kg": coerce_float(tf.get("suggested_kg", 0.0), default=0.0),
                    "expected_revenue": coerce_float(tf.get("expected_revenue", 0.0), default=0.0),
                    "is_festival_pick": bool(tf.get("is_festival_pick", False)),
                    "is_weather_pick": bool(tf.get("is_weather_pick", False)),
                    "stock_label": str(tf.get("stock_label", tf.get("fruit_name", "Fruit"))),
                    "revenue_label": str(tf.get("revenue_label", "")),
                }
            )

        std_stock.append(
            {
                "date": str(date) if date is not None else "",
                "display_date": str(display_date) if display_date is not None else "",
                "predicted_demand": coerce_int(d.get("predicted_demand", d.get("expected_demand", 0)), 0),
                "suggested_stock": coerce_int(d.get("suggested_stock", d.get("upper_bound", 0)), 0),
                "lower_bound": coerce_int(d.get("lower_bound", 0), 0),
                "expected_revenue": coerce_float(d.get("expected_revenue", 0.0), 0.0),
                "confidence_label": str(d.get("confidence_label", "Learning")),
                "demand_label": str(d.get("demand_label", "")),
                "range_label": str(d.get("range_label", "")),
                "action": str(d.get("action", "Keep around items ready.")),
                "event_adjustment": d.get("event_adjustment"),
                "weather_adjustment": d.get("weather_adjustment"),
                "top_fruits": std_top_fruits[:5],
            }
        )

    standardized["stock_advice"] = std_stock

    # festival_advice / weather_advice: keep as dict, standardize to {} if invalid
    festival_advice = standardized.get("festival_advice")
    if festival_advice is None:
        festival_advice = {}
    if not isinstance(festival_advice, dict):
        errors.append("festival_advice must be an object")
        festival_advice = {}

    weather_advice = standardized.get("weather_advice")
    if weather_advice is None:
        weather_advice = {}
    if not isinstance(weather_advice, dict):
        errors.append("weather_advice must be an object")
        weather_advice = {}

    standardized["festival_advice"] = ensure_jsonable(festival_advice)
    standardized["weather_advice"] = ensure_jsonable(weather_advice)

    # created_at
    created_at = standardized.get("created_at")
    if created_at is None:
        errors.append("created_at missing")
        standardized["created_at"] = ""

    standardized = ensure_jsonable(standardized)
    return standardized, errors

