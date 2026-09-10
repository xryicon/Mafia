# Foundation and operations

Production is the existing Cloudflare Worker and Supabase project. Separate development and staging infrastructure is deferred by the Owner. CI uses an isolated PostgreSQL 17 container and a browser-only Supabase fixture; no local app execution is required.

## Deployment
Keep the existing Cloudflare GitHub integration for main. Cloudflare's automatic Next.js configuration prepares the Worker with its supported adapter. Public environment values must be supplied as a pair; production also has paired public defaults. No service-role key is shipped. NEXT_PUBLIC_APP_ENV permits production, development, staging, test and prevents non-production builds from connecting to the production project.

Apply versioned Supabase migrations in filename order through the Supabase migration tool or CLI before publishing frontend code that depends on them. Never reset production. Run supabase/seed.sql after migrations; it only adds missing Player roles. CI applies all migrations to a blank PostgreSQL database and runs the seed twice to check rerun safety.

## Initial Owner
Owner assignment is an explicit operator step for an already verified Auth email. It is never based on registration order or browser input. The authorized initial account is assigned on the connected database, separately from reusable migrations. Subsequent assignments use City Hall. Removing the final Owner is rejected.

## Authorization and sessions
All economic and staff mutations execute within PostgreSQL transactions. Clients cannot update wallets, stock, ownership, permissions or evidence directly. Restricted REST reads additionally check account sanctions and session revocation. A session kick blocks the existing session, including refreshed JWTs, by comparing its Supabase session creation time with the revocation cutoff. A new login creates an eligible session. Bans block game access even if an Auth JWT has not expired.

Moderator permissions are live database mappings. Sensitive economy, grants, role management, audit access and future season reset capability are Owner-only. There is no destructive season reset endpoint.

## Financial and moderation history
A wallet trigger records every inserted balance and balance change with before/delta/after amounts. Existing wallets receive a clearly labeled migration opening balance; original events are retained rather than reconstructed. Ledger, event and audit mutations/deletions/truncation are rejected. Auth/player deletions cannot cascade financial records. Chat and cases use soft deletion; sanctions use revocation. Evidence and audit snapshots remain available to authorized staff.

## Rate limits and logging
A shared database minute bucket enforces gameplay and staff action limits and community posting limits. Failed action attempts count because error handling rolls back only the inner action, retaining the limiter update. Game cooldowns are an additional rule. Supabase Auth handles signup/login throttling; configure stricter Auth limits and CAPTCHA in Supabase if needed for public launch.

Next.js instrumentation emits structured server error records without request bodies, cookies, authorization headers or query strings. Unexpected database action failures emit SQLSTATE and action category through PostgreSQL logs. Inspect Cloudflare Worker logs and Supabase PostgreSQL logs for incidents. No external logging vendor is required.

## Verification
GitHub Actions checks TypeScript, unit tests, production build, browser workflows, migration/seed repeatability and SQL economic/authorization tests. PostgreSQL CI uses a minimal Auth identity contract, so real Supabase Auth token issuance is not mocked as proven. Connected-database rollback tests additionally verify the production schema. Browser fixtures never ship as app routes.

Supabase security advisor reports the new tables as RLS-enabled with no policies: this is intentional deny-by-default access, with all client grants revoked and permission-checked RPCs providing access. Its existing [leaked-password protection recommendation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) is an Auth project setting outside the app migration; it remains disabled.
