# 16 Username and password login

Purpose
Merchants log in with a username and a password instead of an email code. Many test users and
merchants have no email they can open, so the email code blocks them.

Scope
Flutter app (app/):
- One login screen replaces the email screen and the code screen. It has two modes:
  - Login: username, password, "লগইন" button.
  - New account: username, password, "অ্যাকাউন্ট খুলুন" button.
  - Links: switch between the two modes; "পাসওয়ার্ড ভুলে গেছেন?" shows one help line
    (contact BDPay support; the BDPay admin sets a new password in Supabase Studio).
- After a new account, the existing business name screen (spec 05) follows. After login, the existing
  merchant lookup (spec 13) decides: merchant found -> হোম, none -> business name screen.
- Supabase Auth email + password is used underneath. The username is turned into an internal address
  "<username>@users.bdpay.app". No email is ever sent and the user never sees this address.
- The settings account section shows "ইউজারনেম" instead of "ইমেইল".
- Mock (demo build): username "demo", password "123456" opens the demo merchant.
- Removed: email OTP sending, the code screen, the resend countdown and their strings.
Supabase (done by the owner in the Dashboard, no migration):
- Authentication > Sign In / Providers > Email: enabled, "Confirm email" OFF, sign-ups allowed.
- supabase/config.toml already has enable_confirmations = false and minimum_password_length = 6.
Not in scope: password change screen, password reset by email, phone login, admin screens,
server or database changes.

Contract
AuthRepository:
- signIn(username, password): username normalized (trimmed, lower case). Invalid username -> invalidUsername
  without a call. Password shorter than 6 -> wrongPassword without a call. Wrong username or password ->
  wrongPassword. Rate limited -> tooSoon. Account not confirmed -> notConfirmed. No network / other -> offline.
  Success -> merchant lookup as in spec 13.
- signUp(username, password): invalid username -> invalidUsername; password shorter than 6 -> weakPassword
  (both without a call). Username already used -> usernameTaken. Server weak password -> weakPassword.
  Rate limited -> tooSoon. No session after sign-up (confirmations on) -> notConfirmed. Other -> offline.
  Success -> needsBusinessName (or signedIn if a merchant already exists).
- createMerchant and signOut unchanged. The session stays signed in across restarts.
AuthStatus: signedOut, needsBusinessName, signedIn.
AuthResult: done, invalidUsername, weakPassword, wrongPassword, usernameTaken, notConfirmed, offline, tooSoon.

Functional rules
1. Username: 3 to 20 characters, English lower-case letters, digits and "_". Typed upper case becomes lower case.
2. Password: at least 6 characters, shown as dots.
3. A second fast tap sends one request.
4. Errors show as the red line under the fields; the typed username stays.
5. Passwords are never logged or stored by the app (Supabase keeps only the session).

Acceptance criteria
- flutter analyze: no issues. flutter test passes.
- Unit tests: every AuthResult mapping for signIn and signUp (fake gateway and mock); username rules.
- Widget tests: login with demo/123456 shows হোম; wrong password shows the error; new account goes to the
  business name screen then হোম; taken username shows the error; forgot password shows the help line.
- flutter build apk --release with the dart-defines succeeds.
- Manual: on the real server, create an account in the app, enter a business name, log out, log in again.
