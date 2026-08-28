-- Joy and Drain: adds channels.joy and channels.drain.
--
-- Run once in the Supabase SQL editor (Dashboard > SQL Editor > New query >
-- paste > Run), in project vybypyeyzfgakenkotbw.
--
-- IMPORTANT: check the project ref in your browser's address bar first.
-- Running this in the wrong project fails with "relation public.channels does
-- not exist", which looks alarming but means nothing was changed.
--
-- The app does NOT need this to work. Until it runs, joy and drain are stored
-- and reported on the device but do not sync. Supabase rejects an upsert
-- naming a column it does not have, so the app detects that once, pushes
-- channels without these two fields, and retries the full set every 10
-- minutes -- meaning running this starts the sync with no reload and nothing
-- to undo.
--
-- Safe to run more than once.

alter table public.channels add column if not exists joy   smallint;
alter table public.channels add column if not exists drain smallint;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'channels_joy_check') then
    alter table public.channels
      add constraint channels_joy_check check (joy is null or joy between 1 and 5);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'channels_drain_check') then
    alter table public.channels
      add constraint channels_drain_check check (drain is null or drain between 1 and 5);
  end if;
end $$;

-- No RLS changes needed. These are new columns on an existing table, so the
-- existing owner = auth.uid() policy already covers them.

notify pgrst, 'reload schema';

-- Verify: should return two rows, joy / drain, both smallint.
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'channels'
  and column_name in ('joy','drain')
order by column_name;
