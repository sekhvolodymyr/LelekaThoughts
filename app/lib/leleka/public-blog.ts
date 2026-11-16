import 'server-only';
import {cache} from 'react';
import {SUPABASE_URL,PUBLIC_KEY} from './config';
import type {Article} from './blog';
const select='id,author_id,title,excerpt,body,status,created_at,updated_at,published_at,author:profiles!articles_author_id_fkey(display_name,username)';
async function query(params:Record<string,string>):Promise<Article[]>{
 const url=new URL(`${SUPABASE_URL}/rest/v1/articles`);
 for(const [key,value]of Object.entries({select,status:'eq.published',...params}))url.searchParams.set(key,value);
 const response=await fetch(url,{headers:{apikey:PUBLIC_KEY},cache:'no-store'});
 if(!response.ok)throw Error('Не вдалося завантажити статті');
 return response.json();
}
export const publicArticles=()=>query({order:'published_at.desc',limit:'50',select:'id,author_id,title,excerpt,status,created_at,updated_at,published_at,author:profiles!articles_author_id_fkey(display_name,username)'});
export const articleSitemap=()=>query({order:'published_at.desc',limit:'1000',select:'id,updated_at'});
export const publicArticle=cache(async(id:string)=>{
 if(!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(id))return null;
 return (await query({id:`eq.${id}`,limit:'1'}))[0]||null;
});
