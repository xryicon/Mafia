import { test, expect } from "@playwright/test";
import { cookie } from "../fixtures/identity.mjs";

test("player can navigate the game, earn, trade, and buy production", async ({ page, context }) => {
  test.skip(process.env.GAME_TEST_FIXTURE !== "1", "Requires the isolated Supabase fixture, never a real account.");
  await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
  await page.goto("/dashboard");
  await expect(page.getByRole("heading",{level:1})).toHaveText("Your empire.");
  await expect(page.locator(".stats-grid")).toContainText("$10,000");
  await page.screenshot({path:"test-results/blackwater-desktop.png",fullPage:true});
  await page.getByRole("button",{name:"Complete dock errand",exact:true}).click();
  await expect(page.locator(".stats-grid")).toContainText("$10,250");
  await expect(page.getByRole("button",{name:/Crew ready in/})).toBeDisabled();
  const nav=page.getByRole("navigation",{name:"Game navigation"});
  await nav.getByRole("button",{name:"Black market"}).click();
  await page.getByRole("button",{name:"Buy lot",exact:true}).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.getByRole("button",{name:"Confirm purchase"}).click();
  await expect(page.getByRole("dialog")).not.toBeVisible();
  await expect(page.locator(".stats-grid")).toContainText("$10,050");
  await nav.getByRole("button",{name:"Inventory",exact:true}).click();
  await page.getByLabel("Quantity",{exact:true}).fill("2");
  await page.getByLabel("Price per unit ($)",{exact:true}).fill("120");
  await page.getByRole("button",{name:"Post market offer"}).click();
  await expect(page.locator(".game-notice")).toContainText("Offer posted");
  await nav.getByRole("button",{name:"Black market"}).click();
  await page.locator(".own-offers").getByRole("button",{name:"Withdraw"}).click();
  await expect(page.locator(".own-offers")).toContainText("You haven't listed any goods");
  await nav.getByRole("button",{name:"Businesses",exact:true}).click();
  await page.getByRole("button",{name:"Buy business · $3,000",exact:true}).click();
  await expect(page.locator(".stats-grid")).toContainText("$7,050");
  await expect(page.getByRole("button",{name:"Production in progress",exact:true})).toBeDisabled();
  await page.setViewportSize({width:375,height:812});
  for(const name of ["Overview","Operations","Black market","Businesses","Inventory","Ledger"]){
    await nav.getByRole("button",{name,exact:name!=="Black market"}).click();
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
  }
  await nav.getByRole("button",{name:"Overview",exact:true}).click();
  await page.screenshot({path:"test-results/blackwater-mobile.png",fullPage:true});
  await expect(page.getByRole("button",{name:"Log out",exact:true})).toBeVisible();
});
