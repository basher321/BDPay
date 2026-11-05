# Plan 16 Username and password login

1. core/validators.dart: normalizeUsername, isValidUsername (^[a-z0-9_]{3,20}$), usernameToEmail
   (<u>@users.bdpay.app), usernameOf(email) (strips the internal domain), minPasswordLength = 6.
2. domain/account_enums.dart: AuthStatus without codeSent; AuthResult as in the spec.
3. AuthRepository: signIn / signUp replace sendCode / verifyCode.
4. data/supabase/gateway_errors.dart: AuthFailure badRequest, rateLimited, wrongPassword, userExists,
   weakPassword, notConfirmed, other. auth_gateway.dart: authFailureOf maps Supabase codes
   (invalid_credentials, user_already_exists / email_exists, weak_password, email_not_confirmed, 429).
   AuthGateway.signIn / signUp (signUp without a session throws notConfirmed).
5. SupabaseAuthRepository and MockAuthRepository implement the new contract. Mock keeps passwords in memory;
   demo / 123456 is built in.
6. features/auth/login_screen.dart (new) replaces email_screen.dart, code_screen.dart and
   widgets/resend_countdown.dart (removed). app_shell.dart: signedOut -> LoginScreen.
7. l10n: new strings, old email/code strings removed; flutter gen-l10n.
8. Settings account row: "ইউজারনেম" with usernameOf(email).
9. Tests updated; analyze, test, release build.
