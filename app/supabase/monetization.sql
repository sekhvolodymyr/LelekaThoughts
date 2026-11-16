-- Apply after schema.sql, maintenance.sql and hardening.sql.
-- Existing content stays public. Card details are handled only by payment providers.
begin;
alter table public.posts add column if not exists access text not null default 'public' check(access in ('public','subscribers','purchase','either'));
alter table public.posts add column if not exists preview_text text not null default '' check(length(preview_text)<=240);
alter table public.posts add column if not exists price_cents integer check(price_cents between 100 and 10000000);
alter table public.posts add column if not exists paid_root_id uuid references public.posts(id) on delete set null;
alter table public.stories add column if not exists access text not null default 'public' check(access in ('public','subscribers'));
alter table public.drafts add column if not exists access text not null default 'public' check(access in ('public','subscribers','purchase','either'));
alter table public.drafts add column if not exists preview_text text not null default '' check(length(preview_text)<=240);
alter table public.drafts add column if not exists price_cents integer;
create index if not exists posts_paid_root on public.posts(paid_root_id);

create table if not exists public.creator_offers(
 creator_id uuid primary key references public.profiles on delete cascade,
 monthly_cents integer not null default 10000 check(monthly_cents between 100 and 10000000),
 currency text not null default 'UAH' check(currency='UAH'), enabled boolean not null default false
);
alter table public.creator_offers enable row level security;
revoke all on public.creator_offers from anon,authenticated;
grant select on public.creator_offers to anon,authenticated;
create policy creator_offers_read on public.creator_offers for select to anon,authenticated using(app_private.visible_author(creator_id));

create table if not exists app_private.payment_accounts(
 id uuid primary key default gen_random_uuid(),creator_id uuid references public.profiles on delete set null,
 provider text not null check(provider in ('stripe','wayforpay','monobank')),
 credentials text not null default '',credential_context text not null,config jsonb not null default '{}',
 state text not null default 'pending' check(state in ('pending','active','disabled')),
 current boolean not null default true,created_at timestamptz not null default now()
);
create unique index if not exists payment_account_current on app_private.payment_accounts(creator_id,provider) where current;
create table if not exists app_private.payment_orders(
 id uuid primary key default gen_random_uuid(),buyer_id uuid references public.profiles on delete set null,
 creator_id uuid references public.profiles on delete set null,account_id uuid not null references app_private.payment_accounts,
 kind text not null check(kind in ('purchase','subscription')),post_id uuid references public.posts on delete set null,
 amount integer not null check(amount between 100 and 10000000),currency text not null default 'UAH' check(currency='UAH'),
 status text not null default 'creating' check(status in ('creating','pending','paid','failed','refunded')),
 client_key uuid not null,checkout_id text,checkout_url text,checkout_started boolean not null default false,external_subscription text,
 payment_reference text,
 expires_at timestamptz,auto_renew boolean not null default false,cancel_requested boolean not null default false,
 renewal_state text not null default 'idle' check(renewal_state in ('idle','processing','unknown','failed')),
 cancel_retry_at timestamptz not null default now(),
 parent_id uuid references app_private.payment_orders,card_token text,
 consent_at timestamptz,created_at timestamptz not null default now(),unique(buyer_id,client_key)
);
create index if not exists payment_orders_access on app_private.payment_orders(buyer_id,creator_id,status,expires_at);
create index if not exists payment_orders_post on app_private.payment_orders(post_id,buyer_id) where status='paid';
create index if not exists payment_orders_account on app_private.payment_orders(account_id);
create index if not exists payment_orders_creator on app_private.payment_orders(creator_id);
create index if not exists payment_orders_parent on app_private.payment_orders(parent_id);
create index if not exists payment_orders_due on app_private.payment_orders(expires_at) where auto_renew and parent_id is null and status='paid';
create table if not exists app_private.payment_events(
 account_id uuid references app_private.payment_accounts on delete cascade,event_key text not null,
 order_id uuid not null references app_private.payment_orders,created_at timestamptz not null default now(),primary key(account_id,event_key)
);
create index if not exists payment_events_order on app_private.payment_events(order_id);
alter table app_private.payment_events add column if not exists payment_reference text;
create index if not exists payment_events_reference on app_private.payment_events(account_id,payment_reference);
do $$ declare t text;begin foreach t in array array['payment_accounts','payment_orders','payment_events'] loop
 execute format('alter table app_private.%I enable row level security',t);
 execute format('revoke all on app_private.%I from public,anon,authenticated',t);
 execute format('grant all on app_private.%I to service_role',t);
 execute format('create policy deny_client on app_private.%I for all to anon,authenticated using(false) with check(false)',t);
end loop;end $$;

-- Compatibility capability only, never an authorization credential. Older apps
-- must not display private posts in editors that still upload to the public bucket.
create or replace function app_private.paid_client() returns boolean language sql stable set search_path='' as $$
 select coalesce(nullif(current_setting('request.headers',true),'')::jsonb->>'x-client-info','') like '%paid-content/1%'
$$;
revoke all on function app_private.paid_client() from public;
grant execute on function app_private.paid_client() to anon,authenticated,service_role;
create or replace function app_private.billing_actor() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=auth.uid() and not p.suspended and not p.is_demo and u.email_confirmed_at is not null)
$$;
create or replace function app_private.subscribed(creator uuid) returns boolean language sql stable security definer set search_path='' as $$
 select app_private.billing_actor() and exists(select 1 from app_private.payment_orders o where o.buyer_id=auth.uid() and o.creator_id=creator and o.kind='subscription' and o.parent_id is null and o.status='paid' and o.expires_at>now())
$$;
create or replace function app_private.can_read_post(pid uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare p public.posts;begin
 select * into p from public.posts where id=pid;
 if not found or not app_private.visible_author(p.author_id) then return false;end if;
 if p.access<>'public' and not app_private.paid_client() then return false;end if;
 if p.hidden then return p.author_id=auth.uid() or app_private.is_admin();end if;
 if p.access='public' then return true;end if;
 if not app_private.billing_actor() then return false;end if;
 if p.author_id=auth.uid() then return true;end if;
 return (p.access in('subscribers','either') and app_private.subscribed(p.author_id)) or
 (p.access in('purchase','either') and exists(select 1 from app_private.payment_orders o where o.buyer_id=auth.uid() and o.post_id=coalesce(p.paid_root_id,p.id) and o.kind='purchase' and o.status='paid'));
end $$;
revoke all on function app_private.billing_actor(),app_private.subscribed(uuid),app_private.can_read_post(uuid) from public;
grant execute on function app_private.billing_actor(),app_private.subscribed(uuid),app_private.can_read_post(uuid) to anon,authenticated,service_role;
drop policy posts_read on public.posts;
create policy posts_read on public.posts for select to anon,authenticated using(app_private.can_read_post(id));
drop policy stories_read on public.stories;
create policy stories_read on public.stories for select to anon,authenticated using(
 (expires_at>now() or series_id is not null) and not hidden and app_private.visible_author(author_id)
 and (access='public' or (app_private.paid_client() and app_private.billing_actor() and (author_id=auth.uid() or app_private.subscribed(author_id))))
);

-- Safe public metadata is a separate table. It never stores the private body or media.
create table if not exists public.paid_previews(
 id uuid primary key references public.posts on delete cascade,author_id uuid references public.profiles on delete cascade,
 body text not null,access text not null,price_cents integer,paid_root_id uuid,
 topics text[] not null default '{}',thread_id uuid references public.threads on delete set null,part integer,
 created_at timestamptz not null,edited_at timestamptz,deleted boolean not null,locked boolean not null default true,
 media jsonb not null default '[]'
);
create index if not exists paid_previews_author on public.paid_previews(author_id);
create index if not exists paid_previews_thread on public.paid_previews(thread_id,part);
create index if not exists paid_previews_feed on public.paid_previews(created_at desc);
alter table public.paid_previews enable row level security;
revoke all on public.paid_previews from anon,authenticated;
grant select on public.paid_previews to anon,authenticated;
create policy paid_previews_read on public.paid_previews for select to anon,authenticated using(app_private.visible_author(author_id));
create or replace function app_private.sync_paid_preview() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.access='public' or new.hidden then delete from public.paid_previews where id=new.id;return new;end if;
 insert into public.paid_previews(id,author_id,body,access,price_cents,paid_root_id,topics,thread_id,part,created_at,edited_at,deleted)
 values(new.id,new.author_id,case when new.deleted then '' else new.preview_text end,new.access,new.price_cents,new.paid_root_id,new.topics,new.thread_id,new.part,new.created_at,new.edited_at,new.deleted)
 on conflict(id) do update set body=excluded.body,access=excluded.access,price_cents=excluded.price_cents,paid_root_id=excluded.paid_root_id,thread_id=excluded.thread_id,part=excluded.part,edited_at=excluded.edited_at,deleted=excluded.deleted;
 return new;end $$;
revoke all on function app_private.sync_paid_preview() from public,anon,authenticated;
create trigger paid_preview_sync after insert or update on public.posts for each row execute function app_private.sync_paid_preview();

create or replace function app_private.paid_dispatch(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; p public.posts; a text; amount integer; root uuid; m jsonb;begin
 if action='monetization_status' then return jsonb_build_object('installed',true);end if;
 if action='draft' then
  result:=app_private.dispatch(action,payload);
  update public.drafts set access=coalesce(payload->>'access',access),preview_text=coalesce(payload->>'preview_text',preview_text),price_cents=coalesce(nullif(payload->>'price_cents','')::integer,price_cents) where user_id=auth.uid() and slot=coalesce(payload->>'slot','post');
  return result;
 end if;
 if action='creator_offer' then
  if not app_private.billing_actor() then raise exception 'Sign in with a confirmed creator account';end if;
  insert into public.creator_offers(creator_id,monthly_cents,enabled) values(auth.uid(),(payload->>'monthly_cents')::integer,coalesce((payload->>'enabled')::boolean,false))
  on conflict(creator_id) do update set monthly_cents=excluded.monthly_cents,enabled=excluded.enabled;
  return jsonb_build_object('ok',true);
 end if;
 if action in('like','save','repost','comment','pin','delete_post','edit_post') then
  if not app_private.can_read_post((payload->>'id')::uuid) then raise exception 'Paid content requires access';end if;
 end if;
 if action='post' and nullif(payload->>'quote_id','') is not null and not app_private.can_read_post((payload->>'quote_id')::uuid) then raise exception 'Paid content requires access';end if;
 if action='post' or action='edit_post' then
  if action='edit_post' then select * into p from public.posts where id=(payload->>'id')::uuid;
  elsif nullif(payload->>'parent_id','') is not null then select * into p from public.posts where id=(payload->>'parent_id')::uuid;end if;
  a:=coalesce(p.access,payload->>'access','public');
  if a not in('public','subscribers','purchase','either') then raise exception 'Invalid access';end if;
  if p.id is not null and payload?'access' and payload->>'access'<>p.access then raise exception 'Access cannot change after publication';end if;
  amount:=coalesce(p.price_cents,nullif(payload->>'price_cents','')::integer);
  root:=coalesce(p.paid_root_id,p.id);
  if action='post' and p.access<>'public' and p.thread_id is null and nullif(trim(payload->>'thread_title'),'') is null then raise exception 'Set a public thread title';end if;
  if a in('purchase','either') and (amount is null or amount<100 or amount>10000000) then raise exception 'Set a valid purchase price';end if;
  for m in select value from jsonb_array_elements(coalesce(payload->'media','[]')) loop
   if (a='public' and coalesce(m->>'bucket','media')<>'media') or (a<>'public' and coalesce(m->>'bucket','media')<>'private-media') then raise exception 'Use the matching media storage for this access';end if;
   if a<>'public' and not exists(select 1 from storage.objects where bucket_id='private-media' and name=m->>'path') then raise exception 'Private upload unavailable';end if;
  end loop;
  result:=app_private.dispatch(action,payload);
  update public.posts set access=a,preview_text=coalesce(payload->>'preview_text',case when action='edit_post' then p.preview_text else '' end),
   price_cents=case when a in('purchase','either') then amount end,paid_root_id=case when a<>'public' then coalesce(root,(result->>'id')::uuid) end
   where id=(result->>'id')::uuid;
  return result;
 end if;
 if action='story' then
  a:=coalesce(payload->>'access','public');if a not in('public','subscribers') then raise exception 'Invalid story access';end if;
  if (a='public' and coalesce(payload->'media'->>'bucket','media')<>'media') or (a='subscribers' and payload->'media'->>'bucket' is distinct from 'private-media') then raise exception 'Use matching story media storage';end if;
  result:=app_private.dispatch(action,payload);update public.stories set access=a where id=(result->>'id')::uuid;return result;
 end if;
 if action in('view_story','like_story') then
  if exists(select 1 from public.stories s where s.id=(payload->>'id')::uuid and s.access<>'public' and not(app_private.billing_actor() and (s.author_id=auth.uid() or app_private.subscribed(s.author_id)))) then raise exception 'Paid story requires a subscription';end if;
 end if;
 result:=app_private.dispatch(action,payload);
 if action='block' and exists(select 1 from public.blocks where blocker_id=auth.uid() and blocked_id=(payload->>'id')::uuid) then
  update app_private.payment_orders set cancel_requested=true where kind='subscription' and auto_renew and parent_id is null and
   ((buyer_id=auth.uid() and creator_id=(payload->>'id')::uuid) or(creator_id=auth.uid() and buyer_id=(payload->>'id')::uuid));
 elsif action='admin' and payload->>'operation'='suspend' and coalesce((payload->>'value')::boolean,true) then
  update app_private.payment_orders set cancel_requested=true where kind='subscription' and auto_renew and parent_id is null and (buyer_id=(payload->>'id')::uuid or creator_id=(payload->>'id')::uuid);
 end if;
 return result;
end $$;
revoke all on function app_private.paid_dispatch(text,jsonb) from public;
grant execute on function app_private.paid_dispatch(text,jsonb) to anon,authenticated;
revoke all on function app_private.dispatch(text,jsonb) from anon,authenticated;
create or replace function public.app_action(action text,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select app_private.paid_dispatch(action,payload)$$;

create or replace function app_private.can_read_private_media(object_path text) returns boolean language sql stable security definer set search_path='' as $$
 select app_private.paid_client() and app_private.billing_actor() and (
 split_part(object_path,'/',1)=auth.uid()::text or
 exists(select 1 from public.posts p where not p.deleted and app_private.can_read_post(p.id) and exists(select 1 from jsonb_array_elements(p.media)m where m->>'path'=object_path and m->>'bucket'='private-media')) or
 exists(select 1 from public.stories s where s.media->>'path'=object_path and s.media->>'bucket'='private-media' and not s.hidden and (s.expires_at>now() or s.series_id is not null) and app_private.visible_author(s.author_id) and (s.access='public' or app_private.subscribed(s.author_id)))
 )
$$;
revoke all on function app_private.can_read_private_media(text) from public;
grant execute on function app_private.can_read_private_media(text) to authenticated;
create policy private_media_select on storage.objects for select to authenticated using(bucket_id='private-media' and app_private.can_read_private_media(name));
create policy private_media_delete on storage.objects for delete to authenticated using(bucket_id='private-media' and app_private.billing_actor() and split_part(name,'/',1)=auth.uid()::text);

-- Quota remains shared across both buckets; existing public upload calls still work.
alter table app_private.media_reservations add column if not exists bucket text not null default 'media' check(bucket in('media','private-media'));
create or replace function public.reserve_private_upload(owner uuid,object_path text,byte_size bigint) returns void language plpgsql security definer set search_path='' as $$
declare q app_private.config;used_bytes bigint;pending bigint;begin
 if byte_size is null or byte_size<1 or byte_size>52428800 or object_path is null or not(object_path like owner::text||'/%') then raise exception 'Invalid upload';end if;
 if not exists(select 1 from public.profiles p join public.account_settings a on a.id=p.id join auth.users u on u.id=p.id where p.id=owner and not p.suspended and not p.is_demo and u.email_confirmed_at is not null) then raise exception 'Complete your profile';end if;
 select * into q from app_private.config where id=true for update;
 if not q.uploads_enabled then raise exception 'Uploads paused';end if;
 select coalesce(sum((metadata->>'size')::bigint),0) into used_bytes from storage.objects where bucket_id in('media','private-media');
 select coalesce(sum(r.bytes),0) into pending from app_private.media_reservations r where not exists(select 1 from storage.objects o where o.bucket_id=r.bucket and o.name=r.path);
 if used_bytes+pending+byte_size>q.storage_limit_bytes then raise exception 'Media storage limit reached';end if;
 insert into app_private.media_reservations(path,owner_id,bytes,bucket) values(object_path,owner,byte_size,'private-media');
end $$;
-- Public reservation shares the same lock and totals.
create or replace function public.reserve_media_upload(owner uuid,object_path text,byte_size bigint) returns void language plpgsql security definer set search_path='' as $$begin
 perform public.reserve_private_upload(owner,object_path,byte_size);
 update app_private.media_reservations set bucket='media' where path=object_path;
end $$;
create or replace function public.settle_media_upload(object_path text) returns void language plpgsql security definer set search_path='' as $$
declare r app_private.media_reservations;actual bigint;begin
 perform 1 from app_private.config where id=true for update;select * into r from app_private.media_reservations where path=object_path for update;
 if not found then raise exception 'Reservation unavailable';end if;
 select (metadata->>'size')::bigint into actual from storage.objects where bucket_id=r.bucket and name=object_path;
 if actual is null or actual<>r.bytes then raise exception 'Upload size could not be verified';end if;
 delete from app_private.media_reservations where path=object_path;end $$;
create or replace function public.reconcile_media_upload(object_path text,confirmed_failure boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare r app_private.media_reservations;actual bigint;begin
 perform 1 from app_private.config where id=true for update;select * into r from app_private.media_reservations where path=object_path for update;
 if not found then return;end if;
 select (metadata->>'size')::bigint into actual from storage.objects where bucket_id=r.bucket and name=object_path;
 if (actual is not null and actual=r.bytes) or (actual is null and confirmed_failure) then delete from app_private.media_reservations where path=object_path;end if;end $$;
revoke all on function public.reserve_private_upload(uuid,text,bigint) from public,anon,authenticated;
grant execute on function public.reserve_private_upload(uuid,text,bigint) to service_role;

alter table app_private.media_cleanup add column if not exists bucket text not null default 'media' check(bucket in('media','private-media'));
create or replace function app_private.enqueue_media() returns trigger language plpgsql security definer set search_path='' as $$
declare item jsonb;old_media jsonb;new_media jsonb;begin
 if tg_table_name='posts' then old_media:=old.media;new_media:=case when tg_op='DELETE' then '[]'::jsonb else new.media end;
 else old_media:=jsonb_build_array(old.media);new_media:='[]'::jsonb;end if;
 for item in select value from jsonb_array_elements(old_media) loop
 if coalesce(item->>'path','')<>'' and not exists(select 1 from jsonb_array_elements(new_media)m where m->>'path'=item->>'path' and coalesce(m->>'bucket','media')=coalesce(item->>'bucket','media')) then
 insert into app_private.media_cleanup(path,bucket) values(item->>'path',coalesce(item->>'bucket','media'));end if;end loop;
 if tg_op='DELETE' then return old;else return new;end if;end $$;
create or replace function public.cleanup_claim_v2() returns table(id uuid,path text,bucket text) language plpgsql security invoker set search_path='' as $$begin
 delete from public.stories where series_id is null and expires_at<now();delete from app_private.login_attempts where window_start<now()-interval '1 day';
 return query select q.id,q.path,q.bucket from app_private.media_cleanup q order by q.created_at limit 100;end $$;
revoke all on function public.cleanup_claim_v2() from public,anon,authenticated;
grant execute on function public.cleanup_claim_v2() to service_role;

create or replace function public.my_billing() returns jsonb language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.profiles x join auth.users u on u.id=x.id where x.id=auth.uid() and not x.is_demo and u.email_confirmed_at is not null) then raise exception 'Sign in';end if;
 return jsonb_build_object(
 'orders',(select coalesce(jsonb_agg(x),'[]') from(select o.id,o.creator_id,o.kind,o.post_id,o.amount,o.currency,o.status,o.expires_at,o.auto_renew,o.cancel_requested,o.renewal_state,o.created_at,a.provider from app_private.payment_orders o join app_private.payment_accounts a on a.id=o.account_id where buyer_id=auth.uid() and parent_id is null order by o.created_at desc limit 100)x),
 'accounts',(select coalesce(jsonb_agg(x),'[]') from(select id,provider,state,config-'stripe_account' as config from app_private.payment_accounts where creator_id=auth.uid() and current)x));
end $$;
revoke all on function public.my_billing() from public,anon;
grant execute on function public.my_billing() to authenticated;

-- Server-only bookkeeping. Caller identity is established by getUser in the Edge API.
create or replace function public.billing_backend(command text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o app_private.payment_orders;a app_private.payment_accounts;root app_private.payment_orders;offer public.creator_offers;post public.posts;actor uuid;v_id uuid;fresh boolean;until_date timestamptz;begin
 if command='account_get' then
  if p?'account_id' then select * into a from app_private.payment_accounts where id=(p->>'account_id')::uuid;
  elsif p?'stripe_account' then select * into a from app_private.payment_accounts where provider='stripe' and config->>'stripe_account'=p->>'stripe_account' order by created_at desc limit 1;
  else select * into a from app_private.payment_accounts where creator_id=(p->>'creator_id')::uuid and provider=p->>'provider' and current;end if;
  return to_jsonb(a);
 elsif command='account_save' then
  update app_private.payment_accounts set current=false where creator_id=(p->>'creator_id')::uuid and provider=p->>'provider' and current;
  insert into app_private.payment_accounts(creator_id,provider,credentials,credential_context,config,state) values((p->>'creator_id')::uuid,p->>'provider',coalesce(p->>'credentials',''),(p->>'creator_id')||':'||(p->>'provider'),coalesce(p->'config','{}'),coalesce(p->>'state','pending')) returning id into v_id;
  return jsonb_build_object('id',v_id);
 elsif command='account_activate' then
  update app_private.payment_accounts set state='active' where id=(p->>'account_id')::uuid;return jsonb_build_object('ok',true);
 elsif command='account_pubkey' then
  update app_private.payment_accounts set config=jsonb_set(config,'{pubkey}',to_jsonb(p->>'pubkey')) where id=(p->>'account_id')::uuid;return jsonb_build_object('ok',true);
 elsif command='options' then
  return jsonb_build_object('offer',(select to_jsonb(c) from public.creator_offers c where creator_id=(p->>'creator_id')::uuid),
   'accounts',(select coalesce(jsonb_agg(jsonb_build_object('provider',provider,'state',state,'tokenization',coalesce((config->>'tokenization')::boolean,false))),'[]') from app_private.payment_accounts where creator_id=(p->>'creator_id')::uuid and current));
 elsif command='order_create' then
  actor:=(p->>'buyer_id')::uuid;
  perform 1 from public.profiles where id in(actor,(p->>'creator_id')::uuid) order by id for share;
  if actor=(p->>'creator_id')::uuid or not exists(select 1 from public.profiles x join auth.users u on u.id=x.id where x.id=actor and not x.suspended and u.email_confirmed_at is not null) then raise exception 'Invalid buyer';end if;
  if not exists(select 1 from public.profiles where id=(p->>'creator_id')::uuid and not suspended and not is_demo) or exists(select 1 from public.blocks where (blocker_id=actor and blocked_id=(p->>'creator_id')::uuid) or (blocked_id=actor and blocker_id=(p->>'creator_id')::uuid)) then raise exception 'Creator unavailable';end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text||':'||(p->>'creator_id'),0));
  select * into a from app_private.payment_accounts where creator_id=(p->>'creator_id')::uuid and provider=p->>'provider' and state='active' and current;
  if a.id is null then raise exception 'Payment provider is not connected';end if;
  select * into o from app_private.payment_orders where buyer_id=actor and client_key=(p->>'client_key')::uuid;
  if found then
   if o.creator_id<>(p->>'creator_id')::uuid or o.kind<>p->>'kind' or o.account_id<>a.id or o.post_id is distinct from nullif(p->>'post_id','')::uuid then raise exception 'Checkout key already used';end if;
   return to_jsonb(o);
  end if;
  if p->>'kind'='subscription' then
   if p->>'consent' is distinct from 'true' then raise exception 'Recurring payment consent required';end if;
   select * into offer from public.creator_offers where creator_id=a.creator_id and enabled;
   if offer.creator_id is null then raise exception 'Subscription unavailable';end if;
   if exists(select 1 from app_private.payment_orders where buyer_id=actor and creator_id=a.creator_id and kind='subscription' and parent_id is null and ((status in('creating','pending') and auto_renew) or(status='paid' and(expires_at>now() or(auto_renew and not cancel_requested))))) then raise exception 'An existing subscription must be managed first';end if;
   insert into app_private.payment_orders(buyer_id,creator_id,account_id,kind,amount,client_key,auto_renew,consent_at) values(actor,a.creator_id,a.id,'subscription',offer.monthly_cents,(p->>'client_key')::uuid,true,now()) returning * into o;
  elsif p->>'kind'='purchase' then
   select * into post from public.posts where id=(p->>'post_id')::uuid and author_id=a.creator_id and not hidden and not deleted and access in('purchase','either');
   if post.id is null or coalesce(post.paid_root_id,post.id)<>post.id then raise exception 'Purchase root unavailable';end if;
   if exists(select 1 from app_private.payment_orders where buyer_id=actor and post_id=post.id and kind='purchase' and status='paid') then raise exception 'Already purchased';end if;
   select * into o from app_private.payment_orders where buyer_id=actor and post_id=post.id and kind='purchase' and status in('creating','pending') order by created_at limit 1;
   if found then if o.account_id<>a.id then raise exception 'An existing checkout for this post must be resolved first';end if;return to_jsonb(o);end if;
   insert into app_private.payment_orders(buyer_id,creator_id,account_id,kind,post_id,amount,client_key) values(actor,a.creator_id,a.id,'purchase',post.id,post.price_cents,(p->>'client_key')::uuid) returning * into o;
  else raise exception 'Invalid product';end if;return to_jsonb(o);
 elsif command='order_get' then
  select * into o from app_private.payment_orders where id=(p->>'order_id')::uuid;return to_jsonb(o);
 elsif command='order_reference' then
  select * into o from app_private.payment_orders where account_id=(p->>'account_id')::uuid and parent_id is null and ((p?'subscription_id' and external_subscription=p->>'subscription_id') or(p?'payment_reference' and payment_reference=p->>'payment_reference'));
  if o.id is null and p?'payment_reference' then select x.* into o from app_private.payment_orders x join app_private.payment_events e on e.order_id=x.id where e.account_id=(p->>'account_id')::uuid and e.payment_reference=p->>'payment_reference' limit 1;end if;
  return to_jsonb(o);
 elsif command='order_update' then
  update app_private.payment_orders set checkout_id=coalesce(p->>'checkout_id',checkout_id),checkout_url=coalesce(p->>'checkout_url',checkout_url),external_subscription=coalesce(p->>'subscription_id',external_subscription),status=case when status='creating' then coalesce(p->>'status','pending') else status end where id=(p->>'order_id')::uuid;return jsonb_build_object('ok',true);
 elsif command='checkout_claim' then
  update app_private.payment_orders set checkout_started=true where id=(p->>'order_id')::uuid and not checkout_started returning true into fresh;
  return jsonb_build_object('claimed',coalesce(fresh,false));
 elsif command='cancel_request' then
  update app_private.payment_orders set cancel_requested=true where id=(p->>'order_id')::uuid and buyer_id=(p->>'buyer_id')::uuid and kind='subscription' returning * into o;
  if o.id is null then raise exception 'Subscription unavailable';end if;return to_jsonb(o);
 elsif command='cancel_done' then
  update app_private.payment_orders set auto_renew=false,cancel_requested=true where id=(p->>'order_id')::uuid;return jsonb_build_object('ok',true);
 elsif command='cancel_claim' then
  select * into o from app_private.payment_orders where kind='subscription' and parent_id is null and auto_renew and cancel_requested and cancel_retry_at<=now() order by cancel_retry_at for update skip locked limit 1;
  if o.id is null then return null;end if;
  update app_private.payment_orders set cancel_retry_at=now()+interval '5 minutes' where id=o.id;return to_jsonb(o);
 elsif command='event' then
  select * into o from app_private.payment_orders where id=(p->>'order_id')::uuid for update;
  if o.id is null or o.account_id<>(p->>'account_id')::uuid or o.amount is distinct from (p->>'amount')::integer or o.currency is distinct from p->>'currency' then raise exception 'Payment does not match order';end if;
  insert into app_private.payment_events(account_id,event_key,order_id,payment_reference) values(o.account_id,p->>'event_key',o.id,p->>'payment_reference') on conflict do nothing returning true into fresh;
  if not coalesce(fresh,false) then
   if p?'card_token' then update app_private.payment_orders set card_token=p->>'card_token' where id=coalesce(o.parent_id,o.id) and kind='subscription' and status='paid';end if;
   return jsonb_build_object('duplicate',true);end if;
  if p->>'status'='refunded' then update app_private.payment_orders set status='refunded',cancel_requested=(kind='subscription') where id in(o.id,coalesce(o.parent_id,o.id));return jsonb_build_object('ok',true);end if;
  if p->>'status'<>'paid' or o.status='refunded' then return jsonb_build_object('ignored',true);end if;
  select * into root from app_private.payment_orders where id=coalesce(o.parent_id,o.id) for update;
  if o.kind='subscription' then
   until_date:=nullif(p->>'period_end','')::timestamptz;
   if until_date is null then until_date:=greatest(coalesce(root.expires_at,now()),now())+interval '1 month';end if;
   if until_date>now()+interval '45 days' then raise exception 'Invalid billing period';end if;
  end if;
  update app_private.payment_orders set status='paid',expires_at=until_date,external_subscription=coalesce(p->>'subscription_id',external_subscription),payment_reference=coalesce(p->>'payment_reference',payment_reference),card_token=coalesce(p->>'card_token',card_token) where id=o.id;
  if o.kind='subscription' then update app_private.payment_orders set expires_at=greatest(expires_at,until_date),status='paid',renewal_state='idle',card_token=coalesce(p->>'card_token',card_token) where id=root.id and status<>'refunded';end if;
  return jsonb_build_object('ok',true);
 elsif command='renew_claim' then
  select x.* into root from app_private.payment_orders x join app_private.payment_accounts c on c.id=x.account_id where x.kind='subscription' and x.parent_id is null and x.auto_renew and not x.cancel_requested and x.status='paid' and x.expires_at<=now() and x.renewal_state='idle' and x.card_token is not null and c.provider='monobank' and c.state='active' order by x.expires_at for update of x skip locked limit 1;
  if root.id is null then return null;end if;
  update app_private.payment_orders set renewal_state='processing' where id=root.id;
  insert into app_private.payment_orders(buyer_id,creator_id,account_id,kind,amount,client_key,parent_id,auto_renew,consent_at) values(root.buyer_id,root.creator_id,root.account_id,'subscription',root.amount,gen_random_uuid(),root.id,true,root.consent_at) returning * into o;
  return to_jsonb(o)||jsonb_build_object('card_token',root.card_token);
 elsif command='renew_failed' then
  update app_private.payment_orders set renewal_state=case when (p->>'unknown')::boolean then 'unknown' else 'failed' end where id=(select parent_id from app_private.payment_orders where id=(p->>'order_id')::uuid);return jsonb_build_object('ok',true);
 elsif command='deletion_orders' then
  return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from app_private.payment_orders x where (buyer_id=(p->>'user_id')::uuid or creator_id=(p->>'user_id')::uuid) and kind='subscription' and parent_id is null and auto_renew);
 else raise exception 'Unknown billing operation';end if;
end $$;
revoke all on function public.billing_backend(text,jsonb) from public,anon,authenticated;
grant execute on function public.billing_backend(text,jsonb) to service_role;
alter publication supabase_realtime add table public.paid_previews;
commit;
