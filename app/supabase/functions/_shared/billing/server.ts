import {createClient} from 'npm:@supabase/supabase-js@2.119.0';
import {unseal} from './crypto.ts';
import type {Account,Runtime,Secrets} from './providers.ts';
export const url=Deno.env.get('SUPABASE_URL')!;
export const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
export const master=Deno.env.get('PAYMENT_CREDENTIALS_KEY')||'';
export const runtime:Runtime={site:'https://lelekathoughts.vercel.app',hook:`${url}/functions/v1/billing-hook`,stripeKey:Deno.env.get('STRIPE_SECRET_KEY')||'',stripeVersion:'2026-10-28.endive'};
export const live=Deno.env.get('BILLING_LIVE_ENABLED')==='true';
export const monoRecurring=Deno.env.get('MONO_RECURRING_ENABLED')==='true';
export async function backend(command:string,p:Record<string,unknown>={}){const {data,error}=await admin.rpc('billing_backend',{command,p});if(error)throw Error(error.message);return data;}
export function credentials(a:Account):Secrets{return a.credentials?unseal(a.credentials,master,a.credential_context):{};}
export async function readBody(request:Request,max=16384){
 const reader=request.body?.getReader();if(!reader)return '';
 let size=0;const chunks:Uint8Array[]=[];while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>max){await reader.cancel();throw Error('Request too large');}chunks.push(value);}
 const bytes=new Uint8Array(size);let at=0;for(const c of chunks){bytes.set(c,at);at+=c.length;}return new TextDecoder().decode(bytes);
}
