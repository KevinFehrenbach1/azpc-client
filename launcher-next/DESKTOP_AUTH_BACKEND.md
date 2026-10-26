# AZPC Desktop Browser Sign-In — Backend Contract

Launcher 1.0.3 contains the desktop client half of system-browser OAuth. **It cannot complete login until the AZPC website backend implements these endpoints.**

## GET /desktop-auth/authorize
Query: `redirect_uri` (loopback 127.0.0.1 ephemeral port), `state`, `code_challenge`, `code_challenge_method=S256`.
Require a logged-in AZPC web session, or redirect to existing Google/Discord login. Verify callback URI uses 127.0.0.1 and the exact registered loopback path; do not accept arbitrary external redirect domains. Generate a cryptographically random, single-use authorization code, store only its hash and PKCE challenge server-side with a short expiration. Redirect to loopback `/callback?code=...&state=...`.

## POST /api/desktop-auth/exchange
JSON: `{code,code_verifier,redirect_uri}`. Atomically consume the code, validate expiry, redirect URI and S256 verifier, and issue a short-lived AZPC-scoped access token. Response: `{access_token,user:{id,displayName,email,provider}}`. Rate-limit requests and never expose Google/Discord provider tokens.

## Follow-up production requirements
Implement refresh token rotation and OS-protected token storage (Windows DPAPI or Electron safeStorage), account /me and logout/revocation endpoints. Launcher currently retains the AZPC access token **only in process memory**, so it is not yet a persistent sign-in. Never store provider passwords. Do not advertise automatic login as complete until backend endpoints and full browser-to-launcher testing pass.
