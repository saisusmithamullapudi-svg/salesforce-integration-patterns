'use strict';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('../server');

let server;
let base;

before(async () => {
    server = createServer({ logger: { log() {} } });
    await new Promise((resolve) => server.listen(0, resolve));
    base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

const valid = { externalId: '006SYNTH0001', applicantName: 'Synthetic Homeowner', systemPrice: 32000, termMonths: 240, postalCode: '75009' };

const post = (body, headers = {}) =>
    fetch(`${base}/v1/applications`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...headers },
        body: typeof body === 'string' ? body : JSON.stringify(body)
    });

test('health endpoint responds', async () => {
    const res = await fetch(`${base}/health`);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: 'ok' });
});

test('creates an application and returns SUBMITTED', async () => {
    const res = await post(valid, { 'Idempotency-Key': 'key-1' });
    assert.equal(res.status, 201);
    const body = await res.json();
    assert.match(body.applicationId, /^APP-\d+$/);
    assert.equal(body.status, 'SUBMITTED');
});

test('repeating an Idempotency-Key returns the original application', async () => {
    const first = await (await post(valid, { 'Idempotency-Key': 'key-2' })).json();
    const again = await post(valid, { 'Idempotency-Key': 'key-2' });
    assert.equal(again.status, 200);
    assert.deepEqual(await again.json(), first);
});

test('declines applications above the program limit', async () => {
    const res = await post({ ...valid, systemPrice: 150000 }, { 'Idempotency-Key': 'key-3' });
    assert.equal((await res.json()).status, 'DECLINED');
});

test('rejects missing Idempotency-Key', async () => {
    const res = await post(valid);
    assert.equal(res.status, 400);
});

test('rejects invalid fields with a validation message', async () => {
    const res = await post({ ...valid, postalCode: 'ABC', termMonths: 7 }, { 'Idempotency-Key': 'key-4' });
    assert.equal(res.status, 400);
    const { error } = await res.json();
    assert.match(error, /postalCode/);
    assert.match(error, /termMonths/);
});

test('rejects malformed JSON', async () => {
    const res = await post('{bad', { 'Idempotency-Key': 'key-5' });
    assert.equal(res.status, 400);
});

test('X-Mock-Fail forces a transient error for retry demos', async () => {
    const res = await post(valid, { 'Idempotency-Key': 'key-6', 'X-Mock-Fail': '503' });
    assert.equal(res.status, 503);
});

test('looks up an application by id', async () => {
    const created = await (await post(valid, { 'Idempotency-Key': 'key-7' })).json();
    const res = await fetch(`${base}/v1/applications/${created.applicationId}`);
    assert.equal(res.status, 200);
    assert.equal((await res.json()).applicationId, created.applicationId);
    assert.equal((await fetch(`${base}/v1/applications/APP-0`)).status, 404);
});
