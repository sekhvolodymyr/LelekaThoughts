'use client';
import {useEffect,useRef,useState} from 'react';
import {Plus,ChevronLeft,ChevronRight,Heart,Volume2,VolumeX,Pause,Play,Eye,Bookmark,Trash2,Send} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {toast} from 'sonner';
import {supabase,action,removeMedia} from '@/lib/leleka/client';
import type {Story,Series} from '@/lib/leleka/types';
import {useApp} from './provider';
import {Avatar,Modal,FormField} from './ui';
import type {Navigate} from './post-card';
export function StoryStrip({onCreate,onOpen}:{onCreate:()=>void;onOpen:(s:Story[])=>void}){
 const {stories,profiles,t,requireAuth}=useApp();const active=stories.filter(s=>new Date(s.expires_at).getTime()>Date.now());const ids=[...new Set(active.map(s=>s.author_id))];
 return <section className="stories-strip"><h2>{t('Історії, що тривають')}</h2><div className="story-people"><button className="story-person" onClick={()=>requireAuth()&&onCreate()}><span className="story-ring add"><Plus size={26}/></span><span>{t('Додати')}</span></button>{ids.map(id=>{const person=profiles.find(p=>p.id===id);return <button className="story-person" key={id} onClick={()=>onOpen(active.filter(s=>s.author_id===id))}><span className="story-ring"><Avatar profile={person} size={57}/></span><span>{person?.display_name.split(' ')[0]||'Leleka'}</span></button>})}{!ids.length&&<p className="muted story-empty">{t('Розкажіть про свою ідею')}</p>}</div></section>;
}
export function StoryViewer({items,onClose,navigate}:{items:Story[];onClose:()=>void;navigate:Navigate}){
 const app=useApp();const {t,user,profiles,series,threads,posts,mutate,language,requireAuth}=app;const [index,setIndex]=useState(0),[progress,setProgress]=useState(0),[paused,setPaused]=useState(false),[muted,setMuted]=useState(true),[liked,setLiked]=useState(false),[viewers,setViewers]=useState<string[]>([]),[showViews,setShowViews]=useState(false),[saving,setSaving]=useState(false),[title,setTitle]=useState(''),[threadId,setThreadId]=useState(''),[error,setError]=useState('');
 const video=useRef<HTMLVideoElement>(null),seen=useRef(new Set<string>());const story=items[index],person=profiles.find(p=>p.id===story?.author_id),collection=series.find(s=>s.id===story?.series_id),own=user?.id===story?.author_id;const advance=()=>index<items.length-1?setIndex(i=>i+1):onClose();
 useEffect(()=>{if(!story)return;setProgress(0);setError('');setShowViews(false);setSaving(false);if(!seen.current.has(story.id)){seen.current.add(story.id);action('view_story',{id:story.id}).catch(()=>{})}if(user){supabase.from('story_likes').select('user_id').eq('story_id',story.id).eq('user_id',user.id).maybeSingle().then(({data})=>setLiked(!!data));if(own&&new Date(story.expires_at).getTime()>Date.now())supabase.from('story_views').select('viewer_id').eq('story_id',story.id).then(({data})=>setViewers((data||[]).map(x=>x.viewer_id).filter(Boolean)));}else setLiked(false)},[story?.id,user?.id,own]);
 useEffect(()=>{if(!story||paused||story.media.type.startsWith('video/'))return;const timer=setInterval(()=>setProgress(v=>Math.min(100,v+1)),50);return()=>clearInterval(timer)},[story?.id,paused]);
 useEffect(()=>{if(progress>=100&&!paused)advance()},[progress,paused]);
 useEffect(()=>{if(video.current){if(paused)video.current.pause();else void video.current.play().catch(()=>setPaused(true))}},[paused,story?.id]);
 useEffect(()=>{const key=(e:KeyboardEvent)=>{if(e.target instanceof HTMLInputElement||e.target instanceof HTMLTextAreaElement)return;if(e.key==='ArrowRight')advance();if(e.key==='ArrowLeft')setIndex(i=>Math.max(0,i-1));if(e.key===' '){e.preventDefault();setPaused(v=>!v)}};window.addEventListener('keydown',key);return()=>window.removeEventListener('keydown',key)},[index,items.length]);
 if(!story)return null;
 const discussion=story.post_id||posts.filter(p=>p.thread_id===collection?.thread_id).sort((a,b)=>(a.part||0)-(b.part||0))[0]?.id;
 return <Modal open onClose={onClose} title={collection?.title||person?.display_name||t('Сторіс')} wide><div className="story-viewer">
  <div className="story-progress">{items.map((s,i)=><span key={s.id}><i style={{width:`${i<index?100:i===index?progress:0}%`}}/></span>)}</div>
  <div className="story-viewer-head"><Avatar profile={person} size={32}/><strong>{person?.display_name}</strong><button aria-label={paused?'Play':'Pause'} onClick={()=>setPaused(v=>!v)}>{paused?<Play size={18}/>:<Pause size={18}/>}</button>{story.media.type.startsWith('video/')&&<button aria-label="Sound" onClick={()=>setMuted(v=>!v)}>{muted?<VolumeX size={18}/>:<Volume2 size={18}/>}</button>}</div>
  <div className="story-stage" onPointerDown={()=>setPaused(true)} onPointerUp={()=>setPaused(false)} onPointerLeave={()=>{}}>
   {story.media.type.startsWith('video/')?<video key={story.id} ref={video} src={story.media.src} playsInline autoPlay muted={muted} onTimeUpdate={e=>{const v=e.currentTarget;if(v.duration)setProgress(v.currentTime/v.duration*100)}} onEnded={advance} onError={()=>{setError(language==='uk'?'Відео недоступне':'Video unavailable');setPaused(true)}}/>:<img key={story.id} src={story.media.src} alt={story.caption||t('Сторіс')} onError={()=>{setError(t('Помилка'));setPaused(true)}}/>}
   {index>0&&<button className="story-prev" aria-label={t('Повернутися')} onClick={()=>setIndex(i=>i-1)}><ChevronLeft/></button>}<button className="story-next" aria-label={t('Далі')} onClick={advance}><ChevronRight/></button>
   {story.caption&&<p className="story-caption">{story.caption}</p>}
  </div>
  {error&&<p className="error-text">{error}</p>}
  <div className="story-toolbar"><button className={liked?'active':''} aria-label={t('Вподобати')} onClick={()=>{if(requireAuth())void mutate('like_story',{id:story.id}).then(r=>r&&setLiked(r.active)).catch(()=>{})}}><Heart size={22} fill={liked?'currentColor':'none'}/></button>{own&&<button onClick={()=>{setPaused(true);setShowViews(v=>!v)}}><Eye size={20}/>{story.views}</button>}<button aria-label={t('Поділитися')} onClick={()=>{onClose();navigate(`/messages/share-series/${collection?.id||''}`)}} disabled={!collection}><Send size={20}/></button>{own&&!collection&&<button aria-label={t('Зберегти в серію')} onClick={()=>{setSaving(true);setPaused(true)}}><Bookmark size={20}/></button>}{own&&<button aria-label={t('Видалити')} onClick={async()=>{if(!confirm(t('Видалити')+'?'))return;try{await mutate('delete_story',{id:story.id});await removeMedia([story.media]);onClose()}catch{}}}><Trash2 size={19}/></button>}</div>
  {collection?.thread_id&&<button className="text-link" onClick={()=>{onClose();navigate(discussion?`/post/${discussion}`:`/thread/${collection.thread_id}`)}}>{t('Обговорити в ланцюжку')}</button>}
  {showViews&&<div className="story-view-list"><strong>{t('Перегляди')}: {story.views}</strong><p>{t('Анонімні відкриття')}: {story.anonymous_views}</p>{new Date(story.expires_at).getTime()>Date.now()&&<><p>{t('Авторизовані глядачі')}</p>{viewers.map(id=>{const p=profiles.find(x=>x.id===id);return <div className="person-row" key={id}><Avatar profile={p} size={28}/>{p?.display_name||'Leleka'}</div>})}</>}</div>}
  {saving&&<form className="form-stack story-save" onSubmit={async e=>{e.preventDefault();try{await mutate('save_story',{id:story.id,title,thread_id:threadId});setSaving(false);toast.success(t('Збережено'))}catch{}}}><FormField label={t('Назва серії')}><input required value={title} maxLength={100} onChange={e=>setTitle(e.target.value)}/></FormField><select aria-label={t('Ланцюжки')} value={threadId} onChange={e=>setThreadId(e.target.value)}><option value="">{t('Без ланцюжка')}</option>{threads.filter(x=>x.author_id===user?.id).map(th=><option value={th.id} key={th.id}>{th.title}</option>)}</select><Button type="submit">{t('Зберегти')}</Button></form>}
 </div></Modal>;
}
