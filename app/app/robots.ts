import type {MetadataRoute} from 'next';
export default function robots():MetadataRoute.Robots{return {
 rules:{userAgent:'*',allow:'/',disallow:'/api/'},
 sitemap:'https://lelekathoughts.vercel.app/sitemap.xml',
}}
