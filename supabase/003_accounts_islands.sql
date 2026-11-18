-- Feature 1: accounts and islands
-- Tables: users, islands, memberships. Security rules (RLS) on all three.
-- A trigger gives every new sign-up a profile and a solo island.

-- 1. users: one row per person (the public profile for an auth account)
create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 30),
  time_zone text not null default 'UTC',
  created_at timestamptz not null default now()
);

-- 2. islands: a shared island (or a person's solo island)
create table public.islands (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique
    default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  created_by uuid not null references public.users (id) on delete cascade,
  is_solo boolean not null default false,
  created_at timestamptz not null default now()
);

-- 3. memberships: who is on which island
-- status 'set_aside' = a solo island the person left to join friends (never deleted)
create table public.memberships (
  island_id uuid not null references public.islands (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  role text not null default 'member' check (role in ('creator', 'member')),
  status text not null default 'active' check (status in ('active', 'set_aside')),
  joined_at timestamptz not null default now(),
  primary key (island_id, user_id)
);

create index memberships_user_id_idx on public.memberships (user_id);

alter table public.users enable row level security;
alter table public.islands enable row level security;
alter table public.memberships enable row level security;

-- Helper: is the signed-in person a member of this island?
-- "security definer" runs it with the owner's rights so the rules below
-- can call it without looping back into themselves.
create function public.is_island_member(check_island uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.island_id = check_island and m.user_id = auth.uid()
  );
$$;

-- Helper: do I share an island with this person?
create function public.shares_island_with(other_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships mine
    join public.memberships theirs on theirs.island_id = mine.island_id
    where mine.user_id = auth.uid() and theirs.user_id = other_user
  );
$$;

-- users: you can read yourself and people on your islands. You can edit only yourself.
create policy "read myself and island mates" on public.users
  for select to authenticated
  using (id = auth.uid() or public.shares_island_with(id));

create policy "edit myself" on public.users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- islands: members can read their islands. Changes happen only through trusted functions.
create policy "members read their islands" on public.islands
  for select to authenticated
  using (public.is_island_member(id));

-- memberships: you can see who is on your islands. Joining and leaving use functions later.
create policy "members read their island's memberships" on public.memberships
  for select to authenticated
  using (public.is_island_member(island_id));

-- Grants: the app (signed-in people only) may read, and update only two profile columns.
revoke all on public.users, public.islands, public.memberships from anon, authenticated;
grant select on public.users, public.islands, public.memberships to authenticated;
grant update (display_name, time_zone) on public.users to authenticated;

-- New sign-up: make the profile, a solo island, and the membership.
-- Unity can send display_name and time_zone as sign-up metadata.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_name text;
  new_island uuid;
begin
  new_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    split_part(new.email, '@', 1),
    'Islander'
  );
  new_name := left(new_name, 30);

  insert into public.users (id, display_name, time_zone)
  values (
    new.id,
    new_name,
    coalesce(nullif(new.raw_user_meta_data ->> 'time_zone', ''), 'UTC')
  );

  insert into public.islands (name, created_by, is_solo)
  values (new_name || '''s island', new.id, true)
  returning id into new_island;

  insert into public.memberships (island_id, user_id, role)
  values (new_island, new.id, 'creator');

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
