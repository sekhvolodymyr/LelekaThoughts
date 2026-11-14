export const THEMES = [
  {id:'light', label:'Світла', preview:'#faf9f6'},
  {id:'dark', label:'Темна', preview:'#242527'},
  {id:'sunset', label:'Захід сонця', preview:'linear-gradient(135deg,#f9d7b9,#efb4c4)'},
  {id:'lavender', label:'Лаванда', preview:'linear-gradient(135deg,#d5d1fb,#f5d8eb)'},
  {id:'ocean', label:'Океан', preview:'linear-gradient(135deg,#173759,#18757b)'},
  {id:'forest', label:'Ліс', preview:'linear-gradient(135deg,#233d36,#526349)'},
] as const;

export type ThemeId = typeof THEMES[number]['id'];
export function normalizeTheme(value:string):ThemeId {
  return THEMES.find(theme=>theme.id===value)?.id || 'light';
}
