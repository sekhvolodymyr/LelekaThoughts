'use client';
import {useEffect,useState} from 'react';
import {supabase} from '@/lib/leleka/client';
import type {Media} from '@/lib/leleka/types';
export function useMediaSource(media:Media|undefined){
 const [signed,setSigned]=useState<{path:string;url:string}|null>(null);
 useEffect(()=>{
  if(media?.bucket!=='private-media')return;
  let active=true;
  const refresh=async()=>{const {data,error}=await supabase.storage.from('private-media').createSignedUrl(media.path,60);if(active)setSigned(error?null:{path:media.path,url:data.signedUrl});};
  void refresh();const timer=setInterval(()=>void refresh(),45000);return()=>{active=false;clearInterval(timer)};
 },[media?.bucket,media?.path]);
 return media?.bucket==='private-media'?(signed?.path===media.path?signed.url:''):media?.src||'';
}
export function PostImage({media,alt,linked=false}:{media:Media;alt:string;linked?:boolean}){
 const src=useMediaSource(media);
 if(!src)return <span className="private-media-loading" role="status">Медіа із захищеним доступом</span>;
 const image=<img src={src} alt={alt} loading="lazy"/>;
 // Private assets are rendered in place; the signed URL expires in 60 seconds.
 return linked&&media.bucket!=='private-media'?<a href={src} target="_blank" rel="noreferrer">{image}</a>:image;
}
export function MediaThumb({media,alt}:{media:Media;alt:string}){
 const src=useMediaSource(media);if(!src)return null;
 return media.type.startsWith('video/')?<video src={src} preload="metadata" muted/>:<img src={src} alt={alt} loading="lazy"/>;
}
