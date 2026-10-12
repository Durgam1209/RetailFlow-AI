-- Apply manually after reviewing. These views expose aggregates to anon clients;
-- Supabase Auth and owner/staff scoping should be decided before enabling them.

create or replace view public.daily_item_revenue_summary
with (security_invoker = false)
as
select
  s.created_date,
  coalesce(
    i->>'fruitName',
    i->>'fruit_name',
    i->>'name',
    'Unknown item'
  ) as fruit_name,
  sum(
    coalesce(
      nullif(i->>'lineTotal', '')::numeric,
      nullif(i->>'quantityKg', '')::numeric
        * nullif(i->>'unitPrice', '')::numeric,
      0
    )
  ) as total_revenue
from public.sales_log as s
cross join lateral jsonb_array_elements(
  case when jsonb_typeof(s.items) = 'array' then s.items else '[]'::jsonb end
) as i
group by s.created_date, fruit_name;

create or replace view public.sales_by_hour_summary
with (security_invoker = false)
as
select
  s.created_date,
  extract(hour from s.created_time)::integer as hour_of_day,
  sum(s.total_amount)::numeric as total_revenue,
  count(*)::bigint as total_transactions
from public.sales_log as s
group by s.created_date, hour_of_day;

create or replace view public.daily_sales_metrics_summary
with (security_invoker = false)
as
select
  created_date,
  to_char(created_date, 'Dy') as day_of_week,
  sum(total_amount)::numeric as total_revenue,
  count(transaction_id)::bigint as total_transactions,
  avg(total_amount)::numeric as average_bill_value
from public.sales_log
group by created_date;

grant select on public.daily_item_revenue_summary to anon, authenticated;
grant select on public.sales_by_hour_summary to anon, authenticated;
grant select on public.daily_sales_metrics_summary to anon, authenticated;
