export const USERNAME_PATTERN = "^[A-Za-z][A-Za-z0-9_\\-]{2,23}$";
const reserved = new Set(["owner", "admin", "administrator", "moderator", "blackwater", "system", "support"]);
export function usernameError(value: string): string | null {
  const name = value.trim();
  if (!new RegExp(USERNAME_PATTERN).test(name)) return "Use 3–24 letters, numbers, underscores or hyphens. Start with a letter.";
  if (reserved.has(name.toLowerCase()) || /^(Rookie|Player)-/i.test(name)) return "That name is reserved. Choose another username.";
  return null;
}
