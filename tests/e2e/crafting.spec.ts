import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const headers={Authorization:"Bearer "+token},base="http://127.0.0.1:54329";
async function capture(page:Page,name:string){const b=(await page.screenshot({type:"jpeg",quality:72,path:"test-results/"+name+".jpg"})).toString("base64");if(process.env.VISUAL_REVIEW==="1")for(let i=0;i<b.length;i+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(i/12000)+":"+b.slice(i,i+12000));}
async function openTable(page:Page,code="25"){
 await page.goto("/districts/the-waterfront?plot=plot-"+code);const sheet=page.getByRole("dialog");
 await sheet.getByRole("button",{name:"Lease this property",exact:true}).click();await sheet.getByRole("button",{name:"Confirm city lease",exact:true}).click();
 await sheet.getByRole("button",{name:"Install crafting station",exact:true}).click();await sheet.getByRole("button",{name:"Confirm installation",exact:true}).click();
 await sheet.getByRole("link",{name:/Open crafting menu/}).click();await expect(page.locator(".cf-bench")).toContainText("Crafting table · W"+code);
}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixtures");await request.post(base+"/__reset_world",{headers});await request.post(base+"/__crafting_setup",{headers,data:{grant:{pistol_blueprint:2,bullet_blueprint:1,"iron-ingot":20,"copper-ingot":12}}});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);});
test("installed garage table learns once, queues and stores finished equipment",async({page,request})=>{
 await page.setViewportSize({width:1536,height:1050});await openTable(page);
 await expect(page.getByRole("navigation",{name:"Game navigation"})).toBeVisible();
 await page.getByRole("button",{name:/Homemade pistol Blueprint required/}).click();
 await capture(page,"crafting-desktop");await page.getByRole("button",{name:/Learn recipe/}).click();await capture(page,"crafting-learning");
 await page.getByRole("button",{name:"Confirm learning"}).click();await expect(page.locator(".cf-tag")).toHaveText("Recipe learned");
 await page.reload();await expect(page.locator(".cf-tag")).toHaveText("Recipe learned");
 await page.getByRole("button",{name:/Add to crafting queue/}).click();await page.getByRole("button",{name:"Confirm crafting"}).click();await expect(page.locator(".cf-job")).toHaveCount(1);await expect(page.locator(".cf-job").getByRole("button",{name:"Collect",exact:true})).toBeDisabled();
 let d=await (await request.post(base+"/rest/v1/rpc/crafting_state",{headers,data:{}})).json();
 expect(d.inventory.carried.find((g:any)=>g.good_id==="pistol_blueprint").quantity).toBe(1);expect(d.inventory.carried.find((g:any)=>g.good_id==="iron-ingot").quantity).toBe(16);
 await request.post(base+"/__crafting_setup",{headers,data:{ready:true}});await page.getByRole("button",{name:"Refresh crafting"}).click();await page.getByLabel("Crafted item destination").selectOption("storage");
 await page.locator(".cf-job").getByRole("button",{name:"Collect",exact:true}).click();await page.getByRole("button",{name:"Confirm collection"}).click();await expect(page.locator(".cf-job")).toHaveCount(0);
 await expect(page.locator(".cf-property-column .cf-stock-grid")).toContainText("Homemade pistol");
 await expect.poll(()=>page.locator(".cf-page .commodity-art img").evaluateAll((imgs:HTMLImageElement[])=>imgs.length>0&&imgs.every(i=>i.complete&&i.naturalWidth>0))).toBe(true);
 d=await (await request.post(base+"/rest/v1/rpc/crafting_state",{headers,data:{}})).json();expect(d.inventory.stores.find((s:any)=>s.id==="building-25").contents.find((g:any)=>g.good_id==="homemade-pistol").quantity).toBe(1);
 await page.goto("/inventory?building=building-25");await page.getByLabel("Search inventory").fill("Homemade pistol");await page.getByRole("button",{name:"Retrieve",exact:true}).click();await page.getByRole("button",{name:"Confirm retrieval"}).click();await expect(page.getByRole("dialog")).toHaveCount(0);
 await page.goto("/inventory");await page.getByLabel("Search inventory").fill("Homemade pistol");await page.getByRole("button",{name:"Homemade pistol, 1 units",exact:true}).click();await page.getByRole("button",{name:"Equip Secondary weapon",exact:true}).click();await page.getByRole("button",{name:"Confirm equipment"}).click();await expect(page.getByRole("dialog")).toHaveCount(0);await expect(page.locator(".inv-equipment")).toContainText("Homemade pistol");
});
test("warehouse mobile crafting, cancellation and responsive layouts",async({page,request})=>{
 await page.setViewportSize({width:390,height:844});await openTable(page,"26");
 await page.getByRole("button",{name:/Homemade bullets Blueprint required/}).click();await page.getByRole("button",{name:/Learn recipe/}).click();await page.getByRole("button",{name:"Confirm learning"}).click();
 await page.getByLabel("Crafting batches").fill("2");await page.getByRole("button",{name:/Add to crafting queue/}).click();await page.getByRole("button",{name:"Confirm crafting"}).click();await expect(page.locator(".cf-job")).toContainText("× 24");
 for(const width of [360,390,768,1024,1536]){await page.setViewportSize({width,height:1000});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"crafting width "+width).toBe(true);}
 await page.setViewportSize({width:390,height:844});await page.evaluate(()=>scrollTo(0,0));await capture(page,"crafting-mobile");
 await page.getByRole("button",{name:"Cancel Homemade bullets job"}).click();await capture(page,"crafting-mobile-confirmation");await page.getByRole("button",{name:"Confirm cancellation"}).click();await expect(page.locator(".cf-job")).toHaveCount(0);
 const d=await(await request.post(base+"/rest/v1/rpc/inventory_state",{headers,data:{}})).json();expect(d.deliveries.reduce((n:number,x:any)=>n+x.quantity,0)).toBe(4);
});
test("interrupted learning reply retries the same request without consuming a spare",async({page,request})=>{
 await page.goto("/crafting?recipe=homemade-pistol");await expect(page.locator(".cf-bench")).toContainText("Blueprint library");
 let first="";await page.route("**/rest/v1/rpc/crafting_action",async route=>{if(!first){first=route.request().postData()!;await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(first);await route.continue();}});
 await page.getByRole("button",{name:/Learn recipe/}).click();await page.getByRole("button",{name:"Confirm learning"}).click();const modal=page.getByRole("dialog");await expect(modal.getByRole("button",{name:"Retry safely"})).toBeVisible();await page.keyboard.press("Escape");await expect(modal).toBeVisible();await modal.getByRole("button",{name:"Retry safely"}).click();await expect(modal).toHaveCount(0);
 await expect(page.getByRole("button",{name:/Add to crafting queue/})).toBeDisabled();
 const d=await(await request.post(base+"/rest/v1/rpc/crafting_state",{headers,data:{}})).json();expect(d.learned).toEqual(["homemade-pistol"]);expect(d.inventory.carried.find((g:any)=>g.good_id==="pistol_blueprint").quantity).toBe(1);
});
test("Owner recipe changes appear at the crafting table",async({page})=>{
 await page.goto("/owner?section=crafting");await page.getByLabel("Edit crafting recipe").selectOption("homemade-bullets");await page.getByLabel("Output units per batch").fill("18");await page.getByLabel("Craft time per batch (seconds)").fill("90");await page.getByLabel("Recipe audit reason").fill("Adjust ammunition production for this season");await page.getByRole("button",{name:"Save crafting recipe"}).click();await expect(page.locator(".cf-owner [role=status]")).toContainText("Recipe saved");
 await page.goto("/crafting?recipe=homemade-bullets");await expect(page.locator(".cf-output")).toContainText("18");await expect(page.locator(".cf-output")).toContainText("1m 30s");
});
