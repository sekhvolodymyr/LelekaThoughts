'use client';
import {Check} from 'lucide-react';
import {THEMES} from '@/lib/leleka/themes';
import {useApp} from './provider';

export function ThemePicker(){
 const {theme,setTheme,t}=useApp();
 return <fieldset className="theme-picker">
  <legend>{t('Тема')}</legend>
  <p className="theme-description">{t('Застосовується одразу та зберігається на цьому пристрої.')}</p>
  <div className="theme-grid">{THEMES.map(option=><button
   key={option.id} type="button" className="theme-option"
   aria-label={`${t('Тема')}: ${t(option.label)}`} aria-pressed={theme===option.id}
   onClick={()=>setTheme(option.id)}
  >
   <span className="theme-preview" style={{background:option.preview}} aria-hidden="true">
    <span className="theme-preview-sidebar"/><span className="theme-preview-content"><i/><i/><i/></span>
   </span>
   <span className="theme-option-label">{t(option.label)}{theme===option.id&&<Check size={16} aria-hidden="true"/>}</span>
  </button>)}</div>
 </fieldset>;
}
