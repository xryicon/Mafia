// Explicit destinations keep all post-auth redirects on this app.
export function safeNext(value: unknown): string {
  return (value === "/update-password" || value === "/staff" || value === "/community" || value === "/seasons") ? value : "/dashboard";
}

export function isProtectedPage(path: string): boolean {
  return path === "/dashboard" || path.startsWith("/dashboard/") ||
    path === "/seasons" || path.startsWith("/seasons/") || path === "/players" || path.startsWith("/players/") || path === "/update-password" || path === "/staff" || path.startsWith("/staff/") || path === "/community" || path.startsWith("/community/");
}
