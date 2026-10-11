import logging
import os
from pathlib import Path

import dotenv
import holidays
import pandas as pd
from config import configure_logging, runtime_metadata
from supabase import create_client

dotenv.load_dotenv()

SCRIPT_DIR = Path(__file__).parent
LOGGER = logging.getLogger(__name__)


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


def add_holiday_flags(frame: pd.DataFrame, calendar=None) -> pd.DataFrame:
    """Return a copy of sales rows with Indian holiday flags derived from their dates."""
    result = frame.copy()
    calendar = calendar if calendar is not None else holidays.India()
    created_dates = pd.to_datetime(result.get("created_date"), errors="coerce").dt.date
    result["is_holiday"] = created_dates.map(lambda value: bool(value and value in calendar))
    return result


def merge_weather(frame: pd.DataFrame, weather: pd.DataFrame | None) -> pd.DataFrame:
    """Left-merge weather observations by date, preserving sales when weather is missing."""
    result = frame.copy()
    if weather is None or weather.empty:
        result["weather_available"] = False
        return result
    result["created_date"] = pd.to_datetime(result["created_date"], errors="coerce").dt.date
    weather = weather.copy()
    weather["created_date"] = pd.to_datetime(weather["created_date"], errors="coerce").dt.date
    result = result.merge(weather, on="created_date", how="left", suffixes=("", "_weather"))
    weather_columns = [column for column in weather.columns if column != "created_date"]
    result["weather_available"] = result[weather_columns].notna().any(axis=1)
    return result


def main() -> None:
    """Fetch sales, attach known-date holiday context and export the training snapshot."""
    configure_logging()
    LOGGER.info("Fetching data from Supabase", extra={"runtime": runtime_metadata()})
    response = supabase.table("sales_log").select("*").execute()
    df = pd.DataFrame(response.data)
    LOGGER.info("Fetched sales rows", extra={"row_count": len(df)})

    if df.empty:
        LOGGER.warning("No sales data found; skipping export")
        return

    LOGGER.info("Processing Indian holidays")
    df = add_holiday_flags(df)
    LOGGER.info("Holiday context added")

    if not OPENWEATHER_API_KEY:
        LOGGER.warning("WEATHER_KEY not set; weather enrichment is skipped")

    output_path = SCRIPT_DIR / "data" / "processed" / "master_training_data.csv"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    LOGGER.info("Exporting enriched training data", extra={"path": str(output_path)})
    df.to_csv(output_path, index=False)
    LOGGER.info("Data enrichment complete")


if __name__ == "__main__":
    main()
