import {NextResponse} from 'next/server';
// The return page never grants access; only an authenticated provider webhook does.
const back=()=>NextResponse.redirect(new URL('/#/billing','https://lelekathoughts.vercel.app'),303);
export const GET=back;
export const POST=back;
