import {PUBLIC_KEY, SUPABASE_URL} from '@/lib/leleka/config';

export const runtime = 'nodejs';

/** Same-origin transport; Supabase still authenticates and authorizes every action. */
export async function POST(request: Request) {
  const headers = {'Cache-Control': 'no-store'};
  const authorization = request.headers.get('authorization') || '';
  if (!/^Bearer [A-Za-z0-9_.-]+$/.test(authorization)) {
    return Response.json({error: 'Увійдіть до акаунта'}, {status: 401, headers});
  }

  const text = await request.text();
  if (text.length > 4096) {
    return Response.json({error: 'Завеликий запит'}, {status: 413, headers});
  }

  let payload: Record<string, unknown>;
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error();
    payload = parsed;
  } catch {
    return Response.json({error: 'Некоректний запит'}, {status: 400, headers});
  }
  if (!['username_login', 'delete_account'].includes(String(payload.action))) {
    return Response.json({error: 'Невідома дія'}, {status: 400, headers});
  }

  try {
    const response = await fetch(`${SUPABASE_URL}/functions/v1/account`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json', apikey: PUBLIC_KEY, authorization},
      body: JSON.stringify(payload),
      cache: 'no-store',
      signal: AbortSignal.timeout(15000),
    });
    return new Response(await response.text(), {
      status: response.status,
      headers: {...headers, 'Content-Type': 'application/json'},
    });
  } catch {
    return Response.json({error: 'Сервіс тимчасово недоступний. Спробуйте ще раз.'}, {
      status: 502, headers,
    });
  }
}
