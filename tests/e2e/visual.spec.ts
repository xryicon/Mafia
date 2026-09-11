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
test("property panels match the reference and every destination fits a phone",async({page,context,request})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated visual fixture");
 await request.post("http://127.0.0.1:54329/__visual_world",{headers:{Authorization:"Bearer "+token}});
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
 await page.setViewportSize({width:1448,height:1086});await page.goto("/properties?good=steel");
 await loaded(page,".property-hero>.bw-art img");await expect(page.locator(".header-cash")).toContainText("$2,480,000");
 await expect(page.getByRole("heading",{level:1})).toHaveText("Dockside foundry");
 await expect(page.getByRole("button",{name:/Collect [0-9]+ units/})).toBeEnabled();await expect(page.getByRole("progressbar")).toHaveAttribute("aria-valuenow","25");
 await noOverflow(page);await capture(page,"property-reference-desktop",true);
 const before=await page.locator(".property-stats").innerText();await page.getByRole("button",{name:/Collect [0-9]+ units/}).click();
 await expect(page.locator(".property-stats")).not.toHaveText(before);
 await page.goto("/dashboard");await loaded(page,".estate-hero>.bw-art img");await capture(page,"dashboard-reference-desktop",true);
 for(const path of ["/market","/districts","/gangs"]){await page.goto(path);await noOverflow(page);await capture(page,path.slice(1)+"-reference-desktop");}
 await page.setViewportSize({width:375,height:812});
 for(const path of ["/dashboard","/market","/properties?good=steel","/districts","/gangs","/profile","/owner","/support","/players"]){
  await page.goto(path);await expect(page.getByRole("heading",{level:1})).toBeVisible();await noOverflow(page);
  const links=page.getByRole("navigation",{name:"Game navigation"}).getByRole("link");await expect(links).toHaveCount(6);
  for(const link of await links.all()){const box=await link.boundingBox();expect(box!.x).toBeGreaterThanOrEqual(0);expect(box!.x+box!.width).toBeLessThanOrEqual(376);}
  if(path.startsWith("/properties"))await capture(page,"property-reference-mobile",true);
  if(path==="/dashboard")await capture(page,"dashboard-reference-mobile");
 }
});
