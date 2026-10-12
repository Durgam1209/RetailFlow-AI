"""Shared runtime settings for the RetailFlow ML pipeline."""

from __future__ import annotations

import json
import logging
import os
import random
import subprocess
import sys
from datetime import UTC, datetime
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

import dotenv
import numpy as np

dotenv.load_dotenv()

RANDOM_SEED = int(os.getenv("ML_RANDOM_SEED", "42"))
random.seed(RANDOM_SEED)
np.random.seed(RANDOM_SEED)

LOGGER_NAME = "retailflow.ml_pipeline"

PIPELINE_LOG_LEVEL = os.getenv("PIPELINE_LOG_LEVEL", "INFO").upper()
SUPABASE_TIMEOUT_SECONDS = 60
SUPABASE_MAX_RETRIES = 5
RETRY_INITIAL_DELAY_SECONDS = 2
WEATHER_TIMEOUT_SECONDS = 10
WEATHER_CONNECT_TIMEOUT_SECONDS = 5
WEATHER_MAX_RETRIES = 3
WEATHER_CACHE_FILENAME = "weather_cache.json"
DEFAULT_WEATHER_CITY = "Mahadevapura, Bengaluru"
DEFAULT_WEATHER_LATITUDE = 12.9916
DEFAULT_WEATHER_LONGITUDE = 77.6926
DEFAULT_WEATHER_CITY = "Mahadevapura, Bengaluru"
DEFAULT_WEATHER_LATITUDE = 12.9916
DEFAULT_WEATHER_LONGITUDE = 77.6926
FORECAST_HORIZON_DAYS = 7
FORECAST_MIN_TRAIN_DAYS = 14
FORECAST_HOLDOUT_DAYS = 7
FORECAST_MIN_ITEM_HISTORY_DAYS = int(os.getenv("MIN_ITEM_HISTORY_DAYS", "28"))
FORECAST_MIN_ITEM_NONZERO_DAYS = int(os.getenv("MIN_ITEM_NONZERO_DAYS", "7"))
FORECAST_CLOSED_DATES = frozenset(
    value.strip() for value in os.getenv("SHOP_CLOSED_DATES", "").split(",") if value.strip()
)
FORECAST_EXCLUDED_DATES = frozenset(
    value.strip()
    for value in os.getenv("FORECAST_EXCLUDED_DATES", "").split(",")
    if value.strip()
)
BASKET_MIN_TRANSACTIONS = int(os.getenv("BASKET_MIN_TRANSACTIONS", "20"))
BASKET_MIN_SUPPORT_COUNT = int(os.getenv("BASKET_MIN_SUPPORT_COUNT", "3"))
BASKET_MIN_LIFT = float(os.getenv("BASKET_MIN_LIFT", "1.2"))
METRIC_REGRESSION_THRESHOLD = float(os.getenv("METRIC_REGRESSION_THRESHOLD", "0.25"))
INSIGHTS_SCHEMA_VERSION = "1.0"
CONFIDENCE_HIGH_SPREAD = 0.35
CONFIDENCE_MEDIUM_SPREAD = 0.65
BUNDLE_STRONG_CONFIDENCE = 0.70
BUNDLE_GOOD_CONFIDENCE = 0.45
WHOLE_KG_LABEL_THRESHOLD = 10
WEATHER_HOT_THRESHOLD_C = 30
WEATHER_COLD_THRESHOLD_C = 18
WEATHER_RAIN_PROBABILITY_THRESHOLD = 0.5
WEATHER_HUMIDITY_THRESHOLD = 70
WEATHER_PICK_QUANTITY_KG = 2.0
RECENT_SALES_DAYS = 7
FESTIVAL_DEMAND_MULTIPLIER = 1.4
FESTIVAL_MINIMUM_EXTRA_KG = 1.0
FORECAST_TREND_CAP = 0.25
PROPHET_INTERVAL_WIDTH = 0.8
PERFORMANCE_MIN_REGRESSION_RUNS = 3
PERFORMANCE_TRAILING_RUNS = 7
DEFAULT_UNIT_PRICE = 100
MAX_RECOMMENDED_FRUITS = 5
MAX_FESTIVAL_RECOMMENDATIONS = 3
MAX_ACTION_FRUIT_NAMES = 3
MAX_STOCK_ADVICE_ITEMS = 5
BUNDLE_CONFIDENCE_CAP_PERCENT = 95
BUNDLE_CONFIDENCE_PRIOR_COUNT = 1
BUNDLE_ANTECEDENT_PRIOR_COUNT = 2
MIN_RULE_ITEMSET_SIZE = 2
MIN_RULE_ITEMSET_SIZE = 2
MIN_RULE_ITEMSET_SIZE = 2
FORECAST_INTERVAL_LOWER_FACTOR = 0.75
FORECAST_INTERVAL_UPPER_FACTOR = 1.25
SCHEMA_ERROR_SAMPLE_LIMIT = 5

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
DEFAULT_FESTIVAL_FRUITS = ["Banana", "Apple Washington", "Pomegranate"]
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


class JsonLogFormatter(logging.Formatter):
    """Format each log record as one timestamped JSON object with its context fields."""

    _reserved = set(logging.makeLogRecord({}).__dict__)

    def format(self, record: logging.LogRecord) -> str:
        """Serialize a log record, its extra fields, and any traceback as JSON."""
        output = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        output.update(
            {
                key: value
                for key, value in record.__dict__.items()
                if key not in self._reserved and key not in output
            }
        )
        if record.exc_info:
            output["exception"] = self.formatException(record.exc_info)
        return json.dumps(output, default=str, ensure_ascii=False)


def configure_logging() -> None:
    """Set timestamped application logging with an environment-controlled level."""
    level = getattr(logging, PIPELINE_LOG_LEVEL, logging.INFO)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonLogFormatter())
    logging.basicConfig(
        level=level,
        handlers=[handler],
        force=True,
    )


def runtime_metadata() -> dict[str, str | int]:
    """Return Python/library versions and the current repository commit for run logs."""
    package_names = ("pandas", "numpy", "prophet", "mlxtend", "supabase", "holidays")
    versions: dict[str, str | int] = {
        "python_version": sys.version.split()[0],
        "random_seed": RANDOM_SEED,
    }
    for package_name in package_names:
        try:
            versions[f"{package_name}_version"] = version(package_name)
        except PackageNotFoundError:
            versions[f"{package_name}_version"] = "not-installed"
    repo_root = Path(__file__).resolve().parent.parent
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        versions["git_sha"] = result.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        versions["git_sha"] = "unknown"
    return versions
