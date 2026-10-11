# Privacy and Data Retention

## Data in this repository's application schema

The `sales_log` table stores transaction IDs, sale timestamps, totals, item names and quantities, unit prices, and optional weather observations. The current schema and Flutter checkout do not collect customer names, phone numbers, email addresses, account IDs, or device IDs. Transaction IDs identify a sale and are generated locally; they are not linked to a customer profile.

`daily_insights` stores forecast summaries, suggested product bundles, inventory advice, and created/updated timestamps. `daily_sales_summary` exposes daily revenue and transaction counts only.

## Purpose and retention

Sales records support inventory forecasting, sales analytics, and basket analysis. Insight records support the app's recommendations screen. The current schema has no automatic retention or deletion schedule: records remain until a shop operator deletes them. Local pending transactions remain on-device until synced or removed by the shop operator.

## Deletion

There is no customer profile or customer-keyed data to delete in the current schema. A shop operator can delete a specific sale by its transaction ID in the Supabase dashboard or with a restricted administrative SQL session, for example:

```sql
DELETE FROM public.sales_log
WHERE transaction_id = 'TXN-YYYYMMDD-HHMMSS-NNNN';
```

This deletion is not exposed to the public Flutter client. If customer-identifying fields are added later, add a customer identifier, retention policy, and customer-scoped deletion procedure before collecting them.
