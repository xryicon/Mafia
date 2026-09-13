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

test("Your properties and leases finds holdings across streets and survives reload",async({page})=>{
 await page.goto("/districts/the-waterfront?view=mine");
 const mine=page.getByRole("navigation",{name:"Property views"}).getByRole("button",{name:/Your properties & leases/});
 await expect(mine).toHaveAttribute("aria-pressed","true");await expect(page.locator(".dp-cards .dp-card")).toHaveCount(0);await expect(page.locator(".dp-empty")).toContainText("No properties here yet");
 await page.goto("/districts/the-waterfront?plot=plot-25");
 const sheet=page.getByRole("dialog",{name:"Plot W25 details"});
 await sheet.getByRole("button",{name:"Lease this property",exact:true}).click();await sheet.getByRole("button",{name:"Confirm city lease",exact:true}).click();await expect(sheet).toContainText("Your lease");await sheet.getByRole("button",{name:"Close plot details",exact:true}).click();
 await page.getByRole("button",{name:/Harbor Road/}).click();await expect(page.locator(".dp-card")).toHaveCount(6);await mine.click();
 await expect(page).toHaveURL(/view=mine/);await expect(page.locator(".dp-card")).toHaveCount(1);await expect(page.locator(".dp-card")).toContainText("W25");await expect(page.locator(".dp-card")).toContainText("Your lease");
 await page.reload();await expect(mine).toHaveAttribute("aria-pressed","true");await expect(page.locator(".dp-card")).toHaveCount(1);
 await page.getByRole("button",{name:"Manage property",exact:true}).click();await expect(sheet.getByRole("region",{name:"Move goods at this property"})).toBeVisible();
});

for(const [code,width] of [["25",1536],["26",390]] as const)test("on-property transfers in "+(code==="25"?"garage desktop":"warehouse mobile"),async({page,request})=>{
 const headers={Authorization:"Bearer "+token};
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{storage:true}});
 await page.setViewportSize({width,height:code==="25"?1000:844});await page.goto("/districts/the-waterfront?plot=plot-"+code);
 const sheet=page.getByRole("dialog",{name:"Plot W"+code+" details"});
 await sheet.getByRole("button",{name:"Lease this property",exact:true}).click();await sheet.getByRole("button",{name:"Confirm city lease",exact:true}).click();
 const stock=sheet.getByRole("region",{name:"Move goods at this property"});
 const store=stock.getByRole("button",{name:/Store Whiskey/i});await expect(store).toBeVisible();
 await expect.poll(()=>stock.locator(".commodity-art img").evaluateAll((imgs:HTMLImageElement[])=>imgs.length>0&&imgs.every(i=>i.complete&&i.naturalWidth>0))).toBe(true);
 await store.click();
 const transfer=page.getByRole("dialog",{name:"Secure your goods"});await expect(transfer).toBeVisible();
 await expect(transfer.getByLabel("Storage building")).toHaveValue("building-"+code);await expect(transfer.locator("select option")).toHaveCount(1);
 await transfer.getByLabel("Quantity",{exact:true}).fill("2");await capture(page,"property-transfer-"+code);
 await transfer.getByRole("button",{name:"Confirm storage"}).click();await expect(transfer).toHaveCount(0);await expect(sheet).toBeVisible();
 await expect(stock.locator(".dp-stock-capacity")).toContainText("Stored 2 /");await expect(stock.locator(".dp-stock-items")).toContainText("3 units");
 await stock.getByRole("button",{name:"Storage → inventory",exact:true}).click();await expect(stock.locator(".dp-stock-items")).toContainText("2 units");await stock.scrollIntoViewIfNeeded();await capture(page,"property-stock-"+code);
 await stock.getByRole("button",{name:/Retrieve Whiskey/i}).click();const retrieve=page.getByRole("dialog",{name:"Retrieve your goods"});await retrieve.getByRole("button",{name:"Confirm retrieval"}).click();await expect(retrieve).toHaveCount(0);
 await expect(stock.locator(".dp-stock-capacity")).toContainText("Stored 1 /");
 await stock.getByRole("button",{name:/Retrieve Whiskey/i}).click();await page.keyboard.press("Escape");await expect(page.getByRole("dialog",{name:"Retrieve your goods"})).toHaveCount(0);await expect(sheet).toBeVisible();
 const response=await request.post("http://127.0.0.1:54329/rest/v1/rpc/inventory_state",{headers,data:{}}),state=await response.json();
 expect(state.carried.find((i:any)=>i.good_id==="whiskey").quantity).toBe(4);expect(state.stores.find((s:any)=>s.id==="building-"+code).contents.find((i:any)=>i.good_id==="whiskey").quantity).toBe(1);
 expect(state.stores.filter((s:any)=>s.id!=="building-"+code).every((s:any)=>s.contents.length===0)).toBe(true);
 expect(await sheet.evaluate(el=>el.scrollWidth<=el.clientWidth)).toBe(true);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});

test("on-property interrupted transfer preserves its exact retry",async({page,request})=>{
 await page.goto("/districts/the-waterfront?plot=plot-25");
 const sheet=page.getByRole("dialog",{name:"Plot W25 details"});await sheet.getByRole("button",{name:"Lease this property",exact:true}).click();await sheet.getByRole("button",{name:"Confirm city lease",exact:true}).click();
 await sheet.getByRole("button",{name:/Store Whiskey/i}).click();const transfer=page.getByRole("dialog",{name:"Secure your goods"});await transfer.getByLabel("Quantity",{exact:true}).fill("2");
 let first="";await page.route("**/rest/v1/rpc/inventory_action",async route=>{if(!first){first=route.request().postData()!;await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(first);await route.continue();}});
 await transfer.getByRole("button",{name:"Confirm storage"}).click();await expect(transfer.getByRole("button",{name:"Retry safely"})).toBeVisible();await page.keyboard.press("Escape");await expect(transfer).toBeVisible();await transfer.getByRole("button",{name:"Retry safely"}).click();await expect(transfer).toHaveCount(0);await expect(sheet).toBeVisible();
 const r=await request.post("http://127.0.0.1:54329/rest/v1/rpc/inventory_state",{headers:{Authorization:"Bearer "+token},data:{}}),d=await r.json();expect(d.stores.find((s:any)=>s.id==="building-25").used).toBe(2);expect(d.history).toHaveLength(2);
});
