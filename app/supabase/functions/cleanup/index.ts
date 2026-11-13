import {createClient} from 'npm:@supabase/supabase-js@2.119.0';
const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
// Public housekeeping endpoint with a single bounded capability. It accepts no
// IDs/paths from callers; only already-expired rows and trusted queued paths.
// The platform JWT gate requires the project's public anon JWT for invocation.
Deno.serve(async request=>{
 if(request.method!=='POST')return new Response('Method not allowed',{status:405});
 const {data:jobs,error}=await admin.rpc('cleanup_claim');if(error){console.error(error.message);return new Response('Cleanup unavailable',{status:500})}
 if(!jobs?.length)return Response.json({removed:0});
 const {error:removeError}=await admin.storage.from('media').remove(jobs.map((j:{path:string})=>j.path));
 if(removeError){console.error(removeError.message);return new Response('Storage cleanup pending',{status:503})}
 const {error:ackError}=await admin.rpc('cleanup_ack',{ids:jobs.map((j:{id:string})=>j.id)});if(ackError)return new Response('Cleanup acknowledgment pending',{status:503});
 return Response.json({removed:jobs.length});
});
