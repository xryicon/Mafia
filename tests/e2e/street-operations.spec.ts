import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const fixture="http://127.0.0.1:54329";
const headers={Authorization:"Bearer "+token};
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixture only");await request.post(fixture+"/__reset_world",{headers});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
async function steal(page:Page){await page.goto("/bin-diving");await page.getByRole("button",{name:/^Enter /}).click();await page.locator('.scav-target[aria-label^="Car"]').first().click();await page.getByRole("button",{name:/^Steal vehicle/}).click();await page.getByRole("button",{name:"Start getaway",exact:true}).click();await expect(page.locator(".scav-workspace")).toHaveClass(/pursued/);}
async function escape(page:Page){await page.getByRole("button",{name:"Drive to escape route"}).click();await page.getByRole("button",{name:"Escape with car",exact:true}).click();}
test("stolen car automatically sells without a garage; pursuit survives reload and map fits mobile",async({page,request})=>{
 await request.post(fixture+"/__street_setup",{headers,data:{street:true,lockpicks:2}});await page.setViewportSize({width:390,height:844});await steal(page);
 await expect(page.getByRole("button",{name:/Fight back/})).toBeDisabled();await expect(page.getByLabel("District",{exact:true})).toBeDisabled();
 await page.reload();await expect(page.locator(".scav-workspace")).toHaveClass(/pursued/);
 const bounds=await page.locator(".scav-action-desk").boundingBox();expect(bounds!.y+bounds!.height).toBeLessThanOrEqual(846);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:"test-results/street-pursuit-mobile.png"});await escape(page);await expect(page.locator(".bin-notice")).toContainText("sold immediately");await expect(page.locator(".street-wallet")).toContainText("$");
});
test("garage owners keep stolen vehicles and can sell exactly once after an interrupted response",async({page,request})=>{
 await request.post(fixture+"/__street_setup",{headers,data:{street:true,lockpicks:2,garage:true}});await page.setViewportSize({width:1600,height:1000});await steal(page);await escape(page);
 await expect(page.locator(".street-vehicle")).toContainText("Dockside Sedan");await expect(page.locator(".street-vehicle")).toContainText("W25");
 let first=true;await page.route("**/rest/v1/rpc/scavenging_action",async route=>{if(route.request().postDataJSON().p_action==="sell_vehicle"&&first){first=false;await route.fetch();await route.abort();}else await route.continue();});
 page.once("dialog",d=>d.accept());await page.getByRole("button",{name:"Sell vehicle",exact:true}).click();await page.getByRole("button",{name:"Retry safely"}).click();await expect(page.locator(".street-vehicle")).toHaveCount(0);await expect(page.locator(".bin-notice")).toContainText("Vehicle sold");
});
test("equipped gun allows a damaging police exchange, while severe injury leads to prison",async({page,request})=>{
 await request.post(fixture+"/__street_setup",{headers,data:{street:true,lockpicks:2,weapon:true}});await steal(page);await page.getByRole("button",{name:/Fight back/}).click();await expect(page.locator(".bin-notice")).toContainText("escaped injured");await expect(page.locator(".street-card").first()).toContainText("70 / 100");
 await request.post(fixture+"/__reset_world",{headers});await request.post(fixture+"/__street_setup",{headers,data:{street:true,lockpicks:2,weapon:true,health:10}});await steal(page);await page.getByRole("button",{name:/Fight back/}).click();await expect(page).toHaveURL(/prison/);
});
test("street events are actionable and the new page uses readable Blackwater artwork",async({page,request})=>{
 await request.post(fixture+"/__street_setup",{headers,data:{street:true,event:"satchel"}});await page.setViewportSize({width:1600,height:1000});await page.goto("/bin-diving");await expect(page.locator(".street-hero")).toHaveCSS("background-image",/street-operations.webp/);await page.screenshot({path:"test-results/street-entry-desktop.png"});
 await page.getByRole("button",{name:/^Enter /}).click();await page.getByRole("button",{name:"Dropped courier satchel",exact:true}).click();await page.getByRole("button",{name:"Investigate opportunity",exact:true}).click();await page.getByRole("button",{name:"Collect search",exact:true}).click();await expect(page.locator(".bin-result")).toContainText("Pickaxe");await expect(page.locator(".street-event-marker")).toHaveCount(0);
});
