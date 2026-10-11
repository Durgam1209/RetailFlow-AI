import ast
import json
import logging
import os
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from typing import Any

import dotenv
import holidays
import httpx
import pandas as pd
from config import (
    BUNDLE_ANTECEDENT_PRIOR_COUNT,
    BUNDLE_CONFIDENCE_CAP_PERCENT,
    BUNDLE_CONFIDENCE_PRIOR_COUNT,
    BUNDLE_GOOD_CONFIDENCE,
    BUNDLE_STRONG_CONFIDENCE,
    CONFIDENCE_HIGH_SPREAD,
    CONFIDENCE_MEDIUM_SPREAD,
    DEFAULT_FESTIVAL_FRUITS,
    DEFAULT_FRUIT_PRICES,
    DEFAULT_UNIT_PRICE,
    DEFAULT_WEATHER_CITY,
    DEFAULT_WEATHER_LATITUDE,
    DEFAULT_WEATHER_LONGITUDE,
    FESTIVAL_DEMAND_MULTIPLIER,
    FESTIVAL_FRUIT_MAP,
    FESTIVAL_MINIMUM_EXTRA_KG,
    FORECAST_HORIZON_DAYS,
    INSIGHTS_SCHEMA_VERSION,
    MAX_ACTION_FRUIT_NAMES,
    MAX_FESTIVAL_RECOMMENDATIONS,
    MAX_RECOMMENDED_FRUITS,
    MAX_STOCK_ADVICE_ITEMS,
    METRIC_REGRESSION_THRESHOLD,
    PERFORMANCE_MIN_REGRESSION_RUNS,
    PERFORMANCE_TRAILING_RUNS,
    RECENT_SALES_DAYS,
    RETRY_INITIAL_DELAY_SECONDS,
    SUPABASE_MAX_RETRIES,
    SUPABASE_TIMEOUT_SECONDS,
    WEATHER_CACHE_FILENAME,
    WEATHER_COLD_THRESHOLD_C,
    WEATHER_CONNECT_TIMEOUT_SECONDS,
    WEATHER_HOT_THRESHOLD_C,
    WEATHER_HUMIDITY_THRESHOLD,
    WEATHER_MAX_RETRIES,
    WEATHER_PICK_QUANTITY_KG,
    WEATHER_RAIN_PROBABILITY_THRESHOLD,
    WEATHER_TIMEOUT_SECONDS,
    WHOLE_KG_LABEL_THRESHOLD,
    configure_logging,
)
from models.basket_analyzer import run_basket_analysis
from models.demand_forecaster import run_demand_forecasting
from supabase import create_client
from validators import validate_and_standardize_payload, validate_daily_insights_payload

# Load environment variables from .env
dotenv.load_dotenv()

# Get the directory where this script is located
SCRIPT_DIR = Path(__file__).parent
LOGGER = logging.getLogger(__name__)


def _require_env(name):
    value = os.getenv(name)
    if value:
        return value
    raise RuntimeError(
        f"Missing required environment variable: {name}. "
        f"Add it to {SCRIPT_DIR / '.env'} before running the pipeline."
    )


URL = _require_env("SUPABASE_URL")
# Try to use service role key first (for secure backend writes), fall back to anon key
KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or _require_env("SUPABASE_KEY")

# Configure HTTP client with proper timeout and SSL settings
http_client = httpx.Client(
    timeout=SUPABASE_TIMEOUT_SECONDS,
    verify=True,
)

supabase = create_client(URL, KEY)


def _retry_with_backoff(
    func: Callable[[], Any],
    max_retries=SUPABASE_MAX_RETRIES,
    initial_delay=RETRY_INITIAL_DELAY_SECONDS,
):
    """Retry a function with exponential backoff, optimized for connection timeouts"""
    import httpcore
    from httpx import ConnectTimeout

    for attempt in range(max_retries):
        try:
            return func()
        except (ConnectTimeout, httpcore.ConnectTimeout, TimeoutError):
            # Connection timeout - worth retrying with longer delays
            if attempt == max_retries - 1:
                LOGGER.error("Supabase request exhausted its timeout retries")
                raise
            delay = initial_delay * (2**attempt)
            LOGGER.warning(
                "Supabase request timed out; retrying",
                extra={"attempt": attempt + 1, "delay_seconds": delay},
            )
            time.sleep(delay)
        except Exception as e:
            # Other exceptions - only retry a couple times
            if attempt >= max_retries - 2:
                raise
            delay = initial_delay * (2**attempt)
            LOGGER.warning(
                "Supabase request failed; retrying",
                extra={
                    "attempt": attempt + 1,
                    "delay_seconds": delay,
                    "error_type": type(e).__name__,
                },
            )
            time.sleep(delay)


def _safe_float(value, fallback=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


def _display_date(value):
    date = pd.to_datetime(value, errors="coerce")
    if pd.isna(date):
        return str(value)
    return f"{date:%a}, {date:%b} {date.day}"


def _confidence_label(predicted, lower, upper):
    if predicted <= 0:
        return "Learning"
    spread = (upper - lower) / predicted
    if spread <= CONFIDENCE_HIGH_SPREAD:
        return "High confidence"
    if spread <= CONFIDENCE_MEDIUM_SPREAD:
        return "Medium confidence"
    return "Early signal"


def _bundle_strength(confidence):
    if confidence >= BUNDLE_STRONG_CONFIDENCE:
        return "Strong pairing"
    if confidence >= BUNDLE_GOOD_CONFIDENCE:
        return "Good pairing"
    return "Worth testing"


def _parse_items(value):
    if isinstance(value, list):
        return value
    if isinstance(value, str) and value.strip():
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            try:
                return ast.literal_eval(value)
            except (SyntaxError, ValueError):
                return []
    return []


def _item_name(item):
    if not isinstance(item, dict):
        return None
    return item.get("name") or item.get("fruitName") or item.get("fruit_name")


def _format_rupees(value):
    return f"Rs {round(value):,}"


def _format_kg(value):
    return f"{value:.0f} kg" if value >= WHOLE_KG_LABEL_THRESHOLD else f"{value:.1f} kg"


def _item_sales_frame(df):
    rows = []
    if df.empty or "created_date" not in df.columns or "items" not in df.columns:
        return pd.DataFrame(columns=["date", "fruit_name", "quantity_kg", "revenue", "unit_price"])

    for _, sale in df.iterrows():
        sale_date = pd.to_datetime(sale.get("created_date"), errors="coerce")
        if pd.isna(sale_date):
            continue

        for item in _parse_items(sale.get("items")):
            if not isinstance(item, dict):
                continue
            name = _item_name(item)
            if not name:
                continue

            quantity = _safe_float(item.get("quantityKg"), 0)
            unit_price = _safe_float(
                item.get("unitPrice"),
                DEFAULT_FRUIT_PRICES.get(name, 0),
            )
            revenue = _safe_float(item.get("lineTotal"), quantity * unit_price)

            if quantity <= 0 and revenue <= 0:
                continue

            rows.append(
                {
                    "date": sale_date.date(),
                    "fruit_name": name,
                    "quantity_kg": max(quantity, 0),
                    "revenue": max(revenue, 0),
                    "unit_price": unit_price,
                }
            )

    return pd.DataFrame(rows)


def _festival_mapping(festival_name):
    lower_name = festival_name.lower()
    for keyword, fruits in FESTIVAL_FRUIT_MAP.items():
        if keyword in lower_name:
            return fruits
    return DEFAULT_FESTIVAL_FRUITS


def _historical_festival_fruits(df, festival_name, in_holidays):
    if df.empty or "created_date" not in df.columns or "items" not in df.columns:
        return []

    rows = df.copy()
    rows["created_date"] = pd.to_datetime(rows["created_date"], errors="coerce").dt.date
    rows = rows.dropna(subset=["created_date"])
    rows["holiday_name"] = rows["created_date"].apply(
        lambda day: in_holidays.get(day) if day in in_holidays else None
    )
    festival_rows = rows[
        rows["holiday_name"]
        .fillna("")
        .str.lower()
        .str.contains(
            festival_name.lower(),
            regex=False,
        )
    ]

    if festival_rows.empty:
        return []

    item_counts = {}
    for items in festival_rows["items"].apply(_parse_items):
        for item in items:
            name = _item_name(item)
            if not name:
                continue
            quantity = _safe_float(item.get("quantityKg") if isinstance(item, dict) else 1, 1)
            item_counts[name] = item_counts.get(name, 0) + max(quantity, 1)

    return [
        name
        for name, _ in sorted(
            item_counts.items(),
            key=lambda entry: entry[1],
            reverse=True,
        )[:MAX_FESTIVAL_RECOMMENDATIONS]
    ]


def get_festival_advice(df: pd.DataFrame, today: date | None = None) -> dict:
    """Build a high-priority action banner when tomorrow is an Indian holiday."""
    today = today or date.today()
    tomorrow = today + timedelta(days=1)
    in_holidays = holidays.country_holidays(
        "IN",
        years=[today.year - 1, today.year, tomorrow.year],
    )

    if tomorrow not in in_holidays:
        return {}

    festival_name = in_holidays.get(tomorrow)
    historical_fruits = _historical_festival_fruits(df, festival_name, in_holidays)
    recommended_fruits = historical_fruits or _festival_mapping(festival_name)
    fruit_text = ", ".join(recommended_fruits[:MAX_FESTIVAL_RECOMMENDATIONS])

    return {
        "is_active": True,
        "priority": "High",
        "festival_name": festival_name,
        "festival_date": tomorrow.isoformat(),
        "title": f"Tomorrow is {festival_name}",
        "action": f"Stock up on {fruit_text} today.",
        "merchandising": "Place these fruits at the front of the shop for faster pickup.",
        "recommended_fruits": recommended_fruits[:MAX_FESTIVAL_RECOMMENDATIONS],
        "basis": "Historical festival sales" if historical_fruits else "Festival rule mapping",
    }


def fetch_tomorrow_weather(
    city_name: str = DEFAULT_WEATHER_CITY,
    latitude: float = DEFAULT_WEATHER_LATITUDE,
    longitude: float = DEFAULT_WEATHER_LONGITUDE,
) -> dict:
    """Fetch tomorrow's forecast with bounded retries and a last-good cache fallback."""
    cache_path = SCRIPT_DIR / "logs" / WEATHER_CACHE_FILENAME
    api_key = os.getenv("WEATHER_KEY")
    if not api_key:
        LOGGER.warning("WEATHER_KEY is not configured; continuing without weather features")
        return _load_weather_cache(cache_path)

    tomorrow = date.today() + timedelta(days=1)
    forecasts = None
    for attempt in range(WEATHER_MAX_RETRIES):
        try:
            response = httpx.get(
                "https://api.openweathermap.org/data/2.5/forecast",
                params={"lat": latitude, "lon": longitude, "units": "metric", "appid": api_key},
                timeout=httpx.Timeout(
                    WEATHER_TIMEOUT_SECONDS, connect=WEATHER_CONNECT_TIMEOUT_SECONDS
                ),
            )
            response.raise_for_status()
            payload = response.json()
            forecasts = payload.get("list", []) if isinstance(payload, dict) else None
            if not isinstance(forecasts, list):
                raise ValueError("unexpected forecast response shape")
            break
        except (httpx.HTTPError, ValueError) as error:
            LOGGER.warning(
                "OpenWeather request failed",
                extra={"attempt": attempt + 1, "error_type": type(error).__name__},
            )
            if attempt < WEATHER_MAX_RETRIES - 1:
                time.sleep(2**attempt)
    if forecasts is None:
        LOGGER.warning("OpenWeather unavailable; continuing with holiday-only context")
        return _load_weather_cache(cache_path)

    try:
        tomorrow_rows = []
        for item in forecasts:
            forecast_time = datetime.fromtimestamp(item.get("dt", 0))
            if forecast_time.date() == tomorrow:
                tomorrow_rows.append(item)
    except (AttributeError, TypeError, ValueError, OverflowError, OSError):
        LOGGER.warning("OpenWeather returned malformed forecast data; using cache if available")
        return _load_weather_cache(cache_path)

    if not tomorrow_rows:
        LOGGER.warning(
            "OpenWeather returned no forecast for tomorrow; using cached weather if available"
        )
        return _load_weather_cache(cache_path)

    selected = min(
        tomorrow_rows,
        key=lambda item: abs(datetime.fromtimestamp(item.get("dt", 0)).hour - 12),
    )
    main = selected.get("main", {})
    weather = (selected.get("weather") or [{}])[0]
    wind = selected.get("wind", {})
    tomorrow_temps = [
        _safe_float(item.get("main", {}).get("temp"))
        for item in tomorrow_rows
        if item.get("main", {}).get("temp") is not None
    ]
    tomorrow_min = min(tomorrow_temps) if tomorrow_temps else _safe_float(main.get("temp"))
    tomorrow_max = max(tomorrow_temps) if tomorrow_temps else _safe_float(main.get("temp"))

    weather = {
        "date": tomorrow.isoformat(),
        "city": city_name,
        "condition": weather.get("main", "Unknown"),
        "temperature": round(_safe_float(main.get("temp")), 1),
        "min_temperature": round(tomorrow_min, 1),
        "max_temperature": round(tomorrow_max, 1),
        "feels_like": round(_safe_float(main.get("feels_like")), 1),
        "humidity": int(_safe_float(main.get("humidity"))),
        "wind_speed": round(_safe_float(wind.get("speed")), 1),
        "rain_probability": round(_safe_float(selected.get("pop")), 2),
    }
    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps(weather), encoding="utf-8")
    except OSError:
        LOGGER.warning("Weather response is usable, but its cache could not be written")
    return weather


def _load_weather_cache(cache_path):
    try:
        cached = json.loads(cache_path.read_text(encoding="utf-8"))
        LOGGER.warning(
            "Using last good weather response", extra={"date": cached.get("date", "unknown")}
        )
        return cached
    except (OSError, ValueError, TypeError):
        return {}


def _weather_fruit_names(weather):
    if not weather:
        return []

    condition = str(weather.get("condition", "")).lower()
    temperature = _safe_float(weather.get("temperature"))
    humidity = _safe_float(weather.get("humidity"))
    rain_probability = _safe_float(weather.get("rain_probability"))
    fruits = []

    if temperature >= WEATHER_HOT_THRESHOLD_C:
        fruits.extend(["Watermelon", "Watermelon Kiran", "Orange Citrus", "Musambi", "Papaya"])
    if temperature <= WEATHER_COLD_THRESHOLD_C:
        fruits.extend(["Banana", "Apple Washington", "Apple Poland", "Pomegranate"])
    if "rain" in condition or rain_probability >= WEATHER_RAIN_PROBABILITY_THRESHOLD:
        fruits.extend(["Banana", "Pomegranate", "Apple Washington", "Green Grapes"])
    if humidity >= WEATHER_HUMIDITY_THRESHOLD:
        fruits.extend(["Orange Citrus", "Musambi", "Papaya"])

    return list(dict.fromkeys(fruits))


def _apply_weather_adjustment(stock_advice, weather):
    recommended = _weather_fruit_names(weather)
    if not stock_advice or not recommended:
        return stock_advice, {
            **weather,
            "recommended_fruits": recommended,
            "action": "No weather stock adjustment needed.",
        } if weather else {}

    tomorrow_date = weather.get("date")
    has_exact_tomorrow_row = any(day.get("date") == tomorrow_date for day in stock_advice)
    updated_advice = []
    for index, day in enumerate(stock_advice):
        updated_day = {**day}
        if day.get("date") == tomorrow_date or (index == 0 and not has_exact_tomorrow_row):
            top_fruits = list(day.get("top_fruits") or [])
            known = {item.get("fruit_name") for item in top_fruits if isinstance(item, dict)}
            for fruit_name in recommended:
                if fruit_name in known:
                    continue
                unit_price = DEFAULT_FRUIT_PRICES.get(fruit_name, DEFAULT_UNIT_PRICE)
                quantity_kg = WEATHER_PICK_QUANTITY_KG
                top_fruits.append(
                    {
                        "fruit_name": fruit_name,
                        "suggested_kg": quantity_kg,
                        "expected_revenue": round(quantity_kg * unit_price),
                        "is_weather_pick": True,
                        "stock_label": f"{_format_kg(quantity_kg)} {fruit_name}",
                        "revenue_label": _format_rupees(quantity_kg * unit_price),
                    }
                )

            top_fruits = sorted(
                top_fruits,
                key=lambda item: (
                    item.get("is_weather_pick") is True,
                    item.get("expected_revenue", 0),
                ),
                reverse=True,
            )[:MAX_STOCK_ADVICE_ITEMS]
            total_revenue = sum(item.get("expected_revenue", 0) for item in top_fruits)
            total_kg = sum(item.get("suggested_kg", 0) for item in top_fruits)
            updated_day["top_fruits"] = top_fruits
            updated_day["expected_revenue"] = round(total_revenue)
            updated_day["revenue_label"] = f"Expected revenue: {_format_rupees(total_revenue)}"
            updated_day["stock_label"] = (
                f"Top stock target: {_format_kg(total_kg)} across {len(top_fruits)} fruits"
            )
            updated_day["weather_condition"] = weather.get("condition")
            updated_day["weather_min_temperature"] = weather.get("min_temperature")
            updated_day["weather_max_temperature"] = weather.get("max_temperature")
            updated_day["weather_recommended_fruits"] = recommended
            updated_day["weather_adjustment"] = (
                f"Tomorrow weather: {weather.get('condition')} "
                f"{weather.get('min_temperature')} - {weather.get('max_temperature')} C. Boost "
                + ", ".join(recommended[:MAX_ACTION_FRUIT_NAMES])
                + "."
            )
        updated_advice.append(updated_day)

    return updated_advice, {
        **weather,
        "recommended_fruits": recommended,
        "action": (
            f"Tomorrow range: {weather.get('min_temperature')} - "
            f"{weather.get('max_temperature')} C. Boost "
            + ", ".join(recommended[:MAX_ACTION_FRUIT_NAMES])
            + "."
        ),
    }


def fetch_and_prepare_data() -> tuple[pd.DataFrame, pd.DataFrame]:
    """Fetch sales data from Supabase with retry logic"""

    def _fetch_from_supabase():
        LOGGER.info("Fetching sales data from Supabase...")
        LOGGER.info(f"Connecting to: {URL}")
        response = supabase.table("sales_log").select("*").execute()
        return response

    try:
        response = _retry_with_backoff(_fetch_from_supabase, max_retries=5)
        df = pd.DataFrame(response.data)
        LOGGER.info(f"Successfully fetched {len(df)} records from sales_log")
    except Exception:
        LOGGER.exception("Failed to fetch sales data from Supabase")
        raise

    csv_path = SCRIPT_DIR / "data" / "processed" / "master_training_data.csv"
    if not csv_path.exists():
        raise FileNotFoundError(f"Training data not found at {csv_path}")

    enriched_df = pd.read_csv(csv_path)
    LOGGER.info(f"Loaded {len(enriched_df)} training records from CSV")
    from validators import validate_sales_data

    known_items = set(DEFAULT_FRUIT_PRICES)
    # The enriched export is the local catalog snapshot, including configured custom fruit names.
    if "items" in enriched_df:
        for values in enriched_df["items"].apply(_parse_items):
            for item in values if isinstance(values, list) else []:
                name = _item_name(item)
                if name:
                    known_items.add(str(name))
    if not known_items:
        raise ValueError("Input validation failed: no known item names found in sales data")
    df, _ = validate_sales_data(df, known_items, "Supabase sales_log")
    enriched_df, _ = validate_sales_data(enriched_df, known_items, "enriched training data")
    df.attrs["validation_warnings"] = df.attrs.get(
        "validation_warnings", []
    ) + enriched_df.attrs.get("validation_warnings", [])
    return df, enriched_df


def format_basket_rules(rules_df: pd.DataFrame) -> list[dict[str, Any]]:
    """Convert association rules into readable bundle suggestions"""
    if rules_df.empty:
        return []

    bundles = []
    seen_pairs = set()
    sorted_rules = rules_df.sort_values(
        by=["confidence", "lift"],
        ascending=False,
    )

    for idx, row in sorted_rules.iterrows():
        antecedents = (
            list(row["antecedents"])
            if hasattr(row["antecedents"], "__iter__")
            else [row["antecedents"]]
        )
        consequents = (
            list(row["consequents"])
            if hasattr(row["consequents"], "__iter__")
            else [row["consequents"]]
        )

        pair_1 = antecedents[0] if antecedents else "Item"
        pair_2 = consequents[0] if consequents else "Item"
        pair_key = frozenset([pair_1, pair_2])

        if pair_1 == pair_2 or pair_key in seen_pairs:
            continue

        seen_pairs.add(pair_key)
        raw_confidence = _safe_float(row["confidence"] if "confidence" in row else 0.0)
        lift = _safe_float(row["lift"] if "lift" in row else 0.0)
        pair_count = int(_safe_float(row["pair_count"] if "pair_count" in row else 0))
        antecedent_count = int(
            _safe_float(row["antecedent_count"] if "antecedent_count" in row else 0)
        )
        confidence = (
            (pair_count + BUNDLE_CONFIDENCE_PRIOR_COUNT)
            / (antecedent_count + BUNDLE_ANTECEDENT_PRIOR_COUNT)
            if antecedent_count > 0
            else raw_confidence
        )
        confidence_percent = min(round(confidence * 100), BUNDLE_CONFIDENCE_CAP_PERCENT)

        bundles.append(
            {
                "pair_1": pair_1,
                "pair_2": pair_2,
                "title": f"{pair_1} + {pair_2}",
                "confidence": confidence,
                "raw_confidence": raw_confidence,
                "confidence_percent": confidence_percent,
                "lift": lift,
                "pair_count": pair_count,
                "strength": _bundle_strength(confidence),
                "advice": (
                    f"Place {pair_1} near {pair_2}. About "
                    f"{confidence_percent}% of matching baskets include both "
                    f"after adjusting for sample size."
                ),
            }
        )

        if len(bundles) == MAX_RECOMMENDED_FRUITS:
            break

    return bundles


def _fruit_baselines(item_sales):
    if item_sales.empty:
        return {}

    observed_dates = sorted(item_sales["date"].unique())[-RECENT_SALES_DAYS:]
    recent_sales = item_sales[item_sales["date"].isin(observed_dates)]
    day_count = max(len(observed_dates), 1)
    grouped = (
        recent_sales.groupby("fruit_name")
        .agg(
            quantity_kg=("quantity_kg", "sum"),
            revenue=("revenue", "sum"),
            unit_price=("unit_price", "mean"),
        )
        .reset_index()
    )

    baselines = {}
    for _, row in grouped.iterrows():
        name = row["fruit_name"]
        daily_kg = _safe_float(row["quantity_kg"]) / day_count
        daily_revenue = _safe_float(row["revenue"]) / day_count
        unit_price = _safe_float(
            row["unit_price"],
            DEFAULT_FRUIT_PRICES.get(name, 0),
        )
        if daily_kg <= 0 and daily_revenue <= 0:
            continue
        baselines[name] = {
            "quantity_kg": daily_kg,
            "revenue": daily_revenue,
            "unit_price": unit_price,
        }

    return baselines


def _apply_per_fruit_breakdown(stock_advice, enriched_data, festival_advice):
    item_sales = _item_sales_frame(enriched_data)
    baselines = _fruit_baselines(item_sales)
    festival_date = festival_advice.get("festival_date") if festival_advice else None
    festival_fruits = festival_advice.get("recommended_fruits", []) if festival_advice else []

    if not baselines and not festival_fruits:
        return stock_advice

    updated_advice = []
    for day in stock_advice:
        date_str = day["date"]
        is_festival_day = festival_date == date_str
        fruit_rows = []

        for fruit_name, baseline in baselines.items():
            quantity_kg = baseline["quantity_kg"]
            revenue = baseline["revenue"]
            is_festival_pick = is_festival_day and fruit_name in festival_fruits
            if is_festival_day and fruit_name in festival_fruits:
                quantity_kg = max(
                    quantity_kg * FESTIVAL_DEMAND_MULTIPLIER,
                    quantity_kg + FESTIVAL_MINIMUM_EXTRA_KG,
                )
                revenue = quantity_kg * baseline["unit_price"]

            fruit_rows.append(
                {
                    "fruit_name": fruit_name,
                    "suggested_kg": round(quantity_kg, 1),
                    "expected_revenue": round(revenue),
                    "is_festival_pick": is_festival_pick,
                    "stock_label": f"{_format_kg(quantity_kg)} {fruit_name}",
                    "revenue_label": _format_rupees(revenue),
                }
            )

        if is_festival_day:
            known_fruits = {row["fruit_name"] for row in fruit_rows}
            for fruit_name in festival_fruits:
                if fruit_name in known_fruits:
                    continue
                unit_price = DEFAULT_FRUIT_PRICES.get(fruit_name, DEFAULT_UNIT_PRICE)
                quantity_kg = WEATHER_PICK_QUANTITY_KG
                revenue = quantity_kg * unit_price
                fruit_rows.append(
                    {
                        "fruit_name": fruit_name,
                        "suggested_kg": quantity_kg,
                        "expected_revenue": round(revenue),
                        "is_festival_pick": True,
                        "stock_label": f"{_format_kg(quantity_kg)} {fruit_name}",
                        "revenue_label": _format_rupees(revenue),
                    }
                )

        fruit_rows = sorted(
            fruit_rows,
            key=lambda item: (item["is_festival_pick"], item["expected_revenue"]),
            reverse=True,
        )[:MAX_STOCK_ADVICE_ITEMS]

        total_revenue = sum(item["expected_revenue"] for item in fruit_rows)
        total_kg = sum(item["suggested_kg"] for item in fruit_rows)
        updated_day = {
            **day,
            "top_fruits": fruit_rows,
            "expected_revenue": round(total_revenue),
            "revenue_label": f"Expected revenue: {_format_rupees(total_revenue)}",
            "stock_label": (
                f"Top stock target: {_format_kg(total_kg)} across {len(fruit_rows)} fruits"
            ),
            "action": (
                "Prepare "
                + ", ".join(item["stock_label"] for item in fruit_rows[:MAX_ACTION_FRUIT_NAMES])
                + "."
            )
            if fruit_rows
            else day["action"],
        }

        if is_festival_day and festival_fruits:
            updated_day["event_adjustment"] = (
                "Festival boost added for "
                + ", ".join(festival_fruits[:MAX_ACTION_FRUIT_NAMES])
                + "."
            )

        updated_advice.append(updated_day)

    return updated_advice


def format_forecast_advice(forecast_df: pd.DataFrame) -> list[dict[str, Any]]:
    """Convert forecast rows into clear inventory actions for the app"""
    if forecast_df.empty:
        return []

    advice = []
    for idx, row in forecast_df.tail(FORECAST_HORIZON_DAYS).iterrows():
        date_str = str(row["ds"]).split(" ")[0] if "ds" in row else ""
        predicted = max(0.0, _safe_float(row["yhat"] if "yhat" in row else 0.0))
        upper_bound = max(
            predicted, _safe_float(row["yhat_upper"] if "yhat_upper" in row else predicted)
        )
        lower_bound = max(
            0.0,
            min(predicted, _safe_float(row["yhat_lower"] if "yhat_lower" in row else predicted)),
        )
        suggested_stock = round(upper_bound)
        predicted_units = round(predicted)
        confidence = _confidence_label(predicted, lower_bound, upper_bound)

        advice.append(
            {
                "date": date_str,
                "display_date": _display_date(date_str),
                "predicted_demand": predicted_units,
                "upper_bound": suggested_stock,
                "lower_bound": round(lower_bound),
                "suggested_stock": suggested_stock,
                "confidence_label": confidence,
                "demand_label": f"Expect about {predicted_units} items",
                "range_label": f"Likely range: {round(lower_bound)}-{suggested_stock} items",
                "action": f"Keep around {suggested_stock} items ready for the day.",
                "model_basis": row.get("model_basis", "sales trend")
                if hasattr(row, "get")
                else "sales trend",
            }
        )

    return advice


def build_forecast_summary(stock_advice: list[dict[str, Any]]) -> str:
    """Summarize daily stock advice in the sentence shown in the Flutter app."""
    if not stock_advice:
        return "Add a few more sales to generate a reliable demand forecast."
    average_revenue = round(
        sum(item.get("expected_revenue", 0) for item in stock_advice) / len(stock_advice)
    )
    weekly_revenue = sum(item.get("expected_revenue", 0) for item in stock_advice)
    busiest_day = max(
        stock_advice,
        key=lambda item: item.get("expected_revenue", item["predicted_demand"]),
    )
    top_fruits = busiest_day.get("top_fruits", [])
    top_fruit_label = top_fruits[0]["stock_label"] if top_fruits else "priority stock"

    return (
        f"Plan for about {_format_rupees(average_revenue)} revenue per day. "
        f"{busiest_day['display_date']} looks strongest at "
        f"{_format_rupees(busiest_day.get('expected_revenue', 0))}; start with "
        f"{top_fruit_label}. Weekly revenue estimate: {_format_rupees(weekly_revenue)}."
    )


def insert_daily_insight(insight_data: dict[str, Any]) -> Any:
    """Insert an already schema-validated daily insight into Supabase."""
    return supabase.table("daily_insights").insert(insight_data).execute()


def log_performance(metrics: dict[str, Any]) -> dict[str, Any]:
    """Append one run's aggregate evaluation and return metrics with regression flags."""
    log_path = SCRIPT_DIR / "logs" / "performance_history.csv"
    log_path.parent.mkdir(parents=True, exist_ok=True)

    previous = (
        pd.read_csv(log_path) if log_path.exists() and log_path.stat().st_size else pd.DataFrame()
    )
    if not previous.empty and metrics.get("mae_kg") is not None:
        historical_mae = previous.get("mae_kg", pd.Series(dtype="float64"))
        trailing = (
            pd.to_numeric(historical_mae, errors="coerce").dropna().tail(PERFORMANCE_TRAILING_RUNS)
        )
        current_mae = _safe_float(metrics.get("mae_kg"), -1)
        trailing_mean = float(trailing.mean()) if len(trailing) else None
        regression = (
            trailing_mean is not None
            and len(trailing) >= PERFORMANCE_MIN_REGRESSION_RUNS
            and current_mae > trailing_mean * (1 + METRIC_REGRESSION_THRESHOLD)
        )
        metrics["mae_kg_trailing_7_run_avg"] = (
            round(trailing_mean, 3) if trailing_mean is not None else None
        )
        metrics["regression_alert"] = bool(regression)
        if regression:
            metrics["status"] = "degraded"
            LOGGER.warning(
                "Forecast error exceeded its trailing regression threshold",
                extra={"current_mae": current_mae, "trailing_mean_mae": trailing_mean},
            )

    log_entry = pd.DataFrame([{"timestamp": datetime.now().isoformat(), **metrics}])

    pd.concat([previous, log_entry], ignore_index=True, sort=False).to_csv(log_path, index=False)
    return metrics


@dataclass
class StageOutcome:
    """Result of one independently logged pipeline stage."""

    name: str
    succeeded: bool
    value: Any = None


def _run_stage(name: str, callback: Callable[[], Any]) -> StageOutcome:
    """Run one pipeline stage and retain failures so later independent stages can proceed."""
    LOGGER.info("Pipeline stage started", extra={"stage": name})
    try:
        value = callback()
    except Exception:
        LOGGER.exception("Pipeline stage failed", extra={"stage": name})
        return StageOutcome(name=name, succeeded=False)
    LOGGER.info("Pipeline stage completed", extra={"stage": name})
    return StageOutcome(name=name, succeeded=True, value=value)


def _skipped_stage(name: str, reason: str) -> StageOutcome:
    """Log an explicit stage skip caused by a failed prerequisite."""
    LOGGER.error("Pipeline stage skipped", extra={"stage": name, "reason": reason})
    return StageOutcome(name=name, succeeded=False)


def _performance_metrics(
    raw_sales: pd.DataFrame, stock_advice: list, forecast_metrics: dict
) -> dict:
    """Build aggregate performance-history fields from per-item holdout scores."""
    metrics = {
        "status": "success",
        "bundles_generated": 0,
        "forecast_days": len(stock_advice),
        "festival_active": False,
        "total_records_fetched": len(raw_sales),
        "weekly_revenue_estimate": sum(day.get("expected_revenue", 0) for day in stock_advice),
        "item_metrics": json.dumps(forecast_metrics.get("item_metrics", {}), sort_keys=True),
        "evaluation_days": forecast_metrics.get("evaluation_days"),
        "metric_unit": forecast_metrics.get("metric_unit", "kg per item"),
    }
    item_metrics = forecast_metrics.get("item_metrics", {})
    item_scores = [item["prophet"] for item in item_metrics.values() if "prophet" in item]
    baseline_scores = [item["baseline"] for item in item_metrics.values() if "baseline" in item]
    for model_name, scores in (("", item_scores), ("baseline_", baseline_scores)):
        if not scores:
            continue
        metrics[f"{model_name}mae_kg"] = round(
            sum(item["mae_kg"] for item in scores) / len(scores), 3
        )
        metrics[f"{model_name}mse_kg2"] = round(
            sum(item["mse_kg2"] for item in scores) / len(scores), 3
        )
        metrics[f"{model_name}rmse_kg"] = round(
            sum(item["rmse_kg"] for item in scores) / len(scores), 3
        )
    if item_scores:
        total_actual = sum(item["actual_kg"] for item in item_scores)
        metrics["wape_pct"] = (
            round(100 * sum(item["absolute_error_kg"] for item in item_scores) / total_actual, 2)
            if total_actual
            else None
        )
        metrics["bias_kg"] = round(
            sum(item["bias_kg"] for item in item_scores) / len(item_scores), 3
        )
    return metrics


def _format_insight_payload(
    raw_sales: pd.DataFrame,
    enriched_data: pd.DataFrame,
    basket_rules: pd.DataFrame,
    forecast: pd.DataFrame,
) -> tuple[dict, bool]:
    """Build the mobile app's daily insight record from model and enrichment outputs."""
    suggested_bundles = format_basket_rules(basket_rules)
    stock_advice = format_forecast_advice(forecast)
    festival_advice = get_festival_advice(enriched_data)
    stock_advice = _apply_per_fruit_breakdown(stock_advice, enriched_data, festival_advice)
    tomorrow_weather = fetch_tomorrow_weather()
    weather_is_current = (
        tomorrow_weather.get("date") == (date.today() + timedelta(days=1)).isoformat()
    )
    stock_advice, weather_advice = _apply_weather_adjustment(stock_advice, tomorrow_weather)
    payload = {
        "schema_version": INSIGHTS_SCHEMA_VERSION,
        "forecast_summary": build_forecast_summary(stock_advice),
        "suggested_bundles": suggested_bundles,
        "stock_advice": stock_advice,
        "festival_advice": festival_advice,
        "weather_advice": weather_advice,
        "created_at": datetime.now(UTC).isoformat(),
    }
    return payload, weather_is_current


def _push_insight_payload(payload: dict) -> Any:
    """Validate against the JSON contract, then insert the insight record."""
    validate_daily_insights_payload(payload)
    return insert_daily_insight(payload)


def main() -> int:
    """Run validation, basket analysis, forecasting and publish; return nonzero when degraded."""
    configure_logging()
    LOGGER.info("Starting RetailFlow AI intelligence pipeline")
    outcomes: list[StageOutcome] = []
    degradation_reasons: list[str] = []
    validation = _run_stage("validate", fetch_and_prepare_data)
    outcomes.append(validation)

    if validation.succeeded:
        raw_sales, enriched_data = validation.value
        validation_warnings = raw_sales.attrs.get("validation_warnings", [])
        if validation_warnings:
            degradation_reasons.extend(validation_warnings)
            LOGGER.warning(
                "Input data required validation recovery", extra={"warnings": validation_warnings}
            )
        basket = _run_stage("basket", lambda: run_basket_analysis(raw_sales))
        forecast_result = _run_stage("forecast", lambda: run_demand_forecasting(enriched_data))
        outcomes.extend((basket, forecast_result))
    else:
        raw_sales = pd.DataFrame()
        enriched_data = pd.DataFrame()
        basket = _skipped_stage("basket", "input validation failed")
        forecast_result = _skipped_stage("forecast", "input validation failed")
        outcomes.extend((basket, forecast_result))

    if forecast_result.succeeded:
        forecast, forecast_metrics = forecast_result.value
    else:
        forecast, forecast_metrics = pd.DataFrame(), {}

    if validation.succeeded and forecast_result.succeeded:
        formatting = _run_stage(
            "format",
            lambda: _format_insight_payload(
                raw_sales,
                enriched_data,
                basket.value if basket.succeeded else pd.DataFrame(),
                forecast,
            ),
        )
    else:
        reason = "validation or forecast stage failed"
        formatting = _skipped_stage("format", reason)
    outcomes.append(formatting)

    if formatting.succeeded:
        insight_payload, weather_is_current = formatting.value
        if not weather_is_current:
            degradation_reasons.append("weather forecast unavailable or stale")
            LOGGER.warning("Insight uses no current weather forecast")
        if not basket.succeeded:
            insight_payload["suggested_bundles"] = []
            degradation_reasons.append("basket analysis failed")
        insight_payload, payload_warnings = validate_and_standardize_payload(insight_payload)
        if payload_warnings:
            LOGGER.warning(
                "Payload standardization reported warnings", extra={"warnings": payload_warnings}
            )
            degradation_reasons.append("insight payload required fallback values")
    else:
        insight_payload = None

    if insight_payload is not None:
        push = _run_stage("push", lambda: _push_insight_payload(insight_payload))
    else:
        push = _skipped_stage("push", "no validated insight payload is available")
    outcomes.append(push)

    if push.succeeded:
        insight_payload["suggested_bundles"] = insight_payload.get("suggested_bundles", [])
        metrics = _performance_metrics(raw_sales, insight_payload["stock_advice"], forecast_metrics)
        metrics["bundles_generated"] = len(insight_payload["suggested_bundles"])
        metrics["festival_active"] = bool(insight_payload["festival_advice"])
        if degradation_reasons:
            metrics["status"] = "degraded"
        log_result = _run_stage("performance_log", lambda: log_performance(metrics))
        outcomes.append(log_result)
        if log_result.succeeded and log_result.value.get("regression_alert"):
            degradation_reasons.append("forecast metric regression")
    else:
        log_result = _run_stage(
            "performance_log",
            lambda: log_performance(
                {
                    "status": "failed",
                    "total_records_fetched": len(raw_sales),
                    "bundles_generated": 0,
                    "forecast_days": 0,
                }
            ),
        )
        outcomes.append(log_result)

    degraded = bool(degradation_reasons) or any(not outcome.succeeded for outcome in outcomes)
    if degraded:
        LOGGER.error(
            "Pipeline finished with degraded or failed stages",
            extra={
                "failed_stages": [outcome.name for outcome in outcomes if not outcome.succeeded],
                "degradation_reasons": degradation_reasons,
            },
        )
        return 1
    LOGGER.info("Pipeline completed successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
