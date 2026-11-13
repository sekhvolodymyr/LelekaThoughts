'use client';
import {useEffect,useState} from 'react';
import {Heart,MessageCircle,Repeat2,Bookmark,MoreHorizontal,Link2,ArrowUpRight,CornerDownRight,Pin,Send} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {DropdownMenu,DropdownMenuContent,DropdownMenuItem,DropdownMenuTrigger,DropdownMenuGroup} from '@/components/ui/dropdown-menu';
import {toast} from 'sonner';
import {supabase,removeMedia} from '@/lib/leleka/client';
import type {Post,Comment} from '@/lib/leleka/types';
import {useApp} from './provider';
import {Avatar,ago,Modal,FormField} from './ui';
import type {ComposeOptions} from './composer';
export type Navigate=(path:string)=>void;
export function PostCard({post,navigate,compose,openComments=false}:{post:Post;navigate:Navigate;compose:(o:ComposeOptions)=>void;openComments?:boolean}){
 const app=useApp();const {t,user,mutate,requireAuth,posts,saves,series,me,language}=app;const [comments,setComments]=useState(openComments),[report,setReport]=useState(false),[reason,setReason]=useState(''),[busy,setBusy]=useState(false);
 const [remoteQuote,setRemoteQuote]=useState<Post|null>(null);
 const own=user?.id===post.author_id,liked=post.likes?.some(x=>x.user_id===user?.id),reposted=post.reposts?.some(x=>x.user_id===user?.id),saved=saves.includes(post.id),quote=posts.find(p=>p.id===post.quote_id)||remoteQuote;
 useEffect(()=>{if(post.quote_id&&!posts.some(p=>p.id===post.quote_id))supabase.from('posts').select('*,author:profiles!posts_author_id_fkey(*)').eq('id',post.quote_id).maybeSingle().then(({data})=>setRemoteQuote(data as any));},[post.quote_id,posts]);
 const fire=(name:string,p:Record<string,unknown>={})=>void mutate(name,{id:post.id,...p}).catch(()=>{});
 const remove=async()=>{if(!confirm(language==='uk'?'Видалити цей пост?':'Delete this post?'))return;try{await mutate('delete_post',{id:post.id});await removeMedia(post.media)}catch(e){toast.error(e instanceof Error?e.message:String(e))}};
 return <article className="post" id={`post-${post.id}`}>
  <div className="post-avatar"><button aria-label={post.author?.display_name||t('Профіль')} onClick={()=>post.author_id&&navigate(`/profile/${post.author_id}`)}><Avatar profile={post.author}/></button></div>
  <div className="post-main">
   {me?.pinned_post===post.id&&<small className="muted inline"><Pin size={12}/>{t('Закріплено')}</small>}
   <div className="post-byline"><button className="person-name" onClick={()=>post.author_id&&navigate(`/profile/${post.author_id}`)}>{post.author?.display_name||t('Видалений користувач')}</button><span>@{post.author?.username||'deleted'}</span><span>· {ago(post.created_at,language)}</span><div className="post-menu"><DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" size="icon-sm" aria-label={t('Відкрити меню')}><MoreHorizontal size={19}/></Button></DropdownMenuTrigger><DropdownMenuContent align="end"><DropdownMenuGroup>
    <DropdownMenuItem onClick={()=>navigator.clipboard.writeText(`${location.origin}/#/post/${post.id}`).then(()=>toast.success(t('Готово'))).catch(()=>toast.error(t('Помилка')))}>{t('Посилання')}</DropdownMenuItem>
    {!post.deleted&&own&&<><DropdownMenuItem onClick={()=>compose({edit:post})}>{t('Редагувати')}</DropdownMenuItem><DropdownMenuItem onClick={()=>fire('pin')}>{t('Закріпити')}</DropdownMenuItem><DropdownMenuItem onClick={()=>void remove()}>{t('Видалити')}</DropdownMenuItem></>}
    {!own&&<><DropdownMenuItem onClick={()=>{if(requireAuth())setReport(true)}}>{t('Поскаржитися')}</DropdownMenuItem><DropdownMenuItem onClick={()=>post.author_id&&void mutate('block',{id:post.author_id}).catch(()=>{})}>{t('Заблокувати')}</DropdownMenuItem></>}
   </DropdownMenuGroup></DropdownMenuContent></DropdownMenu></div></div>
   {post.author?.is_demo&&<small className="demo-label">{t('Приклад контенту')}</small>}
   <p className={post.deleted?'post-body muted':'post-body'}>{post.deleted?t('Пост видалено'):post.body}</p>
   {post.edited_at&&!post.deleted&&<small className="muted">{t('Змінено')}</small>}
   {post.thread&&<button className="thread-link" onClick={()=>navigate(`/thread/${post.thread_id}/${post.id}`)}><span className="thread-mark"/><span>{post.part&&post.part>1?`${t('Продовження ланцюжка')} · `:''}{post.thread.title} · {t('Частина')} {post.part}</span><ArrowUpRight size={14}/></button>}
   {!post.deleted&&post.media?.length>0&&<div className={`post-media media-${post.media.length}`}>{post.media.map(m=><a key={m.path||m.src} href={m.src} target="_blank" rel="noreferrer"><img src={m.src} alt={post.body.slice(0,120)||t('Фото')} loading="lazy"/></a>)}</div>}
   {post.quote_id&&!post.deleted&&<button className="quote" onClick={()=>navigate(`/post/${post.quote_id}`)}><strong>{quote?.author?.display_name||'LelekaThoughts'}</strong><p>{!quote||quote.deleted?t('Пост видалено'):quote.body}</p></button>}
   {post.thread&&post.part!==1&&<button className="text-link subtle" onClick={()=>navigate(`/thread/${post.thread_id}`)}>{t('Читати від початку')}</button>}
   {series.some(s=>s.thread_id===post.thread_id)&&post.thread_id&&<button className="text-link subtle" onClick={()=>navigate(`/series/${series.find(s=>s.thread_id===post.thread_id)!.id}`)}>{t('Дивитися процес')} <ArrowUpRight size={13}/></button>}
   {!post.deleted&&<div className="post-actions">
    <button className={liked?'active':''} aria-label={t('Вподобати')} aria-pressed={liked} onClick={()=>fire('like')}><Heart size={20} fill={liked?'currentColor':'none'}/><span>{post.likes?.length||''}</span></button>
    <button aria-label={t('Коментарі')} aria-expanded={comments} onClick={()=>setComments(v=>!v)}><MessageCircle size={20}/><span>{post.comments?.length||''}</span></button>
    <DropdownMenu><DropdownMenuTrigger asChild><button className={reposted?'active':''} aria-label={t('Репост')}><Repeat2 size={20}/><span>{post.reposts?.length||''}</span></button></DropdownMenuTrigger><DropdownMenuContent><DropdownMenuGroup><DropdownMenuItem onClick={()=>fire('repost')}>{t('Репост')}</DropdownMenuItem><DropdownMenuItem onClick={()=>requireAuth()&&compose({quote:post})}>{t('Цитувати')}</DropdownMenuItem><DropdownMenuItem onClick={()=>navigate(`/messages/share-post/${post.id}`)}>{t('Поділитися')}</DropdownMenuItem></DropdownMenuGroup></DropdownMenuContent></DropdownMenu>
    <button className={saved?'save-action active':'save-action'} aria-label={t('Зберегти')} aria-pressed={saved} onClick={()=>fire('save')}><Bookmark size={20} fill={saved?'currentColor':'none'}/></button>
   </div>}
   {own&&!post.deleted&&<button className="text-link subtle" onClick={()=>compose({parent:post})}><Link2 size={13}/>{t('Продовжити')}</button>}
   {comments&&<Comments post={post}/>}
  </div>
  <Modal open={report} onClose={()=>setReport(false)} title={t('Поскаржитися')}><form className="form-stack" onSubmit={async e=>{e.preventDefault();setBusy(true);try{await mutate('report',{id:post.id,target_type:'post',reason});setReport(false);toast.success(t('Скаргу надіслано'))}catch{}finally{setBusy(false)}}}><FormField label={language==='uk'?'Причина скарги':'Reason'}><textarea required value={reason} maxLength={1000} onChange={e=>setReason(e.target.value)}/></FormField><Button type="submit" disabled={busy}>{t('Надіслати')}</Button></form></Modal>
 </article>;
}

function Comments({post}:{post:Post}){
 const {user,t,language,mutate,requireAuth}=useApp();const [items,setItems]=useState<Comment[]>([]),[text,setText]=useState(''),[reply,setReply]=useState<Comment|null>(null),[expanded,setExpanded]=useState<string[]>([]),[busy,setBusy]=useState(false);
 const load=async()=>{const {data,error}=await supabase.from('comments').select('*,author:profiles!comments_author_id_fkey(*)').eq('post_id',post.id).order('created_at').limit(200);if(error)toast.error(error.message);else setItems(data as any||[])};
 useEffect(()=>{void load()},[post.id]);
 const send=async(e:React.FormEvent)=>{e.preventDefault();if(!requireAuth())return;setBusy(true);try{await mutate('comment',{id:post.id,body:text,parent_id:reply?.parent_id||reply?.id});if(reply)setExpanded(v=>[...v,reply.parent_id||reply.id]);setText('');setReply(null);await load()}catch{}finally{setBusy(false)}};
 const row=(c:Comment,nested=false)=><div className={nested?'comment reply':'comment'} key={c.id}><Avatar profile={c.author} size={28}/><div className="comment-main"><div className="comment-byline"><strong>{c.author?.display_name||t('Видалений користувач')}</strong><small>{ago(c.created_at,language)}</small></div><p>{c.deleted?t('Коментар видалено'):c.body}</p><div className="comment-links">{!c.deleted&&<button onClick={()=>{if(requireAuth()){setReply(c);setText(`@${c.author?.username||'deleted'} `)}}}>{t('Відповісти')}</button>}{(user?.id===c.author_id||user?.id===post.author_id)&&!c.deleted&&<button onClick={()=>void mutate('delete_comment',{id:c.id}).then(load).catch(()=>{})}>{t('Видалити')}</button>}</div></div></div>;
 return <section className="comments" aria-label={t('Коментарі')}>{items.filter(c=>!c.parent_id).map(c=><div key={c.id}>{row(c)}{items.some(r=>r.parent_id===c.id)&&<button className="reply-toggle" aria-expanded={expanded.includes(c.id)} onClick={()=>setExpanded(v=>v.includes(c.id)?v.filter(x=>x!==c.id):[...v,c.id])}><CornerDownRight size={13}/>{t('Показати відповіді')} ({items.filter(r=>r.parent_id===c.id).length})</button>}{expanded.includes(c.id)&&items.filter(r=>r.parent_id===c.id).map(r=>row(r,true))}</div>)}
  {reply&&<div className="reply-to">@{reply.author?.username}<button aria-label={t('Скасувати')} onClick={()=>{setReply(null);setText('')}}>×</button></div>}
  <form className="comment-form" onSubmit={send}><input aria-label={t('Написати коментар…')} placeholder={t('Написати коментар…')} value={text} onChange={e=>setText(e.target.value)} maxLength={1000}/><Button variant="ghost" size="icon-sm" type="submit" disabled={busy||!text.trim()} aria-label={t('Надіслати')}><Send size={17}/></Button></form>
 </section>;
}
