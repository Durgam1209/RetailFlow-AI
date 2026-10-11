# Supabase Access Audit

This audit reflects the policies and grants defined by the SQL files in this repository. Existing Supabase projects may also have dashboard-created policies or grants; inspect `pg_policies` and table privileges before applying the migration.

## Current access found before `harden_rls.sql`

| Object | RLS enabled? | `anon` can do | `authenticated` can do | `service_role` can do |
|---|---|---|---|---|
| `public.sales_log` | Yes | Select, insert, and update all raw sales rows under permissive `true` policies | Same as `anon` | RLS bypass; table grants depend on project defaults |
| `public.daily_insights` | Yes | Select all insight rows | Select grant existed but no authenticated read policy | Insert, select, and update under the setup script's grants; RLS bypass |
| `public.daily_sales_summary` (view) | N/A | Select daily revenue and transaction counts | Select daily revenue and transaction counts | Owner/service access |

`sales_log` contains raw transaction IDs, timestamps, item names/quantities/prices, and weather data. It contains no customer name, phone, email, or device ID in the current schema, but public raw-row read/update access was broader than necessary.

## Access after manually applying `sql/harden_rls.sql`

| Object | RLS enabled? | `anon` can do | `authenticated` can do | `service_role` can do |
|---|---|---|---|---|
| `public.sales_log` | Yes | Insert only, if transaction ID, amount, item count/list, and weather shape checks pass | No table access | All table operations; Supabase service role bypasses RLS for the backend pipeline |
| `public.daily_insights` | Yes | Select all public insight rows | No table access | Insert; Supabase service role bypasses RLS |
| `public.daily_sales_summary` (view) | N/A | Select aggregate daily totals | Select aggregate daily totals | Owner/service access |

The `USING (true)` policy remains only for `daily_insights` SELECT because these generated recommendations are intentionally public app content. The raw sales insert policy uses explicit shape and range checks. The service role relies on Supabase's documented RLS bypass and explicit table grants; it does not need a permissive RLS policy.

The migration is a proposed file only. It has not been applied to Supabase.
