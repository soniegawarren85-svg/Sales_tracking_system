'use strict';
const el = id => document.getElementById(id);
const params = new URLSearchParams(location.search);
const token = params.get('token') || '';
const api = 'https://us-central1-sales-tracking-d8667.cloudfunctions.net';
let suggestion = '';
let saving = false;

function message(text) {
  el('message').textContent = text;
  el('message').hidden = false;
}

async function request(path, body) {
  const response = await fetch(`${api}/${path}`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(body),
  });
  const result = await response.json();
  if (!response.ok) {
    throw new Error(result.message || 'This reset link is invalid or expired.');
  }
  return result;
}

function randomIndex(n) {
  const value = new Uint32Array(1);
  const limit = Math.floor(4294967296 / n) * n;
  do { crypto.getRandomValues(value); } while (value[0] >= limit);
  return value[0] % n;
}

el('generate').onclick = () => {
  const groups = [
    'ABCDEFGHJKLMNPQRSTUVWXYZ',
    'abcdefghijkmnopqrstuvwxyz',
    '23456789',
    '!@#%*-_+',
  ];
  const alphabet = groups.join('');
  const chars = groups.map(group => group[randomIndex(group.length)]);
  while (chars.length < 20) chars.push(alphabet[randomIndex(alphabet.length)]);
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomIndex(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  suggestion = chars.join('');
  el('suggestion').textContent = suggestion;
  el('suggestion').hidden = el('use').hidden = false;
  el('generate').textContent = 'Generate another password';
};

el('use').onclick = () => {
  el('password').value = el('confirm').value = suggestion;
};

el('form').onsubmit = async event => {
  event.preventDefault();
  if (saving) return;
  if (el('password').value !== el('confirm').value) {
    message('Passwords do not match.');
    return;
  }
  saving = true;
  el('save').disabled = true;
  el('save').textContent = 'Saving…';
  el('message').hidden = true;
  try {
    await request('completePasswordReset', {
      token,
      password: el('password').value,
    });
    el('form').hidden = true;
    el('intro').hidden = true;
    el('message').hidden = true;
    el('success').hidden = false;
    el('success').classList.add('success-visible');
    history.replaceState(null, '', location.pathname);
    el('password').value = el('confirm').value = suggestion = '';
  } catch (error) {
    message(error instanceof TypeError
      ? 'Check your connection and try again.'
      : error.message);
  } finally {
    saving = false;
    el('save').disabled = false;
    el('save').textContent = 'Save new password';
  }
};

(async () => {
  if (!token) {
    el('intro').textContent = 'Open the reset link sent to your email.';
    return;
  }
  try {
    await request('validatePasswordReset', {token});
    el('intro').textContent = 'Choose and confirm your new password.';
    el('form').hidden = false;
  } catch (error) {
    el('intro').textContent = 'This reset link can no longer be used.';
    message(error instanceof TypeError
      ? 'Check your connection and open the link again.'
      : error.message);
  }
})();
