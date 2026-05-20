import pandas as pd
from supabase import create_client
import ast
import json
import os
import dotenv
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
import holidays
import time
import httpx
from models.basket_analyzer import run_basket_analysis
from models.demand_forecaster import run_demand_forecasting
from validators import validate_and_standardize_payload


# Load environment variables from .env
dotenv.load_dotenv()

# Get the directory where this script is located
SCRIPT_DIR = Path(__file__).parent

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
    timeout=60.0,
    verify=True,
)

supabase = create_client(URL, KEY)

FESTIVAL_FRUIT_MAP = {
    "diwali": ["Apple Washington", "Apple Poland", "Pomegranate", "Banana"],
    "deepavali": ["Apple Washington", "Apple Poland", "Pomegranate", "Banana"],
    "ganesh": ["Banana", "Apple Washington", "Pomegranate"],
    "vinayaka": ["Banana", "Apple Washington", "Pomegranate"],
    "makar sankranti": ["Banana", "Orange Citrus", "Pomegranate"],
    "pongal": ["Banana", "Orange Citrus", "Pomegranate"],
    "holi": ["Watermelon", "Orange Citrus", "Green Grapes"],
    "dussehra": ["Banana", "Apple Washington", "Pomegranate"],
    "dasara": ["Banana", "Apple Washington", "Pomegranate"],
    "eid": ["Apple Washington", "Pomegranate", "Green Grapes"],
    "ram navami": ["Banana", "Orange Citrus", "Apple Poland"],
    "janmashtami": ["Banana", "Apple Washington", "Pomegranate"],
    "raksha bandhan": ["Apple Washington", "Pomegranate", "Seedless Green Grapes"],
    "onam": ["Banana", "Pomegranate", "Orange Citrus"],
    "ugadi": ["Banana", "Orange Citrus", "Apple Poland"],
    "christmas": ["Apple Washington", "Green Grapes", "Pomegranate"],
    "republic day": ["Orange Citrus", "Banana", "Apple Washington"],
    "independence day": ["Orange Citrus", "Banana", "Apple Washington"],
}

DEFAULT_FESTIVAL_FRUITS = ["Banana", "Apple Washington", "Pomegranate"]

DEFAULT_FRUIT_PRICES = {
    "Apple Poland": 220,
    "Apple Washington": 180,
    "Banana": 60,
    "Yelakki Banana": 90,
    "Papaya": 50,
    "Orange Citrus": 120,
    "Mandarin Orange": 140,
    "Nagpur Orange": 130,
    "Musambi": 80,
    "Green Grapes": 90,
    "Seedless Green Grapes": 110,
    "Black Grapes": 100,
    "Seedless Black Grapes": 120,
    "Pomegranate": 160,
    "Watermelon": 35,
    "Watermelon Kiran": 45,
}


def _retry_with_backoff(func, max_retries=5, initial_delay=2):
    """Retry a function with exponential backoff, optimized for connection timeouts"""
    import httpcore
    from httpx import ConnectTimeout
    
    for attempt in range(max_retries):
        try:
            return func()
        except (ConnectTimeout, httpcore.ConnectTimeout, TimeoutError) as e:
            # Connection timeout - worth retrying with longer delays
            if attempt == max_retries - 1:
                print(f"Failed after {max_retries} attempts. Connection timeouts may indicate:")
                print("  - Supabase service is down or overloaded")
                print("  - Network connectivity issue")
                print("  - Firewall or proxy blocking the connection")
                print("  - DNS resolution issues")
                raise
            delay = initial_delay * (2 ** attempt)
            print(f"Attempt {attempt + 1} failed with timeout: {type(e).__name__}")
            print(f"Retrying in {delay} seconds...")
            time.sleep(delay)
        except Exception as e:
            # Other exceptions - only retry a couple times
            if attempt >= max_retries - 2:
                raise
            delay = initial_delay * (2 ** attempt)
            print(f"Attempt {attempt + 1} failed: {str(e)}")
            print(f"Retrying in {delay} seconds...")
            time.sleep(delay)


def _safe_float(value, fallback=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


def _display_date(value):
    date = pd.to_datetime(value, errors='coerce')
    if pd.isna(date):
        return str(value)
    return f"{date:%a}, {date:%b} {date.day}"


def _confidence_label(predicted, lower, upper):
    if predicted <= 0:
        return "Learning"
    spread = (upper - lower) / predicted
    if spread <= 0.35:
        return "High confidence"
    if spread <= 0.65:
        return "Medium confidence"
    return "Early signal"


def _bundle_strength(confidence):
    if confidence >= 0.7:
        return "Strong pairing"
    if confidence >= 0.45:
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
    return f"{value:.0f} kg" if value >= 10 else f"{value:.1f} kg"


def _item_sales_frame(df):
    rows = []
    if df.empty or "created_date" not in df.columns or "items" not in df.columns:
        return pd.DataFrame(
            columns=["date", "fruit_name", "quantity_kg", "revenue", "unit_price"]
        )

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
        rows["holiday_name"].fillna("").str.lower().str.contains(
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
        )[:3]
    ]


def get_festival_advice(df, today=None):
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
    fruit_text = ", ".join(recommended_fruits[:3])

    return {
        "is_active": True,
        "priority": "High",
        "festival_name": festival_name,
        "festival_date": tomorrow.isoformat(),
        "title": f"Tomorrow is {festival_name}",
        "action": f"Stock up on {fruit_text} today.",
        "merchandising": "Place these fruits at the front of the shop for faster pickup.",
        "recommended_fruits": recommended_fruits[:3],
        "basis": "Historical festival sales" if historical_fruits else "Festival rule mapping",
    }


def fetch_tomorrow_weather(
    city_name="Mahadevapura, Bengaluru",
    latitude=12.9916,
    longitude=77.6926,
):
    if not os.getenv("WEATHER_KEY"):
        return {}

    tomorrow = date.today() + timedelta(days=1)
    try:
        response = httpx.get(
            "https://api.openweathermap.org/data/2.5/forecast",
            params={
                "lat": latitude,
                "lon": longitude,
                "units": "metric",
                "appid": os.getenv("WEATHER_KEY"),
            },
            timeout=20.0,
        )
        response.raise_for_status()
        forecasts = response.json().get("list", [])
    except Exception as error:
        print(f"Weather forecast fetch failed: {error}")
        return {}

    tomorrow_rows = []
    for item in forecasts:
        forecast_time = datetime.fromtimestamp(item.get("dt", 0))
        if forecast_time.date() == tomorrow:
            tomorrow_rows.append(item)

    if not tomorrow_rows:
        return {}

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

    return {
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


def _weather_fruit_names(weather):
    if not weather:
        return []

    condition = str(weather.get("condition", "")).lower()
    temperature = _safe_float(weather.get("temperature"))
    humidity = _safe_float(weather.get("humidity"))
    rain_probability = _safe_float(weather.get("rain_probability"))
    fruits = []

    if temperature >= 30:
        fruits.extend(["Watermelon", "Watermelon Kiran", "Orange Citrus", "Musambi", "Papaya"])
    if temperature <= 18:
        fruits.extend(["Banana", "Apple Washington", "Apple Poland", "Pomegranate"])
    if "rain" in condition or rain_probability >= 0.5:
        fruits.extend(["Banana", "Pomegranate", "Apple Washington", "Green Grapes"])
    if humidity >= 70:
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
                unit_price = DEFAULT_FRUIT_PRICES.get(fruit_name, 100)
                quantity_kg = 2.0
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
                key=lambda item: (item.get("is_weather_pick") is True, item.get("expected_revenue", 0)),
                reverse=True,
            )[:5]
            total_revenue = sum(item.get("expected_revenue", 0) for item in top_fruits)
            total_kg = sum(item.get("suggested_kg", 0) for item in top_fruits)
            updated_day["top_fruits"] = top_fruits
            updated_day["expected_revenue"] = round(total_revenue)
            updated_day["revenue_label"] = f"Expected revenue: {_format_rupees(total_revenue)}"
            updated_day["stock_label"] = f"Top stock target: {_format_kg(total_kg)} across {len(top_fruits)} fruits"
            updated_day["weather_condition"] = weather.get("condition")
            updated_day["weather_min_temperature"] = weather.get("min_temperature")
            updated_day["weather_max_temperature"] = weather.get("max_temperature")
            updated_day["weather_recommended_fruits"] = recommended
            updated_day["weather_adjustment"] = (
                f"Tomorrow weather: {weather.get('condition')} "
                f"{weather.get('min_temperature')} - {weather.get('max_temperature')} C. Boost "
                + ", ".join(recommended[:3])
                + "."
            )
        updated_advice.append(updated_day)

    return updated_advice, {
        **weather,
        "recommended_fruits": recommended,
        "action": (
            f"Tomorrow range: {weather.get('min_temperature')} - "
            f"{weather.get('max_temperature')} C. Boost "
            + ", ".join(recommended[:3])
            + "."
        ),
    }

def fetch_and_prepare_data():
    """Fetch sales data from Supabase with retry logic"""
    
    def _fetch_from_supabase():
        print("Fetching sales data from Supabase...")
        print(f"Connecting to: {URL}")
        response = supabase.table("sales_log").select("*").execute()
        return response
    
    try:
        response = _retry_with_backoff(_fetch_from_supabase, max_retries=5)
        df = pd.DataFrame(response.data)
        print(f"Successfully fetched {len(df)} records from sales_log")
    except Exception as e:
        print(f"\nERROR: Failed to connect to Supabase")
        print(f"Exception: {str(e)}\n")
        print("Troubleshooting steps:")
        print("1. Verify SUPABASE_URL and SUPABASE_KEY are set in .env")
        print("2. Check your internet connection")
        print("3. Verify the Supabase project is accessible")
        print("4. Check if your IP is blocked by firewall/proxy")
        print("5. Visit https://status.supabase.com to check service status\n")
        raise
    
    csv_path = SCRIPT_DIR / 'data' / 'processed' / 'master_training_data.csv'
    if not csv_path.exists():
        raise FileNotFoundError(f"Training data not found at {csv_path}")
    
    enriched_df = pd.read_csv(csv_path)
    print(f"Loaded {len(enriched_df)} training records from CSV")
    return df, enriched_df

def format_basket_rules(rules_df):
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
        antecedents = list(row['antecedents']) if hasattr(row['antecedents'], '__iter__') else [row['antecedents']]
        consequents = list(row['consequents']) if hasattr(row['consequents'], '__iter__') else [row['consequents']]
        
        pair_1 = antecedents[0] if antecedents else "Item"
        pair_2 = consequents[0] if consequents else "Item"
        pair_key = frozenset([pair_1, pair_2])

        if pair_1 == pair_2 or pair_key in seen_pairs:
            continue

        seen_pairs.add(pair_key)
        raw_confidence = _safe_float(row['confidence'] if 'confidence' in row else 0.0)
        lift = _safe_float(row['lift'] if 'lift' in row else 0.0)
        pair_count = int(_safe_float(row['pair_count'] if 'pair_count' in row else 0))
        antecedent_count = int(
            _safe_float(row['antecedent_count'] if 'antecedent_count' in row else 0)
        )
        confidence = (
            (pair_count + 1) / (antecedent_count + 2)
            if antecedent_count > 0
            else raw_confidence
        )
        confidence_percent = min(round(confidence * 100), 95)

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

        if len(bundles) == 5:
            break
    
    return bundles


def _fruit_baselines(item_sales):
    if item_sales.empty:
        return {}

    observed_dates = sorted(item_sales["date"].unique())[-7:]
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
                quantity_kg = max(quantity_kg * 1.4, quantity_kg + 1)
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
                unit_price = DEFAULT_FRUIT_PRICES.get(fruit_name, 100)
                quantity_kg = 2.0
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
        )[:5]

        total_revenue = sum(item["expected_revenue"] for item in fruit_rows)
        total_kg = sum(item["suggested_kg"] for item in fruit_rows)
        updated_day = {
            **day,
            "top_fruits": fruit_rows,
            "expected_revenue": round(total_revenue),
            "revenue_label": f"Expected revenue: {_format_rupees(total_revenue)}",
            "stock_label": f"Top stock target: {_format_kg(total_kg)} across {len(fruit_rows)} fruits",
            "action": (
                "Prepare "
                + ", ".join(item["stock_label"] for item in fruit_rows[:3])
                + "."
            )
            if fruit_rows
            else day["action"],
        }

        if is_festival_day and festival_fruits:
            updated_day["event_adjustment"] = (
                "Festival boost added for "
                + ", ".join(festival_fruits[:3])
                + "."
            )

        updated_advice.append(updated_day)

    return updated_advice

def format_forecast_advice(forecast_df):
    """Convert forecast rows into clear inventory actions for the app"""
    if forecast_df.empty:
        return []
    
    advice = []
    for idx, row in forecast_df.tail(7).iterrows():
        date_str = str(row['ds']).split(' ')[0] if 'ds' in row else ""
        predicted = max(0.0, _safe_float(row['yhat'] if 'yhat' in row else 0.0))
        upper_bound = max(predicted, _safe_float(row['yhat_upper'] if 'yhat_upper' in row else predicted))
        lower_bound = max(0.0, min(predicted, _safe_float(row['yhat_lower'] if 'yhat_lower' in row else predicted)))
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
                "model_basis": row.get('model_basis', 'sales trend') if hasattr(row, 'get') else 'sales trend',
            }
        )
    
    return advice


def build_forecast_summary(stock_advice):
    if not stock_advice:
        return "Add a few more sales to generate a reliable demand forecast."
    average_revenue = round(
        sum(item.get("expected_revenue", 0) for item in stock_advice)
        / len(stock_advice)
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


def insert_daily_insight(insight_data):
    try:
        return supabase.table("daily_insights").insert(insight_data).execute()
    except Exception as e:
        message = str(e).lower()
        optional_json_columns = ("festival_advice", "weather_advice")
        missing_optional_column = (
            any(column in message for column in optional_json_columns)
            or (
                "could not find" in message
                and "column" in message
                and any(column.replace("_advice", "") in message for column in optional_json_columns)
            )
        )
        if not missing_optional_column:
            raise

        fallback_data = {
            key: value
            for key, value in insight_data.items()
            if key not in optional_json_columns
        }
        print("Optional insight columns not found; retrying without event/weather data.")
        print("Run sql/setup_daily_insights_table.sql to enable all insight cards.")
        return supabase.table("daily_insights").insert(fallback_data).execute()

def log_performance(metrics):
    log_path = SCRIPT_DIR / "logs" / "performance_history.csv"
    log_path.parent.mkdir(parents=True, exist_ok=True)

    log_entry = pd.DataFrame([{
        "timestamp": datetime.now().isoformat(),
        **metrics
    }])

    # Write header only if file is new or empty
    file_is_new = not log_path.exists() or log_path.stat().st_size == 0
    log_entry.to_csv(log_path, mode='a', header=file_is_new, index=False)

def main():

    print("Starting RetailFlow AI intelligence pipeline...")

    raw_sales, enriched_data = fetch_and_prepare_data()

    print("Running market basket analysis...")
    basket_rules = run_basket_analysis(raw_sales)

    print("Generating demand forecast...")
    forecast, forecast_metrics= run_demand_forecasting(enriched_data)

    print("Formatting insights for Flutter app...")
    
    # Parse and structure the outputs
    suggested_bundles = format_basket_rules(basket_rules)
    stock_advice = format_forecast_advice(forecast)
    festival_advice = get_festival_advice(enriched_data)
    stock_advice = _apply_per_fruit_breakdown(
        stock_advice,
        enriched_data,
        festival_advice,
    )
    tomorrow_weather = fetch_tomorrow_weather()
    stock_advice, weather_advice = _apply_weather_adjustment(
        stock_advice,
        tomorrow_weather,
    )
    
    # Generate summary
    forecast_summary = build_forecast_summary(stock_advice)
    
    print("Syncing insights back to Supabase...")
    # Push insights to Supabase
    insight_data = {
        "forecast_summary": forecast_summary,
        "suggested_bundles": suggested_bundles,
        "stock_advice": stock_advice,
        "festival_advice": festival_advice,
        "weather_advice": weather_advice,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    # Validate & standardize payload so Flutter decoding never breaks on schema drift.
    insight_data, validation_errors = validate_and_standardize_payload(insight_data)
    if validation_errors:
        print("Payload validation warnings:")
        for err in validation_errors:
            print(f" - {err}")


    try:
        result = insert_daily_insight(insight_data)
        print("Insights successfully pushed to cloud!")
        print(f"   Forecast: {forecast_summary}")
        if festival_advice:
            print(f"   Festival alert: {festival_advice['title']}")
        if weather_advice:
            print(f"   Weather alert: {weather_advice.get('action')}")
        print(f"   Bundles: {len(suggested_bundles)} recommendations")
        print(f"   Stock advice: {len(stock_advice)} days forecasted")

        
        metrics = {
            "status": "success",
            "bundles_generated": len(suggested_bundles),
            "forecast_days": len(stock_advice),
            "festival_active": bool(festival_advice),
            "total_records_fetched": len(raw_sales),
            "weekly_revenue_estimate": sum(
                day.get("expected_revenue", 0) for day in stock_advice
            ),
            # ✅ Spread forecast metrics in — handles the "not enough data" string gracefully
            **(forecast_metrics if isinstance(forecast_metrics, dict) else {
                "mae": None,
                "accuracy_score": None,
                "sample_size": 0,
            }),
        }
        log_performance(metrics)
        print("Performance log updated.")

    except Exception as e:
        print(f"Failed to insert insights: {e}")
        
        #log failures so we can track them
        log_performance({
            "status": "failed",
            "error": str(e),
            "bundles_generated": 0,
            "forecast_days": 0,
            "festival_active": False,
            "total_records_fetched": len(raw_sales) if 'raw_sales' in locals() else 0,
            "weekly_revenue_estimate": 0,
        })
        raise
    print("Pipeline Complete. Insights are ready!!")

if __name__ == "__main__":
    main()
    
