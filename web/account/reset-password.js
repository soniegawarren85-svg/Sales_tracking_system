(() => {
  const firebaseConfig = {
    apiKey: 'AIzaSyBwjS6H-Dm2LQ6qULhuZPOF56trFNswer8',
    authDomain: 'sales-tracking-d8667.firebaseapp.com',
    projectId: 'sales-tracking-d8667',
    appId: '1:736393182026:web:cbb2a8e55140744d2adfb3',
  };
  const params = new URLSearchParams(location.search);
  const mode = params.get('mode');
  const code = params.get('oobCode');
  let requestId = '';
  try {
    const continuation = new URL(params.get('continueUrl') || 'https://invalid.local');
    requestId = continuation.searchParams.get('requestId') || '';
  } catch (_) {}
  const returnQuery = requestId ? '&requestId=' + encodeURIComponent(requestId) : '';
  const form = document.getElementById('form');
  const reset = document.getElementById('reset');
  const success = document.getElementById('success');
  const message = document.getElementById('message');
  const save = document.getElementById('save');
  const continueLink = document.getElementById('continue');
  const passwordInput = document.getElementById('password');
  const confirmInput = document.getElementById('confirm');
  const strengthFill = document.getElementById('strength-fill');
  const strengthLabel = document.getElementById('strength-label');
  const strengthTrack = document.querySelector('[role="progressbar"]');
  const rules = [...document.querySelectorAll('[data-rule]')];
  const auth = firebase.apps.length
    ? firebase.auth()
    : (firebase.initializeApp(firebaseConfig), firebase.auth());

  function showError(text) {
    message.textContent = text;
    message.hidden = false;
  }

  function describeError(error) {
    switch (error.code) {
      case 'auth/expired-action-code':
      case 'auth/invalid-action-code':
        return 'This reset link is expired or has already been used. Request a new link.';
      case 'auth/user-disabled':
      case 'auth/user-not-found':
        return 'This account is no longer available. Contact an administrator.';
      case 'auth/weak-password':
        return 'Choose a stronger password that meets every requirement.';
      case 'auth/network-request-failed':
        return 'Check your internet connection and try again.';
      default:
        return 'Unable to change the password. Please request a new reset link.';
    }
  }

  function getPasswordRules(value) {
    return {
      length: value.length >= 8,
      uppercase: /[A-Z]/.test(value),
      lowercase: /[a-z]/.test(value),
      number: /\d/.test(value),
      special: /[^A-Za-z0-9\s]/.test(value),
    };
  }

  function updateStrength() {
    const result = getPasswordRules(passwordInput.value);
    const passed = Object.values(result).filter(Boolean).length;
    const percent = (passed / rules.length) * 100;
    const strong = passed === rules.length;
    strengthFill.style.width = `${percent}%`;
    strengthFill.style.backgroundColor = strong
      ? '#168257'
      : passed >= 3 ? '#d18a20' : '#d43c56';
    strengthLabel.textContent = strong
      ? 'Strong'
      : passed >= 3 ? 'Almost strong' : 'Weak';
    strengthLabel.style.color = strong ? '#168257' : '#a31345';
    strengthTrack.setAttribute('aria-valuenow', `${passed}`);
    for (const rule of rules) {
      rule.classList.toggle('passed', result[rule.dataset.rule]);
    }
    save.disabled = !strong;
    return strong;
  }

  function blockClipboard(event) {
    event.preventDefault();
    showError('For security, type your password instead of copying or pasting it.');
  }

  for (const input of [passwordInput, confirmInput]) {
    input.addEventListener('paste', blockClipboard);
    input.addEventListener('copy', blockClipboard);
    input.addEventListener('cut', blockClipboard);
    input.addEventListener('contextmenu', (event) => {
      event.preventDefault();
    });
    input.addEventListener('keydown', (event) => {
      if ((event.ctrlKey || event.metaKey) &&
          ['v', 'c', 'x'].includes(event.key.toLowerCase())) {
        blockClipboard(event);
      }
    });
  }
  passwordInput.addEventListener('input', updateStrength);
  confirmInput.addEventListener('input', updateStrength);

  function returnToLogin() {
    const appLogin = 'angelzbites://login' + (requestId ? '?requestId=' + encodeURIComponent(requestId) : '');
    const webLogin =
      'https://sales-tracking-d8667.web.app/?passwordReset=success' + returnQuery;
    const isMobile = /android|iphone|ipad|ipod/i.test(navigator.userAgent);
    continueLink.href = isMobile ? appLogin : webLogin;

    if (!isMobile) {
      window.setTimeout(() => window.location.replace(webLogin), 1800);
      return;
    }

    let returnedToApp = false;
    const onVisibilityChange = () => {
      if (document.hidden) returnedToApp = true;
    };
    document.addEventListener('visibilitychange', onVisibilityChange);
    window.location.href = appLogin;
    window.setTimeout(() => {
      document.removeEventListener('visibilitychange', onVisibilityChange);
      if (!returnedToApp) window.location.replace(webLogin);
    }, 2200);
  }

  if (mode !== 'resetPassword' || !code) {
    showError('This reset link is invalid. Open the latest reset email.');
  } else {
    history.replaceState(null, '', location.pathname);
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (mode !== 'resetPassword' || !code || save.disabled) return;

    const password = document.getElementById('password').value;
    const confirmation = document.getElementById('confirm').value;
    if (!updateStrength()) {
      showError('Password is weak. Follow all the password requirements.');
      return;
    }
    if (password !== confirmation) {
      showError('The passwords do not match.');
      return;
    }

    save.disabled = true;
    save.textContent = 'Saving password…';
    message.hidden = true;
    try {
      await auth.confirmPasswordReset(code, password);
      reset.hidden = true;
      success.hidden = false;
      history.replaceState(null, '', location.pathname);
      returnToLogin();
    } catch (error) {
      showError(describeError(error));
    } finally {
      save.disabled = false;
      save.textContent = 'Save new password';
    }
  });
})();
