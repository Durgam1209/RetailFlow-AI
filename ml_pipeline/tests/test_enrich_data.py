import pandas as pd
from enrich_data import add_holiday_flags, merge_weather


def test_holiday_flags_use_date_calendar():
    frame = pd.DataFrame({"created_date": ["2026-01-01", "2026-01-02"]})
    result = add_holiday_flags(frame, {pd.Timestamp("2026-01-01").date(): "Holiday"})
    assert result["is_holiday"].tolist() == [True, False]
    assert "is_holiday" not in frame


def test_weather_merge_matches_date_and_marks_missing_weather():
    sales = pd.DataFrame({"created_date": ["2026-01-01", "2026-01-02"], "qty": [2, 3]})
    weather = pd.DataFrame({"created_date": ["2026-01-01"], "temperature": [24.5]})
    result = merge_weather(sales, weather)
    assert result.loc[0, "temperature"] == 24.5
    assert result["weather_available"].tolist() == [True, False]


def test_missing_weather_keeps_sales_and_marks_unavailable():
    sales = pd.DataFrame({"created_date": ["2026-01-01"], "qty": [2]})
    result = merge_weather(sales, None)
    assert result["qty"].tolist() == [2]
    assert result["weather_available"].tolist() == [False]
