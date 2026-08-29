-- Perfect Week: adds plans.assigned_weekday.
--
-- Run once in the Supabase SQL editor (Dashboard > SQL Editor > New query >
-- paste > Run), in project vybypyeyzfgakenkotbw.
--
-- IMPORTANT: check the project ref in your browser's address bar first.
-- Running this in the wrong project fails with "relation public.plans
-- does not exist", which looks alarming but means nothing was changed.
--
-- The app does NOT need this to work. Until it runs, weekday assignments
-- are stored and shown on the device but do not sync. Supabase rejects an
-- upsert naming a column it does not have, so the app detects that once,
-- pushes plans without this field, and retries the full set every 10
-- minutes -- meaning running this starts the sync with no reload and
-- nothing to undo.
--
-- 0-6, JS Date.getDay() convention (0 = Sunday .. 6 = Saturday) -- same
-- convention weekdayTemplate() already used for the old name-matching
-- fallback, so no day-of-week remapping was needed when this shipped.
-- NULL means "not locked to a day" (a free-floating template you apply
-- manually, like before this feature existed).
--
-- Safe to run more than once.

alter table public.plans add column if not exists assigned_weekday smallint;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'plans_assigned_weekday_range_check') then
    alter table public.plans
      add constraint plans_assigned_weekday_range_check check (assigned_weekday is null or assigned_weekday between 0 and 6);
  end if;
end $$;

-- One plan per weekday is enforced in the app (assignWeekdayToPlan clears
-- the old holder before writing the new one), not with a DB constraint --
-- a unique index here would fight the app during the brief window a swap
-- is mid-sync across devices.

-- No RLS changes needed. This is a new column on an existing table, so the
-- existing owner = auth.uid() policy already covers it.

notify pgrst, 'reload schema';

-- Verify: should return one row, assigned_weekday / smallint.
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'plans'
  and column_name  = 'assigned_weekday';
