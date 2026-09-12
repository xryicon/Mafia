import { test, expect } from "@playwright/test";

test("public landing page and sign-up are accessible", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Every fortune");
  await page.getByRole("link", { name: "Enter Blackwater", exact: true }).click();
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Make your name.");
  await expect(page.getByLabel("Email address")).toBeVisible();
  await expect(page.getByLabel("Confirm password")).toBeVisible();
});
test("private pages redirect anonymous visitors to login", async ({ page }) => {
  for (const path of ["/bank", "/dashboard", "/dashboard/private", "/update-password", "/players", "/owner", "/support", "/account", "/seasons", "/market", "/properties", "/districts", "/gangs", "/profile", "/telegrams", "/ledger"]) {
    await page.goto(path);
    await expect(page).toHaveURL(/\/login\?next=/);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Welcome back, boss.");
  }
});
test("private API rejects anonymous and forged sessions", async ({ request }) => {
  for (const cookie of ["", "sb-pyyyceomujtzfzkytizd-auth-token=forged"]) {
    const response = await request.get("/api/me", { headers: { cookie } });
    expect(response.status()).toBe(401);
    expect(await response.json()).toEqual({ error: "Unauthorized" });
    expect(response.headers()["cache-control"]).toContain("no-store");
  }
});
test("callback rejects missing or invalid codes and external destinations", async ({ page }) => {
  await page.goto("/auth/callback?next=https://evil.example");
  await expect(page).toHaveURL(/\/login\?error=invalid-link$/);
  await expect(page.getByRole("status")).toContainText("invalid or expired");
  await page.goto("/auth/callback?code=invalid&next=//evil.example");
  await expect(page).toHaveURL(/\/login\?error=invalid-link$/);
});
test("sign-up catches mismatched passwords before submitting", async ({ page }) => {
  await page.goto("/signup");
  await page.getByLabel("Username",{exact:true}).fill("NewHarborPlayer");
  await page.getByLabel("Email address").fill("example@example.com");
  await page.getByLabel("New password", { exact: true }).fill("a long passphrase one");
  await page.getByLabel("Confirm password").fill("a long passphrase two");
  await page.getByRole("button", { name: "Create account" }).click();
  await expect(page.locator("form").getByRole("alert")).toContainText("both passwords match");
});
test("mobile layout stays within the viewport", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  for (const path of ["/", "/login", "/signup", "/forgot-password"]) {
    await page.goto(path);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  }
});
