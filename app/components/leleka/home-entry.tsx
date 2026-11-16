'use client';
import dynamic from 'next/dynamic';
import {useEffect,useState,type ReactNode} from 'react';

const LelekaApp=dynamic(()=>import('./app-shell'),{ssr:false,loading:()=> <p className="home-loading" role="status">Відкриваємо LelekaThoughts…</p>});

export function HomeEntry({children}:{children:ReactNode}){
 const [inApp,setInApp]=useState(false);
 useEffect(()=>{
  const sync=()=>setInApp(location.hash.startsWith('#/'));
  sync();window.addEventListener('hashchange',sync);
  return()=>window.removeEventListener('hashchange',sync);
 },[]);
 return inApp?<LelekaApp/>:children;
}
