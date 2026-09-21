# Player robberies

Open **Scavenging → enter a district → Players**. Players must both have recently polled that district’s Scavenging view and be stationary, outside searches, active range sessions and prison. An equipped, working gun is required. The matching ammunition must be equipped in Ammo. All checks repeat on the server under the existing season/economy/custody lock order.

## Default rules

- Successful robbery takes 1–80% of the victim’s carried wallet cash. Bank accounts, inventory and property storage are never debited.
- Randomly consume 0–100 compatible bullets, including failures. The full maximum must be equipped before an attempt. Zero means intimidation without firing. Gun wear uses the existing per-shot weapon rule; magazines are reduced accordingly.
- Every valid attempt protects the victim from **all attackers** for 30 minutes. The attacker has a separate five-minute cooldown. Invalid requests consume nothing and grant no protection.
- Base success: 50%. Relative Sharpshooting levels contribute up to 20 percentage points, saved advanced bullseye accuracy up to 20, relative power up to 30, and attacker equipment versus defender equipment up to 20. Final odds are clamped to 5–95%.
- Skill difference is normalized over 19 level steps. Accuracy difference is divided by 100. Power difference is divided by the two powers’ sum (at least one). Equipment attack minus defense is divided by their sum (at least one). Equipment bonuses scale with condition and count once per equipped slot, excluding ammunition and medical supplies.
- Existing guns start with attack/defense 20/10 for the homemade pistol and 35/20 for the M4. Future equippable items can receive bonuses through Owner controls. No new items are created.
- No direct health damage, XP reward, stolen gear or new police behavior is introduced.

**Owner → Player robberies** manages enablement, bullet ranges, theft percentages (always within 1–80%), both cooldowns, presence window, chance factors and equipment bonuses. Changes require an audit reason and version check. Moderator access is not automatic.

## Accounting and security

Cash transfer, ammunition, wear, history and cooldowns commit in one transaction. Both wallet legs use the existing ledger writer. Each accepted request retains its payload, rolled outcome, factor snapshot and rules. Retrying returns the same outcome. Concurrent attackers share the victim protection lock. Target cash and health are not exposed by the player list. For low wallet amounts, integer transfers stay inside the configured percentage range; impossible ranges reject the attempt.

All records are seasonal; old outcomes are immutable and retained. New seasons naturally start with no robbery cooldown or current-season history. Existing wallets, bank deposits and gear are not changed by installing the feature.

Database tests cover authorization, stale rules, eligibility, bank isolation, cash conservation, retries, rollback, ammunition, weapon wear, factors and concurrent attackers. Browser tests cover confirmation, responsive layout, insufficient ammunition, Owner settings and interrupted replies.
