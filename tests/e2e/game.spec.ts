import {test,expect} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";

test("market trading remains usable alongside blank game destinations",async({page,context,request})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture");
 await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
 await page.goto("/market");
 await expect(page.locator(".estate-stats")).toContainText("$10,000");
 await page.getByRole("button",{name:"Buy lot",exact:true}).click();
 await expect(page.getByRole("dialog")).toBeVisible();await page.getByRole("button",{name:"Confirm purchase"}).click();
 await expect(page.getByRole("dialog")).not.toBeVisible();await expect(page.locator(".estate-stats")).toContainText("$9,800");
 await page.locator(".estate-toolbar").getByRole("link",{name:"Inventory",exact:true}).click();
 await page.getByLabel("Quantity",{exact:true}).fill("2");await page.getByLabel("Price per unit ($)",{exact:true}).fill("120");
 await page.getByRole("button",{name:"Post market offer"}).click();await expect(page.locator(".game-notice")).toContainText("Offer posted");
 const nav=page.getByRole("navigation",{name:"Game navigation"});
 await nav.getByRole("link",{name:"Market",exact:true}).click();
 await page.locator(".own-offers").getByRole("button",{name:"Withdraw"}).click();
 await expect(page.locator(".own-offers")).toContainText("You haven't listed any goods");
 await expect(page.locator(".header-cash")).toContainText("$9,800");
 await page.setViewportSize({width:375,height:812});
 for(const [name,path] of [["Dashboard","/dashboard"],["Properties","/properties"],["Districts","/districts"],["Telegrams","/telegrams"]]){
  await nav.getByRole("link",{name,exact:true}).click();await page.waitForURL(url=>url.pathname===path);
  await expect(page.getByRole("main").locator(".fresh-canvas")).toBeVisible();
  await expect(page.getByRole("main").locator("button,a,input,img,article,table,.estate-hero")).toHaveCount(0);
  await expect(nav.getByRole("link",{name,exact:true})).toHaveAttribute("aria-current","page");
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 }
 await page.getByLabel("Player menu",{exact:true}).click();
 await page.getByRole("link",{name:"Financial history",exact:true}).click();
 await expect(page).toHaveURL(/\/ledger$/);
 await expect(page.getByRole("heading",{level:1})).toHaveText("Follow the money.");
 await page.getByLabel("Player menu",{exact:true}).click();
 await expect(page.getByRole("button",{name:"Log out",exact:true})).toBeVisible();
});
