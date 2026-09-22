# Scavenging controls

Scavenging opens the first-person view automatically. Select a district to enter; the loading overlay remains until movement and scene assets are ready. Aerial mode remains available, including `?view=aerial` for direct access.

- WASD / arrows: walk; Shift: sprint.
- Q / R: lean left/right (E remains interact).
- C: toggle crouch; Space: jump.
- 1–6 / mouse wheel: select equipment slot. Selection changes the held view model, not ownership or inventory quantities.
- Tab: open the existing inventory and equipment interface inside street view.
- F / left click: punch a nearby player or police target in front of you.

Crouch, jump and lean are presentation stances on the existing collision-checked ground movement. They do not grant a speed boost, let players cross buildings, or evade server police checks.

Completed bin/car searches automatically invoke the existing guarded finish action. Rewards, limits, cooldowns, inventory capacity and police checks remain authoritative. Interrupted replies retain the existing safe retry mechanism. Car theft retains its explicit getaway button.

Melee uses `scavenging_melee_*` Owner settings. A transaction verifies active season, online street presence, district, range, clear path, cooldown and armour. Player damage is nonlethal, with short victim protection; police retaliate and start a pursuit. No ammunition or cash is consumed. Request replay cannot apply damage twice. Combat and incoming hits are retained in street history.

Apply `20260923010000_street_melee.sql` before deploying melee UI. Validate through GitHub CI; local app/test execution is not authorized for this task.
