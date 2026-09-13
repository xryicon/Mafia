import {test,expect} from "@playwright/test";
import {cookie,token,playerId} from "../fixtures/identity.mjs";
const fixture="http://127.0.0.1:54329";
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated prison fixture");await request.post(fixture+"/__reset_world",{headers:{Authorization:"Bearer "+token}});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
test("island is the prison district and works on desktop and mobile",async({page})=>{
 await page.goto("/districts/blackwater-island");await expect(page.getByRole("heading",{name:"Blackwater Island",exact:true})).toBeVisible();await expect(page.getByRole("heading",{name:"Blackwater Island Prison",exact:true})).toBeVisible();
 for(const width of [1440,375]){await page.setViewportSize({width,height:1000});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:"test-results/prison-visitor-"+width+".png",fullPage:true});}
});
test("jailed players stay on the island across navigation, refresh and release",async({page,request})=>{
 await request.post(fixture+"/__prison_setup",{headers:{Authorization:"Bearer "+token},data:{seconds:600}});
 await page.goto("/dashboard");await expect(page).toHaveURL(/districts\/blackwater-island$/);await expect(page.getByRole("heading",{name:"Serving your sentence"})).toBeVisible();await expect(page.getByRole("timer")).toContainText("00:09:");
 await page.reload();await expect(page.getByRole("heading",{name:"Serving your sentence"})).toBeVisible();
 for(const path of ["/districts/the-waterfront","/districts/mines-and-quarries","/shooting-range","/market"]){await page.goto(path);await expect(page).toHaveURL(/districts\/blackwater-island$/);}
 await page.setViewportSize({width:375,height:900});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:"test-results/prison-custody-mobile.png",fullPage:true});
 await page.getByRole("link",{name:"Contact support"}).click();await expect(page).toHaveURL(/support$/);
 await page.goto("/districts/blackwater-island");
 await request.post(fixture+"/__prison_setup",{headers:{Authorization:"Bearer "+token},data:{seconds:-1}});
 await page.getByRole("button",{name:"Check prison status"}).click();await expect(page.getByRole("heading",{name:"You’re free to leave."})).toBeVisible();await page.getByRole("link",{name:"Return to the city"}).click();await expect(page).toHaveURL(/dashboard$/);
});
test("countdown confirms automatic release and Owner can sentence and release",async({page,request})=>{
 await request.post(fixture+"/__prison_setup",{headers:{Authorization:"Bearer "+token},data:{seconds:3}});
 await page.goto("/districts/blackwater-island");await expect(page.getByRole("heading",{name:"You’re free to leave."})).toBeVisible({timeout:10000});
 await page.goto("/owner?section=prison");await page.getByLabel("Player",{exact:true}).selectOption(playerId);await page.getByLabel("Sentence (minutes)").fill("10");await page.getByLabel("Reason for imprisonment").fill("Prison browser test");await page.getByRole("button",{name:"Send to Blackwater Island"}).click();await expect(page.locator(".prison-register")).toContainText("Prison browser test");
 await page.screenshot({path:"test-results/prison-owner.png",fullPage:true});
 await page.getByLabel("Reason for early release").fill("Release browser test");await page.getByRole("button",{name:"Release player",exact:true}).click();await expect(page.locator(".prison-register")).toContainText("No players are currently in custody.");
 await page.goto("/dashboard");await expect(page).toHaveURL(/dashboard$/);
});

