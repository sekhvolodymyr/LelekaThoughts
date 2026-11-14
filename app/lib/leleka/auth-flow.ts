import {PUBLIC_KEY, SUPABASE_URL} from './config';

export const GOOGLE_UNAVAILABLE = 'Вхід через Google ще не налаштовано. Скористайтеся email або спробуйте пізніше.';
export const AUTH_CONNECTION_ERROR = 'Не вдалося підключитися до сервісу входу. Перевірте інтернет і спробуйте ще раз.';
export const AUTH_CALLBACK_ERROR = 'Не вдалося завершити вхід. Спробуйте ще раз.';
export const AUTH_CANCELLED = 'Вхід скасовано. Можна спробувати ще раз або увійти через email.';
export const AUTH_LINK_EXPIRED = 'Посилання для входу недійсне або застаріло. Запросіть нове.';

// signInWithOAuth constructs a URL without checking whether the provider is
// enabled. Check the public settings before navigating away from the app.
export async function assertGoogleEnabled() {
  let settings: {external?: {google?: boolean}};
  try {
    const response = await fetch(`${SUPABASE_URL}/auth/v1/settings`, {
      headers: {apikey: PUBLIC_KEY},
      cache: 'no-store',
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error('Auth settings unavailable');
    settings = await response.json();
    if (typeof settings?.external?.google !== 'boolean') throw new Error('Invalid auth settings');
  } catch {
    throw new Error(AUTH_CONNECTION_ERROR);
  }
  if (!settings.external!.google) throw new Error(GOOGLE_UNAVAILABLE);
}

// Never display provider-supplied error descriptions or leave them in shared
// URLs. Read errors only; successful session fragments belong to the Auth SDK.
export function readAuthCallbackError(href: string) {
  const url = new URL(href);
  const fragment = url.hash.slice(1);
  const hashParams = fragment.startsWith('/') ? null : new URLSearchParams(fragment);
  const sources = [url.searchParams, hashParams].filter((p): p is URLSearchParams => !!p);
  const params = sources.find(p => p.has('error') || p.has('error_code') || p.has('error_description'));
  if (!params) return null;
  const code = params.get('error_code');
  const description = params.get('error_description') || '';
  const message = code === 'otp_expired' ? AUTH_LINK_EXPIRED
    : /denied by user|user denied|cancel/i.test(description) ? AUTH_CANCELLED
    : AUTH_CALLBACK_ERROR;
  for (const source of sources) {
    for (const key of ['error', 'error_code', 'error_description']) source.delete(key);
  }
  if (hashParams) url.hash = hashParams.toString();
  return {message, cleanUrl: `${url.pathname}${url.search}${url.hash}`};
}
