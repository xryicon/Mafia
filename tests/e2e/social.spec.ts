import {test,expect} from "@playwright/test";
import {cookie} from "../fixtures/identity.mjs";
test("signup reserves a public username and passes it to Auth",async({page})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture");
 await page.goto("/signup");await expect(page.getByLabel("Username",{exact:true})).toHaveAttribute("required","");
 await page.getByLabel("Username",{exact:true}).fill("HarborBoss");await page.getByLabel("Email address").fill("new@example.com");
 await page.getByLabel("New password",{exact:true}).fill("a very long passphrase");await page.getByLabel("Confirm password").fill("a very long passphrase");
 await page.getByRole("button",{name:"Create account"}).click();await expect(page.locator(".auth-panel").getByRole("alert")).toContainText("taken or reserved");
 let submitted:Record<string,any>|undefined;
 await page.route("**/auth/v1/signup*",async route=>{submitted=route.request().postDataJSON();await route.fulfill({status:200,contentType:"application/json",body:JSON.stringify({id:"99999999-9999-4999-8999-999999999999",email:"new@example.com",identities:[],user_metadata:{username:"NewHarborName"}})});});
 await page.getByLabel("Username",{exact:true}).fill("NewHarborName");await page.getByRole("button",{name:"Create account"}).click();
 await expect(page.getByRole("status")).toContainText("Check your email");expect(submitted?.data.username).toBe("NewHarborName");
});
test("reference navigation removes chat and retains account destinations",async({page,context})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture");
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);
 await page.setViewportSize({width:1448,height:1086});await page.goto("/dashboard");
 const nav=page.getByRole("navigation",{name:"Game navigation"});
 await expect(nav.locator("a > span")).toHaveText(["Dashboard","Market","Inventory","Bank","Gangs","Telegrams"]);
 await expect(page.getByRole("complementary",{name:"City chat"})).toHaveCount(0);await expect(page.getByRole("button",{name:/City chat/})).toHaveCount(0);
 await expect(page.locator(".estate-brand .brand-online")).toContainText("2 online");
 await page.getByLabel("Player menu",{exact:true}).click();
 const menu=page.locator(".estate-account-menu");
 for(const name of ["Players & respect","Leaderboards","Seasons","Support","Owner panel"])await expect(menu.getByRole("link",{name,exact:true})).toBeVisible();
 await menu.getByRole("link",{name:"Owner panel",exact:true}).click();await expect(page.getByRole("heading",{name:"Owner panel",exact:true})).toBeVisible();
 await page.setViewportSize({width:375,height:812});await page.goto("/support");await expect(page.getByLabel("Message the city")).toHaveCount(0);
 await expect(nav.getByRole("link")).toHaveCount(6);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
});
test("respect directory keeps global ranks while searching and filtering online",async({page,context})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture");
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);await page.goto("/players");
 const rows=page.getByRole("table").locator("tbody tr");await expect(rows.first()).toContainText("HarborJack");await expect(rows.first()).toContainText("800");
 await page.getByLabel("Search players").fill("IronRose");await page.getByRole("button",{name:"Search",exact:true}).click();await expect(rows).toHaveCount(1);await expect(rows.first()).toContainText("#3");
 await page.getByLabel("Online only").check();await expect(page.getByText("No players match this search.",{exact:true})).toBeVisible();
 await page.setViewportSize({width:375,height:812});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
});

test("existing accounts claim a username before joining the city",async({page,context})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture");
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);
 let claimed=false;
 await page.route("**/rest/v1/rpc/city_status",async route=>{const response=await route.fetch();const data=await response.json();await route.fulfill({response,json:{...data,username:claimed?"ClaimedName":"Rookie-11111111",username_claimed:claimed}});});
 await page.route("**/rest/v1/rpc/claim_username",async route=>{expect(route.request().postDataJSON().candidate).toBe("ClaimedName");claimed=true;await route.fulfill({status:200,contentType:"application/json",body:JSON.stringify({message:"Username saved.",username:"ClaimedName"})});});
 await page.goto("/dashboard");const dialog=page.getByRole("dialog",{name:"Choose your username."});
 await expect(dialog).toBeVisible();await page.keyboard.press("Escape");await expect(dialog).toBeVisible();
 await dialog.getByLabel("Your username",{exact:true}).fill("ClaimedName");await dialog.getByRole("button",{name:"Claim my name",exact:true}).click();
 await expect(dialog).not.toBeVisible();await expect(page.getByRole("heading",{name:"BLACKWATER",exact:true})).toBeVisible();
 await page.unrouteAll({behavior:"wait"});
});
