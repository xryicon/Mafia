import {test,expect} from "@playwright/test";
import {cookie,token,playerId} from "../fixtures/identity.mjs";
test("top navigation supports earning, trading and property production",async({page,context,request})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture");
 await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
 await page.goto("/dashboard");await expect(page.getByRole("heading",{level:1})).toHaveText("Your empire.");
 await expect(page.locator(".estate-stats")).toContainText("$10,000");
 await page.getByRole("button",{name:"Complete dock errand",exact:true}).click();
 await expect(page.locator(".game-notice")).toContainText("Dock errand complete");
 await expect(page.locator(".estate-stats")).toContainText("$10,250");
 await expect(page.getByRole("button",{name:/Crew ready in/})).toBeDisabled();
 const nav=page.getByRole("navigation",{name:"Game navigation"});
 await nav.getByRole("link",{name:"Market",exact:true}).click();
 await page.getByRole("button",{name:"Buy lot",exact:true}).click();
 await expect(page.getByRole("dialog")).toBeVisible();await page.getByRole("button",{name:"Confirm purchase"}).click();
 await expect(page.getByRole("dialog")).not.toBeVisible();await expect(page.locator(".estate-stats")).toContainText("$10,050");
 await page.locator(".estate-toolbar").getByRole("link",{name:"Inventory",exact:true}).click();
 await page.getByLabel("Quantity",{exact:true}).fill("2");await page.getByLabel("Price per unit ($)",{exact:true}).fill("120");
 await page.getByRole("button",{name:"Post market offer"}).click();await expect(page.locator(".game-notice")).toContainText("Offer posted");
 await nav.getByRole("link",{name:"Market",exact:true}).click();await page.locator(".own-offers").getByRole("button",{name:"Withdraw"}).click();await expect(page.locator(".own-offers")).toContainText("You haven't listed any goods");
 await nav.getByRole("link",{name:"Properties",exact:true}).click();await page.getByRole("button",{name:"Buy business · $3,000",exact:true}).click();
 await expect(page.getByRole("button",{name:"Production in progress",exact:true})).toBeDisabled();
 await expect(page.locator(".property-deed")).toContainText("Owned by HarborBoss");
 await expect(page.locator(".header-cash")).toContainText("$7,050");
 await page.setViewportSize({width:375,height:812});
 for(const [name,path] of [["Dashboard","/dashboard"],["Market","/market"],["Properties","/properties"],["Districts","/districts"],["Gangs","/gangs"],["Profile","/players/"+playerId]]){
  await nav.getByRole("link",{name,exact:true}).click();await page.waitForURL(url=>url.pathname===path);await expect(page.getByRole("heading",{level:1})).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
 }
 await page.getByLabel("Player menu",{exact:true}).click();await expect(page.getByRole("button",{name:"Log out",exact:true})).toBeVisible();
});
