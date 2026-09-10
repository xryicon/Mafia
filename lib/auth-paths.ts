// Explicit destinations keep all post-auth redirects on this app.
export function safeNext(value: unknown): string {
  return value === "/update-password" ? value : "/dashboard";
}

export function isProtectedPage(path: string): boolean {
  return path === "/dashboard" || path.startsWith("/dashboard/") ||
    path === "/update-password";
}
