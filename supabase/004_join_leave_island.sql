-- Feature 1: joining and leaving islands
-- The app cannot write to islands or memberships directly (see 003).
-- These two functions are the only way in and out. They run with the owner's
-- rights ("security definer") and check everything themselves.
--
-- Rules:
--   * One active island at a time.
--   * Joining from a solo island sets that solo island aside (never deletes it).
--   * Leaving a shared island brings the set-aside solo island back.
--   * No limit on island size for now (decided Nov 17).

-- join_island('ABCD1234') -> the island's id
create function public.join_island(code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  target public.islands;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  select * into target
  from public.islands
  where invite_code = upper(trim(code));

  if not found then
    raise exception 'That invite code does not match an island';
  end if;

  -- Already on this island: nothing to do.
  if exists (
    select 1 from public.memberships
    where island_id = target.id and user_id = me and status = 'active'
  ) then
    return target.id;
  end if;

  -- Already active on a different shared island: leave it first.
  if exists (
    select 1
    from public.memberships m
    join public.islands i on i.id = m.island_id
    where m.user_id = me and m.status = 'active' and i.is_solo = false
  ) then
    raise exception 'Leave your current island before joining another';
  end if;

  -- Set aside the solo island (kept, not deleted).
  update public.memberships
  set status = 'set_aside'
  where user_id = me and status = 'active';

  -- Join. If they had been on this island before, bring them back.
  insert into public.memberships (island_id, user_id, role, status)
  values (target.id, me, 'member', 'active')
  on conflict (island_id, user_id) do update set status = 'active';

  -- An island with 2 or more people is no longer solo.
  update public.islands set is_solo = false where id = target.id;

  return target.id;
end;
$$;

-- leave_island() -> the id of the island they are back on
create function public.leave_island()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  current_island uuid;
  creator_role text;
  back_on uuid;
  left_count int;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  select m.island_id, m.role into current_island, creator_role
  from public.memberships m
  join public.islands i on i.id = m.island_id
  where m.user_id = me and m.status = 'active' and i.is_solo = false;

  if current_island is null then
    raise exception 'You are not on a shared island';
  end if;

  if creator_role = 'creator' then
    raise exception 'The island creator cannot leave yet';
  end if;

  delete from public.memberships
  where island_id = current_island and user_id = me;

  -- If only one person is left, the island is solo again.
  select count(*) into left_count
  from public.memberships
  where island_id = current_island and status = 'active';
  if left_count <= 1 then
    update public.islands set is_solo = true where id = current_island;
  end if;

  -- Bring the set-aside solo island back.
  update public.memberships
  set status = 'active'
  where user_id = me and status = 'set_aside'
  returning island_id into back_on;

  return back_on;
end;
$$;

-- Only signed-in people may call these.
revoke execute on function public.join_island(text) from public, anon;
revoke execute on function public.leave_island() from public, anon;
grant execute on function public.join_island(text) to authenticated;
grant execute on function public.leave_island() to authenticated;
