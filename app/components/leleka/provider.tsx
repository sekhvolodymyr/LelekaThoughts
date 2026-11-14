'use client';
import {createContext,useCallback,useContext,useEffect,useState} from 'react';
import type {User} from '@supabase/supabase-js';
import {toast} from 'sonner';
import {action,supabase} from '@/lib/leleka/client';
import type {Profile,Post,Story,Series,Thread,Follow,Notice,Conversation} from '@/lib/leleka/types';
import {translate,type Language} from '@/lib/leleka/i18n';
import {normalizeTheme,type ThemeId} from '@/lib/leleka/themes';
type Snapshot={profiles:Profile[];posts:Post[];stories:Story[];series:Series[];threads:Thread[];follows:Follow[];saves:string[];notices:Notice[];conversations:Conversation[];blocks:string[];reads:{conversation_id:string;last_read_at:string}[]};
const EMPTY:Snapshot={profiles:[],posts:[],stories:[],series:[],threads:[],follows:[],saves:[],notices:[],conversations:[],blocks:[],reads:[]};
type Context=Snapshot&{user:User|null;me:Profile|null;ready:boolean;loading:boolean;error:string;language:Language;theme:ThemeId;admin:boolean;setLanguage:(l:Language)=>void;setTheme:(t:string)=>void;t:(s:string)=>string;refresh:()=>Promise<void>;mutate:(name:string,p?:Record<string,unknown>)=>Promise<any>;requireAuth:()=>boolean;authOpen:boolean;setAuthOpen:(v:boolean)=>void;loadMore:()=>void;hasMore:boolean};
const Ctx=createContext<Context>(null!);
export function Provider({children}:{children:React.ReactNode}){
 const [data,setData]=useState(EMPTY),[user,setUser]=useState<User|null>(null),[ready,setReady]=useState(false),[loading,setLoading]=useState(true),[error,setError]=useState(''),[language,setLang]=useState<Language>('uk'),[theme,setThemeState]=useState<ThemeId>('light'),[authOpen,setAuthOpen]=useState(false),[admin,setAdmin]=useState(false),[limit,setLimit]=useState(24),[hasMore,setHasMore]=useState(false);
 const t=useCallback((s:string)=>translate(language,s),[language]);
 const setLanguage=useCallback((l:Language)=>{setLang(l);localStorage.setItem('leleka.language',l);document.documentElement.lang=l},[]);
 const setTheme=useCallback((value:string)=>{const v=normalizeTheme(value);setThemeState(v);localStorage.setItem('leleka.theme',v);document.documentElement.dataset.theme=v},[]);
 useEffect(()=>{setLanguage((localStorage.getItem('leleka.language') as Language)||'uk');setTheme(localStorage.getItem('leleka.theme')||'light');const {data:{subscription}}=supabase.auth.onAuthStateChange((event,session)=>{setUser(session?.user||null);setReady(true);if(event==='PASSWORD_RECOVERY'){setAuthOpen(true);sessionStorage.setItem('leleka.recovery','1')}});supabase.auth.getSession().then(({data:{session}})=>{setUser(session?.user||null);setReady(true)});if('serviceWorker'in navigator)navigator.serviceWorker.register('/sw.js').catch(()=>{});return()=>subscription.unsubscribe()},[setLanguage,setTheme]);
 const refresh=useCallback(async()=>{
  setError('');
  try{
   const queries=[supabase.from('profiles').select('*').order('created_at').limit(200),supabase.from('posts').select('*,author:profiles!posts_author_id_fkey(*),thread:threads(*),likes(user_id),comments(id),reposts(user_id)').order('created_at',{ascending:false}).limit(limit),supabase.from('stories').select('*').order('created_at',{ascending:true}).limit(200),supabase.from('series').select('*').order('created_at',{ascending:false}).limit(100),supabase.from('threads').select('*').order('created_at',{ascending:false}).limit(100),supabase.from('follows').select('follower_id,following_id').limit(3000)];
   if(user)queries.push(supabase.from('saves').select('post_id'),supabase.from('notifications').select('*').order('created_at',{ascending:false}).limit(100),supabase.from('conversations').select('*').order('created_at',{ascending:false}),supabase.from('blocks').select('blocked_id'),supabase.from('message_reads').select('conversation_id,last_read_at'));
   const responses=await Promise.all(queries);for(const r of responses)if(r.error)throw new Error(r.error.message);
   const values=responses.map(r=>r.data||[]);setHasMore(values[1].length===limit);setData({profiles:values[0] as any,posts:values[1] as any,stories:values[2] as any,series:values[3] as any,threads:values[4] as any,follows:values[5] as any,saves:user?values[6].map((r:any)=>r.post_id):[],notices:(values[7]||[]) as any,conversations:(values[8]||[]) as any,blocks:(values[9]||[]).map((r:any)=>r.blocked_id),reads:(values[10]||[]) as any});
  }catch(e){setError(e instanceof Error?e.message:String(e))}finally{setLoading(false)}
 },[user,limit]);
 useEffect(()=>{if(ready)void refresh()},[ready,refresh]);
 useEffect(()=>{if(!ready)return;const channel=supabase.channel('leleka-updates').on('postgres_changes',{event:'*',schema:'public',table:'posts'},()=>void refresh());if(user){channel.on('postgres_changes',{event:'*',schema:'public',table:'notifications',filter:`recipient_id=eq.${user.id}`},()=>void refresh());supabase.rpc('my_admin_status').then(({data})=>setAdmin(!!data))}else setAdmin(false);channel.subscribe();return()=>{void supabase.removeChannel(channel)}},[user,ready,refresh]);
 const requireAuth=()=>{if(!user){setAuthOpen(true);return false}return true};
 const mutate=async(name:string,p:Record<string,unknown>={})=>{if(!requireAuth())return null;try{const result=await action(name,p);await refresh();return result}catch(e){toast.error(e instanceof Error?e.message:String(e));throw e}};
 const value:Context={...data,user,me:data.profiles.find(p=>p.id===user?.id)||null,ready,loading,error,language,theme,admin,setLanguage,setTheme,t,refresh,mutate,requireAuth,authOpen,setAuthOpen,loadMore:()=>setLimit(n=>n+24),hasMore};
 return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}
export const useApp=()=>useContext(Ctx);
