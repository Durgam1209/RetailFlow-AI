import pandas as pd
from models.basket_analyzer import run_basket_analysis


def test_tiny_fixture_returns_expected_association():
    # 12 of 30 baskets contain A+B, while each item appears in 15: lift = 1.6.
    rows = []
    for index in range(30):
        items = [{"fruitName": "Apple"}]
        if index < 12:
            items.append({"fruitName": "Banana"})
        elif index < 15:
            pass
        elif index < 18:
            items.append({"fruitName": "Banana"})
        else:
            items = [{"fruitName": "Orange"}]
        rows.append({"transaction_id": f"tx-{index}", "items": items})
    rules = run_basket_analysis(pd.DataFrame(rows))
    assert not rules.empty
    assert set(rules["transaction_count"]) == {30}
    assert any(
        {"Apple", "Banana"} == set(rule.antecedents | rule.consequents)
        for rule in rules.itertuples()
    )


def test_empty_rules_case_returns_empty_frame():
    rows = [
        {"transaction_id": f"tx-{index}", "items": [{"fruitName": "Apple"}]} for index in range(25)
    ]
    assert run_basket_analysis(pd.DataFrame(rows)).empty
