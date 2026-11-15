// Focused regression with ordinary fixture privileges. Never logs credentials.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const [manifest,statePath,out] = process.argv.slice(2);
const cfg=JSON.parse(fs.readFileSync(manifest,'utf8').replace(/^\uFEFF/,''));
const state=JSON.parse(fs.readFileSync(statePath,'utf8'));
assert.equal(cfg.runId,state.runId);
const u=state.users[0];
assert.ok(u.email.startsWith(cfg.runId+'_') && u.email.endsWith('@example.invalid'));
fs.writeFileSync(out,`${new Date().toISOString()} Focused live regression ${cfg.runId}\n`);
const log=s=>{fs.appendFileSync(out,s+'\n');console.log(s);};
let token, failures=0, checks=0;
async function req(path,body,auth=token,method='POST',extra={}) {
 const r=await fetch(cfg.url+path,{method,signal:AbortSignal.timeout(20000),headers:{apikey:cfg.publicKey,...(auth?{Authorization:`Bearer ${auth}`} :{}),'Content-Type':'application/json',...extra},...(body===undefined?{}:{body:Buffer.isBuffer(body)?body:JSON.stringify(body)})});
 const raw=await r.text();let data;try{data=JSON.parse(raw);}catch{data=raw;}
 return {status:r.status,ok:r.ok,data};
}
const rpc=(action,payload={},auth=token)=>req('/rest/v1/rpc/app_action',{action,payload},auth);
const check=(name,pass)=>{checks++;if(!pass)failures++;log(`${pass?'PASS':'FAIL'} ${name}`);};
try {
 const login=await req('/auth/v1/token?grant_type=password',{email:u.email,password:cfg.password},null);
 assert.equal(login.data.user?.id,u.id); token=login.data.access_token;
 const bad=[null,1,'string',{}, {path:42,src:'https://example.com/x',type:'image/png'}, {path:`${u.id}/x`,src:'javascript:alert(1)',type:'image/png'}, {path:`${u.id}/x`,src:'https://example.com/x',type:'unknown'}];
 for(const [i,media] of bad.entries()) {
  for(const action of ['post','edit_post','story']) {
   const r=await rpc(action,action==='story'?{media}:{id:u.post,body:'regression',media:[media]});
   check(`${action} rejects malformed media ${i}`,r.status>=400&&r.status<500);
  }
 }
 for(const duration of [null,'30',0,-1,31,{},[]]) {
  const r=await rpc('story',{media:{path:`${u.id}/fake.mp4`,src:'https://example.com/x',type:'video/mp4',duration}});
  check(`story rejects invalid duration ${JSON.stringify(duration)}`,r.status>=400&&r.status<500);
 }
 const unchanged=await req(`/rest/v1/posts?select=body&id=eq.${u.post}`,undefined,token,'GET');
 check('invalid edit leaves original content intact',unchanged.ok&&unchanged.data[0]?.body!== 'regression');
 const denied=await req('/rest/v1/rpc/reserve_media_upload',{owner:u.id,object_path:`${u.id}/forged.png`,byte_size:1});
 check('ordinary account cannot reserve quota',denied.status===401||denied.status===403);
 const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64');
 const direct=await req(`/storage/v1/object/media/${u.id}/bypass.png`,png,token,'POST',{'Content-Type':'image/png'});
 check('direct storage quota bypass denied',!direct.ok&&direct.status<500);
 const upload=await req('/functions/v1/media',png,token,'POST',{'Content-Type':'image/png'});
 check('gateway accepts legitimate image upload',upload.ok&&upload.data.path?.startsWith(u.id+'/'));
 if(upload.ok){
  u.paths.push(upload.data.path);fs.writeFileSync(statePath,JSON.stringify(state,null,2));
  const post=await rpc('post',{body:cfg.runId+' valid upload',media:[upload.data]});
  check('legitimate image post accepted',post.ok&&!!post.data.id);
 }
 const before=await req(`/rest/v1/stories?select=views,anonymous_views&id=eq.${u.story}`,undefined,token,'GET');
 const results=await Promise.all(Array.from({length:100},()=>rpc('view_story',{id:u.story},null).catch(()=>({ok:false}))));
 const after=await req(`/rest/v1/stories?select=views,anonymous_views&id=eq.${u.story}`,undefined,token,'GET');
 const counted=results.filter(r=>r.data?.counted===true).length;
 check('100 concurrent anonymous views return successfully',results.every(r=>r.ok));
 check('anonymous opens bounded at 60 per minute',counted<=60&&after.data[0]?.anonymous_views-before.data[0]?.anonymous_views<=60);
 const one=await rpc('view_story',{id:u.story});const two=await rpc('view_story',{id:u.story});
 const viewers=await req(`/rest/v1/story_views?select=viewer_id&story_id=eq.${u.story}&viewer_id=eq.${u.id}`,undefined,token,'GET');
 check('authenticated repeat view deduplicated',one.ok&&two.ok&&viewers.data.length===1);
 // Read-only final capacity probe: records 100 simultaneous requests separately.
 const times=[];let active=0,peak=0;
 const reads=await Promise.all(Array.from({length:100},async()=>{active++;peak=Math.max(peak,active);const start=performance.now();try{return await req('/rest/v1/profiles?select=id&limit=1',undefined,null,'GET');}catch{return {ok:false};}finally{active--;times.push(performance.now()-start);}}));
 times.sort((a,b)=>a-b);log(`CAPACITY read_requests=100 peak=${peak} succeeded=${reads.filter(r=>r.ok).length} p95_ms=${times[94].toFixed(1)}`);
} catch(e){failures++;log(`ERROR ${e.name}: ${String(e.message).replaceAll(cfg.password,'[REDACTED]')}`);}
finally {
 if(token)await req('/auth/v1/logout?scope=global',undefined,token).catch(()=>{});
 log(`RESULT checks=${checks} failures=${failures}`);process.exitCode=failures?1:0;
}
