import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import relay from '../blockfrost-proxy.js';

const INSIGHT_V0 = 'https://mainnet.insight.iagon.com/api/v0/';
const INSIGHT_KEY = 'insight-test-key';
const BLOCKFROST_KEY = 'blockfrost-test-key';

const ADDR =
  'addr1q9d8a3gqwtm6nlvwaqd2x3dcgawz3uytqqqx57stmqmm6mh3vjsy7zs0nsuwktqd5kc6cpzk2ap0sxhs68ynwqrr3fsqcl9w2n';
const STAKE = 'stake1u8cz2hk0a6hm5ag7w2r6t3l7ypu3c3yynjq4a8ucn4nxxqsd0c6pz';
const TX = 'a'.repeat(64);

const WALLET_ROUTES = [
  `addresses/${ADDR}`,
  `addresses/${ADDR}/utxos`,
  `accounts/${STAKE}`,
  `accounts/${STAKE}/addresses`,
  `accounts/${STAKE}/addresses/assets`,
];

let calls;
let respond;
globalThis.fetch = async (url, init = {}) => {
  calls.push({ url: String(url), headers: init.headers || {} });
  return respond(String(url));
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

async function get(query, method = 'GET') {
  const res = {
    statusCode: 200,
    headers: {},
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    json(value) {
      this.body = JSON.stringify(value);
      return this;
    },
    send(value) {
      this.body = value;
      return this;
    },
  };
  await relay({ method, query }, res);
  return res;
}

beforeEach(() => {
  calls = [];
  respond = () => jsonResponse([]);
  process.env.INSIGHT_API_KEY = INSIGHT_KEY;
  process.env.BLOCKFROST_API_KEY = BLOCKFROST_KEY;
});

test('relays each wallet route to Insight /api/v0 with the Insight key as project_id', async () => {
  for (const path of WALLET_ROUTES) {
    calls = [];
    const res = await get({ path });
    assert.equal(res.statusCode, 200, path);
    assert.equal(calls.length, 1, path);
    assert.equal(calls[0].url, `${INSIGHT_V0}${path}`);
    assert.equal(calls[0].headers.project_id, INSIGHT_KEY);
    assert.ok(!JSON.stringify(calls[0]).includes(BLOCKFROST_KEY));
  }
});

test('passes the upstream status and JSON body through unchanged', async () => {
  const body = { status_code: 404, error: 'Not Found', message: 'The requested component has not been found.' };
  respond = () => jsonResponse(body, 404);
  const res = await get({ path: `addresses/${ADDR}` });
  assert.equal(res.statusCode, 404);
  assert.match(res.headers['content-type'], /application\/json/);
  assert.deepEqual(JSON.parse(res.body), body);
});

test('refuses every route the wallet does not use, without spending an upstream call', async () => {
  const refused = [
    '',
    'blocks/latest',
    'epochs/latest/parameters',
    'network',
    'tx/submit',
    `txs/${TX}`,
    `txs/${TX}/utxos`,
    `assets/${'b'.repeat(56)}`,
    `addresses/${ADDR}/transactions`,
    `addresses/${ADDR}/utxos/lovelace`,
    `accounts/${STAKE}/history`,
    `accounts/${ADDR}`,
    `addresses/${STAKE}/../../blocks/latest`,
    'addresses/../blocks/latest',
    `../../v1/addresses/${ADDR}`,
    `../../v1/accounts/${STAKE}`,
    `blocks/latest/addresses/${ADDR}`,
    `blocks/latest/accounts/${STAKE}`,
    `/addresses/${ADDR}`,
    `addresses/${ADDR}?count=100`,
    `addresses/${ADDR}#utxos`,
    `addresses/${ADDR}%2Futxos`,
    `addresses/${ADDR}\n`,
    `ADDRESSES/${ADDR}`,
  ];
  for (const path of refused) {
    const res = await get({ path });
    assert.equal(res.statusCode, 403, `path ${JSON.stringify(path)}`);
  }
  for (const path of [undefined, [`addresses/${ADDR}`, 'blocks/latest'], [`addresses/${ADDR}`]]) {
    const res = await get({ path });
    assert.equal(res.statusCode, 403, `path ${JSON.stringify(path)}`);
  }
  assert.equal(calls.length, 0);
});

test('forwards no query parameters besides the route itself', async () => {
  await get({ path: `addresses/${ADDR}/utxos`, count: '100', page: '1002', order: 'desc', from: '1' });
  assert.equal(calls[0].url, `${INSIGHT_V0}addresses/${ADDR}/utxos`);
});

test('fails closed with 500 when INSIGHT_API_KEY is unset, never falling back to Blockfrost', async () => {
  delete process.env.INSIGHT_API_KEY;
  const res = await get({ path: `accounts/${STAKE}` });
  assert.equal(res.statusCode, 500);
  assert.equal(calls.length, 0);
});

test('rejects methods other than GET', async () => {
  const res = await get({ path: `accounts/${STAKE}` }, 'POST');
  assert.equal(res.statusCode, 405);
  assert.equal(calls.length, 0);
});

test('answers 502 when the upstream reply is not JSON', async () => {
  respond = () => new Response('<html>gateway</html>', { status: 200, headers: { 'content-type': 'text/html' } });
  const res = await get({ path: `accounts/${STAKE}` });
  assert.equal(res.statusCode, 502);
  assert.ok(!res.body.includes('gateway'));
});

test('answers 502 without echoing internals when the upstream is unreachable', async () => {
  respond = () => {
    throw new Error(`connect ECONNREFUSED project_id=${INSIGHT_KEY}`);
  };
  const res = await get({ path: `accounts/${STAKE}` });
  assert.equal(res.statusCode, 502);
  assert.ok(!res.body.includes(INSIGHT_KEY));
  assert.ok(!res.body.includes('ECONNREFUSED'));
});
