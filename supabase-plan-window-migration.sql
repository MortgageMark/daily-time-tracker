-- Per-plan day window: adds start_hour, end_hour and increment_minutes to
-- both plans and dayplans, so a Tuesday template can run to different hours
-- than a Thursday one and a materialised day keeps the window it was made with.
--
-- Run once in the Supabase SQL editor (Dashboard > SQL Editor > New query >
-- paste > Run), in project vybypyeyzfgakenkotbw.
--
-- IMPORTANT: check the project ref in your browser's address bar first.
-- Running this in the wrong project fails with "relation public.plans does
-- not exist", which looks alarming but means nothing was changed.
--
-- The app does NOT need this to work. Until it runs the window is stored and
-- honoured on the device but does not sync: Supabase rejects an upsert naming
-- a column it does not have, so the app detects that once, pushes without
-- these fields, and retries the full set every 10 minutes.
--
-- NULL means "use the default", which is 8am to 6pm in 30-minute slots.
--
-- Safe to run more than once.

alter table public.plans    add column if not exists start_hour        smallint;
alter table public.plans    add column if not exists end_hour          smallint;
alter table public.plans    add column if not exists increment_minutes smallint;

alter table public.dayplans add column if not exists start_hour        smallint;
alter table public.dayplans add column if not exists end_hour          smallint;
alter table public.dayplans add column if not exists increment_minutes smallint;

do $$
declare t text;
begin
  foreach t in array array['plans','dayplans'] loop
    if not exists (select 1 from pg_constraint where conname = t||'_window_check') then
      execute format(
        'alter table public.%I add constraint %I check ('||
        '(start_hour is null or start_hour between 0 and 23) and '||
        '(end_hour is null or end_hour between 1 and 24) and '||
        '(increment_minutes is null or increment_minutes in (15,30,60)))', t, t||'_window_check');
    end if;
  end loop;
end $$;

-- No RLS changes needed: new columns on existing tables, already covered by
-- the owner = auth.uid() policies.

notify pgrst, 'reload schema';

-- Verify: should return six rows, three per table.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('plans','dayplans')
  and column_name in ('start_hour','end_hour','increment_minutes')
order by table_name, column_name;
