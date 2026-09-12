# National Bank

The shared game navigation now links to Bank. Districts remain on the dashboard city map and in the account menu.

Players can deposit wallet money and withdraw bank money at `/bank`. Their private statement shows ten records per page, and the seven-day chart shows their real deposits and withdrawals in UTC. Empty accounts show honest empty states. There are no transfer fees or interest. Loans, mortgages and bonds are deferred.

The Owner's existing Economy settings control whether deposits are open and the maximum transfer amount. Pausing deposits leaves withdrawals available. The season must be open for new transfers. The existing permission and audit system governs settings.

## Financial behavior

- Public RPC wrappers authenticate the caller; private functions own account access. Direct account, ledger and request-table access is revoked and RLS is enabled.
- Bank transfers take the existing season and wallet locks before the account lock. Wallet and bank changes occur in one database transaction.
- Every bank balance change creates an immutable bank entry; wallet changes continue to use the existing ledger trigger.
- A caller-scoped request UUID plus the exact payload makes interrupted replies safe to retry. Altered retries fail.
- Amounts, limits, availability, ownership and current funds are validated by the database.
- Banked money counts toward net worth. Wallet cash rankings retain their current meaning.
- New seasons start with zero bank funds. Old accounts, statements and request records remain intact with their original season.
- The interface never claims public vault reserves, interest or credit products that do not exist.

## Validation

GitHub Actions runs the application build, TypeScript checks, browser tests, existing regression tests and an isolated PostgreSQL migration/transaction suite. Bank tests cover deposits, withdrawals, lost replies, conservation, ownership, invalid amounts, settings, failed writes, statement pagination, UTC chart data, real season reset and concurrent double-spend attempts. Browser screenshots cover desktop and mobile. The app is not run locally.

## Artwork

Original scene generated with the built-in image-generation tool, optimized as:
- `public/art/national-bank.webp` (1672 × 941)
- `public/art/national-bank-small.webp` (768 × 432)

Final generation prompt:

> Use case: stylized-concept. Asset type: wide 16:9 hero artwork for the Blackwater Mafia browser game National Bank page. Create a cinematic, premium 1920s noir waterfront city scene at night: a monumental NATIONAL BANK with tall neoclassical stone columns, heavy bronze doors and warm amber-lit windows stands on the right two-thirds, seen from street level at a slight angle. On the left third leave a naturally darker area of harbor skyline, dock cranes and atmospheric blue-black mist with room for live website heading text. Wet cobblestones reflect copper and gold gas lamps, a few small period cars and distant pedestrians give scale. Deep charcoal iron tones, muted blue-black shadows, restrained copper and warm gold accents. Extremely detailed realistic painterly game concept art consistent with the existing Blackwater harbor and foundry artwork. The impressive bank facade is the focus. Integrated carved facade lettering may read exactly 'NATIONAL BANK'; no other text, no UI panels, no charts, no buttons, no border, no logos or watermark. This is original scene artwork, not a screenshot or a mockup. Wide composition, 1536x1024 or a wider landscape format.

The heading, account numbers, buttons and chart are live interface elements over the artwork.
