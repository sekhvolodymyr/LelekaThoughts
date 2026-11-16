'use client';
import {useEffect,useRef,useState} from 'react';
import {ArrowLeft,Plus,BookOpen} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {supabase} from '@/lib/leleka/client';
import {articleUrl,type Article} from '@/lib/leleka/blog';
import {useApp} from './provider';
import {Blank,FormField} from './ui';
type Draft={id?:string;title:string;excerpt:string;body:string;status:'draft'|'published'};
const empty:Draft={title:'',excerpt:'',body:'',status:'draft'};
export function MyBlog(){
 const {user,t}=useApp();const [items,setItems]=useState<Article[]>([]),[draft,setDraft]=useState<Draft|null>(null),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[limit,setLimit]=useState(50);
 const alive=useRef(true);useEffect(()=>{alive.current=true;return()=>{alive.current=false}},[]);
 const draftKey=`leleka.blog.v1:${user?.id}`;
 async function load(){if(!user)return;setLoading(true);const {data,error}=await supabase.from('articles').select('id,author_id,title,excerpt,status,created_at,updated_at,published_at').eq('author_id',user.id).order('updated_at',{ascending:false}).limit(limit);if(!alive.current)return;setLoading(false);if(error)setError(error.message);else setItems((data||[]) as Article[])}
 useEffect(()=>{void load()},[user?.id,limit]);
 function change(next:Draft){setDraft(next);try{localStorage.setItem(draftKey,JSON.stringify(next))}catch{setError(t('Не вдалося зберегти текст на пристрої. Збережіть чернетку.'))}}
 function create(){setError('');setNotice('');let next=empty;try{const cached=JSON.parse(localStorage.getItem(draftKey)||'null');if(cached&&typeof cached.title==='string'&&typeof cached.body==='string'&&typeof cached.excerpt==='string')next={...empty,...cached}}catch{}setDraft(next)}
 async function edit(id:string){setBusy(true);setError('');try{const {data,error}=await supabase.from('articles').select('*').eq('id',id).eq('author_id',user!.id).single();if(error)throw error;if(alive.current)setDraft(data)}catch(e){if(alive.current)setError((e as Error).message)}finally{if(alive.current)setBusy(false)}}
 async function run(action:string,payload:Record<string,unknown>){
  if(busy)return;setBusy(true);setError('');setNotice('');
  try{
   if(!navigator.onLine)throw Error(t('Немає інтернету'));
   const {error}=await supabase.rpc('blog_action',{action,payload});if(error)throw error;
   if(!alive.current)return;
   if(action==='save'||action==='unpublish')try{localStorage.removeItem(draftKey)}catch{/* Server save succeeded. */}
   setDraft(null);setNotice(t(action==='delete'?'Статтю видалено':action==='unpublish'?'Стаття тепер у чернетках':'Статтю збережено'));await load();
  }catch(e){if(alive.current)setError((e as Error).message)}finally{if(alive.current)setBusy(false)}
 }
 return <section className="my-blog"><header className="page-title"><h1>{t('Мій блог')}</h1>{!draft&&<Button disabled={busy} onClick={create}><Plus size={17}/>{t('Написати статтю')}</Button>}</header>
 <div className="section-pad form-stack">{error&&<p role="alert" className="error-text">{error}</p>}{notice&&<p role="status" className="muted">{notice}</p>}
 {draft?<><Button variant="ghost" className="blog-back" disabled={busy} onClick={()=>setDraft(null)}><ArrowLeft size={16}/>{t('До моїх статей')}</Button>
 <form className="form-stack" onSubmit={e=>{e.preventDefault();void run('save',{...draft,publish:true})}}>
 <FormField label={t('Назва статті')}><input required maxLength={160} value={draft.title} onChange={e=>change({...draft,title:e.target.value})} disabled={busy}/></FormField>
 <FormField label={t('Короткий опис')}><textarea maxLength={240} rows={2} value={draft.excerpt} onChange={e=>change({...draft,excerpt:e.target.value})} disabled={busy}/></FormField>
 <FormField label={t('Текст статті')}><textarea className="blog-editor" maxLength={50000} rows={18} value={draft.body} onChange={e=>change({...draft,body:e.target.value})} disabled={busy}/></FormField>
 <p className="muted blog-hint">{draft.body.length.toLocaleString()} / 50 000 · {t('Чернетки бачиш тільки ти. Текст зберігається на цьому пристрої під час введення.')}</p>
 <div className="blog-editor-actions"><Button type="submit" disabled={busy||!draft.title.trim()||!draft.body.trim()}>{t(draft.status==='published'?'Оновити статтю':'Опублікувати статтю')}</Button>
 {draft.status==='draft'?<Button type="button" variant="outline" disabled={busy||!draft.title.trim()} onClick={()=>void run('save',{...draft,publish:false})}>{t('Зберегти чернетку')}</Button>:<Button type="button" variant="outline" disabled={busy||!draft.title.trim()} onClick={()=>void run('unpublish',{...draft})}>{t('Зняти з публікації')}</Button>}</div>
 </form></>:<>
 <p className="muted">{t('Довші історії, досвід і думки — у власних статтях.')} <a className="text-link" href="/blog">{t('Читати блоги')} ↗</a></p>
 {loading?<p role="status">{t('Завантаження…')}</p>:!items.length?<Blank title="Ще немає статей" description="Почни з ідеї та збережи її як чернетку або поділися з усіма."><BookOpen size={28}/></Blank>:items.map(article=><article className="blog-card" key={article.id}><span className="chip">{t(article.status==='published'?'Опубліковано':'Чернетка')}</span><h2>{article.title}</h2>{article.excerpt&&<p>{article.excerpt}</p>}<small className="muted">{new Date(article.updated_at).toLocaleDateString()}</small><div className="blog-card-actions"><Button variant="outline" disabled={busy} onClick={()=>void edit(article.id)}>{t('Редагувати')}</Button>{article.status==='published'&&<a className="text-link" href={articleUrl(article.id)}>{t('Читати статтю')} ↗</a>}<button className="text-link blog-delete" disabled={busy} onClick={()=>{if(confirm(t('Видалити статтю назавжди?')))void run('delete',{id:article.id})}}>{t('Видалити')}</button></div></article>)}
 {!loading&&items.length===limit&&<Button variant="outline" onClick={()=>setLimit(n=>n+50)}>{t('Показати ще')}</Button>}
 </>}
 </div></section>;
}
