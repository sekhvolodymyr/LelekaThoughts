'use client';
import {useEffect,useRef,useState} from 'react';
import {ImagePlus,X,Film,Link2} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {toast} from 'sonner';
import {TOPICS,type Post,type Media} from '@/lib/leleka/types';
import {action,upload,removeMedia,supabase} from '@/lib/leleka/client';
import {useApp} from './provider';
import {Modal,Avatar,FormField} from './ui';
export type ComposeOptions={kind?:'post'|'story';parent?:Post;edit?:Post;quote?:Post};
export function Composer({options,onClose,onPublished}:{options:ComposeOptions;onClose:()=>void;onPublished:(id?:string)=>void}){
 const {user,me,t,threads,series,posts,refresh}=useApp();const [kind,setKind]=useState(options.kind||'post'),[body,setBody]=useState(options.edit?.body||''),[topics,setTopics]=useState(options.edit?.topics||options.parent?.topics||[]),[files,setFiles]=useState<File[]>([]),[existing,setExisting]=useState<Media[]>(options.edit?.media||[]),[previews,setPreviews]=useState<string[]>([]),[title,setTitle]=useState(''),[seriesId,setSeriesId]=useState(''),[seriesTitle,setSeriesTitle]=useState(''),[threadId,setThreadId]=useState(''),[discussion,setDiscussion]=useState(''),[busy,setBusy]=useState(false),[draftReady,setDraftReady]=useState(false),[offline,setOffline]=useState(false),[error,setError]=useState('');
 const slot=options.parent?`continue:${options.parent.id}`:'post';const localKey=`leleka.draft.v1:${user?.id}:${slot}`;const dirty=useRef(false);const formId=useRef(crypto.randomUUID());
 useEffect(()=>{const sync=()=>setOffline(!navigator.onLine);sync();window.addEventListener('online',sync);window.addEventListener('offline',sync);return()=>{window.removeEventListener('online',sync);window.removeEventListener('offline',sync)}},[]);
 useEffect(()=>{if(options.edit||options.quote){setDraftReady(true);return}let active=true;const local=localStorage.getItem(localKey);if(local){try{const d=JSON.parse(local);setBody(d.body||'');setTopics(d.topics||[])}catch{}}supabase.from('drafts').select('*').eq('slot',slot).maybeSingle().then(({data})=>{if(active&&!dirty.current&&!local&&data){setBody(data.body);setTopics(data.topics)}if(active)setDraftReady(true)});return()=>{active=false}},[localKey,slot,options.edit,options.quote]);
 useEffect(()=>{if(!draftReady||options.edit||options.quote||kind==='story')return;localStorage.setItem(localKey,JSON.stringify({body,topics,parent_id:options.parent?.id}));const timer=setTimeout(()=>{if(navigator.onLine)action('draft',{slot,body,topics,parent_id:options.parent?.id}).catch(()=>{})},900);return()=>clearTimeout(timer)},[body,topics,slot,localKey,draftReady,kind,options]);
 useEffect(()=>{const urls=files.map(f=>URL.createObjectURL(f));setPreviews(urls);return()=>urls.forEach(u=>URL.revokeObjectURL(u))},[files]);
 const pick=(e:React.ChangeEvent<HTMLInputElement>)=>{const selected=Array.from(e.target.files||[]);if(kind==='post'){if(selected.some(f=>!f.type.startsWith('image/'))){setError(t('До 4 фото'));return}if(existing.length+files.length+selected.length>4){setError(t('До 4 фото'));return}setFiles(v=>[...v,...selected])}else setFiles(selected.slice(0,1));setError('');e.target.value=''};
 const submit=async(e:React.FormEvent)=>{e.preventDefault();if(!user||!me||!navigator.onLine)return;setBusy(true);setError('');const uploaded:Media[]=[];try{
  for(const file of files)uploaded.push(await upload(file,user.id));
  if(kind==='story'){
   if(!uploaded[0])throw new Error(t('Завантажте фото або відео до 30 секунд'));
   await action('story',{media:uploaded[0],caption:body,series_id:seriesId,series_title:seriesTitle,thread_id:threadId,post_id:discussion});
  }else{
   const result=await action(options.edit?'edit_post':'post',{id:options.edit?.id,body,topics,media:[...existing,...uploaded],parent_id:options.parent?.id,thread_title:title,quote_id:options.quote?.id,slot});
   if(options.edit){const removed=options.edit.media.filter(m=>!existing.some(x=>x.path===m.path));await removeMedia(removed).catch(()=>toast.error('Пост збережено, але очищення старих фото потребує повторення'));}
   localStorage.removeItem(localKey);await refresh();onPublished(result.id);return;
  }
  await refresh();onPublished();
 }catch(e){await removeMedia(uploaded).catch(()=>{});setError(e instanceof Error?e.message:String(e))}finally{setBusy(false)}};
 const mySeries=series.filter(s=>s.author_id===user?.id),myThreads=threads.filter(s=>s.author_id===user?.id);
 return <Modal open onClose={onClose} title={t(options.edit?'Редагувати':options.parent?'Продовжити':'Створити')} wide>
  {!options.parent&&!options.edit&&!options.quote&&<div className="tabs compact"><button className={kind==='post'?'selected':''} onClick={()=>{setKind('post');setFiles([])}}>{t('Пост')}</button><button className={kind==='story'?'selected':''} onClick={()=>{setKind('story');setFiles([])}}>{t('Сторіс')}</button></div>}
  <form id={formId.current} onSubmit={submit} className="form-stack">
   <div className="compose-author"><Avatar profile={me}/><div><strong>{me?.display_name}</strong><small>@{me?.username}</small></div></div>
   {options.parent&&!options.parent.thread_id&&<FormField label={t('Назва ланцюжка')}><input required maxLength={100} value={title} onChange={e=>setTitle(e.target.value)}/></FormField>}
   {options.parent&&<p className="thread-link"><Link2 size={16}/>{options.parent.thread?.title||options.parent.body.slice(0,70)}</p>}
   <textarea aria-label={t('Розкажіть про свою ідею')} placeholder={t('З чого починається твоя ідея?')} maxLength={kind==='story'?300:1000} value={body} onChange={e=>{dirty.current=true;setBody(e.target.value)}} rows={5} autoFocus/>
   {options.quote&&<blockquote>{options.quote.author?.display_name}<p>{options.quote.body}</p></blockquote>}
   <div className="upload-previews">{existing.map((m,i)=><div key={m.path}><img src={m.src} alt=""/><button type="button" aria-label={t('Видалити')} onClick={()=>setExisting(v=>v.filter((_,n)=>n!==i))}><X size={16}/></button></div>)}{previews.map((url,i)=><div key={url}>{files[i]?.type.startsWith('video/')?<video src={url} controls/>:<img src={url} alt=""/>}<button type="button" aria-label={t('Видалити')} onClick={()=>setFiles(v=>v.filter((_,n)=>n!==i))}><X size={16}/></button></div>)}</div>
   {kind==='post'&&!options.parent&&<fieldset><legend>{t('До 3 тем')}</legend><div className="topic-options">{TOPICS.map(topic=><button type="button" className={topics.includes(topic)?'chip active':'chip'} aria-pressed={topics.includes(topic)} key={topic} onClick={()=>setTopics(v=>v.includes(topic)?v.filter(x=>x!==topic):v.length<3?[...v,topic]:v)}>{t(topic)}</button>)}</div></fieldset>}
   {kind==='story'&&<>
    <FormField label={t('Серія сторіс')}><select value={seriesId} onChange={e=>{setSeriesId(e.target.value);setThreadId(mySeries.find(x=>x.id===e.target.value)?.thread_id||'')}}><option value="">{t('Без серії')}</option>{mySeries.map(s=><option value={s.id} key={s.id}>{s.title}</option>)}</select></FormField>
    {!seriesId&&<FormField label={t('Назва серії')}><input placeholder={t('Без серії')} maxLength={100} value={seriesTitle} onChange={e=>setSeriesTitle(e.target.value)}/></FormField>}
    {(seriesId||seriesTitle)&&<FormField label={t('Ланцюжки')}><select value={threadId} disabled={!!seriesId} onChange={e=>{setThreadId(e.target.value);setDiscussion('')}}><option value="">{t('Без ланцюжка')}</option>{myThreads.map(th=><option value={th.id} key={th.id}>{th.title}</option>)}</select></FormField>}
    {threadId&&<FormField label={t('Обговорення')}><select value={discussion} onChange={e=>setDiscussion(e.target.value)}><option value="">{t('Перший пост')}</option>{posts.filter(p=>p.thread_id===threadId&&!p.deleted).sort((a,b)=>(a.part||0)-(b.part||0)).map(p=><option value={p.id} key={p.id}>{p.part}. {p.body.slice(0,50)}</option>)}</select></FormField>}
   </>}
   {offline&&<p role="status" className="error-text">{t('Немає інтернету')}. {t('Текст збережено на цьому пристрої')}.</p>}
   {error&&<p role="alert" className="error-text">{error}</p>}
   <div className="compose-footer"><label className="upload-button" title={t(kind==='post'?'До 4 фото':'Завантажте фото або відео до 30 секунд')}>{kind==='post'?<ImagePlus size={22}/>:<Film size={22}/>}<span>{t(kind==='post'?'Фото':'Додати')}</span><input type="file" accept={kind==='post'?'image/*':'image/*,video/mp4,video/webm,video/quicktime'} multiple={kind==='post'} onChange={pick} disabled={busy}/></label><small>{body.length}/{kind==='post'?1000:300}</small><Button type="submit" disabled={busy||offline||(kind==='post'?!body.trim()&&!files.length&&!existing.length:!files.length)}>{busy?t('Завантаження…'):t('Опублікувати')}</Button></div>
  </form>
 </Modal>;
}
