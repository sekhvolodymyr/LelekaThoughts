import assert from 'node:assert/strict';
import {test} from 'node:test';
import {postMedia,validMedia} from '../lib/leleka/media';
import {refreshQueue} from '../lib/leleka/refresh-queue';

test('untrusted media cannot become a renderer input', () => {
  for (const value of [null,1,'x',[],{}, {src:1,path:'',type:'image/png'}, {src:'javascript:alert(1)',path:'x',type:'image/png'}, {src:'https://example.com/x',path:'x',type:'video/mp4',duration:'30'}, {src:'https://example.com/x',path:'x',type:'video/mp4',duration:Infinity}]) assert.equal(validMedia(value),false);
  assert.deepEqual(postMedia([null,1,{}]),[]);
});
test('valid seeded images, uploads and 30-second videos remain compatible', () => {
  assert.equal(validMedia({src:'/media/photobook.webp',path:'',type:'image/webp'}),true);
  assert.equal(validMedia({src:'https://example.com/clip',path:'owner/clip.mp4',type:'video/mp4',duration:30}),true);
  assert.equal(postMedia([{src:'https://example.com/photo',path:'owner/photo.png',type:'image/png'}]).length,1);
});
test('refresh queue coalesces bursts and never overlaps requests', async () => {
  let calls=0, active=0, peak=0;
  const queue=refreshQueue(async()=>{calls++;active++;peak=Math.max(peak,active);await new Promise(r=>setTimeout(r,15));active--;},2);
  await Promise.all(Array.from({length:100},()=>queue.request()));
  assert.equal(calls,1);assert.equal(peak,1);
  const one=queue.request();await new Promise(r=>setTimeout(r,5));
  const tail=Array.from({length:100},()=>queue.request());await Promise.all([one,...tail]);
  assert.equal(calls,3);assert.equal(peak,1);queue.stop();
});
