import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {PGlite} from '@electric-sql/pglite';

test('blog: draft privacy, publishing, ownership, limits and deletion',async()=>{
 const db=new PGlite();
 try{
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
   create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema auth to anon,authenticated,service_role;
   create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
   create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,metadata jsonb default '{}');
   alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,delete on storage.objects to authenticated;
   create function storage.foldername(text) returns text[] language sql immutable as $$select string_to_array($1,'/')$$;`);
  for(const name of ['schema','maintenance','hardening'])await db.exec(fs.readFileSync(new URL(`../supabase/${name}.sql`,import.meta.url),'utf8').replace(/^alter publication supabase_realtime.*$/gm,''));
  await db.exec(fs.readFileSync(new URL('../supabase/migrations/20261116094248_creator_blog.sql',import.meta.url),'utf8'));
  await db.exec(fs.readFileSync(new URL('../supabase/migrations/20261116095128_private_blog_dispatch.sql',import.meta.url),'utf8'));
  const users=[1,2,3].map(n=>`40000000-0000-4000-8000-00000000000${n}`);
  const rpc=async(id:string,action:string,payload:unknown={})=>db.transaction(async tx=>{
   await tx.exec('set local role authenticated');await tx.query("select set_config('request.jwt.claim.sub',$1,true)",[id]);
   return (await tx.query<{value:any}>(`select public.${action==='onboard'?'app_action':'blog_action'}($1,$2::jsonb) as value`,[action,JSON.stringify(payload)])).rows[0].value;
  });
  for(const [i,id]of users.entries()){
   await db.query('insert into auth.users values($1,$2,now())',[id,`chat_fixture_${i}@example.invalid`]);
   await rpc(id,'onboard',{username:`chat_fixture_${i}`,display_name:`Chat fixture ${i}`,birth_date:'2000-01-01'});
  }

  const [author,reader]=users;
  const read=async(role:string,id:string)=>db.transaction(async tx=>{await tx.exec('set local role '+role);await tx.query("select set_config('request.jwt.claim.sub',$1,true)",[id]);return (await tx.query('select * from public.articles')).rows;});
  const draft=await rpc(author,'save',{title:'Draft',body:'PRIVATE_DRAFT'});
  assert.equal((await read('anon','')).length,0);
  assert.equal((await read('authenticated',reader)).length,0);
  assert.equal((await read('authenticated',author)).length,1);
  await assert.rejects(()=>rpc(reader,'save',{id:draft.id,title:'Stolen',body:'X',publish:true}));
  await assert.rejects(()=>rpc(reader,'delete',{id:draft.id}));
  await assert.rejects(()=>rpc(reader,'unpublish',{id:draft.id}));
  await assert.rejects(()=>rpc(author,'save',{title:'',body:'X',publish:true}));
  await assert.rejects(()=>rpc(author,'save',{title:'Empty body',publish:true}));
  await assert.rejects(()=>rpc(author,'save',{title:'Too long',body:'x'.repeat(50001)}));
  await rpc(author,'save',{id:draft.id,title:'Published',body:'Article body',publish:true});
  assert.equal((await read('anon','')).length,1);
  await db.query('insert into public.blocks values($1,$2)',[reader,author]);
  assert.equal((await read('authenticated',reader)).length,0);
  assert.equal((await read('anon','')).length,1);
  await rpc(author,'unpublish',{id:draft.id});assert.equal((await read('anon','')).length,0);
  await rpc(author,'save',{id:draft.id,title:'Published again',body:'Updated',publish:true});
  await db.query('update public.profiles set suspended=true where id=$1',[author]);
  assert.equal((await read('anon','')).length,0);
  await assert.rejects(()=>rpc(author,'save',{id:draft.id,title:'Suspended',body:'X'}));
  await db.query('update public.profiles set suspended=false where id=$1',[author]);
  await rpc(author,'delete',{id:draft.id});assert.equal((await read('authenticated',author)).length,0);
  await assert.rejects(()=>db.transaction(async tx=>{await tx.exec('set local role authenticated');await tx.query("insert into public.articles(author_id,title) values($1,'bypass')",[author]);}));
 }finally{await db.close();}
});
