import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
async function capture(page:Page,name:string,fullPage=false){
 const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:70,fullPage});
 if(process.env.VISUAL_REVIEW==="1"){const b64=shot.toString("base64");for(let n=0;n<b64.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+b64.slice(n,n+12000));}
}
test.beforeEach(async({context,request})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated game world");
 await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
});
test("command dashboard uses real game actions and district destinations",async({page})=>{
 await page.setViewportSize({width:1672,height:941});await page.goto("/dashboard");
 await expect(page.getByRole("heading",{name:"BLACKWATER",exact:true})).toBeVisible();
 await expect(page.locator(".command-player-stats")).toContainText("$10,000");
 await expect(page.getByRole("button",{name:"Select The Waterfront",exact:true})).toHaveAttribute("aria-pressed","true");
 await page.getByRole("button",{name:"Zoom in",exact:true}).click();
 await expect(page.locator(".command-atlas svg.district-svg > g").first()).toHaveAttribute("transform",/1.25/);
 await page.getByRole("button",{name:"Fit map",exact:true}).click();
 await page.getByRole("link",{name:"View District",exact:true}).click();
 await expect(page).toHaveURL(/\/districts\/the-waterfront$/);
 await page.goto("/dashboard");await page.getByRole("button",{name:"Find a Job",exact:true}).click();
 const modal=page.getByRole("dialog");await expect(modal).toBeVisible();
 await modal.getByRole("button",{name:"Start operation",exact:true}).first().click();
 await expect(page.locator(".command-player-stats")).toContainText("$10,250");
 await expect(modal).toContainText("+10 power");
 await expect(modal.locator(".command-job .command-button").first()).toBeDisabled();
 await modal.getByRole("button",{name:"Close actions"}).click();
 await page.getByRole("button",{name:"Production",exact:true}).click();
 await modal.getByRole("button",{name:"Buy · $3,000",exact:true}).click();
 await expect(page.locator(".command-player-stats")).toContainText("$7,250");
 await expect(modal.getByRole("button",{name:"Collect 0 units",exact:true})).toBeDisabled();
 await page.keyboard.press("Escape");await expect(modal).not.toBeVisible();
 await expect(page.locator(".command-production")).toContainText("Whiskey crates");
 await page.getByLabel("Select district",{exact:true}).selectOption("the-waterfront");
 await page.getByRole("button",{name:"Travel",exact:true}).click();await expect(page).toHaveURL(/\/districts\/the-waterfront$/);
});
test("reference dashboard renders on desktop, tablet and mobile with working panels",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__visual_world",{headers:{Authorization:"Bearer "+token}});
 await page.setViewportSize({width:1672,height:941});await page.goto("/dashboard");await page.emulateMedia({reducedMotion:"reduce"});
 await expect(page.locator(".command-player-name")).toContainText("HarborBoss");
 await expect(page.locator(".command-gangs")).toContainText("Cobalto Family");
 await expect.poll(()=>page.locator(".command-portrait").evaluate((img:HTMLImageElement)=>img.complete&&img.naturalWidth>0)).toBe(true);
 await expect(page.getByLabel("Inventory stock")).toHaveCount(0);await expect(page.getByRole("meter",{name:"Health",exact:true})).toHaveAttribute("aria-valuenow","100");await expect(page.getByRole("meter",{name:"Armour",exact:true})).toHaveAttribute("aria-valuenow","0");
 await expect(page.locator(".command-atlas").getByRole("link",{name:/Telegram Office/i})).toHaveCount(0);
 await expect(page.locator(".command-office-marker")).toHaveCount(0);
 await expect(page.locator(".command-telegram")).toBeVisible();
 const dashboardBounds=await page.locator(".command-dashboard").boundingBox();console.log("COMMAND_DESKTOP_BOUNDS "+JSON.stringify(dashboardBounds));
 await capture(page,"command-desktop");
 for(const width of [1448,1024,768,375]){
  await page.setViewportSize({width,height:width===375?812:1000});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"Dashboard overflow at "+width).toBe(true);await expect(page.getByRole("meter",{name:"Health",exact:true})).toBeVisible();await expect(page.getByRole("meter",{name:"Armour",exact:true})).toBeVisible();
  const header=await page.locator(".estate-header").boundingBox(),wallet=await page.locator(".header-wallet").boundingBox();
  expect(wallet!.y).toBeGreaterThanOrEqual(header!.y);expect(wallet!.y+wallet!.height).toBeLessThanOrEqual(header!.y+header!.height);
  if(width===375){await page.evaluate(()=>scrollTo(0,0));await capture(page,"command-mobile");await capture(page,"command-mobile-full",true);await page.locator(".command-player-stats").scrollIntoViewIfNeeded();await capture(page,"dashboard-vitals-mobile");}
 }
 await page.locator(".command-telegram").getByRole("link",{name:/Open Telegrams/}).click();await expect(page).toHaveURL(/\/telegrams$/);
 await page.goto("/dashboard");await page.locator(".command-season").getByRole("link",{name:"View Leaderboard",exact:true}).click();
 await expect(page).toHaveURL(/\/seasons\?view=rankings$/);
});

test("dashboard prices show active offers only and paginate five goods per page",async({page})=>{
 let mode:"full"|"one"|"empty"="full";
 await page.route("**/rest/v1/rpc/game_state",async route=>{
  const response=await route.fetch(),game=await response.json();
  const goods=[...game.goods,...[["iron-ingot","Iron ingots"],["copper-ingot","Copper ingots"]].map(([id,name])=>({...game.goods[0],id,name}))];
  const base=game.market[0];
  const offers=goods.slice(0,7).map((g,i)=>({...base,id:"active-"+i,good_id:g.id,unit_price:100+i,quantity:2,status:"active"}));
  offers.push({...base,id:"lower-ask",good_id:goods[0].id,unit_price:80,quantity:1,status:"active"});
  offers.push({...base,id:"sold-cheaper",good_id:goods[0].id,unit_price:1,status:"sold"});
  offers.push({...base,id:"sold-only",good_id:"copper-ingot",unit_price:1,status:"cancelled"});
  offers.push({...base,id:"empty-stock",good_id:"copper-ingot",unit_price:1,quantity:0,status:"active"});
  await route.fulfill({response,json:{...game,goods,market:mode==="empty"?[]:mode==="one"?offers.filter(o=>o.good_id===goods[0].id):offers}});
 });
 await page.setViewportSize({width:1672,height:1000});await page.goto("/dashboard");
 await page.getByRole("button",{name:"Refresh city",exact:true}).click();
 const board=page.locator(".command-market-prices"),rows=board.locator(".command-prices>a");
 await expect(rows).toHaveCount(5);await expect(rows.first()).toContainText("$80");await expect(rows.first()).toContainText("2 offers");await expect(board).toContainText("Lockpick");
 await expect(board).not.toContainText("Copper ingots");await expect(board).not.toContainText("No offers");
 await expect(board.getByRole("button",{name:"Previous market prices page"})).toBeDisabled();
 await expect(board.getByRole("navigation")).toContainText("Page 1 / 2");
 await board.scrollIntoViewIfNeeded();await capture(page,"dashboard-market-pages");
 await board.getByRole("button",{name:"Next market prices page"}).click();
 await expect(rows).toHaveCount(2);await expect(rows).toContainText(["Homemade pistol blueprint","Homemade bullet blueprint"]);
 await expect(board.getByRole("button",{name:"Next market prices page"})).toBeDisabled();
 await expect(board.getByRole("navigation")).toContainText("Page 2 / 2");
 await rows.filter({hasText:"Homemade pistol blueprint"}).getAttribute("href").then(href=>expect(href).toBe("/market?good=pistol_blueprint"));
 await page.setViewportSize({width:375,height:812});await board.scrollIntoViewIfNeeded();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await capture(page,"dashboard-market-pages-mobile");
 await board.getByRole("button",{name:"Previous market prices page"}).click();await expect(rows).toHaveCount(5);
 await board.getByRole("button",{name:"Next market prices page"}).click();
 mode="one";await page.getByRole("button",{name:"Refresh city",exact:true}).click();
 await expect(rows).toHaveCount(1);await expect(rows.first()).toContainText("Whiskey crates");await expect(board.getByRole("navigation")).toHaveCount(0);
 mode="empty";await page.getByRole("button",{name:"Refresh city",exact:true}).click();
 await expect(rows).toHaveCount(0);await expect(board).toContainText("No active offers right now.");
});

test("personal health supports future overheal without stock counters",async({page})=>{
 let mode="boost";
 await page.route("**/rest/v1/rpc/vitals_state",async route=>{
  if(mode==="offline"){await route.fulfill({status:503,json:{message:"Fixture unavailable"}});return;}
  await route.fulfill({json:{season_id:"55555555-5555-4555-8555-555555555555",health:mode==="boost"?120:mode==="ending"?101:37,health_max:100,health_cap:120,armour:40,armour_max:100,decay_seconds:mode==="ending"?1:60,server_time:new Date().toISOString()}});
 });
 await page.setViewportSize({width:1672,height:1000});await page.goto("/dashboard");await page.getByRole("button",{name:"Refresh city",exact:true}).click();
 const health=page.getByRole("meter",{name:"Health",exact:true}),armour=page.getByRole("meter",{name:"Armour",exact:true});
 await expect(health).toHaveAttribute("aria-valuemax","120");await expect(health).toHaveAttribute("aria-valuenow","120");await expect(armour).toHaveAttribute("aria-valuenow","40");
 await expect(page.locator(".command-player-stats dt")).toHaveText(["Cash","Health","Armour","Operations","District heat"]);
 await expect(page.getByLabel("Inventory stock")).toHaveCount(0);await page.locator(".command-player-stats").scrollIntoViewIfNeeded();await capture(page,"dashboard-vitals-boost");
 mode="ending";await page.getByRole("button",{name:"Refresh city",exact:true}).click();await expect(health).toHaveAttribute("aria-valuenow","100");await expect(health).toHaveAttribute("aria-valuemax","100");
 mode="injured";await page.getByRole("button",{name:"Refresh city",exact:true}).click();await expect(health).toHaveAttribute("aria-valuenow","37");
 mode="offline";await page.getByRole("button",{name:"Refresh city",exact:true}).click();await expect(page.getByRole("img",{name:"Health unavailable"})).toBeVisible();
 for(const path of ["/market","/telegrams","/inventory"]){await page.goto(path);await expect(page.getByRole("navigation",{name:"Game navigation"})).toBeVisible();await expect(page.getByLabel("Inventory stock")).toHaveCount(0);}
});

test("quick actions can be selected, reordered, saved and reset",async({page})=>{
 await page.goto('/dashboard');const quick=page.getByRole('region',{name:'Quick actions',exact:true});
 await quick.getByRole('button',{name:'Customize',exact:true}).click();
 await quick.getByRole('checkbox',{name:'Bin Diving',exact:true}).uncheck();
 await quick.getByRole('checkbox',{name:'Inventory',exact:true}).check();
 await quick.getByRole('button',{name:'Move Inventory up',exact:true}).click();
 await quick.getByRole('button',{name:'Save shortcuts',exact:true}).click();
 await expect(quick.getByRole('link',{name:'Bin Diving',exact:true})).toHaveCount(0);
 await expect(quick.getByRole('link',{name:'Inventory',exact:true})).toHaveAttribute('href','/inventory');
 await page.reload();await expect(quick.locator(':scope > .command-button').nth(5)).toHaveText('Inventory');
 await quick.getByRole('button',{name:'Customize',exact:true}).click();
 await quick.getByRole('button',{name:'Reset to default',exact:true}).click();
 await quick.getByRole('button',{name:'Cancel',exact:true}).click();
 await expect(quick.getByRole('link',{name:'Inventory',exact:true})).toBeVisible();
 await quick.getByRole('button',{name:'Customize',exact:true}).click();
 await quick.getByRole('button',{name:'Reset to default',exact:true}).click();
 await quick.getByRole('button',{name:'Save shortcuts',exact:true}).click();
 await expect(quick.getByRole('link',{name:'Inventory',exact:true})).toHaveCount(0);
 await quick.getByRole('button',{name:'Find a Job',exact:true}).click();
 await expect(page.getByRole('dialog')).toContainText('Work the city');
});
