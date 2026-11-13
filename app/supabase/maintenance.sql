create table app_private.login_attempts(fingerprint text primary key, attempts integer not null default 1, window_start timestamptz not null default now());
create table app_private.media_cleanup(id uuid primary key default gen_random_uuid(),path text not null,created_at timestamptz not null default now());
alter table app_private.login_attempts enable row level security;
alter table app_private.media_cleanup enable row level security;
grant all on app_private.login_attempts,app_private.media_cleanup to service_role;
grant select on app_private.config to service_role;
create function public.login_guard(fingerprint text) returns boolean language plpgsql security invoker set search_path='' as $$ declare n integer;begin
 insert into app_private.login_attempts(fingerprint) values(login_guard.fingerprint) on conflict on constraint login_attempts_pkey do update set attempts=case when app_private.login_attempts.window_start<now()-interval '10 minutes' then 1 else app_private.login_attempts.attempts+1 end,window_start=case when app_private.login_attempts.window_start<now()-interval '10 minutes' then now() else app_private.login_attempts.window_start end returning attempts into n;return n<=15;
end $$;
revoke all on function public.login_guard(text) from public,anon,authenticated;
grant execute on function public.login_guard(text) to service_role;
create function app_private.enqueue_media() returns trigger language plpgsql security definer set search_path='' as $$ declare item jsonb; old_media jsonb; new_media jsonb;begin
 if tg_table_name='posts' then old_media:=old.media;new_media:=case when tg_op='DELETE' then '[]'::jsonb else new.media end;
 else old_media:=jsonb_build_array(old.media);new_media:='[]'::jsonb; end if;
 for item in select value from jsonb_array_elements(old_media) loop
  if coalesce(item->>'path','')<>'' and not exists(select 1 from jsonb_array_elements(new_media) m where m->>'path'=item->>'path') then insert into app_private.media_cleanup(path) values(item->>'path'); end if;
 end loop;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
revoke all on function app_private.enqueue_media() from public,anon,authenticated;
create trigger post_media_cleanup after update of media or delete on public.posts for each row execute function app_private.enqueue_media();
create trigger story_media_cleanup after delete on public.stories for each row execute function app_private.enqueue_media();
create function public.cleanup_claim() returns table(id uuid,path text) language plpgsql security invoker set search_path='' as $$ begin
 delete from public.stories where series_id is null and expires_at<now();
 delete from app_private.login_attempts where window_start<now()-interval '1 day';
 return query select q.id,q.path from app_private.media_cleanup q order by created_at limit 100;
end $$;
create function public.cleanup_ack(ids uuid[]) returns void language sql security invoker set search_path='' as $$ delete from app_private.media_cleanup where id=any(ids) $$;
revoke all on function public.cleanup_claim(),public.cleanup_ack(uuid[]) from public,anon,authenticated;
grant execute on function public.cleanup_claim(),public.cleanup_ack(uuid[]) to service_role;

-- Explicit deny policies document that these internal tables are service-only.
create policy deny_client on app_private.admins for all to anon,authenticated using(false) with check(false);
create policy deny_client on app_private.config for all to anon,authenticated using(false) with check(false);
create policy deny_client on app_private.login_attempts for all to anon,authenticated using(false) with check(false);
create policy deny_client on app_private.media_cleanup for all to anon,authenticated using(false) with check(false);
