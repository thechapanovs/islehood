-- Tests for 004_join_leave_island.sql. Run from the repo root with:
--   psql "$URL" -X -f supabase/tests/004_join_leave_island_test.sql
-- Everything is rolled back at the end. Lines marked EXPECT say what you should see.

begin;

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ann@example.test','{"display_name":"Ann"}'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bo@example.test','{"display_name":"Bo"}'),
 ('33333333-3333-3333-3333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cy@example.test','{"display_name":"Cy"}');

-- Remember Ann's invite code (read as admin before switching roles)
select invite_code as ann_code from public.islands where name = 'Ann''s island' \gset

-- A helper view for the checks (admin only, rolled back at the end)
create temp view state as
select u.display_name, i.name as island, i.is_solo, m.role, m.status
from public.memberships m
join public.users u on u.id = m.user_id
join public.islands i on i.id = m.island_id
order by u.display_name, i.name;
grant select on state to authenticated;

set local role authenticated;

\echo '1. Bo joins Ann. EXPECT: Ann island shared; Bo active member there; Bo solo island set_aside'
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}',true) \gset
select public.join_island(:'ann_code') is not null as joined;
reset role;
select * from state order by 1,2;
set local role authenticated;

\echo '2. Bo joins Ann again. EXPECT: succeeds, nothing changes (no error)'
select public.join_island(lower(:'ann_code')) is not null as still_ok;

\echo '3. Bad code. EXPECT error: That invite code does not match an island'
savepoint a;
select public.join_island('ZZZZZZZZ');
rollback to a;

\echo '4. Cy joins Ann too (no limit). EXPECT: success'
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}',true) \gset
select public.join_island(:'ann_code') is not null as joined;

\echo '5. Bo cannot join another island while on Ann''s. Need Cy''s solo code first'
reset role;
select invite_code as cy_code from public.islands where name = 'Cy''s island' \gset
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}',true) \gset
\echo '   EXPECT error: Leave your current island before joining another'
savepoint b;
select public.join_island(:'cy_code');
rollback to b;

\echo '6. Ann (creator) tries to leave. EXPECT error: The island creator cannot leave yet'
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true) \gset
savepoint c;
select public.leave_island();
rollback to c;

\echo '7. Solo person tries to leave. Create Dee first (admin), then EXPECT error: You are not on a shared island'
reset role;
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
values ('44444444-4444-4444-4444-444444444444','00000000-0000-0000-0000-000000000000','authenticated','authenticated','dee@example.test','{"display_name":"Dee"}');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated"}',true) \gset
savepoint d;
select public.leave_island();
rollback to d;

\echo '8. Bo leaves. EXPECT: returns his own island id; Bo active on Bo island, Ann island still shared (Ann, Cy... Cy still on it)'
select set_config('request.jwt.claims','{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}',true) \gset
select public.leave_island() is not null as back_home;
reset role;
select * from state order by 1,2;
set local role authenticated;

\echo '9. Cy leaves too. EXPECT: Ann island is solo again (is_solo = true)'
select set_config('request.jwt.claims','{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}',true) \gset
select public.leave_island() is not null as back_home;
reset role;
select * from state where island = 'Ann''s island';
set local role authenticated;

\echo '10. Anonymous cannot call join_island. EXPECT permission denied'
reset role;
set local role anon;
savepoint e;
select public.join_island(:'ann_code');
rollback to e;

reset role;
rollback;

\echo '11. EXPECT 0 (nothing left behind)'
select count(*) as leftover_users from public.users;
