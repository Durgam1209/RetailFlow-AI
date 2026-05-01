create table if not exists public.sales_log (
  transaction_id text primary key,
  created_at timestamptz not null default now(),
  created_date date not null default current_date,
  created_time time without time zone not null default localtime(0),
  total_amount numeric(10, 2) not null,
  item_count integer not null default 0,
  items jsonb not null,
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
