import {test,expect} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const base="http://127.0.0.1:54329",headers={Authorization:"Bearer "+token};
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixture");await request.post(base+"/__reset_world",{headers});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
test("online mugging panel shows cost, odds, result and protection on desktop and mobile",async({page,request})=>{
 await request.post(base+"/__robbery_setup",{headers,data:{}});await page.goto("/players");
 await page.getByRole("button",{name:/Mugging — online players/}).click();const dialog=page.getByRole("dialog",{name:"Mugging"});await expect(dialog).toBeVisible();await expect(dialog).toContainText("anywhere in Blackwater");
 await expect(dialog).toContainText("0–100");await expect(dialog).toContainText("100 compatible bullets equipped");await dialog.getByRole("button",{name:/HarborJack/}).click();await expect(dialog).toContainText("63.5%");await page.screenshot({path:"test-results/robbery-desktop.png"});
 await dialog.getByRole("button",{name:"Attempt mugging"}).click();await expect(dialog.locator(".robbery-history")).toContainText("Stole $250");await expect(dialog).toContainText("97 compatible bullets equipped");await expect(dialog.getByRole("button",{name:/HarborJack/})).toBeDisabled();
 for(const width of [1448,768,390,360]){await page.setViewportSize({width,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);expect(await dialog.evaluate(e=>e.scrollWidth<=e.clientWidth)).toBe(true);}
 await page.screenshot({path:"test-results/robbery-mobile.png"});await dialog.getByRole("button",{name:"Close mugging panel"}).click();await expect(dialog).not.toBeVisible();
});
test("interrupted robbery response can retry outside the dialog without repeating the attempt",async({page,request})=>{
 await request.post(base+"/__robbery_setup",{headers,data:{}});await page.goto("/players");
 let body="",calls=0;await page.route("**/rest/v1/rpc/robbery_action",async route=>{calls++;if(calls===1){body=route.request().postData()??"";await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(body);await route.continue();}});
 await page.getByRole("button",{name:/Mugging — online players/}).click();await page.getByRole("dialog",{name:"Mugging",exact:true}).getByRole("button",{name:/HarborJack/}).click();await page.getByRole("button",{name:"Attempt mugging"}).click();await expect(page.getByRole("dialog")).not.toBeVisible();await page.getByRole("button",{name:"Retry safely",exact:true}).click();
 await expect(page.locator(".mugging-notice")).toContainText("Stole $250");await page.getByRole("button",{name:/Mugging — online players/}).click();await expect(page.locator(".robbery-history article")).toHaveCount(1);
});
test("insufficient ammunition blocks attempts and Owner can change bullet ranges",async({page,request})=>{
 await request.post(base+"/__robbery_setup",{headers,data:{ammo:20}});await page.goto("/players");await page.getByRole("button",{name:/Mugging — online players/}).click();await page.getByRole("dialog",{name:"Mugging",exact:true}).getByRole("button",{name:/HarborJack/}).click();await expect(page.getByRole("button",{name:"Attempt mugging"})).toBeDisabled();
 await page.goto("/owner?section=robberies");await page.getByLabel("Minimum bullets used",{exact:true}).fill("2");await page.getByLabel("Maximum bullets used",{exact:true}).fill("10");await page.locator(".robbery-owner form").first().getByLabel("Audit reason").fill("Reduce robbery ammunition range");await page.getByRole("button",{name:"Save mugging rules"}).click();await expect(page.getByRole("status")).toContainText("settings saved");await page.reload();await expect(page.getByLabel("Maximum bullets used",{exact:true})).toHaveValue("10");
});

test("Scavenging no longer exposes mugging",async({page,request})=>{
 await request.post(base+"/__robbery_setup",{headers,data:{}});await page.goto("/bin-diving?district=the-waterfront");await page.getByRole("button",{name:"Enter The Waterfront"}).click();
 await expect(page.getByRole("button",{name:/Mugging|Players ·/})).toHaveCount(0);
});

test("online links and player-row Mug buttons open the selected player",async({page,request})=>{
 await request.post(base+"/__robbery_setup",{headers,data:{}});await page.goto("/players");
 await page.getByRole("link",{name:"View online players",exact:true}).click();await expect(page).toHaveURL(/players\?online=1/);await expect(page.getByLabel("Online only",{exact:true})).toBeChecked();await expect(page.getByRole("link",{name:"IronRose",exact:true})).toHaveCount(0);
 await page.getByRole("button",{name:"Mug HarborJack",exact:true}).click();const dialog=page.getByRole("dialog",{name:"Mugging",exact:true});await expect(dialog.getByRole("heading",{name:"Mug HarborJack?",exact:true})).toBeVisible();
 await dialog.getByRole("button",{name:"Close mugging panel"}).click();await page.getByRole("button",{name:"Mug HarborJack",exact:true}).click();await expect(dialog).toBeVisible();await dialog.getByRole("button",{name:"Close mugging panel"}).click();
 await page.getByLabel("Online only",{exact:true}).uncheck();await expect(page.getByRole("link",{name:"IronRose",exact:true})).toBeVisible();await page.getByRole("button",{name:"Show online players",exact:true}).click();await expect(page.getByRole("link",{name:"IronRose",exact:true})).toHaveCount(0);
 await page.setViewportSize({width:390,height:844});await page.screenshot({path:"test-results/mugging-player-buttons-mobile.png"});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
