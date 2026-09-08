begin;
insert into auth.users(id,email) values ('00000000-0000-4000-8000-000000000001','rls-a@example.invalid'),('00000000-0000-4000-8000-000000000002','rls-b@example.invalid');
insert into public.profiles values ('00000000-0000-4000-8000-000000000001','Test A'),('00000000-0000-4000-8000-000000000002','Test B');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
insert into public.comments(post_slug,user_id,content) values ('rls-test','00000000-0000-4000-8000-000000000001','root');
insert into public.post_likes(post_slug,user_id) values ('rls-test','00000000-0000-4000-8000-000000000001');
do $$ begin
 begin
 insert into public.profiles(id,display_name) values ('00000000-0000-4000-8000-000000000099','Impersonator');
 raise exception 'FAIL: profile impersonation accepted';
 exception when insufficient_privilege then null; end;
 begin
 insert into public.post_likes(post_slug,user_id) values ('other','00000000-0000-4000-8000-000000000002');
 raise exception 'FAIL: like impersonation accepted';
 exception when insufficient_privilege then null; end;
 begin
 insert into public.comments(post_slug,user_id,content) values ('rls-test','00000000-0000-4000-8000-000000000001','spam');
 raise exception 'FAIL: spam accepted';
 exception when raise_exception then if SQLERRM not like 'Tunggu%' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
do $$ declare n integer; begin
 update public.comments set content='',deleted_at=now() where post_slug='rls-test';get diagnostics n=row_count;
 if n<>0 then raise exception 'FAIL: delete other comment';end if;
 delete from public.post_likes where post_slug='rls-test';get diagnostics n=row_count;
 if n<>0 then raise exception 'FAIL: delete other like';end if;
 update public.profiles set display_name='Hacked' where id='00000000-0000-4000-8000-000000000001';get diagnostics n=row_count;
 if n<>0 then raise exception 'FAIL: overwrite other profile';end if;
 begin
 insert into public.comments(post_slug,user_id,parent_id,content) select 'other','00000000-0000-4000-8000-000000000002',id,'cross post' from public.comments where post_slug='rls-test';
 raise exception 'FAIL: cross post reply accepted';exception when check_violation then null;end;
end $$;
insert into public.comments(post_slug,user_id,parent_id,content) select 'rls-test','00000000-0000-4000-8000-000000000002',id,'reply' from public.comments where post_slug='rls-test' and parent_id is null;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
update public.comments set content='',deleted_at=now() where post_slug='rls-test' and user_id='00000000-0000-4000-8000-000000000001';
delete from public.post_likes where post_slug='rls-test' and user_id='00000000-0000-4000-8000-000000000001';
do $$begin
 if not exists(select 1 from public.comments where post_slug='rls-test' and parent_id is not null and content='reply') then raise exception 'FAIL: reply lost after parent deletion';end if;
 if exists(select 1 from public.post_likes where post_slug='rls-test') then raise exception 'FAIL: unlike';end if;
end $$;
set local role anon;
do $$begin
 begin
 insert into public.comments(post_slug,user_id,content) values ('rls-test','00000000-0000-4000-8000-000000000001','anonymous');
 raise exception 'FAIL: anonymous write';exception when insufficient_privilege then null;end;
end $$;
select 'PASS: own writes, cross-user isolation, same-post replies, soft deletion, unlike, anonymous denial, rate limiting' as result;
rollback;
