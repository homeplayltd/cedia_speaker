-- ================================================================
-- CEDIA Board Speaker Queue — Polling Feature
-- Run this entire file in your Supabase SQL Editor to add live
-- polls to an existing project. Safe to run more than once.
-- ================================================================

-- ----------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------

-- A poll: a question with a fixed list of options (stored as a JSON
-- array of strings). Only one poll is "active" at a time — that's the
-- one shown on the display, vote, and moderator pages.
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

-- ----------------------------------------------------------------
-- Enable Realtime
-- ----------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table polls;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table poll_votes;
exception when duplicate_object then null;
end $$;

-- ----------------------------------------------------------------
-- Row Level Security (open for this use-case — tighten if needed)
-- ----------------------------------------------------------------
alter table polls enable row level security;
alter table poll_votes enable row level security;

drop policy if exists "Public read/write on polls" on polls;
create policy "Public read/write on polls"
  on polls for all to anon
  using (true)
  with check (true);

drop policy if exists "Public read/write on poll_votes" on poll_votes;
create policy "Public read/write on poll_votes"
  on poll_votes for all to anon
  using (true)
  with check (true);

-- ----------------------------------------------------------------
-- RPC: launch_poll
-- Deactivates any current poll and creates a new active one.
-- ----------------------------------------------------------------
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

-- ----------------------------------------------------------------
-- RPC: close_poll
-- Stops voting on a poll but keeps its results visible.
-- ----------------------------------------------------------------
create or replace function close_poll(p_id uuid)
returns void
language sql
security definer
as $$
  update polls set is_closed = true where id = p_id;
$$;

grant execute on function close_poll(uuid) to anon;

-- ----------------------------------------------------------------
-- RPC: clear_active_poll
-- Removes the poll from the display/vote pages (deactivates it).
-- Vote history is kept.
-- ----------------------------------------------------------------
create or replace function clear_active_poll()
returns void
language sql
security definer
as $$
  update polls set is_active = false where is_active = true;
$$;

grant execute on function clear_active_poll() to anon;

-- ----------------------------------------------------------------
-- RPC: cast_vote
-- Records (or changes) a voter's choice. Rejects votes once the
-- poll is closed or no longer active.
-- ----------------------------------------------------------------
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
