(() => {
  const requestId = new URLSearchParams(location.search || '').get('requestId');
  const appLogin = 'angelzbites://login' + (requestId ? '?requestId=' + encodeURIComponent(requestId) : '');
  const webLogin =
    'https://sales-tracking-d8667.web.app/?passwordReset=success' + (requestId ? '&requestId=' + encodeURIComponent(requestId) : '');
  const link = document.getElementById('continue');
  const isMobile = /android|iphone|ipad|ipod/i.test(navigator.userAgent);

  link.href = isMobile ? appLogin : webLogin;
  history.replaceState(null, '', location.pathname);

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
})();
