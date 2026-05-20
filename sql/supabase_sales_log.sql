create table if not exists public.sales_log (
  transaction_id text primary key,
  created_at timestamptz not null default now(),
  created_date date not null default current_date,
  created_time time without time zone not null default localtime(0),
  total_amount numeric(10, 2) not null,
  item_count integer not null default 0,
  items jsonb not null,
  weather jsonb not null default '{}'::jsonb,
  weather_temperature numeric(5, 2),
  weather_condition text,
  weather_humidity integer,
  weather_wind_speed numeric(6, 2),
  is_synced boolean not null default false
);

alter table public.sales_log
  alter column total_amount type numeric(10, 2),
  alter column created_at set default now(),
  alter column created_date set default current_date,
  alter column created_time type time without time zone using created_time::time,
  alter column created_time set default localtime(0);

alter table public.sales_log
  add column if not exists is_synced boolean not null default false;

alter table public.sales_log
  drop column if exists local_sync_status;

alter table public.sales_log
  add column if not exists item_count integer not null default 0;

alter table public.sales_log
  add column if not exists items jsonb not null default '[]'::jsonb;

alter table public.sales_log
  add column if not exists weather jsonb not null default '{}'::jsonb,
  add column if not exists weather_temperature numeric(5, 2),
  add column if not exists weather_condition text,
  add column if not exists weather_humidity integer,
  add column if not exists weather_wind_speed numeric(6, 2);

alter table public.sales_log
  enable row level security;

drop policy if exists "anon can insert sales_log" on public.sales_log;
create policy "anon can insert sales_log"
on public.sales_log
for insert
to anon, authenticated
with check (true);

drop policy if exists "anon can update sales_log" on public.sales_log;
create policy "anon can update sales_log"
on public.sales_log
for update
to anon, authenticated
using (true)
with check (true);

drop policy if exists "anon can select sales_log" on public.sales_log;
create policy "anon can select sales_log"
on public.sales_log
for select
to anon, authenticated
using (true);

create or replace view public.daily_sales_summary as
select
  created_date,
  to_char(created_date, 'Dy') as day_of_week,
  sum(total_amount::numeric) as total_revenue,
  count(transaction_id) as total_transactions
from public.sales_log
group by created_date
order by created_date desc;

grant select on public.daily_sales_summary to anon;
grant select on public.daily_sales_summary to authenticated;
