// Explicit destinations keep post-auth redirects on this app.
const destinations = ["/refineries", "/bin-diving", "/telegrams", "/ledger", "/dashboard", "/market", "/properties", "/districts", "/gangs", "/profile", "/update-password", "/staff", "/owner", "/community", "/support", "/seasons", "/players", "/account"];
export function safeNext(value: unknown): string {
  return typeof value === "string" && destinations.includes(value) ? value : "/dashboard";
}
export function isProtectedPage(path: string): boolean {
  return destinations.some(destination => path === destination || path.startsWith(destination + "/"));
}
