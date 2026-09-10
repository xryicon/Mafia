import {test,expect,type Page} from "@playwright/test";
import {cookie} from "../fixtures/identity.mjs";

async function capture(page:Page,name:string,fullPage=false){
 const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:45,fullPage});
 if(process.env.VISUAL_REVIEW==="1"){
  const encoded=shot.toString("base64");
  for(let n=0;n<encoded.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+encoded.slice(n,n+12000));
 }
}
async function noOverflow(page:Page){
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true);
}
async function loaded(page:Page,selector:string){
 await expect.poll(()=>page.locator(selector).evaluate((img:HTMLImageElement)=>img.complete&&img.naturalWidth>0)).toBe(true);
}
test("cinematic landing explains player trade and adapts its artwork",async({page})=>{
 await page.setViewportSize({width:1440,height:1000});
 await page.goto("/");
 await expect(page).toHaveTitle(/Blackwater Mafia/);
 await expect(page.getByRole("heading",{level:1})).toContainText("Every fortune");
 await loaded(page,".bw-hero img");
 await expect(page.locator(".bw-hero img")).toHaveJSProperty("currentSrc","http://localhost:3000/art/harbor.webp");
 await page.emulateMedia({reducedMotion:"reduce"});
 await capture(page,"landing-desktop");
 await page.locator("#economy").scrollIntoViewIfNeeded();
 await page.getByRole("button",{name:"Steel",exact:true}).click();
 await expect(page.locator(".preview-lot")).toContainText("Steel · 12 units");
 await page.getByLabel("Set your price").fill("200");
 await expect(page.locator(".preview-total")).toContainText("$2,400");
 await expect(page.locator(".preview-note")).toContainText("Illustrative listing");
 await capture(page,"economy-desktop");
 await page.locator("#city").scrollIntoViewIfNeeded();
 for(const img of await page.locator(".bw-industry img").all())await expect.poll(()=>img.evaluate((el:HTMLImageElement)=>el.complete&&el.naturalWidth>0)).toBe(true);
 await capture(page,"industries-desktop");
 await page.setViewportSize({width:375,height:812});
 await page.goto("/");
 await loaded(page,".bw-hero img");
 await expect(page.locator(".bw-hero img")).toHaveJSProperty("currentSrc","http://localhost:3000/art/harbor-small.webp");
 await noOverflow(page);
 await capture(page,"landing-mobile");
 await page.getByRole("link",{name:"Enter Blackwater",exact:true}).click();
 await loaded(page,".auth-intro img");
 await expect(page.getByLabel("Email address")).toBeVisible();
 await noOverflow(page);
 await capture(page,"signup-mobile",true);
 await page.setViewportSize({width:1440,height:1000});
 await page.goto("/login");
 await loaded(page,".auth-intro img");
 await capture(page,"login-desktop");
 await page.getByRole("link",{name:"Blackwater Mafia home"}).first().click();
 await page.locator(".bw-hero").getByRole("link",{name:"Log in",exact:true}).click();
 await expect(page.getByRole("heading",{level:1})).toHaveText("Welcome back, boss.");
});
test("illustrated game uses real market offers and reachable mobile navigation",async({page,context})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Uses isolated fixture only.");
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
 await page.setViewportSize({width:1440,height:1000});
 await page.goto("/dashboard");
 await loaded(page,".district-hero img");
 await expect(page.getByRole("region",{name:"Player market overview"})).toBeVisible();
 await capture(page,"game-desktop");
 const nav=page.getByRole("navigation",{name:"Game navigation"});
 await page.locator(".pulse-card.silk").click();
 await expect(page.getByRole("heading",{level:1})).toHaveText("The black market.");
 await expect(page.getByRole("button",{name:"Silk bolts",exact:true})).toHaveAttribute("aria-pressed","true");
 await loaded(page,".market-scene img");
 await capture(page,"market-desktop");
 await page.setViewportSize({width:375,height:812});
 await nav.getByRole("button",{name:"Overview",exact:true}).click();
 await noOverflow(page);
 const box=await nav.boundingBox();
 expect(box).not.toBeNull();
 expect(box!.y+box!.height).toBeLessThanOrEqual(813);
 await page.locator(".page-heading").scrollIntoViewIfNeeded();
 await capture(page,"game-mobile");
 for(const name of ["Businesses","Operations","Inventory","Ledger"]){
  await nav.getByRole("button",{name,exact:true}).click();
  await noOverflow(page);
  if(name==="Businesses"){await page.locator(".business-grid").scrollIntoViewIfNeeded();for(const good of ["whiskey","silk","steel"])await loaded(page,".business-card."+good+" img");await capture(page,"business-mobile");}
 }
});
