import {createClient} from '@supabase/supabase-js';
import type {Media} from './types';

// This is a public, deliberately browser-safe key. Authorization is enforced in Postgres.
export const SUPABASE_URL='https://glqsayxjvvnkmhejuqjz.supabase.co';
export const PUBLIC_KEY='sb_publishable_Qj9arKK4QNhVttXhRMX1kA_qIp7U9Ed';
const PUBLIC_ANON_JWT='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdscXNheXhqdnZua21oZWp1cWp6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQxNjk4MDEsImV4cCI6MjEwOTc0NTgwMX0.A0HZDgs3VJQ316kxIE0RHX1EraVAMYnqhZ38A19EDcs';
export const supabase=createClient(SUPABASE_URL,PUBLIC_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
export async function action(name:string,payload:Record<string,unknown>={}) {
 const {data,error}=await supabase.rpc('app_action',{action:name,payload}); if(error) throw new Error(error.message); return data;
}
export async function accountAction(payload:Record<string,unknown>){
 const {data:{session}}=await supabase.auth.getSession();
 const response=await fetch(`${SUPABASE_URL}/functions/v1/account`,{method:'POST',headers:{'Content-Type':'application/json',apikey:PUBLIC_KEY,Authorization:`Bearer ${session?.access_token||PUBLIC_ANON_JWT}`},body:JSON.stringify(payload)});
 const data=await response.json() as {error?:string;session:{access_token:string;refresh_token:string};ok?:boolean}; if(!response.ok) throw new Error(data.error||'Не вдалося виконати дію'); return data;
}
export async function upload(file:File,userId:string):Promise<Media>{
 const state=await action('upload_status'); if(!state.enabled)throw new Error('Завантаження медіа тимчасово призупинено. Текстові публікації доступні.');
 let duration:number|undefined; let blob:Blob=file;
 if(file.type.startsWith('video/')) {
  duration=await new Promise<number>((resolve,reject)=>{const video=document.createElement('video');const url=URL.createObjectURL(file);video.preload='metadata';video.onloadedmetadata=()=>{URL.revokeObjectURL(url);resolve(video.duration)};video.onerror=()=>{URL.revokeObjectURL(url);reject(new Error('Не вдалося прочитати відео'))};video.src=url;});
  if(!Number.isFinite(duration)||duration>30)throw new Error('Відео має тривати до 30 секунд');
 }else if(file.type.startsWith('image/')&&file.type!=='image/gif'){
  const image=await createImageBitmap(file); const ratio=Math.min(1,1800/Math.max(image.width,image.height)); const canvas=document.createElement('canvas');canvas.width=Math.round(image.width*ratio);canvas.height=Math.round(image.height*ratio);canvas.getContext('2d')!.drawImage(image,0,0,canvas.width,canvas.height);image.close();blob=await new Promise<Blob>((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error('Не вдалося обробити фото')),'image/webp',.85));
 }else if(!file.type.startsWith('image/'))throw new Error('Оберіть фото або відео');
 if(blob.size>50*1024*1024)throw new Error('Один файл має бути до 50 МБ — технічне обмеження сховища.');
 const ext=blob.type==='image/webp'?'webp':file.name.split('.').pop()?.replace(/[^a-z0-9]/gi,'')||'bin';const path=`${userId}/${crypto.randomUUID()}.${ext}`;
 const {error}=await supabase.storage.from('media').upload(path,blob,{contentType:blob.type,upsert:false});if(error)throw new Error(error.message);
 return {src:supabase.storage.from('media').getPublicUrl(path).data.publicUrl,path,type:blob.type,...(duration?{duration}:{})};
}
export async function removeMedia(media:Media[]){const paths=media.map(x=>x.path).filter(Boolean);if(paths.length){const {error}=await supabase.storage.from('media').remove(paths);if(error)throw new Error(error.message);}}
