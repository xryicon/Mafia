import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
async function capture(page:Page,name:string){const data=(await page.screenshot({type:"jpeg",quality:65,fullPage:false,path:"test-results/"+name+".jpg"})).toString("base64");if(process.env.VISUAL_REVIEW==="1")for(let n=0;n<data.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+data.slice(n,n+12000));}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated test world");await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);});
test("city atlas, district tabs and linked property purchase",async({page})=>{
 await page.setViewportSize({width:1448,height:1086});await page.goto("/districts");await expect(page.getByRole("heading",{name:"Control the city."})).toBeVisible();await capture(page,"district-city-desktop");
 await page.getByRole("link",{name:"View District"}).click();await expect(page).toHaveURL(/the-waterfront/);await expect(page.getByRole("tab")).toHaveCount(7);await capture(page,"district-overview-desktop");
 await page.getByRole("tab",{name:"Businesses",exact:true}).click();await page.getByLabel("Search",{exact:true}).fill("Telegram");await expect(page.locator(".district-business-card")).toHaveCount(1);await page.locator(".district-business-card").click();await expect(page.getByRole("button",{name:"Plot W06",exact:false})).toHaveAttribute("aria-pressed","true");
 await page.getByRole("button",{name:"Close plot details",exact:true}).click();
 await page.getByRole("button",{name:"Plot W07 · available",exact:true}).click();await capture(page,"district-plot-desktop");
 await page.getByRole("button",{name:"Watch plot",exact:false}).click();await expect(page.getByRole("button",{name:"Watching",exact:false})).toBeVisible();
 await page.getByRole("button",{name:"Buy Plot",exact:true}).click();await page.getByRole("button",{name:"Confirm purchase",exact:true}).click();
 await expect(page.locator(".desktop-plot-details")).toContainText("Your property");await expect(page.locator(".header-cash")).toContainText("$3,305");
 for(const tab of ["Resources","Market","Territory","Activity"]){await page.getByRole("tab",{name:tab,exact:true}).click();await expect(page.getByRole("tabpanel")).toBeVisible();}
 await page.getByLabel("Event category").selectOption("property");await expect(page.locator(".district-events")).toContainText("W07 sold");
});
test("mobile bottom sheet, map controls and Owner district editing",async({page})=>{
 await page.setViewportSize({width:375,height:812});await page.goto("/districts/the-waterfront?tab=Plots");
 await page.getByRole("button",{name:"Zoom in",exact:true}).click();await page.getByRole("button",{name:"Fit map",exact:true}).click();
 await page.getByRole("button",{name:"Plot W14 · available",exact:true}).click();const sheet=page.getByRole("dialog",{name:"Plot W14 details"});await expect(sheet).toBeVisible();await capture(page,"district-plot-mobile");
 await sheet.getByRole("button",{name:"Close plot details"}).click();await expect(sheet).not.toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.goto("/districts/manage?district=the-waterfront");await page.getByLabel("Tagline",{exact:true}).fill("The harbour belongs to the bold.");await page.getByLabel("Reason for this change").fill("Update the district welcome text");await page.getByRole("button",{name:"Save changes",exact:true}).click();await expect(page.getByRole("status")).toContainText("recorded in the audit");
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await capture(page,"district-owner-mobile");
});

test("funded buy orders reserve and refund cash in the existing market",async({page})=>{
 await page.goto("/market?district=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
 const book=page.locator(".district-order-book");
 await book.getByLabel("Units wanted").fill("2");await book.getByLabel("Your unit price").fill("100");await book.getByRole("button",{name:"Fund buy order"}).click();
 await expect(book.getByRole("status")).toContainText("funded and posted");await expect(page.locator(".header-cash")).toContainText("$9,800");
 await book.getByRole("button",{name:"Cancel & refund"}).click();await expect(page.locator(".header-cash")).toContainText("$10,000");
 await expect(book.getByRole("status")).toContainText("Funds returned");
});
