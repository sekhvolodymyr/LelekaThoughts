import {createClient} from 'npm:@supabase/supabase-js@2.119.0';
const url=Deno.env.get('SUPABASE_URL')!;
const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const anonKey=Deno.env.get('SUPABASE_ANON_KEY')!;
const publishable='sb_publishable_Qj9arKK4QNhVttXhRMX1kA_qIp7U9Ed';
const allowedOrigins=new Set(['https://leleka-thoughts.volodymyr-sekh-work.chatgpt.site','http://localhost:5173','http://127.0.0.1:5173','http://localhost:3000','http://127.0.0.1:3000']);
Deno.serve(async request=>{
 const origin=request.headers.get('origin');
 const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':origin&&allowedOrigins.has(origin)?origin:'https://leleka-thoughts.volodymyr-sekh-work.chatgpt.site','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin'};
 const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(request.method!=='POST')return json({error:'Method not allowed'},405);
 if(origin&&!allowedOrigins.has(origin))return json({error:'Origin not allowed'},403);
 if(![anonKey,publishable].includes(request.headers.get('apikey')||''))return json({error:'API key required'},401);
 const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 try{
  const data=await request.json();
  if(data.action==='username_login'){
   const username=String(data.username||'').toLowerCase().replace(/^@/,'');const password=String(data.password||'');
   if(!/^[a-z0-9_.]{3,30}$/.test(username)||!password||password.length>256)return json({error:'Невірний логін або пароль'},400);
   const ip=request.headers.get('x-forwarded-for')?.split(',')[0]||'unknown';const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(ip+':'+username));const fingerprint=Array.from(new Uint8Array(digest)).map(b=>b.toString(16).padStart(2,'0')).join('');
   const {data:allowed,error:guardError}=await admin.rpc('login_guard',{fingerprint});if(guardError||!allowed)return json({error:'Забагато спроб. Спробуйте пізніше.'},429);
   const {data:profile}=await admin.from('profiles').select('id').eq('username',username).eq('is_demo',false).maybeSingle();
   const {data:authUser}=profile?await admin.auth.admin.getUserById(profile.id):{data:null};
   const client=createClient(url,anonKey,{auth:{persistSession:false,autoRefreshToken:false}});
   const {data:result,error}=await client.auth.signInWithPassword({email:authUser?.user?.email||'invalid-user@invalid.example',password});
   if(error||!result.session)return json({error:'Невірний логін або пароль'},400);
   return json({session:{access_token:result.session.access_token,refresh_token:result.session.refresh_token}});
  }
  const token=(request.headers.get('authorization')||'').replace(/^Bearer /i,'');const {data:{user},error}=await admin.auth.getUser(token);
  if(error||!user)return json({error:'Увійдіть до акаунта'},401);
  if(data.action!=='delete_account')return json({error:'Unknown action'},400);
  if(!user.last_sign_in_at||Date.now()-new Date(user.last_sign_in_at).getTime()>5*60*1000)return json({error:'Повторно увійдіть до акаунта перед видаленням (протягом 5 хвилин).'},403);
  // Stop new writes while deletion is in progress; retrying deletion still works.
  const {error:suspendError}=await admin.from('profiles').update({suspended:true}).eq('id',user.id);if(suspendError)throw suspendError;
  // List at offset 0 after each removal so large folders are not skipped.
  for(let page=0;page<100;page++){
   const {data:files,error}=await admin.storage.from('media').list(user.id,{limit:100});if(error)throw error;if(!files?.length)break;
   const {error:removeError}=await admin.storage.from('media').remove(files.map(f=>`${user.id}/${f.name}`));if(removeError)throw removeError;
  }
  const {error:postError}=await admin.from('posts').update({body:'',media:[],deleted:true,edited_at:new Date().toISOString()}).eq('author_id',user.id);if(postError)throw postError;
  const {error:commentError}=await admin.from('comments').update({body:'',deleted:true}).eq('author_id',user.id);if(commentError)throw commentError;
  const {data:ownPosts,error:listError}=await admin.from('posts').select('id').eq('author_id',user.id);if(listError)throw listError;
  const ids=(ownPosts||[]).map(p=>p.id);
  if(ids.length){
   const {data:quotes,error:quoteError}=await admin.from('posts').select('quote_id').in('quote_id',ids);if(quoteError)throw quoteError;
   const retained=new Set((quotes||[]).map(p=>p.quote_id));
   const removable=ids.filter(id=>!retained.has(id));
   if(removable.length){const {error}=await admin.from('posts').delete().in('id',removable);if(error)throw error;}
   const {error:detachError}=await admin.from('posts').update({thread_id:null,part:null}).eq('author_id',user.id);if(detachError)throw detachError;
  }
  const {error:threadError}=await admin.from('threads').delete().eq('author_id',user.id);if(threadError)throw threadError;
  const {error:profileError}=await admin.from('profiles').delete().eq('id',user.id);if(profileError)throw profileError;
  await admin.auth.admin.signOut(token,'global');
  const {error:deleteError}=await admin.auth.admin.deleteUser(user.id);if(deleteError)throw deleteError;
  return json({ok:true});
 }catch(error){console.error('Account operation failed',error instanceof Error?error.message:'Unknown');return json({error:'Не вдалося виконати дію. Спробуйте ще раз.'},500)}
});
