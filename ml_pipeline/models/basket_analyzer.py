import ast
import json
import logging

import pandas as pd
from config import (
    BASKET_MIN_LIFT,
    BASKET_MIN_SUPPORT_COUNT,
    BASKET_MIN_TRANSACTIONS,
)
from mlxtend.frequent_patterns import apriori, association_rules

LOGGER = logging.getLogger(__name__)


def _parse_items(value):
    if isinstance(value, list):
        return value
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return ast.literal_eval(value)
        return []


def _item_name(item):
    if not isinstance(item, dict):
        return None
    return item.get("name") or item.get("fruitName") or item.get("fruit_name")


def run_basket_analysis(df: pd.DataFrame) -> pd.DataFrame:
    """Return supported, high-lift association rules from validated transaction baskets."""
    if df.empty or "items" not in df.columns or "transaction_id" not in df.columns:
        return pd.DataFrame(columns=["antecedents", "consequents", "confidence", "lift"])

    min_transactions = BASKET_MIN_TRANSACTIONS
    min_support_count = BASKET_MIN_SUPPORT_COUNT
    min_lift = BASKET_MIN_LIFT
    empty = pd.DataFrame(
        columns=[
            "antecedents",
            "consequents",
            "confidence",
            "lift",
            "pair_count",
            "antecedent_count",
            "transaction_count",
        ]
    )

    # Convert JSONB item lists into a transaction matrix.
    df = df.copy()
    df["items"] = df["items"].apply(_parse_items)
    exploded = df.explode("items")
    exploded["fruit_name"] = exploded["items"].apply(_item_name)
    exploded = exploded.dropna(subset=["fruit_name"])

    if exploded.empty:
        return empty

    # One-Hot Encoding
    basket = (
        exploded.groupby(["transaction_id", "fruit_name"])["fruit_name"]
        .count()
        .unstack()
        .reset_index()
        .fillna(0)
        .set_index("transaction_id")
    )

    basket_sets = basket.map(lambda x: x > 0)

    transaction_count = len(basket_sets)
    if transaction_count < min_transactions:
        LOGGER.info(
            "Basket analysis skipped below transaction threshold",
            extra={"transaction_count": transaction_count, "minimum": min_transactions},
        )
        return empty
    min_support = min(1.0, min_support_count / transaction_count)
    # Carry the full basket sample size for confidence labels in the app.

    # Find frequent itemsets
    frequent_itemsets = apriori(basket_sets, min_support=min_support, use_colnames=True, max_len=3)

    # Handle case where no frequent itemsets are found
    if len(frequent_itemsets) == 0:
        return empty
    # Keep singleton supports; association_rules needs them to compute confidence/lift.
    rules = association_rules(frequent_itemsets, metric="lift", min_threshold=min_lift)

    # Return empty dataframe if no rules found
    if len(rules) == 0:
        return empty

    rules["pair_count"] = (rules["support"] * transaction_count).round().astype(int)
    rules["antecedent_count"] = (
        (rules["antecedent support"] * transaction_count).round().astype(int)
    )
    rules["transaction_count"] = transaction_count
    rules = rules[(rules["pair_count"] >= min_support_count) & (rules["lift"] > min_lift)]
    if rules.empty:
        return empty

    return rules[
        [
            "antecedents",
            "consequents",
            "confidence",
            "lift",
            "pair_count",
            "antecedent_count",
            "transaction_count",
        ]
    ]
