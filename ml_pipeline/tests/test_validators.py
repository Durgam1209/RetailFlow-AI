import pandas as pd
import pytest
from validators import validate_sales_data


def sales_frame(items=None):
    return pd.DataFrame(
        {
            "transaction_id": ["tx-1"],
            "created_at": ["2026-01-01T10:00:00Z"],
            "created_date": ["2026-01-01"],
            "total_amount": [10],
            "item_count": [len(items or [])],
            "items": [items or []],
        }
    )


def test_negative_quantity_is_excluded_and_counted():
    frame = sales_frame([{"fruitName": "Apple", "quantityKg": -1, "unitPrice": 10}])
    clean, excluded = validate_sales_data(frame)
    assert excluded == 1
    assert clean.iloc[0]["items"] == []


def test_duplicate_transactions_are_removed():
    frame = pd.concat([sales_frame(), sales_frame()], ignore_index=True)
    clean, _ = validate_sales_data(frame)
    assert len(clean) == 1
    assert clean.attrs["validation_warnings"]


def test_null_transaction_key_fails_clearly():
    frame = sales_frame()
    frame.loc[0, "transaction_id"] = None
    with pytest.raises(ValueError, match="transaction_id"):
        validate_sales_data(frame)


def test_empty_input_fails_required_schema_check():
    with pytest.raises(ValueError, match="missing required columns"):
        validate_sales_data(pd.DataFrame())
