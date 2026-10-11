import ast
import json
import os

import pandas as pd
from prophet import Prophet

MIN_PROPHET_DAYS = 14
HOLDOUT_DAYS = 7
MIN_ITEM_HISTORY_DAYS = int(os.getenv('MIN_ITEM_HISTORY_DAYS', '28'))
MIN_ITEM_NONZERO_DAYS = int(os.getenv('MIN_ITEM_NONZERO_DAYS', '7'))


def _calendar_days(start, end):
    """Calendar days are open by default; optionally omit known closed dates."""
    closed = {value.strip() for value in os.getenv('SHOP_CLOSED_DATES', '').split(',') if value.strip()}
    days = pd.date_range(start, end, freq='D')
    if not closed:
        return days
    return pd.DatetimeIndex([day for day in days if day.strftime('%Y-%m-%d') not in closed])


def _daily_demand_frame(df):
    """Build Prophet-ready daily transaction volume for the app forecast."""
    if df.empty or 'created_date' not in df.columns:
        return pd.DataFrame(columns=['ds', 'y'])
    demand_column = 'item_count' if 'item_count' in df.columns else 'total_amount'
    daily = (
        df.assign(created_date=pd.to_datetime(df['created_date'], errors='coerce'))
        .dropna(subset=['created_date'])
        .groupby('created_date', as_index=False)[demand_column].sum()
        .rename(columns={'created_date': 'ds', demand_column: 'y'})
        .sort_values('ds')
    )
    daily['y'] = pd.to_numeric(daily['y'], errors='coerce').fillna(0).clip(lower=0)
    if daily.empty:
        return daily
    calendar = _calendar_days(daily['ds'].min(), daily['ds'].max())
    return daily.set_index('ds').reindex(calendar, fill_value=0).rename_axis('ds').reset_index()


def _small_data_forecast(daily):
    if daily.empty:
        return pd.DataFrame(columns=['ds', 'yhat', 'yhat_upper', 'yhat_lower'])
    recent = daily.tail(7).copy()
    weights = pd.Series(range(1, len(recent) + 1), dtype='float')
    baseline = float((recent['y'].reset_index(drop=True) * weights).sum() / weights.sum())
    previous_average = float(recent['y'].iloc[:-1].mean()) if len(recent) > 1 else baseline
    latest = float(recent['y'].iloc[-1])
    trend_ratio = 0 if previous_average == 0 else (latest - previous_average) / previous_average
    trend_ratio = max(min(trend_ratio, 0.25), -0.25)
    dates = _calendar_days(daily['ds'].max() + pd.Timedelta(days=1),
                           daily['ds'].max() + pd.Timedelta(days=14))[:7]
    return pd.DataFrame([
        {'ds': day, 'yhat': max(0, baseline * (1 + trend_ratio * i / 7)),
         'yhat_lower': max(0, baseline * (1 + trend_ratio * i / 7) * .75),
         'yhat_upper': max(0, baseline * (1 + trend_ratio * i / 7) * 1.25),
         'model_basis': 'recent sales average'}
        for i, day in enumerate(dates, 1)
    ])


def _item_daily_frames(df):
    """Extract quantity (kg) by item, filling no-sale days with zero."""
    if df.empty or 'created_date' not in df or 'items' not in df:
        return {}
    rows = []
    for _, sale in df[['created_date', 'items']].iterrows():
        day = pd.to_datetime(sale['created_date'], errors='coerce')
        if pd.isna(day):
            continue
        items = sale['items']
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
            name = item.get('fruitName') or item.get('fruit_name') or item.get('name')
            try:
                quantity = float(item.get('quantityKg', 0) or 0)
            except (ValueError, TypeError):
                quantity = 0
            if name and quantity >= 0:
                rows.append({'ds': day.normalize(), 'item': str(name), 'y': quantity})
    if not rows:
        return {}
    transactions = pd.DataFrame(rows).groupby(['item', 'ds'], as_index=False)['y'].sum()
    start, end = transactions['ds'].min(), transactions['ds'].max()
    calendar = _calendar_days(start, end)
    result = {}
    for name, group in transactions.groupby('item'):
        frame = group.set_index('ds')[['y']].reindex(calendar, fill_value=0)
        frame.index.name = 'ds'
        result[name] = frame.reset_index()
    return result


def _score(actual, predicted):
    errors = predicted - actual
    denominator = float(actual.sum())
    return {
        'mae_kg': round(float(errors.abs().mean()), 3),
        'mse_kg2': round(float(errors.pow(2).mean()), 3),
        'rmse_kg': round(float((errors.pow(2).mean()) ** .5), 3),
        'wape_pct': round(float(errors.abs().sum() / denominator * 100), 2) if denominator else None,
        'bias_kg': round(float(errors.mean()), 3),
        'sample_size': int(len(actual)),
        'actual_kg': round(denominator, 3),
        'absolute_error_kg': round(float(errors.abs().sum()), 3),
    }


def _evaluate_items(item_frames):
    per_item = {}
    for name, daily in item_frames.items():
        nonzero_days = int((daily['y'] > 0).sum())
        if len(daily) < MIN_ITEM_HISTORY_DAYS or nonzero_days < MIN_ITEM_NONZERO_DAYS:
            per_item[name] = {
                'model_used': 'cold_start_fallback',
                'history_days': int(len(daily)),
                'nonzero_days': nonzero_days,
                'cold_start': True,
            }
            continue
        if len(daily) <= HOLDOUT_DAYS:
            continue
        train = daily.iloc[:-HOLDOUT_DAYS]
        test = daily.iloc[-HOLDOUT_DAYS:]
        actual = test['y'].reset_index(drop=True)
        naive = train['y'].iloc[-HOLDOUT_DAYS:].reset_index(drop=True)
        if len(naive) != len(test):
            continue
        prophet_prediction = None
        if len(train) >= MIN_PROPHET_DAYS and train['y'].sum() > 0:
            try:
                model = Prophet(yearly_seasonality=False, weekly_seasonality=True,
                                daily_seasonality=False, interval_width=.8)
                model.fit(train[['ds', 'y']])
                prophet_prediction = model.predict(test[['ds']])['yhat'].clip(lower=0).reset_index(drop=True)
            except Exception as error:
                print(f"Holdout Prophet evaluation failed for {name}: {error}")
        per_item[name] = {'baseline': _score(actual, naive)}
        if prophet_prediction is not None:
            per_item[name]['prophet'] = _score(actual, prophet_prediction)
            per_item[name]['beats_baseline'] = (
                per_item[name]['prophet']['mae_kg'] < per_item[name]['baseline']['mae_kg']
            )
    return per_item


def run_demand_forecasting(df):
    daily = _daily_demand_frame(df)
    item_metrics = _evaluate_items(_item_daily_frames(df))
    if len(daily) < MIN_PROPHET_DAYS:
        return _small_data_forecast(daily), {'item_metrics': item_metrics, 'evaluation_days': HOLDOUT_DAYS}
    prophet_df = daily.copy()
    prophet_df['floor'] = 0
    model = Prophet(yearly_seasonality=False, weekly_seasonality=True,
                    daily_seasonality=False, interval_width=0.8)
    model.fit(prophet_df)
    future = model.make_future_dataframe(periods=14)
    closed = {value.strip() for value in os.getenv('SHOP_CLOSED_DATES', '').split(',') if value.strip()}
    if closed:
        future = future[~future['ds'].dt.strftime('%Y-%m-%d').isin(closed)]
    future['floor'] = 0
    full_forecast = model.predict(future)
    full_forecast[['yhat', 'yhat_upper', 'yhat_lower']] = full_forecast[
        ['yhat', 'yhat_upper', 'yhat_lower']].clip(lower=0).round(2)
    forecast = full_forecast.tail(7).copy()
    forecast['model_basis'] = 'sales trend model'
    return forecast[['ds', 'yhat', 'yhat_upper', 'yhat_lower', 'model_basis']], {
        'item_metrics': item_metrics,
        'evaluation_days': HOLDOUT_DAYS,
        'metric_unit': 'kg per item',
    }
