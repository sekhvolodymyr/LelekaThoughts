-- LelekaThoughts. Schema and authorization. Seed content lives in seed.sql.
create schema if not exists app_private;
revoke all on schema app_private from public;
grant usage on schema app_private to anon, authenticated, service_role;

-- Apply after schema.sql and maintenance.sql. No paid services or client privileges added.
create or replace function app_private.valid_media(m jsonb, allow_video boolean default false)
returns boolean language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(m) is distinct from 'object' then return false; end if;
 if jsonb_typeof(m->'path') is distinct from 'string' or jsonb_typeof(m->'src') is distinct from 'string' or jsonb_typeof(m->'type') is distinct from 'string' then return false; end if;
 if not ((m->>'src' ~ '^https://[^[:space:]]+$' or m->>'src' ~ '^/media/[a-zA-Z0-9._/-]+$') is true) then return false; end if;
 if m->>'type' in ('image/jpeg','image/png','image/webp','image/gif') then return true; end if;
 if allow_video and m->>'type' in ('video/mp4','video/webm','video/quicktime') then
  if jsonb_typeof(m->'duration') is distinct from 'number' then return false; end if;
  return ((m->>'duration')::numeric>0 and (m->>'duration')::numeric<=30) is true;
 end if;
 return false;
end $$;
create or replace function app_private.valid_post_media(m jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(m) is distinct from 'array' then return false; end if;
 if jsonb_array_length(m)>4 then return false; end if;
 return not exists(select 1 from jsonb_array_elements(m) x where not app_private.valid_media(x,false));
end $$;
revoke all on function app_private.valid_media(jsonb,boolean),app_private.valid_post_media(jsonb) from public;
grant execute on function app_private.valid_media(jsonb,boolean),app_private.valid_post_media(jsonb) to anon,authenticated,service_role;


create table public.profiles (
 id uuid primary key, username text not null unique check (username ~ '^[a-z0-9_\.]{3,30}$'),
 display_name text not null check (length(display_name) between 1 and 60), bio text not null default '' check(length(bio)<=240),
 avatar text not null default '', website text not null default '' check(length(website)<=500), interests text[] not null default '{}',
 pinned_post uuid, is_demo boolean not null default false, suspended boolean not null default false, created_at timestamptz not null default now(),
 check(cardinality(interests)<=12), check(website='' or website ~ '^https?://')
);
create table public.account_settings (id uuid primary key references auth.users on delete cascade, birth_date date not null check(birth_date <= (current_date - interval '16 years')::date), language text not null default 'uk', theme text not null default 'light');
create table app_private.admins (user_id uuid primary key references auth.users on delete cascade);
create table app_private.config (id boolean primary key default true check(id), uploads_enabled boolean not null default true, storage_limit_bytes bigint not null default 950000000);
insert into app_private.config(id) values(true);
alter table app_private.admins enable row level security;
alter table app_private.config enable row level security;
create table public.threads (id uuid primary key default gen_random_uuid(), author_id uuid references public.profiles on delete set null, title text not null check(length(title) between 1 and 100), topics text[] not null default '{}', created_at timestamptz not null default now(), check(cardinality(topics)<=3));
create table public.posts (id uuid primary key default gen_random_uuid(), author_id uuid references public.profiles on delete set null, body text not null default '' check(length(body)<=1000), media jsonb not null default '[]' check(jsonb_typeof(media)='array' and jsonb_array_length(media)<=4), topics text[] not null default '{}', thread_id uuid references public.threads, part integer, quote_id uuid references public.posts on delete set null, deleted boolean not null default false, hidden boolean not null default false, created_at timestamptz not null default now(), edited_at timestamptz, unique(thread_id,part), check(cardinality(topics)<=3));
create table public.series (id uuid primary key default gen_random_uuid(), author_id uuid not null references public.profiles on delete cascade, title text not null check(length(title) between 1 and 100), thread_id uuid references public.threads on delete set null, created_at timestamptz not null default now());
create table public.stories (id uuid primary key default gen_random_uuid(), author_id uuid not null references public.profiles on delete cascade, media jsonb not null, caption text not null default '' check(length(caption)<=300), series_id uuid references public.series on delete set null, post_id uuid references public.posts on delete set null, views bigint not null default 0, account_views bigint not null default 0, anonymous_views bigint not null default 0, anonymous_window_start timestamptz, anonymous_window_count integer not null default 0, hidden boolean not null default false, created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '24 hours');
create table public.story_views (id bigint generated always as identity primary key, story_id uuid not null references public.stories on delete cascade, viewer_id uuid not null references public.profiles on delete cascade, created_at timestamptz not null default now(), unique(story_id,viewer_id));
create table public.story_likes (story_id uuid references public.stories on delete cascade, user_id uuid references public.profiles on delete cascade, primary key(story_id,user_id));
create table public.likes (post_id uuid references public.posts on delete cascade, user_id uuid references public.profiles on delete cascade, created_at timestamptz not null default now(), primary key(post_id,user_id));
create table public.comments (id uuid primary key default gen_random_uuid(), post_id uuid not null references public.posts on delete cascade, author_id uuid references public.profiles on delete set null, parent_id uuid references public.comments, body text not null check(length(body) between 1 and 1000), deleted boolean not null default false, created_at timestamptz not null default now());
create table public.follows (follower_id uuid references public.profiles on delete cascade, following_id uuid references public.profiles on delete cascade, created_at timestamptz not null default now(), primary key(follower_id,following_id), check(follower_id<>following_id));
create table public.reposts (post_id uuid references public.posts on delete cascade, user_id uuid references public.profiles on delete cascade, created_at timestamptz not null default now(), primary key(post_id,user_id));
create table public.saves (post_id uuid references public.posts on delete cascade, user_id uuid references public.profiles on delete cascade, created_at timestamptz not null default now(), primary key(post_id,user_id));
create table public.blocks (blocker_id uuid references public.profiles on delete cascade, blocked_id uuid references public.profiles on delete cascade, primary key(blocker_id,blocked_id), check(blocker_id<>blocked_id));
create table public.notifications (id uuid primary key default gen_random_uuid(), recipient_id uuid not null references public.profiles on delete cascade, actor_id uuid references public.profiles on delete cascade, kind text not null, target text not null default '', read boolean not null default false, created_at timestamptz not null default now());
create table public.conversations (id uuid primary key default gen_random_uuid(), member_a uuid references public.profiles on delete set null, member_b uuid references public.profiles on delete set null, initiator uuid references public.profiles on delete set null, status text not null default 'pending' check(status in ('pending','accepted','declined')), created_at timestamptz not null default now(), unique(member_a,member_b), check(member_a<member_b));
create table public.messages (id uuid primary key default gen_random_uuid(), conversation_id uuid not null references public.conversations on delete cascade, sender_id uuid references public.profiles on delete set null, body text not null check(length(body) between 1 and 4000), share_post uuid references public.posts on delete set null, share_series uuid references public.series on delete set null, created_at timestamptz not null default now());
create table public.message_reads (user_id uuid references public.profiles on delete cascade, conversation_id uuid references public.conversations on delete cascade, last_read_at timestamptz not null default now(), primary key(user_id,conversation_id));
create table public.drafts (user_id uuid references public.profiles on delete cascade, slot text not null default 'post', body text not null default '' check(length(body)<=1000), topics text[] not null default '{}', parent_id uuid, updated_at timestamptz not null default now(), primary key(user_id,slot));
create table public.reports (id uuid primary key default gen_random_uuid(), reporter_id uuid references public.profiles on delete set null, target_type text not null check(target_type in ('post','profile','story')), target_id uuid not null, reason text not null check(length(reason) between 1 and 1000), status text not null default 'open', created_at timestamptz not null default now());

create index posts_feed on public.posts(created_at desc);
create index posts_author on public.posts(author_id,created_at desc);
create index posts_thread on public.posts(thread_id,part);
create index comments_post on public.comments(post_id,created_at);
create index comments_parent on public.comments(parent_id);
create index stories_active on public.stories(expires_at);
create index stories_series on public.stories(series_id,created_at);
create index follows_target on public.follows(following_id);
create index blocks_target on public.blocks(blocked_id);
create index notifications_recipient on public.notifications(recipient_id,created_at desc);
create index messages_conversation on public.messages(conversation_id,created_at);
create index conversations_b on public.conversations(member_b);
create index stories_author on public.stories(author_id);
create index series_author on public.series(author_id);
create index series_thread on public.series(thread_id);
create index views_viewer on public.story_views(viewer_id);
create index likes_user on public.likes(user_id);
create index story_likes_user on public.story_likes(user_id);
create index reposts_user on public.reposts(user_id);
create index saves_user on public.saves(user_id);

-- Internal helpers use definer rights only to inspect non-public access tables.
-- They never accept an actor ID: the authenticated actor always comes from auth.uid().
create function app_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$ select auth.uid() is not null and exists(select 1 from app_private.admins where user_id=auth.uid()) $$;
create function app_private.blocked(other uuid) returns boolean language sql stable security definer set search_path='' as $$ select auth.uid() is not null and exists(select 1 from public.blocks where (blocker_id=auth.uid() and blocked_id=other) or (blocked_id=auth.uid() and blocker_id=other)) $$;
create function app_private.visible_author(other uuid) returns boolean language sql stable security definer set search_path='' as $$ select other is null or (exists(select 1 from public.profiles where id=other and not suspended) and not app_private.blocked(other)) $$;
create function app_private.member(cid uuid) returns boolean language sql stable security definer set search_path='' as $$ select auth.uid() is not null and exists(select 1 from public.conversations where id=cid and auth.uid() in(member_a,member_b)) $$;
create function app_private.uploads_open() returns boolean language sql stable security definer set search_path='' as $$ select uploads_enabled and coalesce((select sum((metadata->>'size')::bigint) from storage.objects where bucket_id='media'),0)<storage_limit_bytes from app_private.config where id=true $$;
revoke all on all functions in schema app_private from public;
grant execute on function app_private.is_admin(),app_private.blocked(uuid),app_private.visible_author(uuid),app_private.member(uuid),app_private.uploads_open() to anon,authenticated;

-- No client gets direct write privileges. Transactional actions below authorize each mutation.
do $$ declare t text; begin foreach t in array array['profiles','account_settings','threads','posts','series','stories','story_views','story_likes','likes','comments','follows','reposts','saves','blocks','notifications','conversations','messages','message_reads','drafts','reports'] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from anon, authenticated',t); execute format('grant select on public.%I to anon, authenticated',t); end loop; end $$;
create policy profiles_read on public.profiles for select to anon,authenticated using(not suspended or id=(select auth.uid()) or app_private.is_admin());
create policy settings_read on public.account_settings for select to authenticated using(id=(select auth.uid()));
create policy threads_read on public.threads for select to anon,authenticated using(app_private.visible_author(author_id) or app_private.is_admin());
create policy posts_read on public.posts for select to anon,authenticated using((not hidden and app_private.visible_author(author_id)) or app_private.is_admin());
create policy series_read on public.series for select to anon,authenticated using(app_private.visible_author(author_id) or app_private.is_admin());
create policy stories_read on public.stories for select to anon,authenticated using(((expires_at>now() or series_id is not null) and not hidden and app_private.visible_author(author_id)) or app_private.is_admin());
create policy views_read on public.story_views for select to authenticated using(exists(select 1 from public.stories s where s.id=story_id and s.author_id=(select auth.uid()) and s.expires_at>now()));
create policy story_likes_read on public.story_likes for select to anon,authenticated using(exists(select 1 from public.stories where id=story_id));
create policy likes_read on public.likes for select to anon,authenticated using(exists(select 1 from public.posts where id=post_id));
create policy comments_read on public.comments for select to anon,authenticated using(app_private.visible_author(author_id) and exists(select 1 from public.posts where id=post_id));
create policy follows_read on public.follows for select to anon,authenticated using(true);
create policy reposts_read on public.reposts for select to anon,authenticated using(app_private.visible_author(user_id) and exists(select 1 from public.posts where id=post_id));
create policy saves_read on public.saves for select to authenticated using(user_id=(select auth.uid()));
create policy blocks_read on public.blocks for select to authenticated using(blocker_id=(select auth.uid()));
create policy notifications_read on public.notifications for select to authenticated using(recipient_id=(select auth.uid()));
create policy conversations_read on public.conversations for select to authenticated using((select auth.uid()) in(member_a,member_b));
create policy messages_read on public.messages for select to authenticated using(app_private.member(conversation_id));
create policy message_reads_read on public.message_reads for select to authenticated using(user_id=(select auth.uid()));
create policy drafts_read on public.drafts for select to authenticated using(user_id=(select auth.uid()));
create policy reports_read on public.reports for select to authenticated using(reporter_id=(select auth.uid()) or app_private.is_admin());

create function app_private.notify(recipient uuid, kind_value text, target_value text) returns void language plpgsql security definer set search_path='' as $$ begin
 if recipient is not null and recipient<>auth.uid() and not app_private.blocked(recipient) then insert into public.notifications(recipient_id,actor_id,kind,target) values(recipient,auth.uid(),kind_value,target_value); end if;
end $$;
revoke all on function app_private.notify(uuid,text,text) from public,anon,authenticated;

create function app_private.dispatch(action text, payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target uuid; pid uuid; tid uuid; sid uuid; cid uuid; other uuid; owner_id uuid; parent uuid; txt text; parts integer; obj record; p public.posts; st public.stories; conv public.conversations; settings public.account_settings; result jsonb; topics_value text[]; media_value jsonb; birth date; added boolean:=false;
begin
 if action='view_story' then
  select * into st from public.stories where id=(payload->>'id')::uuid and not hidden and (expires_at>now() or series_id is not null) and app_private.visible_author(author_id);
  if not found then raise exception 'Story unavailable'; end if;
  if actor is null then
   update public.stories set views=views+1,anonymous_views=anonymous_views+1,
    anonymous_window_count=case when anonymous_window_start is null or anonymous_window_start<now()-interval '1 minute' then 1 else anonymous_window_count+1 end,
    anonymous_window_start=case when anonymous_window_start is null or anonymous_window_start<now()-interval '1 minute' then now() else anonymous_window_start end
    where id=st.id and (anonymous_window_start is null or anonymous_window_start<now()-interval '1 minute' or anonymous_window_count<60);
   return jsonb_build_object('id',st.id,'counted',found);
  end if;
  insert into public.story_views(story_id,viewer_id) values(st.id,actor) on conflict(story_id,viewer_id) do nothing;
  if found then update public.stories set views=views+1,account_views=account_views+case when actor is not null then 1 else 0 end,anonymous_views=anonymous_views+case when actor is null then 1 else 0 end where id=st.id; end if;
  return jsonb_build_object('id',st.id);
 end if;
 if action='upload_status' then return jsonb_build_object('enabled',app_private.uploads_open()); end if;
 if actor is null or not exists(select 1 from auth.users where id=actor and email_confirmed_at is not null) then raise exception 'Sign in with a confirmed email'; end if;
 if action='onboard' then
  birth:=(payload->>'birth_date')::date;
  if birth is null or birth>(current_date-interval '16 years')::date then raise exception 'Registration is available from age 16'; end if;
  if exists(select 1 from public.profiles where id=actor) then raise exception 'Profile already exists'; end if;
  insert into public.account_settings(id,birth_date) values(actor,birth);
  insert into public.profiles(id,username,display_name,interests) values(actor,lower(payload->>'username'),payload->>'display_name',array(select jsonb_array_elements_text(coalesce(payload->'interests','[]'))));
  return jsonb_build_object('id',actor);
 end if;
 if not exists(select 1 from public.profiles where id=actor and not suspended and not is_demo) then raise exception 'Complete your profile or contact support'; end if;
 if not exists(select 1 from public.account_settings where id=actor and birth_date<=(current_date-interval '16 years')::date) then raise exception 'Complete your age verification'; end if;
 target:=nullif(payload->>'id','')::uuid;
 if action='profile' then
  update public.profiles set display_name=coalesce(payload->>'display_name',display_name),bio=coalesce(payload->>'bio',bio),website=coalesce(payload->>'website',website),avatar=coalesce(payload->>'avatar',avatar),interests=case when payload?'interests' then array(select jsonb_array_elements_text(payload->'interests')) else interests end where id=actor;
  update public.account_settings set language=coalesce(payload->>'language',language),theme=coalesce(payload->>'theme',theme) where id=actor;
 elsif action in('post','edit_post') then
  txt:=trim(coalesce(payload->>'body','')); media_value:=coalesce(payload->'media','[]'); topics_value:=array(select jsonb_array_elements_text(coalesce(payload->'topics','[]')));
  if txt='' and jsonb_array_length(media_value)=0 then raise exception 'Write something or add a photo'; end if;
  if jsonb_typeof(media_value)<>'array' or jsonb_array_length(media_value)>4 or length(txt)>1000 or cardinality(topics_value)>3 then raise exception 'Post limits exceeded'; end if;
  if not app_private.valid_post_media(media_value) or exists(select 1 from jsonb_array_elements(media_value) m where not ((m->>'path' like actor::text||'/%') is true)) then raise exception 'Invalid media ownership'; end if;
  if action='edit_post' then
   update public.posts set body=txt,media=media_value,edited_at=now() where id=target and author_id=actor and not deleted returning id into pid;
   if pid is null then raise exception 'Post unavailable'; end if;
  else
   parent:=nullif(payload->>'parent_id','')::uuid;
   if parent is not null then
    select * into p from public.posts where id=parent and author_id=actor and not deleted for update;
    if not found then raise exception 'Only the author may continue a thread'; end if;
    tid:=p.thread_id;
    if tid is null then
     insert into public.threads(author_id,title,topics) values(actor,coalesce(nullif(trim(payload->>'thread_title'),''),left(p.body,60)),p.topics) returning id into tid;
     update public.posts set thread_id=tid,part=1 where id=parent;
    end if;
    perform 1 from public.threads where id=tid and author_id=actor for update;
    select coalesce(max(part),0)+1 into parts from public.posts where thread_id=tid;
    select topics into topics_value from public.threads where id=tid;
   end if;
   if nullif(payload->>'quote_id','') is not null and not exists(select 1 from public.posts where id=(payload->>'quote_id')::uuid and not deleted and not hidden and app_private.visible_author(author_id)) then raise exception 'Original post unavailable'; end if;
   insert into public.posts(author_id,body,media,topics,thread_id,part,quote_id) values(actor,txt,media_value,topics_value,tid,parts,nullif(payload->>'quote_id','')::uuid) returning id into pid;
  end if;
  delete from public.drafts where user_id=actor and slot=coalesce(payload->>'slot','post');
  return jsonb_build_object('id',pid,'thread_id',tid);
 elsif action='delete_post' then
  update public.posts set body='',media='[]',deleted=true,edited_at=now() where id=target and author_id=actor returning id into pid;
  if pid is null then raise exception 'Post unavailable'; end if;
 elsif action='pin' then
  if target is not null and not exists(select 1 from public.posts where id=target and author_id=actor and not deleted) then raise exception 'Post unavailable'; end if;
  update public.profiles set pinned_post=target where id=actor;
 elsif action in('like','save','repost','comment') then
  select * into p from public.posts where id=target and not deleted and not hidden and app_private.visible_author(author_id);
  if not found then raise exception 'Post unavailable'; end if;
  if action='like' then
   delete from public.likes where post_id=target and user_id=actor;
   if not found then insert into public.likes(post_id,user_id) values(target,actor); perform app_private.notify(p.author_id,'like',target::text); added:=true; end if;
  elsif action='save' then
   delete from public.saves where post_id=target and user_id=actor;
   if not found then insert into public.saves(post_id,user_id) values(target,actor); added:=true; end if;
  elsif action='repost' then
   delete from public.reposts where post_id=target and user_id=actor;
   if not found then insert into public.reposts(post_id,user_id) values(target,actor); perform app_private.notify(p.author_id,'repost',target::text); added:=true; end if;
  else
   parent:=nullif(payload->>'parent_id','')::uuid;
   if parent is not null and not exists(select 1 from public.comments where id=parent and post_id=target and parent_id is null and not deleted) then raise exception 'Reply must belong to a top-level comment'; end if;
   insert into public.comments(post_id,author_id,parent_id,body) values(target,actor,parent,trim(payload->>'body')) returning id into pid;
   perform app_private.notify(p.author_id,'comment',target::text);
   if parent is not null then select author_id into owner_id from public.comments where id=parent; if owner_id is distinct from p.author_id then perform app_private.notify(owner_id,'reply',target::text); end if; end if;
  end if;
  return jsonb_build_object('active',added,'id',pid);
 elsif action='delete_comment' then
  update public.comments c set body='',deleted=true where c.id=target and (c.author_id=actor or exists(select 1 from public.posts where id=c.post_id and author_id=actor));
  if not found then raise exception 'Comment unavailable'; end if;
 elsif action='follow' then
  if target=actor or not app_private.visible_author(target) or not exists(select 1 from public.profiles where id=target) then raise exception 'Profile unavailable'; end if;
  delete from public.follows where follower_id=actor and following_id=target;
  if not found then insert into public.follows values(actor,target,now()); perform app_private.notify(target,'follow',actor::text); added:=true; end if;
  return jsonb_build_object('active',added);
 elsif action='block' then
  delete from public.blocks where blocker_id=actor and blocked_id=target;
  if not found then
   insert into public.blocks values(actor,target);
   delete from public.follows where (follower_id=actor and following_id=target) or (following_id=actor and follower_id=target);
  end if;
 elsif action='report' then
  insert into public.reports(reporter_id,target_type,target_id,reason) values(actor,payload->>'target_type',target,trim(payload->>'reason'));
 elsif action='story' then
  if not app_private.uploads_open() then raise exception 'Media uploads are temporarily paused'; end if;
  media_value:=payload->'media';
  if not app_private.valid_media(media_value,true) or not ((media_value->>'path' like actor::text||'/%') is true) then raise exception 'Invalid media'; end if;
  if media_value->>'type' like 'video/%' and (coalesce((media_value->>'duration')::numeric,999)>30 or coalesce((media_value->>'duration')::numeric,0)<=0) then raise exception 'Video must be at most 30 seconds'; end if;
  sid:=nullif(payload->>'series_id','')::uuid;
  tid:=nullif(payload->>'thread_id','')::uuid;
  if tid is not null and not exists(select 1 from public.threads where id=tid and author_id=actor) then raise exception 'Thread unavailable'; end if;
  if sid is not null and not exists(select 1 from public.series where id=sid and author_id=actor) then raise exception 'Series unavailable'; end if;
  if nullif(trim(payload->>'series_title'),'') is not null and sid is null then insert into public.series(author_id,title,thread_id) values(actor,trim(payload->>'series_title'),tid) returning id into sid; end if;
  if sid is not null then select thread_id into tid from public.series where id=sid; end if;
  pid:=nullif(payload->>'post_id','')::uuid;
  if pid is not null and not exists(select 1 from public.posts where id=pid and thread_id=tid and author_id=actor and not deleted) then raise exception 'Discussion post must belong to the linked thread'; end if;
  insert into public.stories(author_id,media,caption,series_id,post_id) values(actor,media_value,coalesce(payload->>'caption',''),sid,pid) returning id into pid;
  return jsonb_build_object('id',pid);
 elsif action='save_story' then
  select * into st from public.stories where id=target and author_id=actor and (expires_at>now() or series_id is not null);
  if not found then raise exception 'Story unavailable'; end if;
  sid:=nullif(payload->>'series_id','')::uuid; tid:=nullif(payload->>'thread_id','')::uuid;
  if tid is not null and not exists(select 1 from public.threads where id=tid and author_id=actor) then raise exception 'Thread unavailable'; end if;
  if sid is null then insert into public.series(author_id,title,thread_id) values(actor,payload->>'title',tid) returning id into sid;
  elsif not exists(select 1 from public.series where id=sid and author_id=actor) then raise exception 'Series unavailable'; end if;
  update public.stories set series_id=sid where id=target;
 elsif action='delete_story' then
  delete from public.stories where id=target and author_id=actor;
  if not found then raise exception 'Story unavailable'; end if;
 elsif action='like_story' then
  if not exists(select 1 from public.stories where id=target and not hidden and (expires_at>now() or series_id is not null) and app_private.visible_author(author_id)) then raise exception 'Story unavailable'; end if;
  delete from public.story_likes where story_id=target and user_id=actor;
  if not found then insert into public.story_likes values(target,actor); added:=true; end if;
  return jsonb_build_object('active',added);
 elsif action='draft' then
  insert into public.drafts(user_id,slot,body,topics,parent_id) values(actor,coalesce(payload->>'slot','post'),coalesce(payload->>'body',''),array(select jsonb_array_elements_text(coalesce(payload->'topics','[]'))),nullif(payload->>'parent_id','')::uuid) on conflict(user_id,slot) do update set body=excluded.body,topics=excluded.topics,parent_id=excluded.parent_id,updated_at=now();
 elsif action='send' then
  other:=(payload->>'recipient_id')::uuid;
  if other=actor or not exists(select 1 from public.profiles where id=other and not is_demo and not suspended) or app_private.blocked(other) then raise exception 'Messaging unavailable'; end if;
  insert into public.conversations(member_a,member_b,initiator,status) values(least(actor,other),greatest(actor,other),actor,case when exists(select 1 from public.follows where follower_id=actor and following_id=other) and exists(select 1 from public.follows where follower_id=other and following_id=actor) then 'accepted' else 'pending' end) on conflict(member_a,member_b) do nothing;
  select * into conv from public.conversations where member_a=least(actor,other) and member_b=greatest(actor,other) for update;
  if conv.status='declined' or (conv.status='pending' and (conv.initiator<>actor or exists(select 1 from public.messages where conversation_id=conv.id))) then raise exception 'Wait until the message request is accepted'; end if;
  insert into public.messages(conversation_id,sender_id,body,share_post,share_series) values(conv.id,actor,trim(payload->>'body'),nullif(payload->>'share_post','')::uuid,nullif(payload->>'share_series','')::uuid);
  perform app_private.notify(other,'message',conv.id::text);
  return jsonb_build_object('id',conv.id);
 elsif action='accept_chat' then
  select * into conv from public.conversations where id=target and actor in(member_a,member_b) and initiator<>actor and status='pending' for update;
  if not found or app_private.blocked(case when conv.member_a=actor then conv.member_b else conv.member_a end) then raise exception 'Request unavailable'; end if;
  update public.conversations set status=case when coalesce((payload->>'accept')::boolean,true) then 'accepted' else 'declined' end where id=target;
 elsif action='read_chat' then
  if not app_private.member(target) then raise exception 'Chat unavailable'; end if;
  insert into public.message_reads(user_id,conversation_id) values(actor,target) on conflict(user_id,conversation_id) do update set last_read_at=now();
  update public.notifications n set read=true where recipient_id=actor and kind='message' and n.target=((payload->>'id')::uuid)::text;
 elsif action='read_notifications' then
  update public.notifications set read=true where recipient_id=actor;
 elsif action='admin' then
  if not app_private.is_admin() then raise exception 'Administrator access required'; end if;
  if payload->>'operation'='resolve' then update public.reports set status='resolved' where id=target;
  elsif payload->>'operation'='hide_post' then update public.posts set hidden=coalesce((payload->>'value')::boolean,true) where id=target;
  elsif payload->>'operation'='hide_story' then update public.stories set hidden=coalesce((payload->>'value')::boolean,true) where id=target;
  elsif payload->>'operation'='suspend' then update public.profiles set suspended=coalesce((payload->>'value')::boolean,true) where id=target and id<>actor;
  else raise exception 'Unknown moderator operation'; end if;
 else raise exception 'Unknown action'; end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function app_private.dispatch(text,jsonb) from public;
grant execute on function app_private.dispatch(text,jsonb) to anon,authenticated;
create function public.app_action(action text,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select app_private.dispatch(action,payload) $$;
revoke all on function public.app_action(text,jsonb) from public;
grant execute on function public.app_action(text,jsonb) to anon,authenticated;
create function public.my_admin_status() returns boolean language sql stable security invoker set search_path='' as $$ select app_private.is_admin() $$;
revoke all on function public.my_admin_status() from public;
grant execute on function public.my_admin_status() to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('media','media',true,52428800,array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','video/quicktime']);
create policy media_insert on storage.objects for insert to authenticated with check(bucket_id='media' and (storage.foldername(name))[1]=(select auth.uid())::text and app_private.uploads_open() and exists(select 1 from public.account_settings where id=(select auth.uid())) and exists(select 1 from public.profiles where id=(select auth.uid()) and not suspended));
create policy media_delete on storage.objects for delete to authenticated using(bucket_id='media' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy media_select on storage.objects for select to authenticated using(bucket_id='media' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- Realtime is scoped by the same RLS policies; never publish private birth dates.
alter publication supabase_realtime add table public.messages,public.notifications,public.posts;
