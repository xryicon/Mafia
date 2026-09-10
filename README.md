# Mafia — Blackwater

## Playable economy

A dark browser strategy game with persistent Supabase-backed cash, respect, businesses, inventory, and player-to-player trading. New characters start with $10,000 in **fictional game currency** and five whiskey crates, awarded once.

- Operations pay $250 / $600 / $1,100 and respect, with shared 60 / 180 / 360 second cooldowns.
- Buy a distillery ($3,000), textile workshop ($5,000), or foundry ($8,000). Production runs in five-minute batches and caps at 24 batches (two hours) between collections.
- Players set their own prices and trade whole lots. Listing stock is held until sold or withdrawn. A sale credits the seller after a 5% fee rounded up to a whole dollar. There are no NPC buyers or seeded market orders.
- The ledger records each player's own actions. Marketplace data refreshes every 30 seconds and after your actions.
- Cash, quantities, fees, cooldowns, and ownership are enforced inside Postgres transactions. Wallets lock in consistent order; an offer can sell only once. Direct client writes are revoked and all tables have RLS.

The migration in `supabase/migrations/20260910205112_mafia_player_economy.sql` was applied to `pyyyceomujtzfzkytizd`. For a different Supabase project, apply it first. `supabase/tests/player_economy.sql` tests trading, conservation, access control, cooldowns, and production in a transaction that rolls back all fixtures.

This is an initial playable economy, not a complete MMO. Rank currently reflects earned respect; crews, combat, territory ownership, banking, and anti-multi-account balancing are not implemented. Currency has no purchase or cash-out flow.

## Authentication and development

A Next.js App Router starter with Supabase email/password authentication and a private dashboard. Responsive cream-and-olive interface, accessible forms, error states, email confirmation, password recovery, logout, and server-enforced access checks.

## Run locally

Use Node.js 22 or newer.

```sh
npm install
cp .env.example .env.local
npm run dev
```

On PowerShell, use `Copy-Item .env.example .env.local` instead of `cp`.
Open http://localhost:3000. The example environment points at **xryicon's Project** (`pyyyceomujtzfzkytizd`) and contains only its browser-safe publishable key. Never substitute a service-role or secret key.

After the first successful install, commit the generated `package-lock.json` and use `npm ci` for reproducible installs.

## Supabase Auth configuration — required before email flows

Open [Auth URL Configuration](https://supabase.com/dashboard/project/pyyyceomujtzfzkytizd/auth/url-configuration).

- Set Site URL to `http://localhost:3000` during development, then your actual HTTPS app origin for production.
- Add these Redirect URLs: `http://localhost:3000/auth/callback` and `http://localhost:3000/auth/callback?next=/update-password`.
- When deploying, add the same two URLs with the production origin.
- Keep email/password sign-up enabled and Confirm email enabled in the Email provider settings.
- Use the standard Confirm signup and Reset password email templates, with their link pointing to `{{ .ConfirmationURL }}`. The SDK sends the appropriate redirect URL. Custom templates must preserve that destination.
- Use a production SMTP provider before public release; Supabase's built-in email delivery has testing restrictions and rate limits.

The app uses PKCE. Open confirmation/reset links in the same browser and device where you requested them. An invalid, expired, or cross-browser link leads to a recoverable login message.

Dashboard settings have **not** been changed by this repository. They must match the origin where you run the app; no production origin has been selected yet.

## Routes

| Route | Access |
| --- | --- |
| `/` | Public landing page |
| `/signup` | Public registration |
| `/login` | Public login |
| `/forgot-password` | Public recovery request |
| `/auth/callback` | PKCE code exchange; accepts only explicit local destinations |
| `/dashboard` | Authenticated user only |
| `/update-password` | Authenticated user only |
| `/api/me` | Returns current user's id/email; anonymous requests return 401 |

Proxy refreshes session cookies and validates claims for navigation. Protected pages and the private API independently call `getUser()` with Supabase to validate the session before returning user data. Proxy redirects preserve refreshed/cleared cookies. Authenticated responses are dynamic and use private/no-store cache headers. Server clients are created per request.

The six `game_*` tables use RLS. Private wallets, inventory, businesses, and ledger entries are only readable by their owner. Active listings and the goods catalog are readable by authenticated players. Mutations go through `game_action`; it accepts an action and validated inputs, never a caller-supplied user ID or balance. Definer implementations live in the unexposed `game_private` schema. `game_state` creates the current user's starter character once and returns their game data.

## Validation

```sh
npm run typecheck
npm test
npm run build
npx playwright install chromium
npm run test:e2e
```

GitHub Actions runs these checks. Tests cover redirect allowlisting, anonymous route protection, forged sessions, private API responses, callback errors, form validation, and mobile overflow. Browser checks do not create users or send email. Database tests create two temporary identities entirely inside a rolled-back transaction. The production database security advisor reported no findings after the migration.

Before release, manually verify with a real inbox:
1. Sign up, confirm the email in the same browser, and reach the dashboard.
2. Log out; dashboard navigation and `/api/me` must deny access.
3. Log in, reload, and confirm the session persists.
4. Request a password reset, follow the link, save a new password, and log in with it.
5. Let the access token expire and confirm refresh preserves the session.
6. Confirm invalid credentials, expired links, and email delivery failures have useful feedback.

## Deployment

Deploy using a host that supports Next.js server rendering (not static GitHub Pages). Set both variables from `.env.example` in the host, run `npm run build`, and start with `npm run start`. Configure Supabase URLs as above. Avoid caching authenticated HTML or Set-Cookie responses at a CDN.


Browser CI builds against a loopback Supabase fixture and tests the signed-in game flows without real accounts or email. The fixture is only started by Playwright when GAME_TEST_FIXTURE=1; it is not an app route, and production continues using the real project values in .env.example. Database correctness is verified separately by the rollback SQL tests. Browser screenshots and traces are saved as GitHub Actions artifacts.


## Cloudflare public auth pages

Login, signup, and password-recovery forms do not run the session-refresh proxy. Protected pages, callbacks, and APIs keep their server-side authentication checks. If both public Supabase variables are absent, the app uses the connected Mafia project's public URL and publishable key. To connect another project, set **both** variables at build time and runtime; partial overrides intentionally produce a configuration error rather than mixing projects. No service-role credentials are bundled.


## Security foundation and City Hall

See [foundation and operations](docs/foundation.md) for deployment, immutable financial history, permissions, moderation, rate limits and logging. Owners and authorized moderators can open City Hall from their game sidebar. Community chat, reports and support tickets are available under Community & support. Gameplay values now come from database settings and can be edited by Owners.

Separate development and staging infrastructure remains deferred. GitHub Actions runs all app and database tests remotely.
