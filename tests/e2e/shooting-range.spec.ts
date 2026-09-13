import {test,expect,type Page,type APIRequestContext} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const headers={Authorization:"Bearer "+token},base="http://127.0.0.1:54329";
async function capture(page:Page,name:string){const b=(await page.screenshot({type:"jpeg",quality:72,path:"test-results/"+name+".jpg"})).toString("base64");if(process.env.VISUAL_REVIEW==="1")for(let i=0;i<b.length;i+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(i/12000)+":"+b.slice(i,i+12000));}
const rpc=async(request:APIRequestContext,fn:string,data={})=>(await request.post(base+"/rest/v1/rpc/"+fn,{headers,data})).json();
async function equip(request:APIRequestContext,n=3){
 await request.post(base+"/__crafting_setup",{headers,data:{grant:{"homemade-pistol":1,"homemade-bullets":n}}});const d=await rpc(request,"range_state");
 for(const [id,slot,quantity]of [["homemade-pistol","secondary",1],["homemade-bullets","ammo",n]]){const r=await rpc(request,"inventory_action",{p_action:"equip",p_payload:{season_id:d.season.id,request_id:crypto.randomUUID(),item_key:"good:"+id,equipment_slot:slot,quantity}});expect(r.error).toBeUndefined();}
}
async function start(page:Page){await page.goto("/shooting-range");await page.getByRole("button",{name:/Start session/}).click();await expect(page.locator(".range-intro")).toHaveCount(0);await expect(page.locator(".range-action-state")).toHaveText("Ready to fire");}
async function aim(page:Page,lane:number){const el=page.getByRole("button",{name:"Shooting lane",exact:true});const b=await el.boundingBox();const t=await page.locator(`[data-lane="${lane}"]`).getAttribute("transform");const xy=t!.match(/[\d.]+/g)!.map(Number);await page.mouse.click(b!.x+xy[0]/1000*b!.width,b!.y+xy[1]/600*b!.height);}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixtures");await request.post(base+"/__reset_world",{headers});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);});

test("range shares game HUD, requires equipment and is reachable from dashboard",async({page})=>{
 await page.goto("/dashboard");await page.locator(".command-quick").getByRole("link",{name:/Shooting Range/i}).click();await expect(page).toHaveURL(/shooting-range/);
 await expect(page.getByRole("navigation",{name:"Game navigation"})).toBeVisible();await expect(page.getByRole("link",{name:/Prepare your loadout/})).toBeVisible();await expect(page.locator(".range-loadout")).toContainText("No weapon equipped");await expect(page.locator(".range-best strong")).toHaveText("0");
});

test("moving targets, verified hits and misses consume actual equipped ammunition and condition",async({page,request})=>{
 await equip(request,3);await page.setViewportSize({width:1672,height:1120});await page.goto("/shooting-range");await expect.poll(()=>page.locator(".range-backdrop").evaluate((i:HTMLImageElement)=>i.complete&&i.naturalWidth>0)).toBe(true);await capture(page,"range-desktop");
 await page.getByRole("button",{name:/Start session/}).click();await expect(page.locator(".range-intro")).toHaveCount(0);const t=await page.locator('[data-lane="0"]').getAttribute("transform");await expect.poll(()=>page.locator('[data-lane="0"]').getAttribute("transform")).not.toBe(t);
 await aim(page,0);await expect(page.locator(".range-condition strong")).toHaveText("99 / 100");await expect(page.locator(".range-firebar strong")).toHaveText("2");await expect(page.locator(".range-target.scored")).toHaveCount(1);await capture(page,"range-active");
 await expect(page.locator(".range-action-state")).toHaveText("Ready to fire");const box=await page.locator(".range-lane").boundingBox();await page.mouse.click(box!.x+10,box!.y+box!.height-10);await expect(page.locator(".range-feedback")).toContainText("Miss.");await expect(page.locator(".range-condition strong")).toHaveText("98 / 100");await expect(page.locator(".range-firebar strong")).toHaveText("1");
 await expect(page.locator(".range-action-state")).toHaveText("Ready to fire");await page.locator(".range-lane").focus();await page.keyboard.press("Space");await expect(page.locator(".range-firebar strong")).toHaveText("0");await expect(page.locator(".range-condition strong")).toHaveText("97 / 100");await expect(page.locator(".range-lane")).toHaveAttribute("aria-disabled","true");
 await page.getByRole("button",{name:"End session",exact:true}).click();await expect(page.locator(".range-recent li")).toHaveCount(1);
 const r=await rpc(request,"range_state");expect(r.stats.shots).toBe(3);expect(r.stats.hits).toBe(1);expect(r.ammo).toBeNull();expect(r.weapons[0].condition).toBe(97);
 await page.goto("/inventory");await page.getByRole("button",{name:"Secondary weapon: Homemade pistol",exact:true}).click();await page.getByRole("button",{name:"Unequip",exact:true}).click();await expect(page.locator(".inv-slot .inv-item").filter({hasText:"Condition 97"})).toHaveCount(1);
});

test("interrupted shot response safely retries without firing again",async({page,request})=>{
 await equip(request,5);await start(page);let first="";await page.route("**/rest/v1/rpc/range_action",async route=>{if(!first){first=route.request().postData()!;await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(first);await route.continue();}});
 await aim(page,0);await expect(page.getByRole("button",{name:"Retry safely"})).toBeVisible();await expect(page.locator(".range-lane")).toHaveAttribute("aria-disabled","true");await page.getByRole("button",{name:"Retry safely"}).click();await expect(page.locator(".range-firebar strong")).toHaveText("4");await expect(page.locator(".range-condition strong")).toHaveText("99 / 100");const d=await rpc(request,"range_state");expect(d.session.shots).toBe(1);
});

test("Owner weapon wear applies at the range and broken weapons stop mobile shots",async({page,request})=>{
 await equip(request,5);await page.goto("/owner?section=shooting-range");await page.getByLabel("Condition lost per shot").fill("100");await page.getByLabel("Weapon audit reason").fill("Test broken weapon protection");await page.getByRole("button",{name:"Save weapon rules",exact:true}).click();await expect(page.locator(".range-owner [role=status]")).toContainText("saved");await page.setViewportSize({width:1536,height:1080});await capture(page,"range-owner");
 await page.setViewportSize({width:390,height:844});await start(page);await capture(page,"range-mobile");await page.locator(".range-lane").click({position:{x:10,y:100},force:true});await expect(page.locator(".range-condition strong")).toHaveText("0 / 100");await expect(page.locator(".range-firebar strong")).toHaveText("4");await expect(page.locator(".range-loadout-status")).toContainText("broken");await expect(page.locator(".range-lane")).toHaveAttribute("aria-disabled","true");
 for(const width of [360,390,768,1024,1536]){await page.setViewportSize({width,height:1000});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"range width "+width).toBe(true);}
 await page.getByRole("button",{name:"End session",exact:true}).click();await expect(page.getByRole("link",{name:/Prepare your loadout/})).toBeVisible();const d=await rpc(request,"range_state");expect(d.stats.shots).toBe(1);expect(d.ammo.quantity).toBe(4);
});
