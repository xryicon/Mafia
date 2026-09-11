import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
async function capture(page:Page,name:string){const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:70});if(process.env.VISUAL_REVIEW==="1"){const b=shot.toString("base64");for(let n=0;n<b.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+b.slice(n,n+12000));}}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated mine fixture");await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
test("all dashboard districts open their destination with a single click",async({page})=>{
 for(const [name,slug]of [["Mines and Quarries","mines-and-quarries"],["Old Town","old-town"],["Downtown","downtown"],["The Waterfront","the-waterfront"],["Industrial Quarter","industrial-quarter"],["Blackwater Island","blackwater-island"],["Drilling Shore","drilling-shore"]]){
  await page.goto("/dashboard");await page.getByRole("button",{name:"Select "+name,exact:true}).click();await expect(page).toHaveURL(new RegExp("/districts/"+slug+"$"));await expect(page.getByRole("heading",{name,exact:true}).first()).toBeVisible();
 }
});
test("public mining requires found equipment, keeps existing tools usable and illustrates resources",async({page,request})=>{
 await page.setViewportSize({width:1672,height:1000});await page.goto("/districts/mines-and-quarries");
 await expect(page.locator(".mine-marker")).toHaveCount(10);await expect(page.locator(".mine-cards .mine-card")).toHaveCount(10);
 await expect.poll(()=>page.locator(".mine-map image").getAttribute("href")).toContain("map.webp");
 await page.locator('.mine-resource-strip').scrollIntoViewIfNeeded();
 await expect.poll(()=>page.locator('.mine-resource-strip img').evaluateAll(imgs=>imgs.length===5&&imgs.every(i=>(i as HTMLImageElement).complete&&(i as HTMLImageElement).naturalWidth>0))).toBe(true);
 await page.getByRole('button',{name:'Show Iron ore sites',exact:true}).click();await expect(page.locator('.mine-cards .mine-card')).toHaveCount(2);await page.getByRole('button',{name:'Clear filters',exact:true}).click();
 await page.getByLabel('Search mine sites').fill('Copperhead');await expect(page.locator('.mine-cards .mine-card')).toHaveCount(1);await page.getByLabel('Search mine sites').fill('');
 await page.evaluate(()=>scrollTo(0,0));await page.getByRole("button",{name:"Zoom in",exact:true}).click();await page.getByRole("button",{name:"Fit map",exact:true}).click();expect(await page.locator(".mine-map svg.district-svg").evaluate(el=>{const b=el.getBoundingClientRect();return [...el.querySelectorAll(".mine-marker>rect")].every(r=>{const q=r.getBoundingClientRect();return q.top>=b.top&&q.bottom<=b.bottom&&q.left>=b.left&&q.right<=b.right;});})).toBe(true);await capture(page,"mining-v2-desktop");
 await page.getByRole("button",{name:"View MQ-01 North Ridge Iron Mine",exact:true}).click();
 const detail=page.locator(".mine-desktop-details");await expect(detail).toContainText('Equipment discovery is coming later');await expect(page.getByRole('button',{name:/Buy pickaxe|Replace pickaxe/})).toHaveCount(0);await expect(page.locator('.mine-equipment')).toContainText('Not equipped');
 await request.post('http://127.0.0.1:54329/__mining_equipped',{headers:{Authorization:'Bearer '+token}});await page.getByRole('button',{name:'Refresh',exact:true}).click();await expect(page.locator('.header-cash')).toContainText('$10,000');
 await detail.getByRole("button",{name:"Start mining shift",exact:true}).click();
 await expect(page.getByRole("button",{name:"Collect mined resources",exact:true})).toBeDisabled();await expect(page.locator(".mine-equipment")).toContainText("99 condition");
 await request.post("http://127.0.0.1:54329/__finish_mining",{headers:{Authorization:"Bearer "+token}});await page.getByRole("button",{name:"Refresh",exact:true}).click();
 await page.getByRole("button",{name:"Collect mined resources",exact:true}).click();await expect(page.locator(".mine-shift")).toHaveCount(0);
 await page.getByRole("button",{name:"Your haul",exact:true}).click();await expect(page.locator(".mine-inventory")).toContainText("4 units");await expect(page.locator(".mine-history")).toContainText("4 Iron ore");
 await expect(page.locator('.mine-inventory img')).toHaveCount(5);await capture(page,'mining-v2-resource-haul');await page.locator(".mine-inventory").getByRole("link").first().click();await expect(page).toHaveURL(/\/market\?good=iron-ore&view=inventory/);await expect(page.locator(".market-inventory")).toContainText("Iron ore");await expect(page.locator('.market-inventory img[src*="resources/iron-ore"]')).toBeVisible();
 await page.goto("/districts/mines-and-quarries");
 for(const width of [1448,1024,768,375]){await page.setViewportSize({width,height:width===375?812:1000});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"Mining overflow at "+width).toBe(true);}
 await page.getByRole("button",{name:"Open MQ-04 East Quarry",exact:true}).click();const sheet=page.getByRole("dialog",{name:"MQ-04 mine details"});await expect(sheet).toBeVisible();await expect(sheet).toContainText("Private extraction rights");await expect(sheet.getByRole("button",{name:"Start mining shift"})).toHaveCount(0);await capture(page,"mining-mobile-site");await sheet.getByRole("button",{name:"Close mine details"}).click();await expect(sheet).not.toBeVisible();
 await page.getByRole("button",{name:"District activity",exact:true}).click();await expect(page.locator(".mine-history li")).toHaveCount(10);
});
test("Owner opens a mine and auctions it; a player reserves their bid",async({page,request})=>{
 page.on("pageerror",e=>console.log("MINING_PAGE_ERROR "+e.message));
 await page.setViewportSize({width:1448,height:1100});await page.goto("/owner?section=mines&mine=mine-2");
 await page.getByLabel("Site status",{exact:true}).selectOption("open");await page.getByLabel("Reason for this change").fill("Open the copper mine for auction");await page.getByRole("button",{name:"Save mine settings"}).click();await expect(page.locator(".mine-notice")).toContainText("saved");
 await page.getByLabel("Minimum bid ($)").fill("1000");await page.getByLabel("Auction duration (minutes)").fill("5");await page.getByLabel("Reason for this auction").fill("Release city extraction rights");await page.getByRole("button",{name:"Start mine auction"}).click();await expect(page.getByRole("heading",{name:"Auction in progress"})).toBeVisible();await capture(page,"mining-owner-controls");
 await request.post("http://127.0.0.1:54329/__mining_player",{headers:{Authorization:"Bearer "+token}});await page.goto("/districts/mines-and-quarries?mine=mine-2");
 const detail=page.locator(".mine-desktop-details");await expect(detail.getByRole("link",{name:/Owner site controls/})).toHaveCount(0);await detail.getByLabel("Your bid for the mine ($)").fill("1000");await detail.getByRole("button",{name:"Confirm mine bid"}).click();await expect(page.locator(".header-cash")).toContainText("$8,970");await expect(detail).toContainText("Leading: HarborBoss");await capture(page,"mining-auction-desktop");
});
test("interrupted mining shifts retry safely with one reward reservation",async({page,request})=>{
 await request.post('http://127.0.0.1:54329/__mining_equipped',{headers:{Authorization:'Bearer '+token}});
 await page.goto('/districts/mines-and-quarries?mine=mine-0');let interrupted=false;await page.route('**/rest/v1/rpc/mining_action',async route=>{if(!interrupted){interrupted=true;await route.fetch();await route.abort('failed');}else await route.continue();});
 await page.locator('.mine-desktop-details').getByRole('button',{name:'Start mining shift',exact:true}).click();await page.getByRole('button',{name:'Retry same request'}).click();await expect(page.getByRole('status')).toContainText('Mining shift started');await expect(page.locator('.header-cash')).toContainText('$10,000');await expect(page.locator('.mine-equipment')).toContainText('99 condition');await expect(page.locator('.mine-shift')).toHaveCount(1);
});
