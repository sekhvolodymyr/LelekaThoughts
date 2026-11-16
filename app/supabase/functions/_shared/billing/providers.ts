import {hmac,moneyCents} from './crypto.ts';
export type Provider='stripe'|'wayforpay'|'monobank';
export type Order={id:string;buyer_id:string;creator_id:string;account_id:string;kind:'purchase'|'subscription';amount:number;currency:'UAH';checkout_id?:string;checkout_url?:string;external_subscription?:string;parent_id?:string;card_token?:string;status:string;created_at:string};
export type Account={id:string;creator_id:string;provider:Provider;credentials:string;credential_context:string;config:Record<string,any>;state:string};
export type Secrets=Record<string,string>;
export type Runtime={site:string;hook:string;stripeKey:string;stripeVersion:string;request?:typeof fetch};
export function nextMonth(date:Date){const result=new Date(date);const day=result.getUTCDate();result.setUTCDate(1);result.setUTCMonth(result.getUTCMonth()+1);const last=new Date(Date.UTC(result.getUTCFullYear(),result.getUTCMonth()+1,0)).getUTCDate();result.setUTCDate(Math.min(day,last));return result;}
export async function remote(url:string,init:RequestInit={},request:typeof fetch=fetch){
 const r=await request(url,{...init,signal:AbortSignal.timeout(15000),redirect:'error'});
 const data=await r.json() as Record<string,any>;if(!r.ok)throw Error(`Payment provider rejected request (${r.status})`);return data;
}
export function stripeHeaders(env:Runtime,account?:string){if(!env.stripeKey)throw Error('Stripe is not configured');return {Authorization:`Bearer ${env.stripeKey}`,'Stripe-Version':env.stripeVersion,...(account?{'Stripe-Account':account}:{})};}
export function safeCheckout(url:string,provider:Provider){
 const u=new URL(url);const allowed=provider==='stripe'?['checkout.stripe.com','accounts.stripe.com']:provider==='monobank'?['pay.mbnk.biz','pay.monobank.ua']:['secure.wayforpay.com','invoice.wayforpay.com'];
 if(u.protocol!=='https:'||u.username||u.password||!allowed.includes(u.hostname))throw Error('Unexpected payment destination');return u.href;
}
export async function createCheckout(o:Order,a:Account,s:Secrets,env:Runtime){
 const label=o.kind==='subscription'?'LelekaThoughts — щомісячна підписка':'LelekaThoughts — разовий доступ';
 const back=`${env.site}/#/billing?order=${o.id}`;const hook=`${env.hook}?provider=${a.provider}&order=${o.id}`;
 if(a.provider==='stripe'){
  const body=new URLSearchParams({'mode':o.kind==='subscription'?'subscription':'payment','success_url':back,'cancel_url':`${env.site}/#/billing`,
   'client_reference_id':o.id,'metadata[order_id]':o.id,'line_items[0][price_data][currency]':'uah','line_items[0][price_data][unit_amount]':String(o.amount),
   'line_items[0][price_data][product_data][name]':label,'line_items[0][quantity]':'1','expires_at':String(Math.floor(Date.now()/1000)+1800)});
  if(o.kind==='subscription'){body.set('line_items[0][price_data][recurring][interval]','month');body.set('subscription_data[metadata][order_id]',o.id);}
  else body.set('payment_intent_data[metadata][order_id]',o.id);
  const data=await remote('https://api.stripe.com/v1/checkout/sessions',{method:'POST',headers:{...stripeHeaders(env,a.config.stripe_account),'Content-Type':'application/x-www-form-urlencoded','Idempotency-Key':o.id},body},env.request);
  return {checkout_id:data.id,checkout_url:safeCheckout(data.url,'stripe')};
 }
 if(a.provider==='monobank'){
  const data=await remote('https://api.monobank.ua/api/merchant/invoice/create',{method:'POST',headers:{'X-Token':s.token,'Content-Type':'application/json','X-Cms':'LelekaThoughts'},body:JSON.stringify({amount:o.amount,ccy:980,merchantPaymInfo:{reference:o.id,destination:label},redirectUrl:back,webHookUrl:hook,validity:1800,paymentType:'debit',...(o.kind==='subscription'?{saveCardData:{saveCard:true,walletId:o.id}}:{})})},env.request);
  return {checkout_id:data.invoiceId,checkout_url:safeCheckout(data.pageUrl,'monobank')};
 }
 const date=Math.floor(Date.now()/1000),amount=(o.amount/100).toFixed(2),domain=new URL(env.site).hostname;
 const signature=hmac('md5',s.secret,[s.merchant,domain,o.id,date,amount,'UAH',label,1,amount].join(';'));
 const next=nextMonth(new Date());
 const format=(d:Date)=>`${String(d.getUTCDate()).padStart(2,'0')}.${String(d.getUTCMonth()+1).padStart(2,'0')}.${d.getUTCFullYear()}`;
 return {checkout_id:o.id,checkout_url:'https://secure.wayforpay.com/pay',form:{merchantAccount:s.merchant,merchantAuthType:'SimpleSignature',merchantDomainName:domain,merchantSignature:signature,orderReference:o.id,orderDate:String(date),amount,currency:'UAH','productName[]':label,'productCount[]':'1','productPrice[]':amount,serviceUrl:hook,returnUrl:`${env.site}/api/billing/return`,language:'UA',...(o.kind==='subscription'?{regularOn:'1',regularBehavior:'preset',regularMode:'monthly',regularAmount:amount,dateNext:format(next)}:{regularMode:'none'})}};
}
export async function cancelProvider(o:Order,a:Account,s:Secrets,env:Runtime){
 if(a.provider==='stripe'){
  if(!o.external_subscription){
   if(o.checkout_id){
    const url=`https://api.stripe.com/v1/checkout/sessions/${encodeURIComponent(o.checkout_id)}`;
    const session=await remote(url,{headers:stripeHeaders(env,a.config.stripe_account)},env.request);
    if(typeof session.subscription==='string')return cancelProvider({...o,external_subscription:session.subscription},a,s,env);
    if(session.status==='expired')return {ok:true};
    return remote(url+'/expire',{method:'POST',headers:stripeHeaders(env,a.config.stripe_account)},env.request);
   }
   throw Error('Subscription confirmation is pending');
  }
  return remote(`https://api.stripe.com/v1/subscriptions/${encodeURIComponent(o.external_subscription)}`,{method:'POST',headers:{...stripeHeaders(env,a.config.stripe_account),'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({cancel_at_period_end:'true'})},env.request);
 }
 if(a.provider==='wayforpay'){
  if(!s.password)throw Error('WayForPay recurring management is not configured');
  const call=(requestType:string)=>remote('https://api.wayforpay.com/regularApi',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({requestType,merchantAccount:s.merchant,merchantPassword:s.password,orderReference:o.id})},env.request);
  try{const r=await call('REMOVE');if(Number(r.reasonCode)===4100)return r;}catch{/* Reconcile a lost successful removal response. */}
  const state=await call('STATUS');if(state.orderReference===o.id&&['Removed','Completed'].includes(state.status)&&Number(state.reasonCode)===4100)return state;
  throw Error('Provider has not confirmed cancellation');
 }
 // Monobank renewals are initiated only by our scheduler, which checks cancel_requested.
 return {ok:true};
}
export async function monoRenew(o:Order,s:Secrets,cardToken:string,env:Runtime){
 return remote('https://api.monobank.ua/api/merchant/wallet/payment',{method:'POST',headers:{'X-Token':s.token,'Content-Type':'application/json','X-Cms':'LelekaThoughts'},body:JSON.stringify({cardToken,amount:o.amount,ccy:980,initiationKind:'merchant',paymentType:'debit',merchantPaymInfo:{reference:o.id,destination:'LelekaThoughts — поновлення підписки'},redirectUrl:`${env.site}/#/billing`,webHookUrl:`${env.hook}?provider=monobank&order=${o.id}`})},env.request);
}
export async function verifyWayforpayPlan(o:Order,a:Account,s:Secrets,env:Runtime){
 const state=await remote('https://api.wayforpay.com/regularApi',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({requestType:'STATUS',merchantAccount:s.merchant,merchantPassword:s.password,orderReference:o.id})},env.request);
 if(Number(state.reasonCode)!==4100||state.orderReference!==o.id)throw Error('Recurring plan needs reconciliation');
 // Regular settings are not part of the Purchase form signature. Verify them
 // using the merchant-authenticated API before accepting a subscription.
 if(state.mode!=='monthly'||moneyCents(state.amount)!==o.amount||state.currency!==o.currency){
  await cancelProvider(o,a,s,env);throw Error('Unexpected recurring plan was cancelled');
 }
 return state;
}
