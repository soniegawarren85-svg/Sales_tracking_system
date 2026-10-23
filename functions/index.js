'use strict';

const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const {createHash} = require('node:crypto');
const admin = require('firebase-admin');
const {defineSecret, defineString} = require('firebase-functions/params');
const {onRequest} = require('firebase-functions/v2/https');
const {
  RATE_LIMIT_MS,
  createPasswordResetHandlers,
  isResetEligibleProfile,
} = require('./password_reset');

admin.initializeApp();

const db = admin.firestore();
const resendApiKey = defineSecret('RESEND_API_KEY');
const RATE_LIMIT_RETENTION_MS = 24 * 60 * 60 * 1000;
const resetSender = defineString('RESET_SENDER', {
  default: "Angel'Z Bites Cupcakes <onboarding@resend.dev>",
});
const resetPageUrl = defineString('RESET_PAGE_URL', {
  default: 'https://us-central1-sales-tracking-d8667.cloudfunctions.net/passwordResetPage',
});
const resetTemplate = readFileSync(join(__dirname, 'password-reset-email.html'), 'utf8');
const resetPageHtml = readFileSync(
  join(__dirname, 'reset_page', 'reset.html'),
  'utf8',
);
const resetPageScript = readFileSync(
  join(__dirname, 'reset_page', 'reset.js'),
  'utf8',
);
const resetPage = resetPageHtml.replace(
  '<script src="reset.js" defer></script>',
  `<script>${resetPageScript}</script>`,
);

function emailKey(email) {
  return createHash('sha256').update(email).digest('hex');
}

async function findEligibleAccount(email) {
  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (error) {
    if (error.code === 'auth/user-not-found') return null;
    throw error;
  }
  if (user.disabled || user.email?.toLowerCase() !== email) return null;

  // Bind the profile to the Auth UID, never to an email-only match.
  const ref = db.collection('staff_requests').doc(user.uid);
  const profile = (await ref.get()).data();
  if (!profile) return null;
  const authoritative = {...profile, authEmail: user.email};
  if (!isResetEligibleProfile(authoritative, email)) return null;
  if (profile.authEmail !== user.email || profile.email !== user.email ||
      profile.pendingAuthEmail === user.email) {
    await ref.update({
      email: user.email,
      authEmail: user.email,
      ...(profile.pendingAuthEmail === user.email
        ? {pendingAuthEmail: admin.firestore.FieldValue.delete()} : {}),
    });
  }
  return {uid: user.uid, email: user.email};
}

async function allowRequest(email, now, ip) {
  const collection = db.collection('password_reset_rate_limits');
  const emailRef = collection.doc(`email_${emailKey(email)}`);
  const ipRef = collection.doc(`ip_${emailKey(ip)}`);
  return db.runTransaction(async (transaction) => {
    const [emailSnapshot, ipSnapshot] = await Promise.all([
      transaction.get(emailRef),
      transaction.get(ipRef),
    ]);
    const previous = emailSnapshot.data()?.requestedAt?.toMillis?.() ?? 0;
    if (now - previous < RATE_LIMIT_MS) return false;
    const recentIpRequests = (ipSnapshot.data()?.requests ?? [])
      .map((timestamp) => timestamp.toMillis())
      .filter((timestamp) => now - timestamp < RATE_LIMIT_MS);
    if (recentIpRequests.length >= 10) return false;
    transaction.set(emailRef, {
      requestedAt: admin.firestore.Timestamp.fromMillis(now),
      expireAt: admin.firestore.Timestamp.fromMillis(
        now + RATE_LIMIT_RETENTION_MS,
      ),
    });
    transaction.set(ipRef, {
      requests: [
        ...recentIpRequests.map((timestamp) =>
          admin.firestore.Timestamp.fromMillis(timestamp)),
        admin.firestore.Timestamp.fromMillis(now),
      ],
      expireAt: admin.firestore.Timestamp.fromMillis(
        now + RATE_LIMIT_RETENTION_MS,
      ),
    });
    return true;
  });
}

async function saveReset({hashedToken, hashedStatusToken, uid, expiresAt}) {
  await db.collection('password_reset_tokens').doc(hashedToken).set({
    uid,
    hashedStatusToken,
    expiresAt: admin.firestore.Timestamp.fromMillis(expiresAt),
    expireAt: admin.firestore.Timestamp.fromMillis(expiresAt + 24 * 60 * 60 * 1000),
    consumed: false,
  });
  await db.collection('password_reset_status').doc(hashedStatusToken).set({
    completed: false,
    expireAt: admin.firestore.Timestamp.fromMillis(expiresAt + 24 * 60 * 60 * 1000),
  });
}

async function deleteReset(hashedToken) {
  await db.collection('password_reset_tokens').doc(hashedToken).delete();
}

async function updateResetExpiry(hashedToken, expiresAt) {
  await db.collection('password_reset_tokens')
    .doc(hashedToken)
    .update({
      expiresAt: admin.firestore.Timestamp.fromMillis(expiresAt),
    });
}

async function getReset(hashedToken) {
  const snapshot = await db.collection('password_reset_tokens')
    .doc(hashedToken)
    .get();
  const data = snapshot.data();
  if (!data) return null;
  return {
    consumed: data.consumed === true,
    expiresAt: data.expiresAt.toMillis(),
  };
}

async function consumeReset(hashedToken, now) {
  const ref = db.collection('password_reset_tokens').doc(hashedToken);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data();
    if (!data ||
        data.consumed === true ||
        data.expiresAt.toMillis() <= now) {
      return null;
    }
    transaction.update(ref, {
      consumed: true,
      consumedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {uid: data.uid, hashedStatusToken: data.hashedStatusToken};
  });
}

async function sendResetEmail({to, resetUrl}) {
  const {Resend} = require('resend');
  const resend = new Resend(resendApiKey.value());
  const html = resetTemplate.replaceAll('{{RESET_LINK}}', resetUrl);
  const result = await resend.emails.send({
    from: resetSender.value(),
    to,
    subject: "Reset your Angel'Z Bites Cupcakes password",
    html,
  });
  if (result.error) throw new Error(result.error.message);
}

const handlers = createPasswordResetHandlers({
  findEligibleAccount,
  allowRequest,
  saveReset,
  updateResetExpiry,
  deleteReset,
  getReset,
  consumeReset,
  sendEmail: sendResetEmail,
  updatePassword: async (uid, password) => {
    // Stop legacy password fallback before accepting the new Auth password.
    await db.collection('staff_requests').doc(uid).update({
      passwordAuthMode: 'firebase',
      password: admin.firestore.FieldValue.delete(),
      passwordHash: admin.firestore.FieldValue.delete(),
      passwordCredential: admin.firestore.FieldValue.delete(),
      mustChangePassword: false,
    });
    await admin.auth().updateUser(uid, {password});
  },
  markCompleted: async (hash) => {
    if (hash) await db.collection('password_reset_status').doc(hash).update({completed: true});
  },
  getStatus: async (hash) => (await db.collection('password_reset_status').doc(hash).get()).data(),
  resetPageUrl: resetPageUrl.value(),
});

function cors(handler) {
  return async (req, res) => {
    const allowedOrigin = new URL(resetPageUrl.value()).origin;
    const origin = req.get('origin');
    const trustedOrigins = new Set([
      allowedOrigin,
      'https://sales-tracking-d8667.web.app',
      'https://sales-tracking-d8667-account.web.app',
      'https://sales-tracking-d8667.firebaseapp.com',
    ]);
    let isLocalDevelopmentOrigin = false;
    if (origin && URL.canParse(origin)) {
      const parsedOrigin = new URL(origin);
      isLocalDevelopmentOrigin =
        parsedOrigin.protocol === 'http:' &&
        ['localhost', '127.0.0.1', '[::1]'].includes(parsedOrigin.hostname);
    }
    if (origin &&
        !trustedOrigins.has(origin) &&
        !isLocalDevelopmentOrigin) {
      res.status(403).json({message: 'Origin not allowed.'});
      return;
    }
    res.set('Access-Control-Allow-Origin', origin || allowedOrigin);
    res.set('Vary', 'Origin');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    await handler(req, res);
  };
}

exports.requestPasswordReset = onRequest(
  {region: 'us-central1', secrets: [resendApiKey]},
  cors(handlers.requestReset),
);
exports.completePasswordReset = onRequest(
  {region: 'us-central1'},
  cors(handlers.completeReset),
);
exports.validatePasswordReset = onRequest(
  {region: 'us-central1'},
  cors(handlers.validateReset),
);
exports.passwordResetStatus = onRequest(
  {region: 'us-central1'},
  cors(handlers.resetStatus),
);
exports.passwordResetPage = onRequest({region: 'us-central1'}, (req, res) => {
  if (req.method !== 'GET') {
    res.status(405).send('Method not allowed.');
    return;
  }
  res.set('Cache-Control', 'no-store');
  res.set('Referrer-Policy', 'no-referrer');
  res.set('X-Content-Type-Options', 'nosniff');
  res.type('html').send(resetPage);
});
