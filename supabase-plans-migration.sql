-- Daily Time Tracker — plans + dayplans sync
--
-- Run this once in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to run more than once (every statement is guarded).
--
-- Column conventions copied from the existing channels/sessions tables:
--   id text primary key, owner uuid default auth.uid(), profile_id text,
--   snake_case columns, created_at / updated_at timestamptz.

-- ---------------------------------------------------------------
-- plans — reusable templates ("Monday", "Heavy Pipeline Day", ...)
-- ---------------------------------------------------------------
create table if not exists public.plans (
  id          text primary key,
  owner       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  profile_id  text not null,
  name        text not null default 'Plan',
  schedule    jsonb not null default '{}'::jsonb,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- dayplans — one materialised schedule per profile per date.
-- This is what makes "edit today without changing the template" work.
-- ---------------------------------------------------------------
create table if not exists public.dayplans (
  id          text primary key,          -- "<profile_id>|<date>"
  owner       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  profile_id  text not null,
  date        text not null,             -- business date, YYYY-MM-DD
  plan_id     text,                      -- template it came from (may be null)
  plan_name   text,                      -- snapshot of the template name
  schedule    jsonb not null default '{}'::jsonb,
  edited      boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create unique index if not exists dayplans_owner_profile_date_idx
  on public.dayplans (owner, profile_id, date);

-- ---------------------------------------------------------------
-- Row Level Security — each user sees only their own rows,
-- matching how channels/sessions are already protected.
-- ---------------------------------------------------------------
alter table public.plans    enable row level security;
alter table public.dayplans enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies
                 where schemaname='public' and tablename='plans' and policyname='plans_own_rows') then
    create policy plans_own_rows on public.plans
      for all using (owner = auth.uid()) with check (owner = auth.uid());
  end if;

  if not exists (select 1 from pg_policies
                 where schemaname='public' and tablename='dayplans' and policyname='dayplans_own_rows') then
    create policy dayplans_own_rows on public.dayplans
      for all using (owner = auth.uid()) with check (owner = auth.uid());
  end if;
end $$;

-- ---------------------------------------------------------------
-- Keep updated_at honest — the sync merge compares it to decide
-- whether a remote row should overwrite a local one.
-- ---------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists plans_touch_updated_at on public.plans;
create trigger plans_touch_updated_at
  before update on public.plans
  for each row execute function public.touch_updated_at();

drop trigger if exists dayplans_touch_updated_at on public.dayplans;
create trigger dayplans_touch_updated_at
  before update on public.dayplans
  for each row execute function public.touch_updated_at();

-- Verify
select 'plans' as table, count(*) from public.plans
union all
select 'dayplans', count(*) from public.dayplans;
