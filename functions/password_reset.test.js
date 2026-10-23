'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  RESET_WINDOW_MS,
  createPasswordResetHandlers,
  isResetEligibleProfile,
  tokenHash,
} = require('./password_reset');

function response() {
  return {
    code: 200,
    body: null,
    status(code) {
      this.code = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}

test('reset eligibility excludes inactive profiles and non-auth contact emails', () => {
  expectEligibleProfile({
    role: 'admin',
    status: 'accepted',
    authEmail: 'admin@example.com',
  }, 'admin@example.com', true);
  expectEligibleProfile({
    role: 'staff',
    status: 'temporarily_suspended',
    authEmail: 'staff@example.com',
  }, 'staff@example.com', false);
  expectEligibleProfile({
    role: 'super_admin',
    email: 'super@example.com',
  }, 'super@example.com', false);
  expectEligibleProfile({
    role: 'staff',
    email: 'contact@example.com',
    authEmail: 'login@example.com',
  }, 'contact@example.com', false);
});

function expectEligibleProfile(profile, email, expected) {
  assert.equal(isResetEligibleProfile(profile, email), expected);
}

test('reset request creates a random one-time token with a three-minute expiry', async () => {
  const now = Date.UTC(2026, 9, 21);
  let currentTime = now;
  const saved = [];
  const updatedExpiry = [];
  let message;
  const handlers = createPasswordResetHandlers({
    findEligibleAccount: async (email) => ({
      uid: 'staff-1',
      email,
    }),
    allowRequest: async () => true,
    saveReset: async (reset) => saved.push(reset),
    updateResetExpiry: async (hash, expiresAt) =>
      updatedExpiry.push({hash, expiresAt}),
    deleteReset: async () => {},
    getReset: async () => null,
    consumeReset: async () => null,
    sendEmail: async (email) => {
      message = email;
      currentTime += 10000;
    },
    updatePassword: async () => {},
    resetPageUrl: 'https://example.test/account/reset.html',
    now: () => currentTime,
  });
  const res = response();

  await handlers.requestReset({
    method: 'POST',
    body: {email: 'STAFF@example.com'},
  }, res);

  assert.equal(res.code, 202);
  assert.equal(Date.parse(res.body.expiresAt), now + 10000 + RESET_WINDOW_MS);
  assert.equal(saved.length, 1);
  assert.equal(saved[0].uid, 'staff-1');
  assert.equal(saved[0].expiresAt, now + RESET_WINDOW_MS);
  assert.deepEqual(updatedExpiry, [{
    hash: saved[0].hashedToken,
    expiresAt: now + 10000 + RESET_WINDOW_MS,
  }]);
  assert.equal(saved[0].hashedToken, tokenHash(
    new URL(message.resetUrl).searchParams.get('token'),
  ));
  assert.equal(message.to, 'staff@example.com');
});

test('unknown account response does not reveal account existence', async () => {
  const handlers = createPasswordResetHandlers({
    findEligibleAccount: async () => null,
    allowRequest: async () => true,
    saveReset: async () => assert.fail('must not create a token'),
    updateResetExpiry: async () => {},
    deleteReset: async () => {},
    getReset: async () => null,
    consumeReset: async () => null,
    sendEmail: async () => assert.fail('must not send an email'),
    updatePassword: async () => {},
    resetPageUrl: 'https://example.test/account/reset.html',
  });
  const res = response();

  await handlers.requestReset({
    method: 'POST',
    body: {email: 'unknown@example.com'},
  }, res);

  assert.equal(res.code, 202);
  assert.match(res.body.message, /If an active account matches/);
});

test('expired and already-used tokens cannot change a password', async () => {
  const handlers = createPasswordResetHandlers({
    findEligibleAccount: async () => null,
    allowRequest: async () => true,
    saveReset: async () => {},
    updateResetExpiry: async () => {},
    deleteReset: async () => {},
    getReset: async () => null,
    consumeReset: async () => null,
    sendEmail: async () => {},
    updatePassword: async () => assert.fail('must not update the password'),
    resetPageUrl: 'https://example.test/account/reset.html',
  });
  const res = response();

  await handlers.completeReset({
    method: 'POST',
    body: {token: 't'.repeat(48), password: 'Strong@Password2'},
  }, res);

  assert.equal(res.code, 400);
  assert.match(res.body.message, /invalid, expired, or already used/);
});

test('valid token changes the password once', async () => {
  let updated;
  const handlers = createPasswordResetHandlers({
    findEligibleAccount: async () => null,
    allowRequest: async () => true,
    saveReset: async () => {},
    updateResetExpiry: async () => {},
    deleteReset: async () => {},
    getReset: async () => null,
    consumeReset: async (hash) => hash === tokenHash('valid-token'.padEnd(48, 'x'))
      ? {uid: 'staff-1'}
      : null,
    sendEmail: async () => {},
    updatePassword: async (uid, password) => { updated = {uid, password}; },
    resetPageUrl: 'https://example.test/account/reset.html',
  });
  const res = response();

  await handlers.completeReset({
    method: 'POST',
    body: {token: 'valid-token'.padEnd(48, 'x'), password: 'Strong@Password2'},
  }, res);

  assert.equal(res.code, 200);
  assert.deepEqual(updated, {uid: 'staff-1', password: 'Strong@Password2'});
});

test('reset validation refuses a token at or past its three-minute deadline', async () => {
  const now = Date.UTC(2026, 9, 21);
  const handlers = createPasswordResetHandlers({
    findEligibleAccount: async () => null,
    allowRequest: async () => true,
    saveReset: async () => {},
    updateResetExpiry: async () => {},
    deleteReset: async () => {},
    getReset: async () => ({expiresAt: now, consumed: false}),
    consumeReset: async () => null,
    sendEmail: async () => {},
    updatePassword: async () => {},
    resetPageUrl: 'https://example.test/account/reset.html',
    now: () => now,
  });
  const res = response();

  await handlers.validateReset({
    method: 'POST',
    body: {token: 't'.repeat(48)},
  }, res);

  assert.equal(res.code, 400);
  assert.equal(res.body.valid, false);
});
