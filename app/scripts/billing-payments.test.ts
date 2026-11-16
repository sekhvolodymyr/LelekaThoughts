import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,sign} from 'node:crypto';
import {equal,hmac,moneyCents,monoEvent,seal,stripeEvent,unseal,wayforpayEvent} from '../supabase/functions/_shared/billing/crypto.ts';
import {cancelProvider,createCheckout,monoRenew,nextMonth,remote,safeCheckout,verifyWayforpayPlan,type Account,type Order,type Runtime} from '../supabase/functions/_shared/billing/providers.ts';
const order:Order={id:'20000000-0000-4000-8000-000000000001',buyer_id:'fixture-buyer',creator_id:'fixture-creator',account_id:'fixture-account',kind:'subscription',amount:12550,currency:'UAH',status:'creating',created_at:new Date().toISOString()};
const account:Account={id:'fixture-account',creator_id:'fixture-creator',provider:'stripe',credentials:'',credential_context:'fixture-context',config:{stripe_account:'acct_fixture'},state:'active'};
const runtime:Runtime={site:'https://lelekathoughts.vercel.app',hook:'https://example.invalid/billing-hook',stripeKey:'sk_test_fixture_not_a_real_key',stripeVersion:'2026-10-28.endive'};
test('WayForPay unsigned recurring settings must match the server price and interval',async()=>{
 const calls:string[]=[];let mode='monthly';
 const request:typeof fetch=async(_url,init)=>{const p=JSON.parse(String(init?.body));calls.push(p.requestType);return Response.json(p.requestType==='REMOVE'?{reasonCode:4100}:{reasonCode:4100,orderReference:order.id,mode,amount:'125.50',currency:'UAH'});};
 const a={...account,provider:'wayforpay' as const};const secrets={merchant:'fixture',password:'fixture'};
 await verifyWayforpayPlan(order,a,secrets,{...runtime,request});mode='daily';
 await assert.rejects(()=>verifyWayforpayPlan(order,a,secrets,{...runtime,request}));assert.deepEqual(calls,['STATUS','STATUS','REMOVE']);
});
test('credentials are authenticated, randomized and bound to the creator/provider',()=>{
 const master=Buffer.alloc(32,7).toString('base64'),value={token:'private_fixture_token'};
 const one=seal(value,master,'creator:monobank'),two=seal(value,master,'creator:monobank');
 assert.notEqual(one,two);assert.ok(!one.includes(value.token));assert.deepEqual(unseal(one,master,'creator:monobank'),value);
 assert.throws(()=>unseal(one,master,'another-creator:monobank'));assert.throws(()=>unseal(one,Buffer.alloc(32,8).toString('base64'),'creator:monobank'));
 const fields=one.split('.');fields[3]=Buffer.from('tampered').toString('base64url');assert.throws(()=>unseal(fields.join('.'),master,'creator:monobank'));
});
test('Stripe raw-body signature, tolerance and mutation checks',()=>{
 const raw='{"type":"invoice.paid","amount":12550}',secret='fixture_secret',time=1700000000;
 const signature=`t=${time},v1=${hmac('sha256',secret,`${time}.${raw}`)}`;
 assert.equal(stripeEvent(raw,signature,secret,time).amount,12550);
 assert.throws(()=>stripeEvent(raw.replace('12550','1'),signature,secret,time));assert.throws(()=>stripeEvent(raw,signature,secret,time+301));assert.throws(()=>stripeEvent(raw,signature,'wrong',time));assert.equal(equal('a','longer'),false);
});
test('WayForPay signature covers amount, merchant and stable replay key',()=>{
 const data={merchantAccount:'fixture',orderReference:order.id,amount:'125.50',currency:'UAH',authCode:'123456',cardPan:'4242****4242',transactionStatus:'Approved',reasonCode:1100,processingDate:123};
 const canonical=[data.merchantAccount,data.orderReference,data.amount,data.currency,data.authCode,data.cardPan,data.transactionStatus,data.reasonCode].join(';');
 const callback={...data,merchantSignature:hmac('md5','fixture-secret',canonical)};
 const first=wayforpayEvent(JSON.stringify(callback),'fixture-secret','fixture');assert.equal(moneyCents(first.amount),12550);
 assert.throws(()=>wayforpayEvent(JSON.stringify({...callback,amount:'1'}),'fixture-secret','fixture'));
 assert.throws(()=>wayforpayEvent(JSON.stringify(callback),'fixture-secret','other-merchant'));
 assert.equal(first.eventKey,wayforpayEvent(JSON.stringify({...callback,processingDate:999}),'fixture-secret','fixture').eventKey,'Unsigned metadata cannot manufacture another paid month');
});
test('Monobank ECDSA raw-body verification rejects mutation',()=>{
 const {publicKey,privateKey}=generateKeyPairSync('ec',{namedCurve:'prime256v1'});const raw=JSON.stringify({invoiceId:'fixture',amount:12550,ccy:980});
 const signature=sign('sha256',Buffer.from(raw),privateKey).toString('base64');const key=Buffer.from(publicKey.export({format:'pem',type:'spki'})).toString('base64');
 assert.equal(monoEvent(raw,signature,key).amount,12550);assert.throws(()=>monoEvent(raw.replace('12550','1'),signature,key));assert.throws(()=>monoEvent(raw,'invalid',key));
});
test('Checkout is created directly on the creator account, with monthly Billing and idempotency',async()=>{
 let captured:RequestInit|undefined;
 const request:typeof fetch=async(_url,init)=>{captured=init;return Response.json({id:'cs_fixture',url:'https://checkout.stripe.com/c/pay/fixture'})};
 await createCheckout(order,account,{}, {...runtime,request});
 const headers=captured!.headers as Record<string,string>,body=captured!.body as URLSearchParams;
 assert.equal(headers['Stripe-Account'],'acct_fixture');assert.equal(headers['Idempotency-Key'],order.id);assert.equal(body.get('mode'),'subscription');assert.equal(body.get('line_items[0][price_data][unit_amount]'),'12550');assert.equal(body.get('line_items[0][price_data][recurring][interval]'),'month');assert.equal(body.has('subscription_data[transfer_data][destination]'),false);
});
test('Monobank saves cards only for subscriptions and uses merchant-initiated renewals',async()=>{
 let captured:any;
 const request:typeof fetch=async(_url,init)=>{captured=JSON.parse(String(init!.body));return Response.json({invoiceId:'fixture',pageUrl:'https://pay.mbnk.biz/fixture'})};
 const mono={...account,provider:'monobank' as const};
 await createCheckout(order,mono,{token:'fixture'},{...runtime,request});assert.equal(captured.saveCardData.saveCard,true);assert.equal(captured.amount,12550);
 await createCheckout({...order,kind:'purchase'},mono,{token:'fixture'},{...runtime,request});assert.equal(captured.saveCardData,undefined);
 await monoRenew(order,{token:'fixture'},'fixture-card',{...runtime,request});assert.equal(captured.initiationKind,'merchant');assert.equal(captured.cardToken,'fixture-card');
});
test('WayForPay form uses the creator merchant, fixed monthly plan and no card fields',async()=>{
 const data=await createCheckout(order,{...account,provider:'wayforpay'},{merchant:'creator_fixture',secret:'fixture-secret'},{...runtime});
 assert.ok('form'in data);const form=data.form! as Record<string,string>;assert.equal(form.merchantAccount,'creator_fixture');assert.equal(form.regularMode,'monthly');assert.equal(form.regularAmount,'125.50');assert.equal(form.regularBehavior,'preset');assert.ok(!Object.keys(form).some(k=>/cardNumber|cvv/i.test(k)));
});
test('Cancellation keeps Stripe paid period and WFP uses its recurring API',async()=>{
 const calls:{url:string;body:any}[]=[];const request:typeof fetch=async(url,init)=>{calls.push({url:String(url),body:init?.body});return Response.json({reasonCode:4100})};
 await cancelProvider({...order,external_subscription:'sub_fixture'},account,{}, {...runtime,request});assert.equal((calls[0].body as URLSearchParams).get('cancel_at_period_end'),'true');
 await cancelProvider(order,{...account,provider:'wayforpay'},{merchant:'fixture',password:'fixture-password'},{...runtime,request});assert.equal(JSON.parse(calls[1].body).requestType,'REMOVE');
});
test('Unknown network outcomes are not retried; destinations and calendar boundaries are checked',async()=>{
 let calls=0;await assert.rejects(()=>remote('https://example.invalid',{},async()=>{calls++;throw Error('timeout')}));assert.equal(calls,1);
 for(const url of ['http://checkout.stripe.com/x','https://checkout.stripe.com.evil.invalid/x','https://user@checkout.stripe.com/x','javascript:alert(1)'])assert.throws(()=>safeCheckout(url,'stripe'));
 assert.equal(nextMonth(new Date('2027-01-31T12:00:00Z')).toISOString(),'2027-02-28T12:00:00.000Z');
 assert.throws(()=>moneyCents('1e4'));assert.throws(()=>moneyCents('-1'));assert.throws(()=>moneyCents('1.001'));
});
