'use client';
import {Dialog,DialogContent,DialogTitle,DialogDescription,DialogClose} from '@/components/ui/dialog';
import {X} from 'lucide-react';
import {useId,isValidElement,cloneElement,type ReactElement} from 'react';
import {Avatar as AvatarRoot,AvatarImage,AvatarFallback} from '@/components/ui/avatar';
import {Empty,EmptyHeader,EmptyTitle,EmptyDescription} from '@/components/ui/empty';
import {Field,FieldLabel} from '@/components/ui/field';
import {useApp} from './provider';
import type {Profile} from '@/lib/leleka/types';

export function Avatar({profile,size=40}:{profile?:Partial<Profile>|null;size?:number}){return <AvatarRoot style={{width:size,height:size}} className="person-avatar"><AvatarImage src={profile?.avatar||undefined} alt=""/><AvatarFallback>{(profile?.display_name||'L').slice(0,2).toUpperCase()}</AvatarFallback></AvatarRoot>}
export function Modal({open,onClose,title,description,children,wide=false}:{open:boolean;onClose:()=>void;title:string;description?:string;children:React.ReactNode;wide?:boolean}){const {t}=useApp();return <Dialog open={open} onOpenChange={v=>!v&&onClose()}><DialogContent showCloseButton={false} className={wide?'app-modal wide':'app-modal'}><DialogTitle>{title}</DialogTitle><DialogDescription className={description?'modal-description':'sr-only'}>{description||title}</DialogDescription>{children}<DialogClose className="modal-close" aria-label={t('Закрити')}><X size={18}/></DialogClose></DialogContent></Dialog>}
export function FormField({label,children}:{label:string;children:React.ReactNode}){const id=useId();return <Field className="form-field"><FieldLabel htmlFor={id}>{label}</FieldLabel>{isValidElement(children)?cloneElement(children as ReactElement<{id?:string}>,{id}):children}</Field>}
export function Blank({title='Поки порожньо',description,children}:{title?:string;description?:string;children?:React.ReactNode}){const {t}=useApp();return <Empty><EmptyHeader><EmptyTitle>{t(title)}</EmptyTitle>{description&&<EmptyDescription>{t(description)}</EmptyDescription>}</EmptyHeader>{children}</Empty>}
export function ago(value:string,language='uk'){const ms=Date.now()-new Date(value).getTime();const n=Math.max(1,Math.floor(ms/60000));if(n<60)return `${n} ${language==='uk'?'хв':'min'}`;if(n<1440)return `${Math.floor(n/60)} ${language==='uk'?'год':'h'}`;return new Date(value).toLocaleDateString(language==='uk'?'uk-UA':'en-GB',{day:'numeric',month:'short'});}
export function Stork(){return <svg viewBox="0 0 48 52" fill="none" aria-hidden="true"><path d="M9 39 31 20c2-2 2-6 1-9-1-2 0-5 3-5 3 0 4 2 3 5l8 4-11-1c1 9-2 15-10 19L9 39Zm16-6-1 14m6-17-1 17m-8 0h6m0 0h6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/><circle cx="36" cy="9" r=".8" fill="currentColor"/></svg>}
