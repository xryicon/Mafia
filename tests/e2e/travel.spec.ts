import {test,expect} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const base="http://127.0.0.1:54329",headers={Authorization:"Bearer "+token};
test.beforeEach(async({request,context})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixture");await request.post(base+"/__reset_world",{headers});await request.post(base+"/__travel_setup",{headers,data:{heat:32,car:true}});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);});
test("dashboard shows personal heat and district entry requires a timed journey",async({page,request})=>{
 await page.goto("/dashboard");await expect(page.getByRole("meter",{name:"Your district heat"})).toHaveAttribute("aria-valuenow","32");
 await page.goto("/districts/old-town");const gate=page.getByRole("region",{name:"District travel"});await expect(gate).toBeVisible();await expect(gate.getByRole("button",{name:/Drive/})).toBeDisabled();
 await gate.getByRole("button",{name:/Buy 10 fuel/}).click();await expect(gate.getByRole("combobox")).toContainText("10/100 fuel");await gate.getByRole("button",{name:/Drive/}).click();await expect(gate.getByRole("timer")).toBeVisible();
 await page.reload();await expect(gate.getByRole("timer")).toBeVisible();
 const state=await(await request.post(base+"/rest/v1/rpc/travel_state",{headers,data:{}})).json();expect(state.vehicles[0].fuel).toBe(5);
 await page.goto("/dashboard");await expect(page.locator(".command-location")).toContainText("The Waterfront");await request.post(base+"/__travel_setup",{headers,data:{arrive:true}});await page.evaluate(()=>window.dispatchEvent(new Event("focus")));await expect(page.locator(".command-location")).toContainText("Old Town");
 await page.goto("/dashboard");await expect(page.locator(".command-location")).toContainText("Old Town");await expect(page.locator(".command-location")).not.toContainText("The Waterfront");await page.reload();await expect(page.locator(".command-location")).toContainText("Old Town");await page.setViewportSize({width:390,height:844});await expect(page.locator(".command-location")).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
test("phone travel choices show train fare and free walking",async({page})=>{await page.setViewportSize({width:390,height:844});await page.goto("/districts/old-town");const gate=page.getByRole("region",{name:"District travel"});await expect(gate.getByRole("button",{name:/Train/})).toContainText("$50");await expect(gate.getByRole("button",{name:/Walk/})).toContainText("Free");expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:"test-results/district-travel-mobile.jpg",type:"jpeg"});});
