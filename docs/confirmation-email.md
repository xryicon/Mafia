# Blackwater account confirmation

The signup email and confirmation page share the original waterfront artwork, copper button, serif headings and four opportunity cards. The email uses tables, inline styles, JPEG/PNG assets and an Outlook background fallback. Important copy and links remain live text. Normal email-client differences (including blocked images) are expected; the confirmation button remains usable without imagery.

## Flow

The email links to `/auth/confirm?token_hash={{ .TokenHash }}&type=email`. This server route verifies the single-use token with Supabase and sets the session cookie. It removes the token from the URL when redirecting to `/auth/confirmed`. The success page requires a server-verified user with a confirmed email; query parameters never establish confirmation. Expired, used or invalid links get a matching recovery screen. Confirmation also works when the link is opened on a different device from registration.

The existing PKCE callback remains available for older emails and password reset. Signup callbacks lead to the confirmed page; password reset continues to `/update-password`. External redirect destinations remain blocked. Responses use no-store and no-referrer, and confirmation pages are excluded from indexing.

## Hosted configuration

`supabase/config.toml` intentionally declares only the live site URL, three callback allowlist entries and the confirmation template. Review `supabase config diff --project-ref pyyyceomujtzfzkytizd` before applying with `supabase config push`. Deploy the app and assets first, then update the hosted template. Do not change SMTP, email verification requirements, token lifetime, recovery templates or other settings as part of this release.

[Supabase email-template documentation](https://supabase.com/docs/guides/auth/auth-email-templates). New free projects using Supabase's default mail service require custom SMTP before templates can be customized ([platform change](https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier)); a paid plan or existing custom SMTP permits this setting. Preserve the old template/configuration outside the repository before publishing.

## Artwork

Generated with the built-in image-generation tool. Files: `public/art/email/waterfront.jpg` (email), `public/art/email/waterfront.webp` (web). The five PNG icons in the same directory come from Blackwater's existing vector logo and icon paths. All assets are hosted on the game domain.

Prompt:

Use case: stylized-concept. Asset type: text-free hero background for the Blackwater Mafia signup confirmation email and account-confirmed web page. A premium 1920s noir industrial waterfront at night, cinematic painterly realism, tall art-deco downtown buildings glowing with warm amber windows across a harbor, dock cranes framing the left and right, black water reflecting copper lamps, a moored old cargo vessel to the right, wet stone quayside in the near foreground, thick coiled mooring rope and iron bollard at lower right, dramatic midnight clouds and a faint moon behind the skyline. Blue-black, iron, deep charcoal, muted copper and gold palette. Compose a wide landscape image roughly 3:2, with dark open space across the upper left and central left for large ivory serif headings to be overlaid in HTML. Preserve visible harbor details and luminous windows in the center and right, luxurious restrained contrast. The setting is a city whose fortunes are built by trade. No people, no weapons, no letters, no words, no typography, no logos, no borders, no buttons, no interface, no watermarks. This is illustration only, never an email screenshot.
