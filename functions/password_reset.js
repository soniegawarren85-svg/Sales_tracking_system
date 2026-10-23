'use strict';

const {createHash, randomBytes} = require('node:crypto');

const RESET_WINDOW_MS = 3 * 60 * 1000;
const RATE_LIMIT_MS = RESET_WINDOW_MS;

function tokenHash(token) {
  return createHash('sha256').update(token).digest('hex');
}

function isResetEligibleProfile(profile, email) {
  const role = `${profile.role ?? 'staff'}`.trim().toLowerCase();
  const status = `${profile.status ?? ''}`
    .trim()
    .toLowerCase()
    .replace(/[_-]/g, ' ');
  const accountEmail = `${profile.authEmail ?? ''}`.trim() || profile.email;
  const hasEmail =
    `${accountEmail ?? ''}`.trim().toLowerCase() === email;
  return hasEmail &&
    ['staff', 'admin'].includes(role) &&
    ![
      'pending',
      'rejected',
      'deactivated',
      'suspended',
      'temporarily suspended',
      'temporary suspended',
    ].includes(status) &&
    profile.isDeactivated !== true &&
    profile.isSuspended !== true &&
    profile.isDeleted !== true &&
    !(profile.requiresBranchAssignment === true &&
      (!Array.isArray(profile.branchIds) ||
        profile.branchIds.every((branchId) => `${branchId}`.trim() === '')));
}

function createPasswordResetHandlers({
  findEligibleAccount,
  allowRequest,
  saveReset,
  updateResetExpiry,
  deleteReset,
  getReset,
  consumeReset,
  sendEmail,
  updatePassword,
  markCompleted = async () => {},
  getStatus = async () => null,
  resetPageUrl,
  now = Date.now,
}) {
  async function requestReset(req, res) {
    if (req.method !== 'POST') {
      res.status(405).json({message: 'Method not allowed.'});
      return;
    }

    const email = typeof req.body?.email === 'string'
      ? req.body.email.trim().toLowerCase()
      : '';
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      res.status(400).json({message: 'Enter a valid email address.'});
      return;
    }

    try {
      const requestedAt = now();
      if (!(await allowRequest(email, requestedAt, req.ip || 'unknown'))) {
        res.status(429).json({
          message: 'Please wait before requesting another reset link.',
        });
        return;
      }

      const statusToken = randomBytes(32).toString('base64url');
      let expiresAt = requestedAt + RESET_WINDOW_MS;
      const account = await findEligibleAccount(email);
      if (account) {
        const token = randomBytes(32).toString('base64url');
        const hashedToken = tokenHash(token);
        await saveReset({
          hashedToken,
          hashedStatusToken: tokenHash(statusToken),
          uid: account.uid,
          expiresAt,
        });
        const resetUrl = new URL(resetPageUrl);
        resetUrl.searchParams.set('token', token);
        try {
          await sendEmail({
            to: account.email,
            resetUrl: resetUrl.toString(),
          });
          expiresAt = now() + RESET_WINDOW_MS;
          await updateResetExpiry(hashedToken, expiresAt);
        } catch (error) {
          await deleteReset(hashedToken);
          throw error;
        }
      }

      res.status(202).json({
        message: 'If an active account matches, a reset email will be sent.',
        statusToken,
        expiresAt: new Date(expiresAt).toISOString(),
      });
    } catch (error) {
      console.error('Password reset request failed:', error);
      res.status(500).json({
        message: 'Unable to send the password reset email. Please try again.',
      });
    }
  }

  async function completeReset(req, res) {
    if (req.method !== 'POST') {
      res.status(405).json({message: 'Method not allowed.'});
      return;
    }

    const token = typeof req.body?.token === 'string' ? req.body.token : '';
    const password = typeof req.body?.password === 'string'
      ? req.body.password
      : '';
    if (token.length < 32 || password.length < 8 || password.length > 128 ||
        !/[A-Z]/.test(password) || !/[a-z]/.test(password) ||
        !/[0-9]/.test(password) || !/[^A-Za-z0-9\s]/.test(password)) {
      res.status(400).json({
        message: 'Use a valid reset link and at least 8 characters with uppercase, lowercase, a number, and a special character.',
      });
      return;
    }

    try {
      const reset = await consumeReset(tokenHash(token), now());
      if (!reset) {
        res.status(400).json({
          message: 'This reset link is invalid, expired, or already used. Request a new link.',
        });
        return;
      }
      await updatePassword(reset.uid, password);
      await markCompleted(reset.hashedStatusToken);
      res.status(200).json({message: 'Password changed successfully.'});
    } catch (error) {
      console.error('Password reset completion failed:', error);
      res.status(500).json({
        message: 'Unable to save the new password. Request a new reset link and try again.',
      });
    }
  }

  async function validateReset(req, res) {
    if (req.method !== 'POST') {
      res.status(405).json({message: 'Method not allowed.'});
      return;
    }
    const token = typeof req.body?.token === 'string' ? req.body.token : '';
    if (token.length < 32) {
      res.status(400).json({valid: false});
      return;
    }
    try {
      const reset = await getReset(tokenHash(token));
      const valid = reset != null &&
        reset.consumed !== true &&
        reset.expiresAt > now();
      res.status(valid ? 200 : 400).json({valid});
    } catch (error) {
      console.error('Password reset link validation failed:', error);
      res.status(500).json({
        message: 'Unable to check this reset link. Try again.',
      });
    }
  }

  async function resetStatus(req, res) {
    if (req.method !== 'POST') {
      res.status(405).json({message: 'Method not allowed.'});
      return;
    }
    const token = req.body?.statusToken;
    if (typeof token !== 'string' || token.length < 32 || token.length > 128) {
      res.status(400).json({message: 'Invalid request.'});
      return;
    }
    try {
      const status = await getStatus(tokenHash(token));
      res.status(200).json({status: status?.completed === true ? 'completed' : 'pending'});
    } catch (error) {
      res.status(503).json({message: 'Unable to check reset status. Please try again.'});
    }
  }
  return {requestReset, completeReset, validateReset, resetStatus};
}

module.exports = {
  RATE_LIMIT_MS,
  RESET_WINDOW_MS,
  createPasswordResetHandlers,
  isResetEligibleProfile,
  tokenHash,
};
