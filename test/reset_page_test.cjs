const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const {webcrypto} = require('node:crypto');

test('reset page validates one-time link, confirms password and shows success', async () => {
  const nodes = new Map();
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, {value: '', hidden: true, textContent: ''});
    return nodes.get(id);
  };
  const calls = [];
  const context = {
    document: {getElementById: node}, URLSearchParams, Uint32Array,
    crypto: webcrypto,
    location: {search: '?token=one-time-test-token', pathname: '/account/reset.html'},
    history: {replaceState() {}},
    fetch: async (url, request) => {
      calls.push({url, body: JSON.parse(request.body)});
      return {
        ok: true,
        json: async () => url.endsWith('/validatePasswordReset')
          ? {valid: true}
          : {message: 'Password changed successfully.'},
      };
    },
  };
  vm.runInNewContext(fs.readFileSync('web/account/reset.js', 'utf8'), context);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(node('form').hidden, false);
  node('password').value = 'new-password';
  node('confirm').value = 'different-password';
  await node('form').onsubmit({preventDefault() {}});
  assert.equal(calls.length, 1);
  assert.match(node('message').textContent, /do not match/);
  node('generate').onclick();
  const first = node('suggestion').textContent;
  node('generate').onclick();
  assert.notEqual(node('suggestion').textContent, first);
  node('use').onclick();
  const next = node('password').value;
  assert.equal(next.length, 20);
  assert.equal(node('confirm').value, next);
  await node('form').onsubmit({preventDefault() {}});
  assert.equal(calls[1].url.endsWith('/completePasswordReset'), true);
  assert.equal(calls[1].body.token, 'one-time-test-token');
  assert.equal(calls[1].body.password, next);
  assert.equal(node('success').hidden, false);
  assert.equal(node('form').hidden, true);
});

test('reset page refuses a link that the backend has expired', async () => {
  const nodes = new Map();
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, {value: '', hidden: true, textContent: ''});
    return nodes.get(id);
  };
  const context = {
    document: {getElementById: node},
    URLSearchParams,
    Uint32Array,
    crypto: webcrypto,
    location: {search: '?token=expired-token', pathname: '/account/reset.html'},
    history: {replaceState() {}},
    fetch: async () => ({
      ok: false,
      json: async () => ({message: 'This reset link is invalid or expired.'}),
    }),
  };
  vm.runInNewContext(fs.readFileSync('web/account/reset.js', 'utf8'), context);
  await new Promise(resolve => setImmediate(resolve));

  assert.equal(node('form').hidden, true);
  assert.equal(node('intro').textContent, 'This reset link can no longer be used.');
  assert.match(node('message').textContent, /invalid or expired/);
});
