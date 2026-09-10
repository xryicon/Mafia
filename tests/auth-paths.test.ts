import { strict as assert } from "node:assert";
import { test } from "node:test";
import { safeNext, isProtectedPage } from "../lib/auth-paths";

test("only explicitly allowed local destinations survive redirects", () => {
  assert.equal(safeNext("/update-password"), "/update-password");
  for (const value of [undefined, null, "", "/dashboard", "//evil.example", "https://evil.example", "/\\evil.example", "%2f%2fevil.example", "/auth/callback", ["/update-password"]]) {
    assert.equal(safeNext(value), "/dashboard");
  }
});
test("dashboard descendants and password changes require authentication", () => {
  for (const path of ["/dashboard", "/dashboard/private", "/update-password"]) assert.ok(isProtectedPage(path));
  for (const path of ["/", "/login", "/signup", "/forgot-password", "/auth/callback", "/dashboard-other"]) assert.equal(isProtectedPage(path), false);
});
