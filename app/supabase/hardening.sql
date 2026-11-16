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

-- Reject malformed new state; legacy records are checked separately before validation.
alter table public.posts drop constraint if exists posts_media_shape;
alter table public.posts add constraint posts_media_shape check(app_private.valid_post_media(media)) not valid;
alter table public.stories drop constraint if exists stories_media_shape;
alter table public.stories add constraint stories_media_shape check(app_private.valid_media(media,true)) not valid;
alter table public.posts validate constraint posts_media_shape;
alter table public.stories validate constraint stories_media_shape;
alter table public.stories add column if not exists anonymous_window_start timestamptz;
alter table public.stories add column if not exists anonymous_window_count integer not null default 0;
-- Anonymous analytics uses bounded counters, never one permanent row per opening.
delete from public.story_views where viewer_id is null;
alter table public.story_views drop constraint if exists story_views_viewer_id_fkey;
alter table public.story_views add constraint story_views_viewer_id_fkey foreign key(viewer_id) references public.profiles(id) on delete cascade;
alter table public.story_views alter column viewer_id set not null;

create table if not exists app_private.media_reservations (
 path text primary key, owner_id uuid not null, bytes bigint not null check(bytes between 1 and 52428800), created_at timestamptz not null default now()
);
alter table app_private.media_reservations enable row level security;
revoke all on app_private.media_reservations from public,anon,authenticated;
grant all on app_private.media_reservations to service_role;
create index if not exists media_reservations_owner on app_private.media_reservations(owner_id);

create or replace function public.reserve_media_upload(owner uuid,object_path text,byte_size bigint)
returns void language plpgsql security definer set search_path='' as $$
declare quota app_private.config; used_bytes bigint; pending_bytes bigint;
begin
 if byte_size is null or byte_size<1 or byte_size>52428800 or object_path is null or not (object_path like owner::text||'/%') then raise exception 'Invalid upload reservation'; end if;
 if not exists(select 1 from public.profiles p join public.account_settings a on a.id=p.id join auth.users u on u.id=p.id where p.id=owner and not p.suspended and not p.is_demo and u.email_confirmed_at is not null) then raise exception 'Complete your profile'; end if;
 select * into quota from app_private.config where id=true for update;
 if not quota.uploads_enabled then raise exception 'Media uploads are temporarily paused'; end if;
 select coalesce(sum((metadata->>'size')::bigint),0) into used_bytes from storage.objects where bucket_id='media';
 select coalesce(sum(r.bytes),0) into pending_bytes from app_private.media_reservations r where not exists(select 1 from storage.objects o where o.bucket_id='media' and o.name=r.path);
 if used_bytes+pending_bytes+byte_size>quota.storage_limit_bytes then raise exception 'Media storage limit reached'; end if;
 insert into app_private.media_reservations(path,owner_id,bytes) values(object_path,owner,byte_size);
end $$;
create or replace function public.settle_media_upload(object_path text)
returns void language plpgsql security definer set search_path='' as $$
declare reserved app_private.media_reservations; actual bigint;
begin
 perform 1 from app_private.config where id=true for update;
 select * into reserved from app_private.media_reservations where path=object_path for update;
 if not found then raise exception 'Reservation unavailable'; end if;
 select (metadata->>'size')::bigint into actual from storage.objects where bucket_id='media' and name=object_path;
 if actual is null or actual<>reserved.bytes then raise exception 'Upload size could not be verified'; end if;
 delete from app_private.media_reservations where path=object_path;
end $$;
revoke all on function public.reserve_media_upload(uuid,text,bigint),public.settle_media_upload(text) from public,anon,authenticated;
grant execute on function public.reserve_media_upload(uuid,text,bigint),public.settle_media_upload(text) to service_role;
create or replace function public.reconcile_media_upload(object_path text,confirmed_failure boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare reserved app_private.media_reservations; actual bigint;
begin
 perform 1 from app_private.config where id=true for update;
 select * into reserved from app_private.media_reservations where path=object_path for update;
 if not found then return; end if;
 select (metadata->>'size')::bigint into actual from storage.objects where bucket_id='media' and name=object_path;
 if (actual is not null and actual=reserved.bytes) or (actual is null and confirmed_failure) then
  delete from app_private.media_reservations where path=object_path;
 end if;
end $$;
revoke all on function public.reconcile_media_upload(text,boolean) from public,anon,authenticated;
grant execute on function public.reconcile_media_upload(text,boolean) to service_role;
-- Only the authenticated media Edge gateway can write with its server key.
-- Client deletion/listing remain ownership scoped. Old clients need the new APK.
drop policy if exists media_insert on storage.objects;

create index if not exists threads_author on public.threads(author_id);
create index if not exists posts_quote on public.posts(quote_id);
create index if not exists stories_post on public.stories(post_id);
create index if not exists comments_author on public.comments(author_id);
create index if not exists notifications_actor on public.notifications(actor_id);
create index if not exists conversations_initiator on public.conversations(initiator);
create index if not exists messages_sender on public.messages(sender_id);
create index if not exists messages_share_post on public.messages(share_post);
create index if not exists messages_share_series on public.messages(share_series);
create index if not exists message_reads_conversation on public.message_reads(conversation_id);
create index if not exists reports_reporter on public.reports(reporter_id);

-- Updated dispatcher is appended below from the source schema by the patch.

create or replace function app_private.dispatch(action text, payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
