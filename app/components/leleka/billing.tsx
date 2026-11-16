'use client';
import {useEffect,useRef,useState} from 'react';
import {LockKeyhole,CreditCard,ArrowUpRight} from 'lucide-react';
import {Button} from '@/components/ui/button';
import {action,supabase} from '@/lib/leleka/client';
import {billingAction,price} from '@/lib/leleka/paid-content';
import type {Post} from '@/lib/leleka/types';
import {useApp} from './provider';
import {Blank,FormField,Modal} from './ui';
const methods=[['wayforpay','WayForPay'],['monobank','Monobank'],['stripe','Stripe']] as const;
type Options={live:boolean;offer:{enabled:boolean;monthly_cents:number}|null;accounts:{provider:string;available:boolean;recurring:boolean}[]};
function leaveForPayment(data:{url?:string;form?:Record<string,string>}){
 if(!data.url)throw Error('Не отримано платіжне посилання');const url=new URL(data.url);
 if(url.protocol!=='https:'||url.username||url.password||!['checkout.stripe.com','accounts.stripe.com','secure.wayforpay.com','invoice.wayforpay.com','pay.mbnk.biz','pay.monobank.ua'].includes(url.hostname))throw Error('Некоректна адреса оплати');
 if(data.form){const form=document.createElement('form');form.method='POST';form.action=url.href;for(const [name,value]of Object.entries(data.form)){const input=document.createElement('input');input.type='hidden';input.name=name;input.value=String(value);form.appendChild(input);}document.body.appendChild(form);form.submit();}
 else window.location.assign(url.href);
}
export function PurchaseButton({creatorId,post,label}:{creatorId:string;post?:Post;label?:string}){
 const {requireAuth,t,refresh}=useApp();const [open,setOpen]=useState(false),[options,setOptions]=useState<Options|null>(null),[error,setError]=useState(''),[busy,setBusy]=useState(false),[consent,setConsent]=useState(false),[kind,setKind]=useState<'subscription'|'purchase'>(post&&post.access!=='subscribers'?'purchase':'subscription');
 const attempts=useRef(new Map<string,string>());
 useEffect(()=>{if(!open)return;let active=true;setError('');void billingAction('options',{creator_id:creatorId}).then(data=>{if(active)setOptions(data as unknown as Options)}).catch(e=>active&&setError(e.message));return()=>{active=false}},[open,creatorId]);
 const subscribe=!post||post.access==='subscribers'||post.access==='either';
 const purchase=!!post&&post.access!=='subscribers';
 const amount=kind==='subscription'?options?.offer?.monthly_cents:post?.price_cents;
 const pay=async(provider:string)=>{setBusy(true);setError('');try{
  const key=`${kind}:${provider}`;if(!attempts.current.has(key))attempts.current.set(key,crypto.randomUUID());
  const data=await billingAction('checkout',{provider,kind,creator_id:creatorId,post_id:kind==='purchase'?(post?.paid_root_id||post?.id):null,consent,client_key:attempts.current.get(key)});
  if(data.paid){await refresh();setOpen(false);}else leaveForPayment(data);
 }catch(e){setError(e instanceof Error?e.message:'Оплата недоступна')}finally{setBusy(false)}};
 return <><Button variant="outline" onClick={()=>{if(requireAuth())setOpen(true)}}><LockKeyhole size={16}/>{label||t('Відкрити доступ')}</Button>
 <Modal open={open} onClose={()=>!busy&&setOpen(false)} title={t('Доступ до контенту')}>
  <div className="form-stack"><p className="muted">{t('Оплата надходить напряму креатору. Дані картки вводяться на сторінці платіжного сервісу.')}</p>
  {subscribe&&purchase&&<div className="tabs"><button className={kind==='purchase'?'selected':''} onClick={()=>setKind('purchase')}>{t('Разова покупка')}</button><button className={kind==='subscription'?'selected':''} onClick={()=>setKind('subscription')}>{t('Підписка')}</button></div>}
  <strong className="billing-price">{amount?price(amount):t('Тариф ще не налаштований')}{kind==='subscription'&&amount?` / ${t('місяць')}`:''}</strong>
  <p>{t(kind==='subscription'?'Доступ до контенту автора для підписників. Щомісячне автопродовження, яке можна скасувати в розділі «Підписки та покупки».':'Разова оплата відкриває цей пост і його продовження в ланцюжку.')}</p>
  {kind==='subscription'&&<label className="billing-consent"><input type="checkbox" checked={consent} onChange={e=>setConsent(e.target.checked)}/><span>{t('Погоджуюся на щомісячне автоматичне списання вказаної суми до скасування підписки.')}</span></label>}
  {options&&!options.live&&<p className="billing-notice" role="status">{t('Платежі ще не активовано. Кошти не списуються.')}</p>}
  {methods.map(([id,name])=>{const method=options?.accounts.find(x=>x.provider===id);const ready=!!method?.available&&(kind!=='subscription'||!!method.recurring&&!!options?.offer?.enabled);return <Button variant="outline" key={id} disabled={busy||!ready||!amount||kind==='subscription'&&!consent} onClick={()=>void pay(id)}><CreditCard size={17}/>{name}<small>{!ready?t('Ще не підключено'):t('Оплатити')}</small></Button>})}
  {!options&&!error&&<p role="status">{t('Завантаження…')}</p>}{error&&<p className="error-text" role="alert">{error}</p>}
  </div>
 </Modal></>;
}
export function PaidPostNotice({post}:{post:Post}){
 const {t}=useApp();return <section className="paid-post-notice"><LockKeyhole size={23}/><strong>{t('Приватний контент')}</strong><p>{t(post.access==='subscribers'?'Для платних підписників автора':post.access==='purchase'?'Доступ після разової покупки':'Доступ після покупки або відповідної підписки')}</p>{post.author_id&&<PurchaseButton creatorId={post.author_id} post={post}/>}</section>;
}
export function CreatorSubscription({creatorId}:{creatorId:string}){
 const {user,t}=useApp();const [offer,setOffer]=useState<{enabled:boolean;monthly_cents:number}|null>(null);
 useEffect(()=>{let active=true;supabase.from('creator_offers').select('enabled,monthly_cents').eq('creator_id',creatorId).maybeSingle().then(({data})=>{if(active)setOffer(data)});return()=>{active=false}},[creatorId]);
 return offer?.enabled&&user?.id!==creatorId?<div className="creator-subscription"><PurchaseButton creatorId={creatorId} label={`${t('Платна підписка')} · ${price(offer.monthly_cents)} / ${t('місяць')}`}/></div>:null;
}
type Bill={id:string;creator_id:string|null;kind:string;amount:number;status:string;expires_at:string|null;auto_renew:boolean;cancel_requested:boolean;provider:string};
export function BillingPage(){
 const {user,me,profiles,t,refresh}=useApp();const [orders,setOrders]=useState<Bill[]>([]),[accounts,setAccounts]=useState<{id:string;provider:string;state:string}[]>([]),[monthly,setMonthly]=useState('100'),[enabled,setEnabled]=useState(false),[status,setStatus]=useState<{live:boolean;credentialStorage:boolean;stripe:boolean}|null>(null),[error,setError]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[tab,setTab]=useState('purchases');
 const [provider,setProvider]=useState('monobank'),[token,setToken]=useState(''),[merchant,setMerchant]=useState(''),[secret,setSecret]=useState(''),[password,setPassword]=useState(''),[country,setCountry]=useState(''),[tokenization,setTokenization]=useState(false);
 const load=async()=>{const {data,error}=await supabase.rpc('my_billing');if(error)throw Error('Розділ оплати ще готується');setOrders(data.orders||[]);setAccounts(data.accounts||[]);};
 useEffect(()=>{if(!user)return;let active=true;void Promise.all([load(),billingAction('status').then(s=>{if(active)setStatus({live:!!s.live,credentialStorage:!!s.credentialStorage,stripe:!!s.stripe})}),supabase.from('creator_offers').select('*').eq('creator_id',user.id).maybeSingle().then(({data})=>{if(active&&data){setMonthly(String(data.monthly_cents/100));setEnabled(data.enabled)}})]).catch(e=>active&&setError(e.message));let rounds=0;const timer=setInterval(()=>{if(rounds++<5)void load().catch(()=>{});else clearInterval(timer)},3000);return()=>{active=false;clearInterval(timer)}},[user?.id]);
 if(!user||!me)return <Blank title="Увійдіть, щоб долучитися"/>;
 const run=async(work:()=>Promise<void>)=>{setBusy(true);setError('');setNotice('');try{await work()}catch(e){setError(e instanceof Error?e.message:'Не вдалося виконати дію')}finally{setBusy(false)}};
 return <><header className="page-title"><h1>{t('Підписки та покупки')}</h1></header><div className="tabs"><button className={tab==='purchases'?'selected':''} onClick={()=>setTab('purchases')}>{t('Мої покупки')}</button><button className={tab==='creator'?'selected':''} onClick={()=>setTab('creator')}>{t('Для креатора')}</button></div><section className="section-pad form-stack">
 {error&&<p className="error-text" role="alert">{error}</p>}{notice&&<p className="billing-notice" role="status">{notice}</p>}
 {tab==='purchases'?<>{orders.map(o=><div className="billing-order" key={o.id}><strong>{profiles.find(p=>p.id===o.creator_id)?.display_name||t('Креатор')}</strong><p>{t(o.kind==='subscription'?'Підписка':'Разова покупка')} · {price(o.amount)} · {o.provider}</p><p className="muted">{t(({paid:'Оплачено',pending:'Очікує підтвердження',creating:'Створюється рахунок',refunded:'Повернено',failed:'Оплата не пройшла'} as Record<string,string>)[o.status]||o.status)}{o.expires_at?` · ${t('Доступ до')} ${new Date(o.expires_at).toLocaleDateString()}`:''}</p>{o.auto_renew&&o.kind==='subscription'&&<Button variant="outline" disabled={busy} onClick={()=>void run(async()=>{const result=await billingAction('cancel',{order_id:o.id});setNotice(result.message);await load();await refresh()})}>{t(o.cancel_requested?'Повторити скасування':'Скасувати автопродовження')}</Button>}</div>)}{!orders.length&&<Blank title="Поки порожньо" description="Тут з’являться ваші платні підписки та придбаний контент."/>}<Button variant="outline" disabled={busy} onClick={()=>void run(load)}>{t('Оновити статус')}</Button></>:<>
 <h2>{t('Монетизація')}</h2><p className="muted">{t('Ціну разової покупки задавайте в редакторі поста. Нижче — місячна підписка на ваш контент.')}</p>
 <form className="form-stack" onSubmit={e=>{e.preventDefault();void run(async()=>{const cents=Math.round(Number(monthly)*100);if(!Number.isSafeInteger(cents)||cents<100||cents>10000000)throw Error('Вкажіть суму від 1 до 100 000 грн');await action('creator_offer',{monthly_cents:cents,enabled});setNotice(t('Збережено'))})}}><FormField label={t('Ціна підписки, грн / місяць')}><input type="number" min="1" max="100000" step="0.01" required value={monthly} onChange={e=>setMonthly(e.target.value)}/></FormField><label className="billing-consent"><input type="checkbox" checked={enabled} onChange={e=>setEnabled(e.target.checked)}/>{t('Показувати платну підписку в профілі')}</label><Button disabled={busy} type="submit">{t('Зберегти')}</Button></form>
 <h2>{t('Платіжні акаунти')}</h2><p className="billing-notice">{t('Кожен креатор підключає власний бізнес-акаунт. Платежі надходять напряму йому. Активація потребує перевірки провайдера.')}</p>
 {methods.map(([id,name])=><div className="billing-provider" key={id}><strong>{name}</strong><span>{t(accounts.find(a=>a.provider===id)?.state==='active'?'Підключено':accounts.some(a=>a.provider===id)?'Очікує перевірки':'Ще не підключено')}</span><a href={id==='stripe'?'https://stripe.com/connect':id==='monobank'?'https://monobank.ua/acquiring':'https://wayforpay.com/uk'} target="_blank" rel="noreferrer">{t('Про підключення')} <ArrowUpRight size={13}/></a></div>)}
 {!status?.credentialStorage&&<p className="muted">{t('Безпечне введення ключів ще не активоване власником платформи. Поки не надсилайте ключі в чат чи публікації.')}</p>}
 <FormField label={t('Провайдер')}><select value={provider} onChange={e=>{setProvider(e.target.value);setToken('');setSecret('');setPassword('')}}>{methods.map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></FormField>
 {provider==='stripe'?<><FormField label={t('Країна реєстрації бізнесу (код із 2 літер)')}><input maxLength={2} value={country} onChange={e=>setCountry(e.target.value.toUpperCase())} placeholder="PL"/></FormField><Button disabled={busy||!status?.stripe||country.length!==2} onClick={()=>void run(async()=>leaveForPayment(await billingAction('stripe_connect',{country})))}>{t('Підключити Stripe')}</Button>{accounts.some(a=>a.provider==='stripe')&&<Button variant="outline" disabled={busy} onClick={()=>void run(async()=>{await billingAction('stripe_status');await load()})}>{t('Перевірити Stripe')}</Button>}</>:status?.credentialStorage&&<form className="form-stack" autoComplete="off" onSubmit={e=>{e.preventDefault();void run(async()=>{const result=await billingAction('connect',{provider,token,merchant,secret,password,tokenization});setToken('');setSecret('');setPassword('');setNotice(result.message);await load()})}}>{provider==='monobank'?<><FormField label="Monobank X-Token"><input type="password" required autoComplete="new-password" value={token} onChange={e=>setToken(e.target.value)}/></FormField><label className="billing-consent"><input type="checkbox" checked={tokenization} onChange={e=>setTokenization(e.target.checked)}/>{t('Monobank підтвердив активацію токенізації для автосписань')}</label></>:<><FormField label="Merchant Account"><input required value={merchant} onChange={e=>setMerchant(e.target.value)}/></FormField><FormField label="Secret Key"><input type="password" required autoComplete="new-password" value={secret} onChange={e=>setSecret(e.target.value)}/></FormField><FormField label="Merchant Password (Regular API)"><input type="password" required autoComplete="new-password" value={password} onChange={e=>setPassword(e.target.value)}/></FormField></>}<Button type="submit" disabled={busy}>{t('Зберегти зашифровані ключі')}</Button></form>}
 </>}
 </section></>;
}
