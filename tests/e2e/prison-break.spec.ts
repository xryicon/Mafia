import {test,expect} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const fixture="http://127.0.0.1:54329";
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated prison fixture");await request.post(fixture+"/__reset_world",{headers:{Authorization:"Bearer "+token}});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});

test("dashboard-styled lock minigame frees an inmate and updates the leaderboard",async({page,request})=>{
 await request.post(fixture+"/__prison_setup",{headers:{Authorization:"Bearer "+token},data:{visitor:true,seconds:600,lockpicks:2}});
 await page.goto("/districts/blackwater-island");
 await expect(page.locator('[data-feature="prison-break-command"]')).toBeVisible();
 await expect(page.getByRole("heading",{name:"Blackwater Island Prison",exact:true})).toBeVisible();
 await expect(page.getByRole("heading",{name:"Inmate intelligence"})).toBeVisible();
 await expect(page.getByText("HarborJack",{exact:true})).toBeVisible();
 await page.getByRole("button",{name:"Plan jailbreak"}).click();
 await expect(page.locator(".prison-lock-head h2")).toHaveText("HarborJack");
 await expect(page.getByRole("img",{name:/Prison lock with lockpick/})).toBeVisible();
 await page.screenshot({path:"test-results/prison-break-lock.png",fullPage:true});
 await page.getByLabel("Lockpick angle").fill("12");
 await page.getByRole("button",{name:"Apply tension"}).click();
 await expect(page.getByRole("heading",{name:"Clean extraction."})).toBeVisible();
 await expect(page.locator(".prison-outcome p:not(.eyebrow)")).toContainText("earned +50 power");
 await expect(page.locator(".prison-leaderboard")).toContainText("HarborBoss");
 await expect(page.locator(".prison-leaderboard")).toContainText("1");
 await page.screenshot({path:"test-results/prison-break-success.png",fullPage:true});
});

test("five failed tensions send the rescuer to prison for the target release time",async({page,request})=>{
 await request.post(fixture+"/__prison_setup",{headers:{Authorization:"Bearer "+token},data:{visitor:true,seconds:600,lockpicks:1}});
 await page.goto("/districts/blackwater-island");await page.getByRole("button",{name:"Plan jailbreak"}).click();
 await page.getByLabel("Lockpick angle").fill("-80");
 for(let move=0;move<5;move++){const button=page.getByRole("button",{name:"Apply tension"});await button.click();if(move<4)await expect(button).toBeEnabled();}
 await expect(page.getByRole("heading",{name:"Serving your sentence"})).toBeVisible();
 await expect(page.getByRole("timer")).toContainText("00:09:");
 await expect(page.getByText(/same remaining time as the inmate/)).toBeVisible();
 await page.setViewportSize({width:375,height:900});
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.screenshot({path:"test-results/prison-break-caught-mobile.png",fullPage:true});
});

test("letting the lock timer expire also sends the rescuer to prison",async({page,request})=>{
 await request.post(fixture+"/__prison_setup",{headers:{Authorization:"Bearer "+token},data:{visitor:true,seconds:600,lockpicks:1}});
 await page.goto("/districts/blackwater-island");await page.getByRole("button",{name:"Plan jailbreak"}).click();
 await request.post(fixture+"/__prison_break_expire",{headers:{Authorization:"Bearer "+token}});
 await page.reload();
 await expect(page.getByRole("heading",{name:"Serving your sentence"})).toBeVisible();
 await expect(page.getByText(/Caught trying to break HarborJack/)).toBeVisible();
});
test("Owner can adjust the power awarded for future breakouts",async({page})=>{
 await page.goto("/owner?section=prison");
 await page.getByLabel("Power awarded on success").fill("125");
 await page.getByRole("button",{name:"Save breakout reward"}).click();
 await expect(page.getByRole("status")).toContainText("Prison-break power reward saved.");
 await expect(page.locator(".prison-reward-control")).toContainText("+125 power");
});




