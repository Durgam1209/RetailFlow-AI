import pandas as pd
from supabase import create_client
import ast
import json
import os
import dotenv
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
import holidays
from models.basket_analyzer import run_basket_analysis
from models.demand_forecaster import run_demand_forecasting

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

def fetch_and_prepare_data():

    #pulling the data from sales_log table
    response = supabase.table("sales_log").select("*").execute()
    df = pd.DataFrame(response.data)
    csv_path = SCRIPT_DIR / 'data' / 'processed' / 'master_training_data.csv'
    enriched_df = pd.read_csv(csv_path)
    return df,enriched_df

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
        is_missing_festival_column = (
            "festival_advice" in message
            or ("could not find" in message and "column" in message and "festival" in message)
        )
        if not is_missing_festival_column:
            raise

        fallback_data = {
            key: value
            for key, value in insight_data.items()
            if key != "festival_advice"
        }
        print("festival_advice column not found; retrying without event banner data.")
        print("Run sql/setup_daily_insights_table.sql to enable festival banners.")
        return supabase.table("daily_insights").insert(fallback_data).execute()

def main():

    print("Starting RetailFlow AI intelligence pipeline...")

    raw_sales, enriched_data = fetch_and_prepare_data()

    print("Running market basket analysis...")
    basket_rules = run_basket_analysis(raw_sales)

    print("Generating demand forecast...")
    forecast = run_demand_forecasting(enriched_data)

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
    
    # Generate summary
    forecast_summary = build_forecast_summary(stock_advice)
    
    print("Syncing insights back to Supabase...")
    # Push insights to Supabase
    insight_data = {
        "forecast_summary": forecast_summary,
        "suggested_bundles": suggested_bundles,
        "stock_advice": stock_advice,
        "festival_advice": festival_advice,
        "created_at": datetime.now(timezone.utc).isoformat()
    }

    try:
        result = insert_daily_insight(insight_data)
        print("Insights successfully pushed to cloud!")
        print(f"   Forecast: {forecast_summary}")
        if festival_advice:
            print(f"   Festival alert: {festival_advice['title']}")
        print(f"   Bundles: {len(suggested_bundles)} recommendations")
        print(f"   Stock advice: {len(stock_advice)} days forecasted")
    except Exception as e:
        print(f"Failed to insert insights: {e}")
        print("   Make sure the 'daily_insights' table exists in Supabase")
        print("   Check RLS policies - anon key needs INSERT access")
        raise
    print("Pipeline Complete. Insights are ready!!")

if __name__ == "__main__":
    main()
    

