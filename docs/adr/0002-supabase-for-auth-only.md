# 2. Clients use Supabase for auth only

*Inferred from code, confirm or correct.*

**Decision.** Clients sign in against Supabase Auth with the publishable key. Every other
request goes to `apps/api` with the Supabase access token as a Bearer token. The API checks the
token with `supabaseAdmin.auth.getUser` on every request (`apps/api/src/lib/auth.ts:48`).

**Evidence.**
- iOS imports only the `Auth` product of supabase-swift.
- Mobile and web contain no `supabase.from`, `.rpc` or `.channel` calls.

**Consequences.**
- Each API request makes a network round trip to Supabase Auth.
- **Sign-up is inconsistent.** iOS uses `POST /auth/sign-up`, which creates the profile and
  identity rows. Mobile and web call `supabase.auth.signUp` directly, which does not.
