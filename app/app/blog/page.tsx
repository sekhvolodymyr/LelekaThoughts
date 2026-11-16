import type {Metadata} from 'next';
import Link from 'next/link';
import {LogoMark} from '@/components/leleka/logo-mark';
import {publicArticles} from '@/lib/leleka/public-blog';
import {articleUrl} from '@/lib/leleka/blog';
export const dynamic='force-dynamic';
export const metadata:Metadata={title:'Блоги креаторів — LelekaThoughts',description:'Статті, творчі історії та досвід авторів української соцмережі LelekaThoughts.',alternates:{canonical:'/blog'},openGraph:{url:'/blog',title:'Блоги креаторів — LelekaThoughts'}};
export default async function Blog(){const items=await publicArticles();return <main className="public-blog">
 <header className="public-blog-header"><Link href="/"><LogoMark/>LelekaThoughts</Link><a href="/#/blog">Мій блог ↗</a></header>
 <h1>Блоги креаторів</h1><p className="article-intro">Творчі історії, досвід і думки, яким потрібне більше місця.</p>
 {!items.length&&<p>Перші статті вже на підході. <a className="text-link" href="/#/blog">Напиши свою ↗</a></p>}
 {items.map(a=><article className="blog-card" key={a.id}><small className="muted">{a.author?.display_name||'Автор'} · {new Date(a.published_at!).toLocaleDateString('uk-UA')}</small><h2><Link href={articleUrl(a.id)}>{a.title}</Link></h2>{a.excerpt&&<p>{a.excerpt}</p>}<Link className="text-link" href={articleUrl(a.id)}>Читати статтю ↗</Link></article>)}
 <footer><a className="text-link" href="/#/feed">До стрічки LelekaThoughts ↗</a></footer>
 </main>}
