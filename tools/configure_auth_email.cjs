// Uses the Firebase CLI's existing sign-in without printing or persisting tokens.
const path = require('node:path');
const cli = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
(async () => {
  const auth = require(path.join(cli, 'auth'));
  const {requireAuth} = require(path.join(cli, 'requireAuth'));
  const {Client} = require(path.join(cli, 'apiv2'));
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error('Sign in with firebase login first.');
  await requireAuth({project: 'sales-tracking-d8667', ...account});
  const client = new Client({urlPrefix: 'https://identitytoolkit.googleapis.com', apiVersion: 'admin/v2'});
  const resource = '/projects/sales-tracking-d8667/config';
  const config = (await client.get(resource)).body;
  const templates = config.notification?.sendEmail || {};
  if (process.argv.includes('--apply')) {
    const backup = 'docs/account-email-template-backup.json';
    if (!fs.existsSync(backup)) fs.writeFileSync(backup, JSON.stringify({
      callbackUri: templates.callbackUri,
      resetPasswordTemplate: templates.resetPasswordTemplate,
      verifyEmailTemplate: templates.verifyEmailTemplate,
      changeEmailTemplate: templates.changeEmailTemplate,
    }, null, 2));
    const sendEmail = {};
    const masks = [];
    for (const name of ['resetPasswordTemplate', 'verifyEmailTemplate', 'changeEmailTemplate']) {
      sendEmail[name] = {senderDisplayName: "Angel'Z Bites Cupcakes"};
      masks.push(`notification.sendEmail.${name}.senderDisplayName`);
    }
    const callback = process.argv.find(arg => arg.startsWith('--callback='))?.slice(11);
    if (callback) { sendEmail.callbackUri = callback; masks.push('notification.sendEmail.callbackUri'); }
    await client.patch(resource, {notification: {sendEmail}}, {queryParams: {updateMask: masks.join(',')}});
  }
  const updated = (await client.get(resource)).body.notification?.sendEmail || {};
  console.log(JSON.stringify({callbackUri: updated.callbackUri,
    resetSender: updated.resetPasswordTemplate?.senderDisplayName,
    resetSubject: updated.resetPasswordTemplate?.subject,
    resetBodyFormat: updated.resetPasswordTemplate?.bodyFormat}, null, 2));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
