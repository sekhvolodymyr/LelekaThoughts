import {admin,backend,credentials,live,master,monoRecurring,readBody,runtime} from '../_shared/billing/server.ts';
import {seal} from '../_shared/billing/crypto.ts';
import {cancelProvider,createCheckout,remote,safeCheckout,stripeHeaders,type Account,type Order} from '../_shared/billing/providers.ts';
const origins=new Set([runtime.site,'http://localhost:5173','http://127.0.0.1:5173']);
Deno.serve(async request=>{
 const origin=request.headers.get('origin');const headers={'Content-Type':'application/json','Cache-Control':'private, no-store','Vary':'Origin','Access-Control-Allow-Origin':origin&&origins.has(origin)?origin:runtime.site,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
 const json=(data:unknown,status=200)=>Response.json(data,{status,headers});
 if(origin&&!origins.has(origin))return json({error:'Origin not allowed'},403);
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(request.method!=='POST')return json({error:'Method not allowed'},405);
 try{
  const token=request.headers.get('authorization')?.replace(/^Bearer /i,'')||'';
  const {data:{user},error}=await admin.auth.getUser(token);
  if(error||!user?.email_confirmed_at)return json({error:'Увійдіть із підтвердженим email'},401);
  const {data:profile}=await admin.from('profiles').select('id,suspended,is_demo,display_name').eq('id',user.id).maybeSingle();
  if(!profile||profile.is_demo)return json({error:'Завершіть реєстрацію'},403);
  const input=JSON.parse(await readBody(request));const action=input.action;
  if(profile.suspended&&!['status','cancel'].includes(action))return json({error:'Акаунт призупинено. Скасування підписок залишається доступним.'},403);
  if(['connect','stripe_connect','stripe_status','checkout','cancel'].includes(action)){
   const {data:allowed,error}=await admin.rpc('login_guard',{fingerprint:`billing:${action}:${user.id}`});
   if(error||!allowed)return json({error:'Забагато спроб. Спробуйте пізніше.'},429);
  }
  if(action==='status')return json({live,stripe:!!runtime.stripeKey&&!!Deno.env.get('STRIPE_WEBHOOK_SECRET'),credentialStorage:!!master,monoRecurring});
  if(action==='options'){
   const result=await backend('options',{creator_id:input.creator_id});
   return json({...result,live,accounts:result.accounts.map((a:{provider:string;state:string;tokenization:boolean})=>({...a,available:live&&a.state==='active'&&(a.provider!=='stripe'||!!runtime.stripeKey),recurring:a.provider==='monobank'?monoRecurring&&a.tokenization:true}))});
  }
  if(action==='connect'&&['wayforpay','monobank'].includes(input.provider)){
   if(!master)return json({error:'Захищене підключення платіжних акаунтів ще готується. Ключі поки не вводьте.'},503);
   const provider=input.provider;let secret:Record<string,string>;let config:Record<string,unknown>={};
   if(provider==='monobank'){
    if(typeof input.token!=='string'||input.token.length<16||input.token.length>1024)throw Error('Некоректний токен');
    await remote('https://api.monobank.ua/api/merchant/details',{headers:{'X-Token':input.token}});
    const pub=await remote('https://api.monobank.ua/api/merchant/pubkey',{headers:{'X-Token':input.token}});
    secret={token:input.token};config={tokenization:input.tokenization===true,pubkey:pub.key};
   }else{
    if(!['merchant','secret','password'].every(k=>typeof input[k]==='string'&&input[k].length>=3&&input[k].length<=1024))throw Error('Заповніть дані WayForPay');
    secret={merchant:input.merchant,secret:input.secret,password:input.password};
   }
   await backend('account_save',{creator_id:user.id,provider,credentials:seal(secret,master,`${user.id}:${provider}`),config,state:'pending'});
   return json({ok:true,pending:true,message:'Ключі збережено зашифрованими. Потрібні перевірка провайдера та тест webhook перед активацією.'});
  }
  if(action==='stripe_connect'){
   if(!runtime.stripeKey)return json({error:'Stripe Connect ще не підключений власником LelekaThoughts'},503);
   const country=String(input.country||'').toLowerCase();if(!/^[a-z]{2}$/.test(country))throw Error('Вкажіть країну реєстрації бізнесу');
   let a:Account|null=await backend('account_get',{creator_id:user.id,provider:'stripe'});
   if(!a){
    const account=await remote('https://api.stripe.com/v2/core/accounts',{method:'POST',headers:{...stripeHeaders(runtime),'Content-Type':'application/json','Idempotency-Key':`creator:${user.id}`},body:JSON.stringify({contact_email:user.email,display_name:profile.display_name,dashboard:'full',identity:{country},configuration:{merchant:{capabilities:{card_payments:{requested:true}}}},defaults:{responsibilities:{fees_collector:'stripe',losses_collector:'stripe'}}})});
    await backend('account_save',{creator_id:user.id,provider:'stripe',config:{stripe_account:account.id},state:'pending'});
    a=await backend('account_get',{creator_id:user.id,provider:'stripe'});
   }
   if(!a)throw Error('Не вдалося створити підключення');
   const link=await remote('https://api.stripe.com/v2/core/account_links',{method:'POST',headers:{...stripeHeaders(runtime),'Content-Type':'application/json'},body:JSON.stringify({account:a.config.stripe_account,use_case:{type:'account_onboarding',account_onboarding:{configurations:['merchant'],return_url:`${runtime.site}/#/billing`,refresh_url:`${runtime.site}/#/billing`}}})});
   return json({url:safeCheckout(link.url,'stripe')});
  }
  if(action==='stripe_status'){
   const a:Account|null=await backend('account_get',{creator_id:user.id,provider:'stripe'});if(!a)return json({active:false});
   const account=await remote(`https://api.stripe.com/v1/accounts/${encodeURIComponent(a.config.stripe_account)}`,{headers:stripeHeaders(runtime)});
   if(account.charges_enabled&&account.payouts_enabled)await backend('account_activate',{account_id:a.id});return json({active:!!account.charges_enabled&&!!account.payouts_enabled});
  }
  if(action==='checkout'){
   if(!live)return json({error:'Оплата ще не активована. Кошти не списуватимуться.'},503);
   if(input.kind==='subscription'&&input.consent!==true)throw Error('Підтвердіть згоду на щомісячне автосписання');
   const a:Account|null=await backend('account_get',{creator_id:input.creator_id,provider:input.provider});
   if(!a||a.state!=='active')throw Error('Провайдер автора ще не активований');
   if(input.kind==='subscription'&&a.provider==='monobank'&&(!monoRecurring||!a.config.tokenization))throw Error('Monobank ще не активував регулярні платежі');
   const o:Order=await backend('order_create',{buyer_id:user.id,creator_id:input.creator_id,provider:input.provider,kind:input.kind,post_id:input.post_id||null,client_key:input.client_key,consent:input.consent===true});
   if(o.status==='paid')return json({paid:true});
   if(o.checkout_url&&a.provider!=='wayforpay')return json({url:safeCheckout(o.checkout_url,a.provider),order_id:o.id});
   // A timed-out invoice creation is never retried automatically for providers
   // without an idempotency key. Its original operation must be reconciled first.
   if(o.checkout_id&&a.provider!=='wayforpay')throw Error('Оплата очікує підтвердження');
   const claim=await backend('checkout_claim',{order_id:o.id});
   if(!claim.claimed&&a.provider==='monobank')throw Error('Рахунок уже створюється або потребує перевірки. Не повторюйте оплату.');
   const checkout=await createCheckout(o,a,credentials(a),runtime);
   await backend('order_update',{order_id:o.id,...checkout,status:'pending'});
   return json({order_id:o.id,url:checkout.checkout_url,...('form' in checkout?{form:checkout.form}:{})});
  }
  if(action==='cancel'){
   const o:Order&{cancel_requested:boolean}=await backend('cancel_request',{order_id:input.order_id,buyer_id:user.id});
   const a:Account=await backend('account_get',{account_id:o.account_id});
   await cancelProvider(o,a,credentials(a),runtime);await backend('cancel_done',{order_id:o.id});
   return json({ok:true,message:'Автопродовження скасовано. Доступ діє до кінця оплаченого періоду.'});
  }
  return json({error:'Unknown action'},400);
 }catch(error){
  // Never return provider payloads, tokens, encrypted credentials or raw database records.
  const message=error instanceof Error?error.message:'Payment unavailable';
  console.error('Billing request failed');
  return json({error:message},400);
 }
});
