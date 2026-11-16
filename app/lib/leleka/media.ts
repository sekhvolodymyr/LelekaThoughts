import type {Media} from './types';

const images = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);
const videos = new Set(['video/mp4', 'video/webm', 'video/quicktime']);
export function validMedia(value: unknown): value is Media {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const m = value as Record<string, unknown>;
  if(m.bucket!==undefined&&m.bucket!=='media'&&m.bucket!=='private-media')return false;
  if (typeof m.src !== 'string' || typeof m.path !== 'string' || typeof m.type !== 'string') return false;
  if (!/^https:\/\/\S+$/.test(m.src) && !/^\/media\/[a-zA-Z0-9._/-]+$/.test(m.src)) return false;
  return images.has(m.type) || (videos.has(m.type) && typeof m.duration === 'number' && Number.isFinite(m.duration) && m.duration > 0 && m.duration <= 30);
}
export function postMedia(value: unknown): Media[] {
  return Array.isArray(value) ? value.filter((m): m is Media => validMedia(m) && images.has(m.type)).slice(0, 4) : [];
}
