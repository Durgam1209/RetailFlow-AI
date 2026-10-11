import pandas as pd
import pytest
from models.demand_forecaster import _newsvendor_quantile, _score, _time_holdout_split


def test_metrics_match_hand_computed_values():
    metrics = _score(pd.Series([2.0, 4.0]), pd.Series([3.0, 2.0]))
    assert metrics["mae_kg"] == 1.5
    assert metrics["mse_kg2"] == 2.5
    assert metrics["rmse_kg"] == pytest.approx(2.5**0.5, abs=0.001)
    assert metrics["wape_pct"] == 50.0
    assert metrics["bias_kg"] == -0.5


def test_newsvendor_quantile_uses_underage_and_overage_costs():
    # Cu = 8 - 3 = 5; Co = 3; Cu / (Cu + Co) = 5 / 8.
    assert _newsvendor_quantile(unit_price=8, unit_cost=3) == pytest.approx(0.625)
    assert _newsvendor_quantile(unit_price=2, unit_cost=5) == 0


def test_evaluation_rows_never_enter_training_rows():
    series = pd.DataFrame({"ds": pd.date_range("2026-01-01", periods=12), "y": range(12)})
    train, evaluation = _time_holdout_split(series, 3)
    assert train["ds"].max() < evaluation["ds"].min()
    assert set(train["ds"]).isdisjoint(evaluation["ds"])
    assert evaluation["y"].tolist() == [9, 10, 11]
