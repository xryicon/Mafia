import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
async function capture(page:Page,name:string){const data=(await page.screenshot({type:"jpeg",quality:68,fullPage:false,path:"test-results/"+name+".jpg"})).toString("base64");if(process.env.VISUAL_REVIEW==="1")for(let n=0;n<data.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+data.slice(n,n+12000));}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated world");await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);});
test("street properties, prepaid city lease and installed workspace",async({page})=>{
 await page.setViewportSize({width:1536,height:1000});await page.goto("/districts/the-waterfront");
 await expect(page.locator(".dp-cards .dp-card")).toHaveCount(6);
 await expect(page.getByRole("navigation",{name:"District streets"})).toBeVisible();
 await capture(page,"district-properties-desktop");
 await page.getByRole("button",{name:/Warehouse Row/}).click();
 await page.getByLabel("Availability",{exact:true}).selectOption("rent");
 await expect(page.locator(".dp-card")).toHaveCount(2);
 await page.getByRole("button",{name:"View property W25",exact:true}).click();
 const sheet=page.getByRole("dialog",{name:"Plot W25 details"});
 await expect(sheet).toContainText("200 storage units");
 await sheet.getByRole("button",{name:"Lease this property",exact:true}).click();
 await expect(page.locator(".header-cash")).toContainText("$10,000");
 await sheet.getByRole("button",{name:"Confirm city lease",exact:true}).click();
 await expect(sheet).toContainText("Your lease");
 await expect(page.locator(".header-cash")).toContainText("$9,700");
 await sheet.getByRole("button",{name:"Install crafting station",exact:true}).click();
 await sheet.getByRole("button",{name:"Confirm installation",exact:true}).click();
 await expect(sheet).toContainText("No crafting recipes are available yet.");
 await expect(page.locator(".header-cash")).toContainText("$9,200");
 await capture(page,"district-property-workspace");
 await sheet.getByRole("link",{name:/Open secure storage/}).click();
 await expect(page).toHaveURL(/inventory\?building=building-25/);
 await expect(page.locator(".inv-store.selected")).toContainText("W25");
 await expect(page.locator(".inv-store.selected")).toContainText("180 units");
 await expect(page.locator(".inv-store.selected")).toContainText("Crafting station installed");
});
test("mobile property drawer and Owner city rental editor",async({page})=>{
 await page.setViewportSize({width:390,height:844});await page.goto("/districts/the-waterfront");
 await capture(page,"district-properties-mobile");
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await page.getByRole("button",{name:/Warehouse Row/}).click();
 await page.getByRole("button",{name:"View property W26",exact:true}).click();
 const sheet=page.getByRole("dialog",{name:"Plot W26 details"});await expect(sheet).toBeVisible();await expect(sheet).toContainText("2,000 storage units");await capture(page,"district-property-mobile");
 await sheet.getByRole("button",{name:"Close plot details",exact:true}).click();
 await page.goto("/districts/manage?district=the-waterfront");await page.getByLabel("Manage",{exact:true}).selectOption("property_registry");
 await page.getByLabel("Property record",{exact:true}).selectOption("template-25");
 await page.getByLabel("Rent per period ($)",{exact:true}).fill("650");await page.getByLabel("Property audit reason",{exact:true}).fill("Adjust the city garage rental tariff");
 await page.getByRole("button",{name:"Save property listing",exact:true}).click();await expect(page.getByRole("status")).toContainText("Property registry updated");
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);

 await page.getByLabel("Property record",{exact:true}).selectOption("template-7");await page.getByLabel("Property image",{exact:true}).fill("/art/foundry-small.webp");await page.getByLabel("Property audit reason",{exact:true}).fill("Update a property image without offering a city lease");await page.getByRole("button",{name:"Save property listing",exact:true}).click();await expect(page.getByRole("status")).toContainText("Property registry updated");
 await page.goto("/districts/the-waterfront?tab=Overview&plot=plot-25");await expect(page.getByRole("dialog")).toContainText("$650");
});
test("interrupted property response safely retries one payment",async({page})=>{
 await page.goto("/districts/the-waterfront?tab=Overview&plot=plot-25");
 let payload:string|undefined;
 await page.route("**/rest/v1/rpc/property_action",async route=>{if(!payload){payload=route.request().postData()!;await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(payload);await route.continue();}});
 const sheet=page.getByRole("dialog");await sheet.getByRole("button",{name:"Lease this property",exact:true}).click();await sheet.getByRole("button",{name:"Confirm city lease",exact:true}).click();
 await sheet.getByRole("button",{name:"Check action result",exact:true}).click();
 await expect(sheet).toContainText("Your lease");await expect(page.locator(".header-cash")).toContainText("$9,700");
});
