import {test,expect} from "@playwright/test";
import {cookie} from "../fixtures/identity.mjs";
test("signup reserves a public username and passes it to Auth",async({page})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture");
 await page.goto("/signup");await expect(page.getByLabel("Username",{exact:true})).toHaveAttribute("required","");
 await page.getByLabel("Username",{exact:true}).fill("HarborBoss");await page.getByLabel("Email address").fill("new@example.com");
 await page.getByLabel("New password",{exact:true}).fill("a very long passphrase");await page.getByLabel("Confirm password").fill("a very long passphrase");
 await page.getByRole("button",{name:"Create account"}).click();await expect(page.getByRole("alert")).toContainText("taken or reserved");
 let submitted:Record<string,any>|undefined;
 await page.route("**/auth/v1/signup*",async route=>{submitted=route.request().postDataJSON();await route.fulfill({status:200,contentType:"application/json",body:JSON.stringify({id:"99999999-9999-4999-8999-999999999999",email:"new@example.com",identities:[],user_metadata:{username:"NewHarborName"}})});});
 await page.getByLabel("Username",{exact:true}).fill("NewHarborName");await page.getByRole("button",{name:"Create account"}).click();
 await expect(page.getByRole("status")).toContainText("Check your email");expect(submitted?.data.username).toBe("NewHarborName");
});
test("named city chat persists across pages and refreshes in another window",async({page,context})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture");
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);
 await page.setViewportSize({width:1600,height:1000});await page.goto("/dashboard");
 const chat=page.getByRole("complementary",{name:"City chat"});
 await expect(chat).toBeVisible();await expect(chat.getByRole("link",{name:"HarborJack",exact:true})).toBeVisible();
 await expect(page.locator(".city-status-row")).toContainText("2 online");
 expect((await chat.boundingBox())!.x).toBeGreaterThanOrEqual(1290);
 const other=await context.newPage();await other.setViewportSize({width:1440,height:900});await other.goto("/support");
 await page.getByRole("navigation",{name:"City navigation"}).getByRole("link",{name:"Leaderboards",exact:true}).click();
 await expect(chat).toBeVisible();await page.getByLabel("Message the city").fill("A new deal at the docks");await chat.getByRole("button",{name:"Send",exact:false}).click();
 const message=chat.locator("article").filter({hasText:"A new deal at the docks"});await expect(message.getByRole("link",{name:"HarborBoss",exact:true})).toBeVisible();
 await expect(other.getByRole("log").getByText("A new deal at the docks",{exact:true})).toBeVisible({timeout:10000});
 await message.getByRole("button",{name:/Remove your message/}).click();await expect(other.getByRole("log").getByText("A new deal at the docks",{exact:true})).toHaveCount(0,{timeout:10000});await other.close();
 await page.setViewportSize({width:375,height:812});await expect(chat).not.toBeVisible();
 await page.getByRole("button",{name:/City chat/}).click();await expect(chat).toBeVisible();await page.getByRole("button",{name:"Close city chat",exact:true}).click();await expect(chat).not.toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
});
test("respect directory keeps global ranks while searching and filtering online",async({page,context})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture");
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);await page.goto("/players");
 const rows=page.getByRole("table").locator("tbody tr");await expect(rows.first()).toContainText("HarborJack");await expect(rows.first()).toContainText("800");
 await page.getByLabel("Search players").fill("IronRose");await page.getByRole("button",{name:"Search",exact:true}).click();await expect(rows).toHaveCount(1);await expect(rows.first()).toContainText("#3");
 await page.getByLabel("Online only").check();await expect(page.getByText("No players match this search.",{exact:true})).toBeVisible();
 await page.setViewportSize({width:375,height:812});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
});
