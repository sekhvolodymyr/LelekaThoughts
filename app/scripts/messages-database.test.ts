import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {PGlite} from '@electric-sql/pglite';

test('chat: send, read, accept, reply and isolate read notifications',async()=>{
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
  const users=[1,2,3].map(n=>`40000000-0000-4000-8000-00000000000${n}`);
  const rpc=async(id:string,action:string,payload:unknown={})=>db.transaction(async tx=>{
   await tx.exec('set local role authenticated');await tx.query("select set_config('request.jwt.claim.sub',$1,true)",[id]);
   return (await tx.query<{value:any}>('select public.app_action($1,$2::jsonb) as value',[action,JSON.stringify(payload)])).rows[0].value;
  });
  for(const [i,id]of users.entries()){
   await db.query('insert into auth.users values($1,$2,now())',[id,`chat_fixture_${i}@example.invalid`]);
   await rpc(id,'onboard',{username:`chat_fixture_${i}`,display_name:`Chat fixture ${i}`,birth_date:'2000-01-01'});
  }
  const [sender,recipient,stranger]=users;
  const chat=await rpc(sender,'send',{recipient_id:recipient,body:'First request'});
  const other=await rpc(stranger,'send',{recipient_id:recipient,body:'Other chat'});
  await assert.rejects(()=>rpc(sender,'send',{recipient_id:recipient,body:'Wait for acceptance'}));
  await rpc(recipient,'read_chat',{id:chat.id});
  const notices=(await db.query<{target:string;read:boolean}>('select target,read from public.notifications where recipient_id=$1',[recipient])).rows;
  assert.equal(notices.find(n=>n.target===chat.id)?.read,true);
  assert.equal(notices.find(n=>n.target===other.id)?.read,false);
  await assert.rejects(()=>rpc(stranger,'read_chat',{id:chat.id}));
  await rpc(recipient,'accept_chat',{id:chat.id,accept:true});
  await rpc(recipient,'send',{recipient_id:sender,body:'Reply'});
  await rpc(sender,'read_chat',{id:chat.id});
  await rpc(sender,'send',{recipient_id:recipient,body:'Follow-up'});
  await rpc(recipient,'read_chat',{id:chat.id});
  assert.equal((await db.query('select id from public.messages where conversation_id=$1',[chat.id])).rows.length,3);
 }finally{await db.close();}
});
