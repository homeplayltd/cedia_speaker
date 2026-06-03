-- ================================================================
-- CEDIA Board Speaker Queue — Supabase Schema
-- Run this entire file in your Supabase SQL Editor
-- ================================================================

-- Meeting state (single row, always id = 1)
create table if not exists meeting_state (
  id integer primary key default 1,
  topic text not null default '',
  current_speaker_name text default null,
  current_speaker_subject text default null,
  speaker_started_at timestamptz default null,
  updated_at timestamptz default now(),
  constraint single_row check (id = 1)
);

-- Columns added after the original release (idempotent for existing projects)
alter table meeting_state add column if not exists queue_open boolean not null default true;
alter table meeting_state add column if not exists speaker_time_seconds integer not null default 120;

-- Seed the single row
insert into meeting_state (id) values (1) on conflict (id) do nothing;

-- Speaker queue (FIFO by joined_at)
create table if not exists queue (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  subject text not null,
  joined_at timestamptz default now()
);

-- ----------------------------------------------------------------
-- Enable Realtime
-- ----------------------------------------------------------------
alter publication supabase_realtime add table meeting_state;
alter publication supabase_realtime add table queue;

-- ----------------------------------------------------------------
-- Row Level Security (open for this use-case — tighten if needed)
-- ----------------------------------------------------------------
alter table meeting_state enable row level security;
alter table queue enable row level security;

create policy "Public read/write on meeting_state"
  on meeting_state for all to anon
  using (true)
  with check (true);

create policy "Public read/write on queue"
  on queue for all to anon
  using (true)
  with check (true);

-- ----------------------------------------------------------------
-- RPC: clear_queue
-- Deletes all rows from the queue with SECURITY DEFINER so it
-- bypasses RLS. Called from the moderator panel.
-- ----------------------------------------------------------------
create or replace function clear_queue()
returns void
language sql
security definer
as $$
  delete from queue where true;
$$;

-- Grant execute to anon role
grant execute on function clear_queue() to anon;

-- ----------------------------------------------------------------
-- RPC: reset_meeting
-- Clears the queue AND resets meeting_state in one call.
-- ----------------------------------------------------------------
create or replace function reset_meeting()
returns void
language sql
security definer
as $$
  delete from queue where true;
  update meeting_state set
    topic = '',
    current_speaker_name = null,
    current_speaker_subject = null,
    speaker_started_at = null,
    updated_at = now()
  where id = 1;
$$;

grant execute on function reset_meeting() to anon;

-- ----------------------------------------------------------------
-- RPC: set_topic
-- Sets a new topic and clears the queue atomically.
-- ----------------------------------------------------------------
create or replace function set_topic(new_topic text)
returns void
language sql
security definer
as $$
  delete from queue where true;
  update meeting_state set
    topic = new_topic,
    current_speaker_name = null,
    current_speaker_subject = null,
    speaker_started_at = null,
    updated_at = now()
  where id = 1;
$$;

grant execute on function set_topic(text) to anon;

-- ----------------------------------------------------------------
-- RPC: next_speaker  
-- Removes first queue entry and sets them as current speaker.
-- ----------------------------------------------------------------
create or replace function next_speaker()
returns void
language plpgsql
security definer
as $$
declare
  v_next record;
begin
  select * into v_next from queue order by joined_at asc limit 1;
  if v_next is null then return; end if;
  delete from queue where id = v_next.id;
  update meeting_state set
    current_speaker_name = v_next.name,
    current_speaker_subject = v_next.subject,
    speaker_started_at = now(),
    updated_at = now()
  where id = 1;
end;
$$;

grant execute on function next_speaker() to anon;

-- ----------------------------------------------------------------
-- RPC: end_speaker
-- Clears the current speaker without advancing.
-- ----------------------------------------------------------------
create or replace function end_speaker()
returns void
language sql
security definer
as $$
  update meeting_state set
    current_speaker_name = null,
    current_speaker_subject = null,
    speaker_started_at = null,
    updated_at = now()
  where id = 1;
$$;

grant execute on function end_speaker() to anon;

-- ----------------------------------------------------------------
-- RPC: remove_from_queue
-- Removes a single speaker by UUID.
-- ----------------------------------------------------------------
create or replace function remove_from_queue(row_id uuid)
returns void
language sql
security definer
as $$
  delete from queue where id = row_id;
$$;

grant execute on function remove_from_queue(uuid) to anon;

-- ================================================================
-- POLLS — live polling feature
-- (Also available standalone in supabase/polls.sql)
-- ================================================================

-- A poll: a question with a fixed list of options (JSON array of
-- strings). Only one poll is "active" at a time.
create table if not exists polls (
  id uuid primary key default gen_random_uuid(),
  question text not null,
  options jsonb not null default '[]'::jsonb,
  is_active boolean not null default false,
  is_closed boolean not null default false,
  created_at timestamptz default now()
);

-- One row per voter per poll. A device votes once (unique voter_id),
-- but may change its choice until the poll is closed.
create table if not exists poll_votes (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null references polls(id) on delete cascade,
  option_index integer not null,
  voter_id text not null,
  created_at timestamptz default now(),
  unique (poll_id, voter_id)
);

-- Realtime
alter publication supabase_realtime add table polls;
alter publication supabase_realtime add table poll_votes;

-- RLS (open for this use-case)
alter table polls enable row level security;
alter table poll_votes enable row level security;

create policy "Public read/write on polls"
  on polls for all to anon using (true) with check (true);

create policy "Public read/write on poll_votes"
  on poll_votes for all to anon using (true) with check (true);

-- RPC: launch_poll — deactivate current poll, create a new active one
create or replace function launch_poll(p_question text, p_options jsonb)
returns polls
language plpgsql
security definer
as $$
declare
  v_poll polls;
begin
  update polls set is_active = false where is_active = true;
  insert into polls (question, options, is_active, is_closed)
    values (p_question, p_options, true, false)
    returning * into v_poll;
  return v_poll;
end;
$$;

grant execute on function launch_poll(text, jsonb) to anon;

-- RPC: close_poll — stop voting but keep results visible
create or replace function close_poll(p_id uuid)
returns void language sql security definer as $$
  update polls set is_closed = true where id = p_id;
$$;

grant execute on function close_poll(uuid) to anon;

-- RPC: clear_active_poll — remove poll from display/vote pages
create or replace function clear_active_poll()
returns void language sql security definer as $$
  update polls set is_active = false where is_active = true;
$$;

grant execute on function clear_active_poll() to anon;

-- RPC: cast_vote — record or change a voter's choice (rejects if closed)
create or replace function cast_vote(p_poll_id uuid, p_voter_id text, p_option_index integer)
returns void
language plpgsql
security definer
as $$
begin
  if not exists (
    select 1 from polls
    where id = p_poll_id and is_active = true and is_closed = false
  ) then
    raise exception 'Poll is not open for voting';
  end if;

  insert into poll_votes (poll_id, voter_id, option_index)
    values (p_poll_id, p_voter_id, p_option_index)
  on conflict (poll_id, voter_id)
    do update set option_index = excluded.option_index, created_at = now();
end;
$$;

grant execute on function cast_vote(uuid, text, integer) to anon;
