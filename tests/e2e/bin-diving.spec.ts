import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
async function capture(page:Page,name:string){const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:70});if(process.env.VISUAL_REVIEW==="1"){const b=shot.toString("base64");for(let n=0;n<b.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+b.slice(n,n+12000));}}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixture only");await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
test("dashboard entry, find a pickaxe, equip it and mine with the same equipment",async({page})=>{
 await page.setViewportSize({width:1600,height:1100});await page.goto("/dashboard");await page.getByRole("link",{name:"Bin Diving",exact:true}).click();await expect(page).toHaveURL(/bin-diving/);await expect(page.locator(".command-city")).toBeVisible();
 await capture(page,"bin-desktop");
 await page.getByRole("button",{name:"Search the bins"}).click();await expect(page.locator(".bin-result")).toContainText("Pickaxe");await expect(page.getByRole("button",{name:/Next dive in/})).toBeDisabled();
 await page.getByRole("button",{name:"Equip pickaxe",exact:false}).click();await expect(page.locator(".bin-equipment")).toContainText("100 condition remaining");
 await page.getByRole("link",{name:"Explore Mines & Quarries"}).click();await expect(page.locator(".mine-equipment")).toContainText("100 condition remaining");
});
test("cash and both blueprints persist, with one cooldown across districts",async({page,request})=>{
 await page.goto("/bin-diving?district=the-waterfront");await expect(page.locator(".bin-search>header")).toContainText("The Waterfront");
 for(const [item,label] of [["cash","$75"],["pistol_blueprint","Homemade pistol blueprint"],["bullet_blueprint","Homemade bullet blueprint"],["nothing","Nothing this time."]]){
  await request.post("http://127.0.0.1:54329/__bin_setup",{headers:{Authorization:"Bearer "+token},data:{next:item,ready:true}});
  await page.getByRole("button",{name:"Refresh bin diving"}).click();await page.getByRole("button",{name:"Search the bins"}).click();await expect(page.locator(".bin-result")).toContainText(label);
  await page.locator(".bin-district-list").getByRole("button",{name:/Old Town/}).click();await expect(page.getByRole("button",{name:/Next dive in/})).toBeDisabled();
 }
 await page.reload();await expect(page.locator(".bin-stash")).toContainText("Homemade pistol blueprint");await expect(page.locator(".bin-history li")).toHaveCount(4);
});
test("district openings refresh automatically and mobile layout fits",async({page,request})=>{
 await page.setViewportSize({width:390,height:844});await page.goto("/bin-diving");
 await request.post("http://127.0.0.1:54329/__bin_setup",{headers:{Authorization:"Bearer "+token},data:{addDistrict:true,lockdown:true}});
 await page.getByRole("button",{name:"Refresh bin diving"}).click();await expect(page.getByLabel("District",{exact:true}).locator("option")).toContainText(["Select a district","Mines and Quarries"]);
 await page.getByLabel("District",{exact:true}).selectOption("new-district");await expect(page.locator(".bin-search>header")).toContainText("New District");
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await capture(page,"bin-mobile");await page.getByLabel("District",{exact:true}).selectOption("district-0");await expect(page.getByRole("button",{name:"Search the bins"})).toBeDisabled();
});
test("Owner can save percentages and ordinary players cannot edit them",async({page,request,context})=>{
 const streets=await context.newPage();await streets.goto("/bin-diving");await expect(streets.locator(".bin-loot-grid article").filter({hasText:"Pickaxe"}).locator(".bin-chance")).toHaveText("8%");
 await page.goto("/owner?section=bin-diving");await page.getByLabel("Pickaxe chance (%)",{exact:true}).fill("25");await page.getByRole("button",{name:"Save bin diving rules"}).click();await expect(page.getByRole("status")).toContainText("rules saved");
 await expect(streets.locator(".bin-loot-grid article").filter({hasText:"Pickaxe"}).locator(".bin-chance")).toHaveText("25%");
 await streets.getByRole("link",{name:"← Dashboard",exact:true}).click();await streets.goBack();await expect(streets.locator(".bin-loot-grid article").filter({hasText:"Pickaxe"}).locator(".bin-chance")).toHaveText("25%");await streets.close();
 await page.reload();await expect(page.getByLabel("Pickaxe chance (%)",{exact:true})).toHaveValue("25");
 await page.getByLabel("Loose cash chance (%)").fill("100");await expect(page.getByRole("button",{name:"Save bin diving rules"})).toBeDisabled();
 await request.post("http://127.0.0.1:54329/__bin_setup",{headers:{Authorization:"Bearer "+token},data:{player:true}});await page.reload();await expect(page.locator(".bin-owner")).toContainText("Owner permission required.");
});
test("an interrupted reward response retries the original request without duplicating loot",async({page})=>{
 await page.goto("/bin-diving");
 let original:string|undefined;let calls=0;
 await page.route("**/rest/v1/rpc/bin_diving_action",async route=>{
  calls++;if(calls===1){original=route.request().postData()??"";await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(original);await route.continue();}
 });
 await page.getByRole("button",{name:"Search the bins"}).click();await page.getByRole("button",{name:"Retry safely"}).click();
 await expect(page.locator(".bin-result")).toContainText("Pickaxe");await expect(page.locator(".bin-history li")).toHaveCount(1);await expect(page.locator(".bin-stash-row").filter({hasText:"Spare equipment"}).locator("b")).toHaveText("1");
});

test("Owner grants reach the stash and both market sale formats, with matching artwork",async({page})=>{
 await page.setViewportSize({width:1600,height:1100});await page.goto("/owner?section=adjustments");
 const grant=page.locator("form").filter({has:page.getByRole("heading",{name:"Asset grant",exact:true})});
 for(const item of ["pickaxe","pistol_blueprint","bullet_blueprint"]){
  await grant.getByLabel("Item",{exact:true}).selectOption(item);await grant.getByLabel("Quantity",{exact:true}).fill("1");await grant.getByLabel("Reason",{exact:true}).fill("Reward a city founder");
  await grant.getByRole("button",{name:"Save asset grant"}).click();await expect(page.locator(".game-notice")).toContainText("Saved");await expect(grant.getByRole("button",{name:"Save asset grant"})).toBeEnabled();
 }
 await page.goto("/bin-diving");await expect(page.locator(".bin-stash-row>b")).toHaveText(["1","1","1"]);
 await expect.poll(()=>page.locator(".bin-stash-row img").evaluateAll(imgs=>imgs.length===3&&imgs.every(img=>(img as HTMLImageElement).complete&&(img as HTMLImageElement).naturalWidth>0))).toBe(true);
 await capture(page,"bin-loot-desktop");
 await page.getByRole("link",{name:"Trade Pickaxe",exact:true}).click();await expect(page.locator(".market-ticket").getByLabel("Commodity")).toHaveValue("pickaxe");
 const ticket=page.locator(".market-ticket");
 await ticket.getByLabel("Quantity",{exact:true}).fill("1");await ticket.getByLabel("Price per unit ($)",{exact:true}).fill("150");await ticket.getByRole("button",{name:"Post market offer"}).click();await expect(page.locator(".market-notice")).toContainText("Offer posted");
 await page.goto("/bin-diving");await expect(page.locator(".bin-stash-row>b")).toHaveText(["0","1","1"]);await expect(page.getByRole("button",{name:"Equip pickaxe",exact:false})).toBeDisabled();
 await page.goto("/market?view=mine&good=pickaxe");await page.getByRole("button",{name:"Withdraw",exact:true}).click();await expect(page.locator(".market-notice")).toContainText("Offer withdrawn");
 for(const item of ["pistol_blueprint","bullet_blueprint"]){
  await ticket.getByLabel("Commodity").selectOption(item);await ticket.getByRole("button",{name:"Auction",exact:true}).click();await ticket.getByLabel("Quantity",{exact:true}).fill("1");await ticket.getByRole("button",{name:"Start auction",exact:true}).click();await expect(page.locator(".market-notice")).toContainText("Auction opened");
  // The inventory filter follows the deep link; select this commodity to view its auction.
  await page.locator(".market-commodities").getByRole("button").filter({hasText:item==="pistol_blueprint"?"Homemade pistol blueprint":"Homemade bullet blueprint"}).click();
  await page.getByRole("button",{name:"Withdraw auction",exact:true}).click();await expect(ticket.locator(".market-stock-note")).toContainText("1 units available");
 }
 await page.setViewportSize({width:390,height:844});await page.goto("/bin-diving");await expect(page.locator(".bin-stash-row>b")).toHaveText(["1","1","1"]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await capture(page,"bin-loot-mobile");
 await page.goto("/refineries");
 for(const id of ["iron-ingot","copper-ingot"]){const art=page.locator('img[src*="/art/resources/'+id+'"]').first();await art.scrollIntoViewIfNeeded();await expect.poll(()=>art.evaluate((img:HTMLImageElement)=>img.complete&&img.naturalWidth>0)).toBe(true);}
});
