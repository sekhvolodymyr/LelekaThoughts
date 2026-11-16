-- Additive blog feature. Does not modify posts, payments or existing RLS.
begin;
create table public.articles(
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.profiles(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 160),
 excerpt text not null default '' check(length(excerpt)<=240),
 body text not null default '' check(length(body)<=50000),
 status text not null default 'draft' check(status in('draft','published')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 published_at timestamptz,
 constraint articles_published_body check(status<>'published' or(length(trim(body))>0 and published_at is not null))
);
create index articles_author_updated on public.articles(author_id,updated_at desc);
create index articles_published on public.articles(published_at desc) where status='published';
alter table public.articles enable row level security;
revoke all on public.articles from public,anon,authenticated;
grant select on public.articles to anon,authenticated;
grant all on public.articles to service_role;
create policy articles_read on public.articles for select to anon,authenticated using(
 author_id=(select auth.uid()) or (status='published' and app_private.visible_author(author_id))
);
create function public.blog_action(action text,payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); article_id uuid:=nullif(payload->>'id','')::uuid; result uuid;begin
 if actor is null or not exists(
  select 1 from auth.users u join public.profiles p on p.id=u.id join public.account_settings s on s.id=p.id
  where p.id=actor and not p.suspended and not p.is_demo and u.email_confirmed_at is not null and s.birth_date<=(current_date-interval '16 years')::date
 ) then raise exception 'Sign in with a verified creator account';end if;
 if action='save' then
  if article_id is null then
   insert into public.articles(author_id,title,excerpt,body,status,published_at)
   values(actor,trim(payload->>'title'),coalesce(payload->>'excerpt',''),coalesce(payload->>'body',''),case when payload->>'publish'='true' then 'published' else 'draft' end,case when payload->>'publish'='true' then now() end) returning id into result;
  else
   update public.articles set title=trim(payload->>'title'),excerpt=coalesce(payload->>'excerpt',''),body=coalesce(payload->>'body',''),
    status=case when payload->>'publish'='true' then 'published' else status end,
    published_at=case when payload->>'publish'='true' then coalesce(published_at,now()) else published_at end,updated_at=now()
    where id=article_id and author_id=actor returning id into result;
  end if;
 elsif action='unpublish' then
  update public.articles set status='draft',updated_at=now(),
   title=case when payload?'title' then trim(payload->>'title') else title end,
   excerpt=case when payload?'excerpt' then payload->>'excerpt' else excerpt end,
   body=case when payload?'body' then payload->>'body' else body end
   where id=article_id and author_id=actor returning id into result;
 elsif action='delete' then
  delete from public.articles where id=article_id and author_id=actor returning id into result;
 else raise exception 'Unknown blog action';end if;
 if result is null then raise exception 'Article unavailable';end if;
 return jsonb_build_object('id',result);
end $$;
revoke all on function public.blog_action(text,jsonb) from public,anon;
grant execute on function public.blog_action(text,jsonb) to authenticated;
commit;
