import os
from pathlib import Path

import dotenv
import holidays
import pandas as pd
from supabase import create_client


dotenv.load_dotenv()

SCRIPT_DIR = Path(__file__).parent


def _require_env(name):
    value = os.getenv(name)
    if value:
        return value
    raise RuntimeError(
        f"Missing required environment variable: {name}. "
        f"Add it to {SCRIPT_DIR / '.env'} before running the enrichment step."
    )


SUPABASE_URL = _require_env("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or _require_env("SUPABASE_KEY")
OPENWEATHER_API_KEY = os.getenv("WEATHER_KEY")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)


def main():
    print("Fetching data from Supabase...")
    response = supabase.table("sales_log").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Fetched {len(df)} rows from sales_log")

    if df.empty:
        print("No sales data found. Skipping export.")
        return

    print("Processing Indian holidays...")
    in_holidays = holidays.India()
    created_dates = pd.to_datetime(df.get("created_date"), errors="coerce").dt.date
    df["is_holiday"] = created_dates.map(lambda value: bool(value and value in in_holidays))
    print("Holiday context added")

    if not OPENWEATHER_API_KEY:
        print("OPENWEATHER_API_KEY not set. Weather enrichment is skipped for now.")

    output_path = SCRIPT_DIR / "data" / "processed" / "master_training_data.csv"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Exporting to {output_path}...")
    df.to_csv(output_path, index=False)
    print("Data enrichment complete")


if __name__ == "__main__":
    main()
