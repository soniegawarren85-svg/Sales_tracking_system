# Password reset email setup

The Flutter Forgot Password screen sends reset emails directly through
Firebase Authentication using `sendPasswordResetEmail`. It works with the
Firebase Spark plan and does not require Resend, a Cloud Function, or a
provider API key. Firebase controls the reset link's validity period. After
the reset succeeds, Firebase returns to the branded completion page and then
routes back to Login.

## Firebase Console setup

1. In Firebase Console, open **Authentication → Sign-in method** and enable
   **Email/Password**.
2. Under **Authentication → Templates**, configure the **Password reset**
   email subject, sender name, and message.
3. Under **Authentication → Settings → Authorized domains**, make sure the
   domain hosting the Flutter Web app is listed. For local development, add
   `localhost` if it is not already present. Add
   `sales-tracking-d8667-account.web.app` as well.
4. Send a reset request to an email address that belongs to a Firebase
   Authentication user and check its inbox and Spam folder.

The screen confirms success only after Firebase accepts the request. It then
shows instructions to open Gmail and follow the reset link. The app applies a
60-second resend cooldown; it is not an estimate of link expiration.

The account password can only be reset for the email registered with Firebase
Authentication. Updating a contact email in a Firestore profile alone does not
change the Firebase Authentication email.

Staff, admin, and super-admin profile editors keep the existing email active
while a replacement is pending. Admin and super-admin email changes require
the current password and use Firebase Authentication's
`verifyBeforeUpdateEmail`; other profile fields save normally. The profile
shows the pending address until it is verified. After a super-admin verifies
the link, use **Check / resend** in the profile editor to sync the verified
address to the profile. A password change also updates the linked Firebase
identity so later email changes can be reauthenticated.

In Firebase Console, enable **Email/Password** and configure the **Email
address verification** template. Add the Flutter Web domain to **Authorized
domains**. Firebase sends the verification link; no Resend provider or Cloud
Function is used. If a verification email is pending, the current sign-in
address remains active until the new address is confirmed.

## Hosting the successful-reset page

The branded reset handler at
`https://sales-tracking-d8667-account.web.app/reset-password.html` uses the
Firebase Auth JavaScript SDK to verify the one-time code and save the new
password. After Firebase confirms the change, it shows the success message
and returns to Login on the same device. Deploy the static Hosting site:

```powershell
firebase.cmd deploy --only hosting --project sales-tracking-d8667
```

The reset form requires at least 8 characters, an uppercase letter, a lowercase
letter, a number, and a special character. It shows live rule checks and
strength progress and only enables Save when every rule passes and the
confirmation matches. Password copy/paste is disabled on the reset page and
the Flutter Login password field.

After deploying, open **Authentication → Templates → Password reset**, edit
the template, enable **Customize action URL**, and set it to
`https://sales-tracking-d8667-account.web.app/reset-password.html`. Save the
template. The custom URL must be on an authorized domain, or Firebase will
reject reset requests with `unauthorized-continue-uri`.

With the Spark plan, Firebase cannot notify a separate tablet that a reset was
completed on a phone. Open the reset email on the tablet to return on that same
device, or use **Password changed? Return to Login** on the tablet after
completing the reset on the phone.
