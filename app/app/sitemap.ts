import type {MetadataRoute} from 'next';
import {articleSitemap} from '@/lib/leleka/public-blog';
export const dynamic='force-dynamic';
export default async function sitemap():Promise<MetadataRoute.Sitemap>{const articles=await articleSitemap();return [
 {url:'https://lelekathoughts.vercel.app/',lastModified:'2026-11-16'},
 {url:'https://lelekathoughts.vercel.app/blog'},
 ...articles.map(a=>({url:`https://lelekathoughts.vercel.app/blog/${a.id}`,lastModified:a.updated_at})),
]}
