import {createCipheriv,createDecipheriv,createHmac,randomBytes,timingSafeEqual,verify} from 'node:crypto';
import {Buffer} from 'node:buffer';

export function equal(a:string,b:string){const x=Buffer.from(a),y=Buffer.from(b);return x.length===y.length&&timingSafeEqual(x,y);}
export function hmac(algorithm:'md5'|'sha256',secret:string,message:string){return createHmac(algorithm,secret).update(message).digest('hex');}
function key(master:string){const k=Buffer.from(master,'base64');if(k.length!==32)throw Error('Payment credential encryption is not configured');return k;}
export function seal(value:unknown,master:string,context:string){
 const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key(master),iv);cipher.setAAD(Buffer.from(context));
 const data=Buffer.concat([cipher.update(JSON.stringify(value),'utf8'),cipher.final()]);
 return ['v1',iv.toString('base64url'),cipher.getAuthTag().toString('base64url'),data.toString('base64url')].join('.');
}
export function unseal<T=Record<string,string>>(value:string,master:string,context:string):T{
 const [version,iv,tag,data]=value.split('.');if(version!=='v1'||!iv||!tag||!data)throw Error('Invalid encrypted credential');
 const cipher=createDecipheriv('aes-256-gcm',key(master),Buffer.from(iv,'base64url'));cipher.setAAD(Buffer.from(context));cipher.setAuthTag(Buffer.from(tag,'base64url'));
 return JSON.parse(Buffer.concat([cipher.update(Buffer.from(data,'base64url')),cipher.final()]).toString('utf8'));
}
export function stripeEvent(raw:string,signature:string,secret:string,now=Math.floor(Date.now()/1000)){
 const fields=signature.split(',').map(s=>s.split('='));const time=fields.find(x=>x[0]==='t')?.[1];
 if(!time||!/^\d+$/.test(time)||Math.abs(now-Number(time))>300)throw Error('Invalid webhook timestamp');
 const expected=hmac('sha256',secret,`${time}.${raw}`);
 if(!fields.some(x=>x[0]==='v1'&&equal(x[1]||'',expected)))throw Error('Invalid webhook signature');
 return JSON.parse(raw);
}
export function monoEvent(raw:string,signature:string,publicKeyBase64:string){
 if(!signature||!verify('sha256',Buffer.from(raw),Buffer.from(publicKeyBase64,'base64').toString('utf8'),Buffer.from(signature,'base64')))throw Error('Invalid webhook signature');
 return JSON.parse(raw);
}
export function wayforpayEvent(raw:string,secret:string,merchant:string){
 const data=JSON.parse(raw);const fields=['merchantAccount','orderReference','amount','currency','authCode','cardPan','transactionStatus','reasonCode'];
 if(fields.some(k=>typeof data[k]!=='string'&&typeof data[k]!=='number'))throw Error('Invalid callback fields');
 const canonical=fields.map(k=>String(data[k])).join(';');
 if(data.merchantAccount!==merchant||!equal(String(data.merchantSignature||'').toLowerCase(),hmac('md5',secret,canonical)))throw Error('Invalid webhook signature');
 return {...data,eventKey:hmac('sha256',secret,canonical)};
}
export function moneyCents(value:unknown){
 if((typeof value!=='string'&&typeof value!=='number')||!/^\d+(\.\d{1,2})?$/.test(String(value)))throw Error('Invalid payment amount');
 const [whole,decimal='']=String(value).split('.');const cents=Number(whole)*100+Number(decimal.padEnd(2,'0'));
 if(!Number.isSafeInteger(cents))throw Error('Invalid payment amount');return cents;
}
