import {backend,credentials,live,master,monoRecurring,readBody,runtime} from '../_shared/billing/server.ts';
import {equal,hmac,moneyCents,monoEvent,seal,stripeEvent,unseal,wayforpayEvent} from '../_shared/billing/crypto.ts';
import {cancelProvider,monoRenew,remote,stripeHeaders,verifyWayforpayPlan,type Account,type Order} from '../_shared/billing/providers.ts';
import {Buffer} from 'node:buffer';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
Deno.serve(async request=>{
 if(request.method!=='POST')return json({error:'Method not allowed'},405);
 const route=new URL(request.url);
 try{
  if(route.searchParams.get('renew')==='1'){
   const secret=Deno.env.get('BILLING_CRON_SECRET')||'';
   if(!secret||!equal(request.headers.get('x-billing-cron')||'',secret))return json({error:'Unauthorized'},401);
   for(let i=0;i<10;i++){
    const order:Order|null=await backend('cancel_claim');if(!order)break;
    try{const account:Account=await backend('account_get',{account_id:order.account_id});await cancelProvider(order,account,credentials(account),runtime);await backend('cancel_done',{order_id:order.id});}
    catch{console.error('Cancellation needs reconciliation',{order:order.id});}
   }
   if(!live||!monoRecurring||!master)return json({processed:0});
   let processed=0;
   for(let i=0;i<10;i++){
    const o:Order|null=await backend('renew_claim');if(!o)break;
    try{
     const a:Account=await backend('account_get',{account_id:o.account_id});
     const token=unseal<{token:string}>(o.card_token!,master,`card:${o.parent_id}`);
     // Exactly one attempt per claimed renewal. An unknown outcome is held for
     // reconciliation; repeating an off-session charge could debit twice.
     const result=await monoRenew(o,credentials(a),token.token,runtime);
     await backend('order_update',{order_id:o.id,checkout_id:result.invoiceId,status:'pending'});processed++;
    }catch{await backend('renew_failed',{order_id:o.id,unknown:true});console.error('Renewal needs reconciliation',{order:o.id});}
   }
   return json({processed});
  }
  const raw=await readBody(request,262144);let o:Order|null=null,a:Account|null=null;
  const provider=route.searchParams.get('provider');let payload:Record<string,unknown>|null=null;let ack:unknown={received:true};
  if(provider==='stripe'){
   const secret=Deno.env.get('STRIPE_WEBHOOK_SECRET')||'';if(!secret)throw Error('Webhook not configured');
   const e=stripeEvent(raw,request.headers.get('stripe-signature')||'',secret);
   if(e.livemode!==true||typeof e.account!=='string')throw Error('Expected a live connected-account event');
   a=await backend('account_get',{stripe_account:e.account});if(!a)throw Error('Unknown merchant');
   const d=e.data?.object;
   if(e.type==='checkout.session.completed'&&d.mode==='payment'&&d.payment_status==='paid'){
    o=await backend('order_get',{order_id:d.client_reference_id});
    if(!o||o.checkout_id!==d.id||o.kind!=='purchase')throw Error('Unexpected Checkout Session');
    payload={event_key:`session:${d.id}`,amount:d.amount_total,currency:String(d.currency).toUpperCase(),status:'paid',payment_reference:d.payment_intent};
   }else if(e.type==='invoice.paid'){
    const subscription=d.parent?.subscription_details?.subscription;if(typeof subscription!=='string')throw Error('Subscription missing');
    const sub=await remote(`https://api.stripe.com/v1/subscriptions/${encodeURIComponent(subscription)}`,{headers:stripeHeaders(runtime,e.account)});
    o=await backend('order_get',{order_id:sub.metadata?.order_id});
    if(!o||o.kind!=='subscription')throw Error('Unknown subscription order');
    const paid=await remote(`https://api.stripe.com/v1/invoice_payments?invoice=${encodeURIComponent(d.id)}&status=paid&limit=100`,{headers:stripeHeaders(runtime,e.account)});
    const payment=paid.data?.find((x:any)=>x.payment?.type==='payment_intent'&&x.amount_paid===o!.amount);
    if(!payment)throw Error('No confirmed card payment');
    const intent=await remote(`https://api.stripe.com/v1/payment_intents/${encodeURIComponent(payment.payment.payment_intent)}`,{headers:stripeHeaders(runtime,e.account)});
    if(intent.status!=='succeeded'||intent.amount_received!==o.amount)throw Error('Payment not received');
    const end=Math.max(...(d.lines?.data||[]).map((x:any)=>Number(x.period?.end)||0));
    if(!end)throw Error('Billing period missing');
    payload={event_key:`invoice:${d.id}`,amount:d.amount_paid,currency:String(d.currency).toUpperCase(),status:'paid',period_end:new Date(end*1000).toISOString(),subscription_id:subscription,payment_reference:intent.id};
   }else if(e.type==='charge.refunded'||e.type==='charge.dispute.created'){
    const charge=e.type==='charge.refunded'?d:await remote(`https://api.stripe.com/v1/charges/${encodeURIComponent(d.charge)}`,{headers:stripeHeaders(runtime,e.account)});
    o=await backend('order_reference',{account_id:a.id,payment_reference:charge.payment_intent});
    if(!o)throw Error('Refund payment needs reconciliation');
    payload={event_key:`revoke:${e.id}`,amount:charge.amount,currency:String(charge.currency).toUpperCase(),status:'refunded',payment_reference:charge.payment_intent};
   }else if(e.type==='customer.subscription.deleted'||e.type==='customer.subscription.updated'){
    if(e.type.endsWith('deleted')||d.cancel_at_period_end){o=await backend('order_get',{order_id:d.metadata?.order_id});if(o&&o.account_id===a.id)await backend('cancel_done',{order_id:o.id});}
    return json(ack);
   }else return json(ack);
  }else if(provider==='wayforpay'||provider==='monobank'){
   const orderId=route.searchParams.get('order');if(!orderId)throw Error('Order missing');
   o=await backend('order_get',{order_id:orderId});if(!o)throw Error('Unknown order');
   a=await backend('account_get',{account_id:o.account_id});if(!a||a.provider!==provider)throw Error('Merchant mismatch');
   const s=credentials(a);
   if(provider==='wayforpay'){
    const d=wayforpayEvent(raw,s.secret,s.merchant);if(d.orderReference!==o.id)throw Error('Order mismatch');
    const time=Math.floor(Date.now()/1000);ack={orderReference:o.id,status:'accept',time,signature:hmac('md5',s.secret,`${o.id};accept;${time}`)};
    if(!['Approved','Refunded','RefundInProcessing'].includes(d.transactionStatus))return json(ack);
    if(d.transactionStatus==='RefundInProcessing')return json(ack);
    if(d.transactionStatus==='Approved'&&o.kind==='subscription')await verifyWayforpayPlan(o,a,s,runtime);
    payload={event_key:`wfp:${d.eventKey}`,amount:moneyCents(d.amount),currency:d.currency,status:d.transactionStatus==='Approved'?'paid':'refunded'};
   }else{
    if(!a.config.pubkey)throw Error('Merchant signing key needs setup');
    const d=monoEvent(raw,request.headers.get('x-sign')||'',a.config.pubkey);
    if(d.reference!==o.id||(o.checkout_id&&d.invoiceId!==o.checkout_id))throw Error('Invoice mismatch');
    const current=await remote(`https://api.monobank.ua/api/merchant/invoice/status?invoiceId=${encodeURIComponent(d.invoiceId)}`,{headers:{'X-Token':s.token}});
    if(current.reference!==o.id||current.invoiceId!==d.invoiceId||current.ccy!==980)throw Error('Invoice mismatch');
    const refunded=current.status==='reversed'||(current.cancelList||[]).some((x:any)=>x.status==='success');
    if(current.status!=='success'&&!refunded)return json(ack);
    payload={event_key:`mono:${current.invoiceId}:${refunded?'refund':'paid'}`,amount:current.amount,currency:'UAH',status:refunded?'refunded':'paid',payment_reference:current.invoiceId};
    if(o.kind==='subscription'&&current.walletData?.cardToken&&master)payload.card_token=seal({token:current.walletData.cardToken},master,`card:${o.parent_id||o.id}`);
   }
  }else throw Error('Unknown provider');
  if(!o||!a||!payload||o.account_id!==a.id)throw Error('Payment binding mismatch');
  await backend('event',{...payload,order_id:o.id,account_id:a.id});
  if(o.kind==='subscription'&&(o as any).cancel_requested){
   await cancelProvider({...o,external_subscription:String(payload.subscription_id||o.external_subscription||'')},a,credentials(a),runtime);
   await backend('cancel_done',{order_id:o.id});
  }
  return json(ack);
 }catch{
  console.error('Webhook rejected or needs reconciliation');
  // Non-2xx keeps transient failures eligible for provider retries. Never grant
  // access on parsing errors, redirects, unsigned callbacks or a return URL.
  return json({error:'Webhook could not be verified or applied'},400);
 }
});
