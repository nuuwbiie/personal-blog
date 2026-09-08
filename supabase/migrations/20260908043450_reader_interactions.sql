-- Content stays in GitHub. These tables contain reader interactions only.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check (char_length(btrim(display_name)) between 2 and 50)
);
create table public.comments (
 id uuid primary key default gen_random_uuid(),
 post_slug text not null check (char_length(post_slug) between 1 and 180 and post_slug ~ '^[a-zA-Z0-9_/-]+$'),
 user_id uuid not null references public.profiles(id) on delete cascade,
 parent_id uuid,
 content text not null,
 created_at timestamptz not null default now(),
 deleted_at timestamptz,
 unique(id,post_slug),
 foreign key(parent_id,post_slug) references public.comments(id,post_slug),
 check (parent_id is null or parent_id<>id),
 check ((deleted_at is null and char_length(btrim(content)) between 1 and 3000) or (deleted_at is not null and content=''))
);
create index comments_post_created_idx on public.comments(post_slug,created_at,id);
create index comments_user_idx on public.comments(user_id,created_at desc);
create index comments_parent_idx on public.comments(parent_id,post_slug);
create table public.post_likes (
 post_slug text not null check (char_length(post_slug) between 1 and 180 and post_slug ~ '^[a-zA-Z0-9_/-]+$'),
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(post_slug,user_id)
);
create index post_likes_user_idx on public.post_likes(user_id);

alter table public.profiles enable row level security;
alter table public.comments enable row level security;
alter table public.post_likes enable row level security;
revoke all on public.profiles,public.comments,public.post_likes from anon,authenticated;
grant select on public.profiles,public.comments,public.post_likes to anon,authenticated;
grant insert(id,display_name),update(display_name) on public.profiles to authenticated;
grant insert(post_slug,user_id,parent_id,content),update(content,deleted_at) on public.comments to authenticated;
grant insert(post_slug,user_id),delete on public.post_likes to authenticated;

create policy profiles_read on public.profiles for select to anon,authenticated using (true);
create policy profiles_create_own on public.profiles for insert to authenticated with check (id=(select auth.uid()) and not coalesce((select auth.jwt()->>'is_anonymous')::boolean,false));
create policy profiles_update_own on public.profiles for update to authenticated using (id=(select auth.uid())) with check (id=(select auth.uid()));

create policy comments_read on public.comments for select to anon,authenticated using (true);
create policy comments_create_own on public.comments for insert to authenticated with check (user_id=(select auth.uid()) and deleted_at is null and not coalesce((select auth.jwt()->>'is_anonymous')::boolean,false));
create policy comments_delete_own on public.comments for update to authenticated using (user_id=(select auth.uid()) and deleted_at is null) with check (user_id=(select auth.uid()) and deleted_at is not null and content='');

create policy likes_read on public.post_likes for select to anon,authenticated using (true);
create policy likes_create_own on public.post_likes for insert to authenticated with check (user_id=(select auth.uid()) and not coalesce((select auth.jwt()->>'is_anonymous')::boolean,false));
create policy likes_delete_own on public.post_likes for delete to authenticated using (user_id=(select auth.uid()));

-- Invoker trigger sees public comments through SELECT RLS. Lock per author to make rate limits concurrency-safe.
create function private.validate_comment() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='INSERT' then
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,0));
  if exists(select 1 from public.comments where user_id=new.user_id and created_at>now()-interval '15 seconds') then
   raise exception 'Tunggu 15 detik sebelum mengirim komentar lagi' using errcode='P0001';
  end if;
  if (select count(*) from public.comments where user_id=new.user_id and created_at>now()-interval '1 hour') >= 30 then
   raise exception 'Terlalu banyak komentar. Tunggu satu jam' using errcode='P0001';
  end if;
  if new.parent_id is not null and not exists(select 1 from public.comments where id=new.parent_id and post_slug=new.post_slug and parent_id is null) then
   raise exception 'Reply must reference a root comment on the same post' using errcode='23514';
  end if;
  new.created_at=now();
 else
  if new.user_id<>old.user_id or new.post_slug<>old.post_slug or new.parent_id is distinct from old.parent_id or new.created_at<>old.created_at then
   raise exception 'Comment identity is immutable' using errcode='23514';
  end if;
  new.deleted_at=now();
  new.content='';
 end if;
 return new;
end;
$$;
revoke all on function private.validate_comment() from public,anon,authenticated;
create trigger validate_comment before insert or update on public.comments for each row execute function private.validate_comment();
