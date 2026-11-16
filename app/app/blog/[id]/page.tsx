import type {Metadata} from 'next';
import Link from 'next/link';
import {notFound} from 'next/navigation';
import {publicArticle} from '@/lib/leleka/public-blog';
import {articleUrl} from '@/lib/leleka/blog';
import {LogoMark} from '@/components/leleka/logo-mark';
export const dynamic='force-dynamic';
type Props={params:Promise<{id:string}>};
export async function generateMetadata({params}:Props):Promise<Metadata>{
 const {id}=await params;const a=await publicArticle(id);if(!a)return {title:'Статтю не знайдено — LelekaThoughts',robots:{index:false,follow:false}};
 const description=a.excerpt||a.body.slice(0,160);
 return {title:`${a.title} — LelekaThoughts`,description,alternates:{canonical:articleUrl(a.id)},openGraph:{type:'article',title:a.title,description,url:articleUrl(a.id),publishedTime:a.published_at!,modifiedTime:a.updated_at,authors:[a.author?.display_name||'Автор']},twitter:{title:a.title,description}};
}
export default async function ArticlePage({params}:Props){
 const {id}=await params;const a=await publicArticle(id);if(!a)notFound();
 const schema={'@context':'https://schema.org','@type':'BlogPosting',headline:a.title,description:a.excerpt||a.body.slice(0,160),datePublished:a.published_at,dateModified:a.updated_at,mainEntityOfPage:`https://lelekathoughts.vercel.app${articleUrl(a.id)}`,author:{'@type':'Person',name:a.author?.display_name||'Автор',url:`https://lelekathoughts.vercel.app/#/profile/${a.author_id}`},publisher:{'@type':'Organization',name:'LelekaThoughts',logo:{'@type':'ImageObject',url:'https://lelekathoughts.vercel.app/icon-512.png'}}};
 return <main className="public-blog"><script type="application/ld+json" dangerouslySetInnerHTML={{__html:JSON.stringify(schema).replace(/</g,'\\u003c')}}/>
 <header className="public-blog-header"><Link href="/"><LogoMark/>LelekaThoughts</Link><Link href="/blog">Усі статті ↗</Link></header>
 <article><h1>{a.title}</h1>{a.excerpt&&<p className="article-intro">{a.excerpt}</p>}<div className="article-byline"><a href={`/#/profile/${a.author_id}`}>{a.author?.display_name||'Автор'}{a.author?.username?` · @${a.author.username}`:''}</a><time dateTime={a.published_at!}>{new Date(a.published_at!).toLocaleDateString('uk-UA')}</time></div><div className="article-body">{a.body.split(/\n\s*\n/).map((paragraph,i)=><p key={i}>{paragraph}</p>)}</div></article>
 <footer><Link className="text-link" href="/blog">← До блогів креаторів</Link></footer>
 </main>;
}
