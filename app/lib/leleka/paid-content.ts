import {supabase,SUPABASE_URL,PUBLIC_KEY} from './client';
import type {Post} from './types';
const select='*,author:profiles!posts_author_id_fkey(*),thread:threads(*),likes(user_id),comments(id),reposts(user_id)';
export async function listPosts(options:{limit?:number;id?:string;ids?:string[];threadId?:string;authorId?:string;text?:string}={}){
 try{
  const build=(table:'posts'|'paid_previews')=>{
   let q=supabase.from(table).select(table==='posts'?select:'*,author:profiles!paid_previews_author_id_fkey(*),thread:threads(*)');
   if(options.id)q=q.eq('id',options.id);if(options.ids)q=q.in('id',options.ids);
   if(options.threadId)q=q.eq('thread_id',options.threadId);if(options.authorId)q=q.eq('author_id',options.authorId);
   if(options.text)q=q.ilike('body',`%${options.text}%`);
   return q.order(options.threadId?'part':'created_at',{ascending:!!options.threadId}).limit(options.limit||24);
  };
  const [full,preview]=await Promise.all([build('posts'),build('paid_previews')]);
  if(full.error)throw full.error;
  // Allows preparing the client before the separately approved database rollout.
  if(preview.error&&!['PGRST205','42P01'].includes(preview.error.code))throw preview.error;
  const byId=new Map<string,Post>();
  for(const p of (preview.data||[]) as unknown as Post[])byId.set(p.id,{...p,media:[],likes:[],comments:[],reposts:[],quote_id:null,hidden:false,locked:true});
  for(const p of (full.data||[]) as unknown as Post[])byId.set(p.id,p);
  const data=[...byId.values()].sort((a,b)=>options.threadId?(a.part||0)-(b.part||0):Date.parse(b.created_at)-Date.parse(a.created_at)).slice(0,options.limit||24);
  return {data,error:null};
 }catch(e){return {data:[] as Post[],error:{message:e instanceof Error?e.message:String((e as {message?:string})?.message||'Не вдалося завантажити пости')}};}
}
export async function billingAction(action:string,payload:Record<string,unknown>={}){
 const {data:{session}}=await supabase.auth.getSession();if(!session)throw Error('Увійдіть до акаунта');
 const response=await fetch(`${SUPABASE_URL}/functions/v1/billing`,{method:'POST',headers:{apikey:PUBLIC_KEY,Authorization:`Bearer ${session.access_token}`,'Content-Type':'application/json'},body:JSON.stringify({action,...payload})});
 const data=await response.json() as Record<string,any>;if(!response.ok)throw Error(data.error||'Платіжний сервіс ще готується');return data;
}
export const price=(cents:number)=>new Intl.NumberFormat('uk-UA',{style:'currency',currency:'UAH',maximumFractionDigits:2}).format(cents/100);
