'use client';
import {useEffect,useState} from 'react';
import {toast} from 'sonner';
import {Button} from '@/components/ui/button';
import {supabase,action,accountAction} from '@/lib/leleka/client';
import {TOPICS} from '@/lib/leleka/types';
import {useApp} from './provider';
import {Modal,FormField} from './ui';

export function AuthDialog(){
 const {authOpen,setAuthOpen,user,me,loading,refresh,t,language}=useApp();const [mode,setMode]=useState('login'),[email,setEmail]=useState(''),[password,setPassword]=useState(''),[code,setCode]=useState(''),[sent,setSent]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const [username,setUsername]=useState(''),[name,setName]=useState(''),[birth,setBirth]=useState(''),[interests,setInterests]=useState<string[]>([]);
 const onboarding=!!user&&!me&&!loading;
 useEffect(()=>{if(user){setName(user.user_metadata?.display_name||user.user_metadata?.full_name||'');setUsername(user.user_metadata?.username||'');setBirth(user.user_metadata?.birth_date||'')}if(sessionStorage.getItem('leleka.recovery'))setMode('new-password')},[user]);
 const choose=(v:string)=>{setMode(v);setSent(false);setError('')};
 const run=async(fn:()=>Promise<void>)=>{setBusy(true);setError('');try{await fn()}catch(e){setError(e instanceof Error?e.message:String(e))}finally{setBusy(false)}};
 const submit=(e:React.FormEvent)=>{e.preventDefault();void run(async()=>{
  if(onboarding){await action('onboard',{username,display_name:name,birth_date:birth,interests});await refresh();setAuthOpen(false);return;}
  if(mode==='new-password'){const {error}=await supabase.auth.updateUser({password});if(error)throw error;sessionStorage.removeItem('leleka.recovery');toast.success(t('Готово'));setAuthOpen(false);return;}
  if(mode==='login'){
   if(email.includes('@')&&!email.startsWith('@')){const {error}=await supabase.auth.signInWithPassword({email,password});if(error)throw error;}
   else{const result=await accountAction({action:'username_login',username:email.replace(/^@/,''),password});const {error}=await supabase.auth.setSession(result.session);if(error)throw error;}
   setAuthOpen(false);
  }else if(mode==='signup'){
   const {error}=await supabase.auth.signUp({email,password,options:{emailRedirectTo:location.origin,data:{username,display_name:name,birth_date:birth}}});if(error)throw error;setSent(true);
  }else if(mode==='otp'){
   const {error}=sent?await supabase.auth.verifyOtp({email,token:code,type:'email'}):await supabase.auth.signInWithOtp({email,options:{emailRedirectTo:location.origin}});if(error)throw error;if(sent)setAuthOpen(false);else setSent(true);
  }else if(mode==='reset'){const {error}=await supabase.auth.resetPasswordForEmail(email,{redirectTo:location.origin});if(error)throw error;setSent(true);}
 });};
 const google=()=>void run(async()=>{const {error}=await supabase.auth.signInWithOAuth({provider:'google',options:{redirectTo:location.origin}});if(error)throw error;});
 const title=onboarding?'Завершити реєстрацію':mode==='signup'?'Реєстрація':mode==='reset'?'Відновити пароль':mode==='otp'?'Код на email':mode==='new-password'?'Новий пароль':'Увійти';
 return <Modal open={authOpen||onboarding} onClose={()=>{if(!onboarding)setAuthOpen(false)}} title={t(title)} description={onboarding?t('Мінімальний вік — 16 років'):'LelekaThoughts'}>
  {!onboarding&&mode!=='new-password'&&<><Button variant="outline" onClick={google} disabled={busy}>G&nbsp; {t('Продовжити з Google')}</Button><div className="tabs compact">{['login','signup','otp'].map((m,i)=><button type="button" key={m} className={mode===m?'selected':''} onClick={()=>choose(m)}>{t(['Увійти','Реєстрація','Код на email'][i])}</button>)}</div></>}
  <form onSubmit={submit} className="form-stack">
   {!onboarding&&mode!=='new-password'&&<FormField label={mode==='login'?t('Email або @нік'):'Email'}><input required type={mode==='login'?'text':'email'} autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)}/></FormField>}
   {(mode==='login'||mode==='signup'||mode==='new-password')&&!onboarding&&<FormField label={t('Пароль')}><input required type="password" minLength={mode==='login'?1:8} autoComplete={mode==='login'?'current-password':'new-password'} value={password} onChange={e=>setPassword(e.target.value)}/></FormField>}
   {(onboarding||mode==='signup')&&<>
    <FormField label={t('Ім’я')}><input required maxLength={60} value={name} onChange={e=>setName(e.target.value)} autoComplete="name"/></FormField>
    <FormField label={t('Унікальний @нік')}><input required pattern="[a-z0-9_.]{3,30}" minLength={3} maxLength={30} value={username} onChange={e=>setUsername(e.target.value.toLowerCase())} autoComplete="nickname" placeholder="your.name"/></FormField>
    <FormField label={t('Дата народження')}><input required type="date" value={birth} max={`${new Date().getFullYear()-16}-${String(new Date().getMonth()+1).padStart(2,'0')}-${String(new Date().getDate()).padStart(2,'0')}`} onChange={e=>setBirth(e.target.value)}/></FormField>
    {onboarding&&<fieldset><legend>{t('Оберіть інтереси')}</legend><div className="topic-options">{TOPICS.map(topic=><button key={topic} type="button" aria-pressed={interests.includes(topic)} className={interests.includes(topic)?'chip active':'chip'} onClick={()=>setInterests(v=>v.includes(topic)?v.filter(x=>x!==topic):[...v,topic])}>{t(topic)}</button>)}</div></fieldset>}
   </>}
   {mode==='otp'&&sent&&<FormField label={language==='uk'?'Код із листа':'Code from email'}><input required inputMode="numeric" autoComplete="one-time-code" value={code} onChange={e=>setCode(e.target.value)} minLength={6} maxLength={10}/></FormField>}
   {sent&&<p role="status" className="success-text">{t(mode==='signup'?'Підтвердіть email за посиланням у листі':'Перевірте пошту')}</p>}
   {error&&<p role="alert" className="error-text">{error}</p>}
   <Button type="submit" disabled={busy||(sent&&mode!=='otp')}>{busy?t('Завантаження…'):t(onboarding?'Завершити реєстрацію':mode==='otp'?(sent?'Підтвердити код':'Надіслати код'):mode==='signup'?'Реєстрація':mode==='reset'?'Відновити пароль':mode==='new-password'?'Змінити пароль':'Увійти')}</Button>
   {mode==='login'&&!onboarding&&<button type="button" className="text-link" onClick={()=>choose('reset')}>{t('Відновити пароль')}</button>}
  </form>
 </Modal>;
}
