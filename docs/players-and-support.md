# Player identity and city community

Signup requires a unique username of 3–24 characters. Names start with a letter and allow letters, numbers, underscores and hyphens. Reserved staff names cannot be claimed. The Auth insert trigger reserves names in the same transaction as account creation; its case-insensitive unique index resolves signup races. Editing Auth user metadata cannot change a name or grant a role.

Existing accounts keep their current game state and choose a public name at their next visit. Later changes require an Owner action with the players.rename permission and an audit reason. Names in active offers update; completed financial and archived season records remain preserved.

Online means a player has a recent heartbeat from a valid Auth session. Multiple sessions count once. Logged-out, expired-presence, kicked, banned and deleted players are excluded. Owners can configure presence_window_seconds and chat_poll_seconds under Economy & production. Chat and the count refresh while the page is visible; desktop chat occupies the right rail, while smaller screens use a drawer.

Players are ranked by server-recorded current-season respect. Ties share a rank, and search/online filters preserve the overall rank. Banned/deleted players are excluded from this directory.

Support creates private tickets and displays staff replies. The previous /community route redirects to /support. Public chat is provided by the common city layout and is never included in the support_state response.

The /owner office requires the roles.manage permission on the server. It brings existing economy, roles, grants, seasons, tickets, evidence, chat moderation and audit tools into separate sections. Moderators retain the permission-filtered /staff panel. All mutations continue through guarded database functions.

Validation runs in GitHub Actions, including PostgreSQL migrations and rollback tests, TypeScript, production builds and browser workflows. No production account, season or balance is reset for these tests.
