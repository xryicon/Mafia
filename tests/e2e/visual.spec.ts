import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
async function capture(page:Page,name:string,fullPage=false){
 const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:60,fullPage});
 if(process.env.VISUAL_REVIEW==="1"){const encoded=shot.toString("base64");for(let n=0;n<encoded.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+encoded.slice(n,n+12000));}
}
async function noOverflow(page:Page){
 const layout=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,overflow:[...document.querySelectorAll("body *")].map(el=>({tag:el.tagName,class:el.className,x:el.getBoundingClientRect().x,right:el.getBoundingClientRect().right})).filter(r=>r.x<-.5||r.right>innerWidth+.5).slice(0,30)}));
 if(layout.scroll>layout.width){console.log("LAYOUT_OVERFLOW "+page.url()+" "+JSON.stringify(layout));await capture(page,"overflow-mobile");}
 expect(layout.scroll,"Horizontal overflow at "+page.url()).toBeLessThanOrEqual(layout.width);
}
async function loaded(page:Page,selector:string){await expect.poll(()=>page.locator(selector).evaluate((img:HTMLImageElement)=>img.complete&&img.naturalWidth>0)).toBe(true);}
test("public artwork and signup remain responsive",async({page})=>{
 await page.setViewportSize({width:1448,height:1086});await page.goto("/");await loaded(page,".bw-hero img");await expect(page.getByRole("heading",{level:1})).toContainText("Every fortune");
 await page.emulateMedia({reducedMotion:"reduce"});await capture(page,"landing-desktop");await page.locator("#economy").scrollIntoViewIfNeeded();
 await page.getByRole("button",{name:"Steel",exact:true}).click();await page.getByLabel("Set your price").fill("200");await expect(page.locator(".preview-total")).toContainText("$2,400");
 await page.setViewportSize({width:375,height:812});await page.goto("/signup");await loaded(page,".auth-intro img");await expect(page.getByLabel("Username",{exact:true})).toBeVisible();await noOverflow(page);
 await capture(page,"signup-mobile",true);
});
test("game navigation and inventory stay responsive",async({page,context,request})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated visual fixture");
 await request.post("http://127.0.0.1:54329/__visual_world",{headers:{Authorization:"Bearer "+token}});
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
 await page.setViewportSize({width:1672,height:941});await page.goto("/market");
 await expect(page.getByLabel("Inventory stock")).toContainText("540");
 await expect(page.locator(".estate-header")).toHaveCSS("height","62px");
 await noOverflow(page);await capture(page,"shared-market-desktop");
 await page.setViewportSize({width:1044,height:700});await page.goto("/telegrams");
 await expect(page.locator(".header-cash")).toContainText("$2,480,000");
 const nav=page.getByRole("navigation",{name:"Game navigation"});
 await expect(nav.locator("a > span")).toHaveText(["Dashboard","Market","Inventory","Bank","Gangs","Telegrams"]);
 await expect(nav.getByRole("link",{name:"Profile",exact:true})).toHaveCount(0);
 for(const link of await nav.getByRole("link").all())await expect(link.locator("svg")).toBeHidden();
 await expect(page.locator(".estate-header")).toHaveCSS("height","120px");
 await expect(page.locator(".header-power")).toHaveText("Power 1,247");
 await expect(page.locator(".header-rank")).toHaveText("Caporegime");
 await expect(page.locator(".estate-brand .brand-online")).toHaveText("2 online");
 await noOverflow(page);await capture(page,"clear-city-desktop");
 for(const path of ["/properties?good=steel"]){
  await page.goto(path);await expect(page).toHaveURL(/\/inventory$/);await expect(page.locator(".inv-page")).toBeVisible();
  await expect(page.locator(".estate-footer")).toBeVisible();
  await noOverflow(page);
 }
 await capture(page,"inventory-redirect-desktop");
 await page.setViewportSize({width:375,height:812});
 for(const path of ["/inventory","/bank","/dashboard","/market","/properties","/districts","/gangs","/telegrams","/ledger","/owner","/staff","/support","/players","/profile","/seasons","/account","/districts/the-waterfront","/districts/manage"]){
  await page.goto(path);await noOverflow(page);
  await expect(page.locator(".command-city")).toHaveCount(1);
  await expect(page.locator(".estate-header")).toHaveCSS("height","143px");
  await expect(page.locator(".estate-header img.don-portrait")).toHaveAttribute("src","/art/command-portrait.jpg");
  const header=await page.locator(".estate-header").boundingBox(),wallet=await page.locator(".header-wallet").boundingBox();
  console.log("HEADER_BOUNDS "+JSON.stringify({path,header,wallet}));
  expect(wallet!.y).toBeGreaterThanOrEqual(header!.y);
  expect(wallet!.y+wallet!.height).toBeLessThanOrEqual(header!.y+header!.height);
  const links=nav.getByRole("link");await expect(links).toHaveCount(6);
  for(const link of await links.all()){const box=await link.boundingBox();expect(box!.x).toBeGreaterThanOrEqual(0);expect(box!.x+box!.width).toBeLessThanOrEqual(376);}
  if(path==="/dashboard")await capture(page,"clear-city-mobile");
  if(path==="/market")await capture(page,"shared-market-mobile");
 }
});
