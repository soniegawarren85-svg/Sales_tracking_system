const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

function runHandler({
  search = '?mode=resetPassword&oobCode=one-time-code',
  userAgent = 'Mozilla/5.0 (Linux; Android 14)',
  resetError,
} = {}) {
  const nodes = new Map();
  const rules = ['length', 'uppercase', 'lowercase', 'number', 'special']
    .map(rule => ({
      dataset: {rule},
      classList: {
        toggle(name, enabled) {
          this[name] = enabled;
        },
      },
    }));
  const node = id => {
    if (!nodes.has(id)) {
      nodes.set(id, {
        value: '',
        hidden: id === 'success' || id === 'message',
        disabled: id === 'save',
        textContent: '',
        style: {},
        attributes: {},
        setAttribute(name, value) {
          this.attributes[name] = value;
        },
        addEventListener(event, callback) {
          this[`on${event}`] = callback;
        },
      });
    }
    return nodes.get(id);
  };
  const timers = [];
  const calls = [];
  const documentListeners = {};
  const auth = {
    async confirmPasswordReset(code, password) {
      calls.push({code, password});
      if (resetError) throw resetError;
    },
  };
  const firebase = {
    apps: [],
    initializeApp(config) {
      this.apps.push(config);
    },
    auth: () => auth,
  };
  const context = {
    document: {
      hidden: false,
      getElementById: node,
      querySelector: () => node('strength-track'),
      querySelectorAll: () => rules,
      addEventListener(event, callback) {
        documentListeners[event] = callback;
      },
      removeEventListener(event) {
        delete documentListeners[event];
      },
    },
    URLSearchParams,
    URL,
    location: {search, pathname: '/reset-password.html'},
    history: {replaceState() {}},
    navigator: {userAgent},
    firebase,
    window: {
      location: {
        href: '',
        replace(url) {
          this.redirect = url;
        },
      },
      setTimeout(callback, delay) {
        timers.push({callback, delay});
      },
    },
  };
  vm.runInNewContext(
    fs.readFileSync('web/account/reset-password.js', 'utf8'),
    context,
  );
  return {context, node, rules, calls, timers};
}

test('valid reset updates password, shows success and opens app login', async () => {
  const {context, node, calls, timers} = runHandler();
  node('password').value = 'StrongPass1!';
  node('confirm').value = 'StrongPass1!';
  node('password').oninput();
  node('confirm').oninput();

  await node('form').onsubmit({preventDefault() {}});

  assert.deepEqual(calls, [{
    code: 'one-time-code',
    password: 'StrongPass1!',
  }]);
  assert.equal(node('reset').hidden, true);
  assert.equal(node('success').hidden, false);
  assert.equal(node('continue').href, 'angelzbites://login');
  assert.equal(context.window.location.href, 'angelzbites://login');
  assert.equal(timers[0].delay, 2200);
});

test('password mismatch does not submit the reset code', async () => {
  const {node, calls} = runHandler();
  node('password').value = 'StrongPass1!';
  node('confirm').value = 'OtherPass2!';
  node('password').oninput();
  node('confirm').oninput();

  await node('form').onsubmit({preventDefault() {}});

  assert.equal(calls.length, 0);
  assert.equal(node('message').textContent, 'The passwords do not match.');
});

test('password strength rules update progress and block weak passwords', async () => {
  const {node, rules} = runHandler();

  node('password').value = 'weak';
  node('password').oninput();
  assert.equal(node('strength-track').attributes['aria-valuenow'], '1');
  assert.equal(node('strength-label').textContent, 'Weak');
  assert.equal(node('save').disabled, true);
  assert.equal(rules.find(rule => rule.dataset.rule === 'length').classList.passed, false);

  node('password').value = 'StrongPass1!';
  node('password').oninput();
  node('confirm').value = 'StrongPass1!';
  node('confirm').oninput();
  assert.equal(node('strength-track').attributes['aria-valuenow'], '5');
  assert.equal(node('strength-label').textContent, 'Strong');
  assert.equal(node('save').disabled, false);
  assert.ok(rules.every(rule => rule.classList.passed));
});

test('password fields block paste, copy, cut and keyboard shortcuts', () => {
  const {node} = runHandler();
  let prevented = false;
  node('password').onpaste({preventDefault() { prevented = true; }});
  assert.equal(prevented, true);
  assert.match(node('message').textContent, /type your password/);

  prevented = false;
  node('confirm').onkeydown({
    ctrlKey: true,
    metaKey: false,
    key: 'v',
    preventDefault() { prevented = true; },
  });
  assert.equal(prevented, true);
});

test('expired reset code shows an actionable error', async () => {
  const {node, calls} = runHandler({
    resetError: {code: 'auth/expired-action-code'},
  });
  node('password').value = 'StrongPass1!';
  node('confirm').value = 'StrongPass1!';
  node('password').oninput();
  node('confirm').oninput();

  await node('form').onsubmit({preventDefault() {}});

  assert.equal(calls.length, 1);
  assert.match(node('message').textContent, /expired or has already been used/);
  assert.equal(node('success').hidden, true);
});
