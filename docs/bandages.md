# Bandages

Bandages and their blueprint use the existing goods catalog, inventory, Medical slot, player market, Owner asset grants and property storage. Find the blueprint while scavenging a bin or successfully opening a car. Learning consumes one blueprint and unlocks the recipe for the current season.

Default recipe: one silk makes five bandages in 60 seconds at an installed crafting station. Owners can change inputs, outputs and time in **Crafting & blueprints**. Default blueprint drop chance is up to 3%, taken only from the empty-result probability; existing prize chances are preserved. Change it in **Bin diving & loot**.

One bandage restores up to 20 health, capped at normal maximum health. Configure `bandage_heal_amount` in **Owner → Economy**. Health at or above the normal maximum consumes nothing. Stored bandages must be retrieved. Both carried and equipped bandages can be used. Each use is server-authoritative, transactional, season-guarded and retry-safe; inventory consumption and health changes retain ledger/audit history.

## Artwork provenance

Generated with the built-in image-generation tool, one square image per item. Originals: `art-source/medical/bandages.png` and `art-source/medical/bandages-blueprint.png`. Optimized WebP copies in `public/art/medical/` at 512, 256 and 96 pixels. No external source image used.

Bandages prompt: Use case: stylized-concept. Create a single square inventory item artwork for Blackwater Mafia, a premium 1920s noir crime economy browser game. Subject: two clean ivory cloth bandage rolls and a neatly folded gauze strip, one roll partly unfurled, on a dark worn charcoal workbench. Close product still life, strong readable silhouette at 96 pixels, centered composition filling most of frame, detailed cloth fibres, warm amber side light and muted copper highlights, blue-black shadows. No blood, wounds, people, branding, letters, numbers, labels, frame, or UI. One finished game asset, square.

Blueprint prompt: Use case: stylized-concept. Create a single square inventory item artwork for Blackwater Mafia, premium 1920s noir crime economy browser game. Subject: a slightly curled aged blue drafting sheet bearing a simple white outline sketch of rolled cloth bandages and folded gauze, tied with a narrow worn copper-colored ribbon, on a dark charcoal workbench. This represents a collectible bandages crafting blueprint. Centered readable item silhouette, close product still life filling most of square, warm amber side lighting, muted copper, blue-black shadows, elegant realistic game artwork. No readable words, letters, numbers, measurements, logos, modern packaging, blood, people, frames, or UI. One finished game asset, square.
