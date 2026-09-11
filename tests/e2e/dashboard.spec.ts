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
 await expect(modal).toContainText("+10 respect");
 await expect(modal.getByRole("button",{name:"1m",exact:true}).first()).toBeDisabled();
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
 await expect(page.getByLabel("Inventory stock")).toContainText("540");
 await capture(page,"command-desktop");
 for(const width of [1448,1024,768,375]){
  await page.setViewportSize({width,height:width===375?812:1000});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"Dashboard overflow at "+width).toBe(true);
  const header=await page.locator(".estate-header").boundingBox(),wallet=await page.locator(".header-wallet").boundingBox();
  expect(wallet!.y).toBeGreaterThanOrEqual(header!.y);expect(wallet!.y+wallet!.height).toBeLessThanOrEqual(header!.y+header!.height);
  if(width===375){await page.evaluate(()=>scrollTo(0,0));await capture(page,"command-mobile");await capture(page,"command-mobile-full",true);}
 }
 await page.locator(".command-telegram").getByRole("link",{name:/Open Telegrams/}).click();await expect(page).toHaveURL(/\/telegrams$/);
 await page.goto("/dashboard");await page.locator(".command-season").getByRole("link",{name:"View Leaderboard",exact:true}).click();
 await expect(page).toHaveURL(/\/seasons\?view=rankings$/);
});

