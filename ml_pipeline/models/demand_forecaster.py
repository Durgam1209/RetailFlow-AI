import pandas as pd
from prophet import Prophet
from sklearn.metrics import mean_absolute_error

MIN_PROPHET_DAYS = 14


def _daily_demand_frame(df):
    """Build Prophet-ready daily item demand from sales transactions."""
    if df.empty or 'created_date' not in df.columns:
        return pd.DataFrame(columns=['ds', 'y'])

    demand_column = 'item_count' if 'item_count' in df.columns else 'total_amount'
    daily = (
        df.assign(created_date=pd.to_datetime(df['created_date'], errors='coerce'))
        .dropna(subset=['created_date'])
        .groupby('created_date', as_index=False)[demand_column]
        .sum()
        .rename(columns={'created_date': 'ds', demand_column: 'y'})
        .sort_values('ds')
    )
    daily['y'] = pd.to_numeric(daily['y'], errors='coerce').fillna(0).clip(lower=0)
    return daily


def _small_data_forecast(daily):
    """Use a stable weighted-average forecast until there is enough history."""
    if daily.empty:
        return pd.DataFrame(columns=['ds', 'yhat', 'yhat_upper', 'yhat_lower'])

    recent = daily.tail(7).copy()
    weights = pd.Series(range(1, len(recent) + 1), dtype='float')
    baseline = float((recent['y'].reset_index(drop=True) * weights).sum() / weights.sum())

    previous_average = float(recent['y'].iloc[:-1].mean()) if len(recent) > 1 else baseline
    latest = float(recent['y'].iloc[-1])
    trend_ratio = 0 if previous_average == 0 else (latest - previous_average) / previous_average
    trend_ratio = max(min(trend_ratio, 0.25), -0.25)

    start_date = daily['ds'].max() + pd.Timedelta(days=1)
    dates = pd.date_range(start_date, periods=7, freq='D')

    rows = []
    for index, date in enumerate(dates, start=1):
        gentle_trend = 1 + (trend_ratio * index / 7)
        yhat = max(0, baseline * gentle_trend)
        rows.append(
            {
                'ds': date,
                'yhat': yhat,
                'yhat_lower': max(0, yhat * 0.75),
                'yhat_upper': max(0, yhat * 1.25),
                'model_basis': 'recent sales average',
            }
        )

    return pd.DataFrame(rows)


def run_demand_forecasting(df):
    daily = _daily_demand_frame(df)
    if len(daily) < MIN_PROPHET_DAYS:
        return _small_data_forecast(daily), {}   # ← unpack-safe empty metrics

    prophet_df = daily.copy()
    prophet_df['floor'] = 0

    model = Prophet(
        yearly_seasonality=False,
        weekly_seasonality=True,
        daily_seasonality=False,
        interval_width=0.8,
    )
    model.fit(prophet_df)

    future = model.make_future_dataframe(periods=7)
    future['floor'] = 0
    full_forecast = model.predict(future)   # ← keep full forecast (historical + future)

    full_forecast[['yhat', 'yhat_upper', 'yhat_lower']] = (
        full_forecast[['yhat', 'yhat_upper', 'yhat_lower']]
        .clip(lower=0)
        .round(2)
    )

    # ✅ Metrics use historical overlap (actuals vs in-sample predictions)
    daily_df = prophet_df.rename(columns={'y': 'y'})[['ds', 'y']]
    performance = calculate_performance_metrics(daily_df, full_forecast)

    # Slice to future 7 days only for the app
    forecast = full_forecast.tail(7).copy()
    forecast['model_basis'] = 'sales trend model'

    return forecast[['ds', 'yhat', 'yhat_upper', 'yhat_lower', 'model_basis']], performance

def calculate_performance_metrics(daily_df, forecast_df):
    """Compare recent actual sales to previous predictions."""
    # Align actuals and predictions on the date (ds)
    actuals = daily_df[['ds', 'y']].copy()
    preds = forecast_df[['ds', 'yhat']].copy()
    
    merged = actuals.merge(preds, on='ds', how='inner')
    
    if merged.empty:
        return "Not enough overlapping data for performance metrics."

    mae = mean_absolute_error(merged['y'], merged['yhat'])
    accuracy_pct = max(0, 100 - (mae / merged['y'].mean() * 100)) if merged['y'].mean() > 0 else 0
    
    return {
        "mae": round(mae, 2),
        "accuracy_score": f"{round(accuracy_pct, 1)}%",
        "sample_size": len(merged)
    }