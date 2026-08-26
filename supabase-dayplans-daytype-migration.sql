-- Non-working days: adds dayplans.day_type.
--
-- Run this once in the Supabase SQL editor (Dashboard > SQL Editor > New query
-- > paste > Run), in project vybypyeyzfgakenkotbw.
--
-- IMPORTANT: check the project ref in your browser's address bar first. Running
-- this in the wrong project fails with "relation public.dayplans does not
-- exist", which looks alarming but means nothing was changed.
--
-- The app does NOT need this to work. Until it runs, marking a day off works
-- normally on the device but does not sync to your other devices. Supabase
-- rejects an upsert naming a column it does not have, so the app detects that
-- once, pushes dayplans without this field, and retries the full set every 10
-- minutes -- meaning running this starts the sync with no reload and nothing
-- to undo.
--
-- Safe to run more than once.

alter table public.dayplans add column if not exists day_type text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'dayplans_day_type_check') then
    alter table public.dayplans
      add constraint dayplans_day_type_check
      check (day_type is null or day_type in ('vacation','holiday','sick','personal'));
  end if;
end $$;

-- No RLS changes needed. This is a new column on an existing table, so the
-- existing dayplans_own_rows policy (owner = auth.uid()) already covers it.

notify pgrst, 'reload schema';

-- Verify: should return one row, day_type / text.
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'dayplans'
  and column_name  = 'day_type';
