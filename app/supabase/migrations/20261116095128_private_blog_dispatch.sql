-- Keep the privileged implementation outside the exposed API schema.
begin;
do $move$
declare definition text;begin
 select pg_get_functiondef('public.blog_action(text,jsonb)'::regprocedure) into definition;
 if position('SECURITY DEFINER' in definition)=0 then raise exception 'Unexpected blog function version';end if;
 execute replace(definition,'FUNCTION public.blog_action(', 'FUNCTION app_private.blog_dispatch(');
end $move$;
revoke all on function app_private.blog_dispatch(text,jsonb) from public,anon;
grant execute on function app_private.blog_dispatch(text,jsonb) to authenticated;
create or replace function public.blog_action(action text,payload jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select app_private.blog_dispatch(action,payload)$$;
revoke all on function public.blog_action(text,jsonb) from public,anon;
grant execute on function public.blog_action(text,jsonb) to authenticated;
commit;
