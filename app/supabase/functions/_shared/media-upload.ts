import {createClient} from 'npm:@supabase/supabase-js@2.119.0';

const url = Deno.env.get('SUPABASE_URL')!;
const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {auth: {persistSession: false, autoRefreshToken: false}});
const maxBytes = 50 * 1024 * 1024;
const types: Record<string, string> = {'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif', 'video/mp4': 'mp4', 'video/webm': 'webm', 'video/quicktime': 'mov'};
const origins = new Set(['https://lelekathoughts.vercel.app', 'https://leleka-thoughts.volodymyr-sekh-work.chatgpt.site', 'http://localhost:5173', 'http://127.0.0.1:5173', 'http://localhost:3000', 'http://127.0.0.1:3000']);

export function serveMedia(bucket:'media'|'private-media'){
Deno.serve(async request => {
  const origin = request.headers.get('origin');
  const headers = {'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Vary': 'Origin',
    'Access-Control-Allow-Origin': origin && origins.has(origin) ? origin : 'https://lelekathoughts.vercel.app',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-media-access', 'Access-Control-Allow-Methods': 'POST, OPTIONS'};
  const json = (data: unknown, status = 200) => Response.json(data, {status, headers});
  if (origin && !origins.has(origin)) return json({error: 'Origin not allowed'}, 403);
  if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers});
  if (request.method !== 'POST') return json({error: 'Method not allowed'}, 405);
  const token = request.headers.get('authorization')?.replace(/^Bearer /i, '') || '';
  const {data: {user}, error: authError} = await admin.auth.getUser(token);
  if (authError || !user?.email_confirmed_at) return json({error: 'Sign in with a confirmed email'}, 401);
  const type = request.headers.get('content-type')?.split(';')[0].trim() || '';
  if (!types[type]) return json({error: 'Unsupported media type'}, 415);
  const declared = Number(request.headers.get('content-length'));
  if (declared > maxBytes) return json({error: 'Maximum file size is 50 MiB'}, 413);
  // Validate actual bytes before reserving; never trust a client size/path claim.
  const reader = request.body?.getReader();
  if (!reader) return json({error: 'Empty media'}, 400);
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) { await reader.cancel(); return json({error: 'Maximum file size is 50 MiB'}, 413); }
      chunks.push(value);
    }
  } catch { return json({error: 'Upload interrupted'}, 400); }
  if (!size) return json({error: 'Empty media'}, 400);
  // A distinct endpoint fails closed during rollout: an older public upload
  // function must never receive a private file while ignoring a new header.
  if(request.headers.get('x-media-access')==='private'&&bucket==='media')return json({error:'Use the private-media endpoint'},400);
  if(bucket==='private-media'){
    const {data:existing}=await admin.storage.getBucket(bucket);
    if(existing?.public)return json({error:'Private media storage is not private'},503);
    if(!existing){const {error}=await admin.storage.createBucket(bucket,{public:false,fileSizeLimit:maxBytes,allowedMimeTypes:Object.keys(types)});if(error){const {data:retry}=await admin.storage.getBucket(bucket);if(!retry||retry.public)return json({error:'Private media storage unavailable'},503);}}
  }
  const path = `${user.id}/${crypto.randomUUID()}.${types[type]}`;
  const {error: quotaError} = await admin.rpc(bucket==='media'?'reserve_media_upload':'reserve_private_upload', {owner: user.id, object_path: path, byte_size: size});
  if (quotaError) return json({error: quotaError.message}, 409);
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  chunks.length = 0;
  try {
    const {error} = await admin.storage.from(bucket).upload(path, bytes, {contentType: type, upsert: false});
    if (error) throw error;
    const {error: settleError} = await admin.rpc('settle_media_upload', {object_path: path});
    if (settleError) throw settleError;
    return json({path, type, bucket, src: `${url}/storage/v1/object/${bucket==='media'?'public':'authenticated'}/${bucket}/${path}`});
  } catch (error) {
    // An explicit Storage API response has finished the operation. A network
    // failure has no such guarantee; never free bytes for a possibly late write.
    const definite = !!error && typeof error === 'object' && 'statusCode' in error;
    await admin.rpc('reconcile_media_upload', {object_path: path, confirmed_failure: definite});
    // A lost response can hide a committed upload. Keep its reservation charged;
    // do not expire/release it while an upstream write could still complete.
    console.error('Media upload requires reconciliation', {path, definite});
    return json({error: 'Upload could not be confirmed. Please try again later.'}, 503);
  }
});

}
