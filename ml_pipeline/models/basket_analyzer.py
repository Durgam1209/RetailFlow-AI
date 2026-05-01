from mlxtend.frequent_patterns import apriori, association_rules
import ast
import json
import pandas as pd


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
    return item.get('name') or item.get('fruitName') or item.get('fruit_name')


def run_basket_analysis(df):
    if df.empty or 'items' not in df.columns or 'transaction_id' not in df.columns:
        return pd.DataFrame(columns=['antecedents', 'consequents', 'confidence', 'lift'])

    # Convert JSONB items list into a transaction matrix[cite: 1]
    df = df.copy()
    df['items'] = df['items'].apply(_parse_items)
    exploded = df.explode('items')
    exploded['fruit_name'] = exploded['items'].apply(_item_name)
    exploded = exploded.dropna(subset=['fruit_name'])

    if exploded.empty:
        return pd.DataFrame(columns=['antecedents', 'consequents', 'confidence', 'lift'])
    
    # One-Hot Encoding
    basket = (exploded.groupby(['transaction_id', 'fruit_name'])['fruit_name']
              .count().unstack().reset_index().fillna(0)
              .set_index('transaction_id'))
    
    basket_sets = basket.map(lambda x: x > 0)
    
    transaction_count = len(basket_sets)
    min_support = max(0.05, 2 / transaction_count)

    # Find frequent itemsets
    frequent_itemsets = apriori(basket_sets, min_support=min_support, use_colnames=True)
    
    # Handle case where no frequent itemsets are found
    if len(frequent_itemsets) == 0:
        return pd.DataFrame(columns=['antecedents', 'consequents', 'confidence', 'lift'])
    
    rules = association_rules(frequent_itemsets, metric="lift", min_threshold=1)
    
    # Return empty dataframe if no rules found
    if len(rules) == 0:
        return pd.DataFrame(columns=['antecedents', 'consequents', 'confidence', 'lift'])
    
    rules['pair_count'] = (rules['support'] * transaction_count).round().astype(int)
    rules['antecedent_count'] = (
        rules['antecedent support'] * transaction_count
    ).round().astype(int)

    return rules[
        [
            'antecedents',
            'consequents',
            'confidence',
            'lift',
            'pair_count',
            'antecedent_count',
        ]
    ]
