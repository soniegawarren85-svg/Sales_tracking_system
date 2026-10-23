const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

function runPage(userAgent) {
  const link = {href: ''};
  const timers = [];
  const listeners = {};
  const context = {
    URLSearchParams,
    document: {
      hidden: false,
      getElementById: () => link,
      addEventListener: (event, listener) => {
        listeners[event] = listener;
      },
      removeEventListener: (event) => {
        delete listeners[event];
      },
    },
    navigator: {userAgent},
    history: {replaceState() {}},
    location: {pathname: '/reset-complete.html', replace() {}},
    window: {
      location: {href: '', replace(url) { this.redirect = url; }},
      setTimeout(callback, delay) {
        timers.push({callback, delay});
      },
    },
  };
  vm.runInNewContext(
    fs.readFileSync('web/account/reset-complete.js', 'utf8'),
    context,
  );
  return {context, link, timers, listeners};
}

test('successful reset automatically returns a web user to Login', () => {
  const {context, link, timers} = runPage('Mozilla/5.0 (Windows NT 10.0)');

  assert.equal(
    link.href,
    'https://sales-tracking-d8667.web.app/?passwordReset=success',
  );
  assert.equal(timers[0].delay, 1800);
  timers[0].callback();
  assert.equal(
    context.window.location.redirect,
    'https://sales-tracking-d8667.web.app/?passwordReset=success',
  );
});

test('successful reset opens the app login link on mobile', () => {
  const {context, link, timers} = runPage('Mozilla/5.0 (Linux; Android 14)');

  assert.equal(link.href, 'angelzbites://login');
  assert.equal(context.window.location.href, 'angelzbites://login');
  assert.equal(timers[0].delay, 2200);
});
