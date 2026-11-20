import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const assets = new URL('../dist/Wuwa Tappo.app/Contents/Resources/original/assets/', import.meta.url);
const entry = readFileSync(new URL('index-BelNnexT.js', assets), 'utf8');
const desktop = readFileSync(new URL('index-BGIVWra7.js', assets), 'utf8');

function section(source, start, end) {
  const first = source.indexOf(start);
  const last = source.indexOf(end, first + start.length);
  assert(first >= 0 && last > first, `Room behavior changed around ${start}`);
  return source.slice(first, last);
}

test('public room and random join use the shipped HTTP method and payload', async () => {
  const requests = [];
  const api = vm.runInNewContext(
    section(entry, 'function randomJoinRoom(){', 'function favoriteAsset(') + ';({randomJoinRoom,setRoomPublic})',
    { jsonpClient: { async post(path, payload) { requests.push({ path, payload: { ...payload } }); } } },
  );
  await api.randomJoinRoom();
  await api.setRoomPublic('123456', true);
  await api.setRoomPublic('123456', false);
  assert.deepEqual(requests, [
    { path: 'api/frontend/rooms/random-join', payload: {} },
    { path: 'api/frontend/rooms/public', payload: { room_no: '123456', is_public: true } },
    { path: 'api/frontend/rooms/public', payload: { room_no: '123456', is_public: false } },
  ]);
});

test('room kick and ownership transfer send Socket.IO messages for an eligible member', async () => {
  const sent = [];
  const role = { value: 'member' };
  const room = vm.runInNewContext(
    section(desktop, 'async function Gt(w,b){', 'async function Et(){') + ';({kick:xn,transfer:Wt})',
    {
      i: role, J: { value: false }, p: { value: [{ id: 8 }, { id: 9 }] },
      ee: () => 8, He: () => true, Ho: reply => reply.c === 0,
      async Wn(event, { u }) { sent.push([event, u]); return { c: 0 }; },
      setTimeout, clearTimeout,
    },
  );
  assert.equal(await room.kick(9), false);
  role.value = 'owner';
  assert.equal(await room.kick(8), false);
  assert.equal(await room.transfer(999), false);
  assert.equal(await room.kick(9), true);
  assert.equal(await room.transfer(9), true);
  assert.deepEqual(sent, [['rk', 9], ['rt', 9]]);
});
