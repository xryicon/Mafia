import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const headers={Authorization:"Bearer "+token},gid="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const setup="http://127.0.0.1:54329/__gang_setup";
async function capture(page:Page,name:string){const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:65,fullPage:true});if(process.env.VISUAL_REVIEW==="1"){const b=shot.toString("base64");for(let i=0;i<b.length;i+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(i/12000)+":"+b.slice(i,i+12000));}}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixture");await request.post("http://127.0.0.1:54329/__reset_world",{headers});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
test("headquarters rank controls, approvals and settings persist",async({page,request})=>{
 await request.post(setup,{headers,data:{application:true}});await page.goto("/gangs");
 await expect(page.getByRole("heading",{name:"Cobalto Family",exact:true})).toBeVisible();
 await page.getByRole("navigation",{name:"Gang sections"}).getByRole("button",{name:"members",exact:true}).click();
 const jack=page.locator(".gh-members article").filter({hasText:"HarborJack"});await jack.getByRole("button",{name:"Change rank"}).click();await page.getByLabel("Member rank",{exact:true}).selectOption("underboss");await page.getByRole("button",{name:"Save rank",exact:true}).click();await expect(jack).toContainText("Underboss");
 await page.getByRole("navigation",{name:"Gang sections"}).getByRole("button",{name:/requests/}).click();await page.locator(".gh-applications").getByRole("button",{name:"Accept",exact:true}).click();await page.getByRole("button",{name:"Accept request",exact:true}).click();await expect(page.locator(".gh-applications article")).toHaveCount(0);
 await page.getByRole("button",{name:"Gang settings",exact:true}).click();await page.getByLabel("Gang description").fill("Our name carries weight.");await page.getByLabel("Recruitment",{exact:true}).selectOption("closed");await page.getByRole("button",{name:"Save gang settings"}).click();await page.reload();await expect(page.locator(".gh-motto")).toHaveText("Our name carries weight.");await expect(page.locator(".gh-stats")).toContainText("Closed");
});
test("visitor requests send a Telegram and keep the bank private",async({page,request})=>{
 await request.post(setup,{headers,data:{role:"visitor"}});await page.goto("/gangs?gang="+gid);
 await expect(page.getByRole("button",{name:"Deposit money",exact:true})).toHaveCount(0);await expect(page.getByRole("button",{name:"Gang bank",exact:true})).toHaveCount(0);
 await page.getByRole("button",{name:"Request to join",exact:true}).click();await page.getByRole("button",{name:"Send join request",exact:true}).click();await expect(page.locator(".gh-pending")).toContainText("pending");await page.reload();await expect(page.locator(".gh-pending")).toBeVisible();
 await page.goto("/telegrams");await page.locator(".tg-conversations").getByRole("button").filter({hasText:"Join request"}).click();await expect(page.getByRole("link",{name:"Open gang headquarters"})).toHaveAttribute("href","/gangs?gang="+gid+"&tab=requests");
});
test("bank deposits update both balances and retries are idempotent",async({page})=>{
 await page.goto("/gangs");await page.getByRole("navigation",{name:"Gang sections"}).getByRole("button",{name:"Gang bank",exact:true}).click();
 let original="",calls=0;await page.route("**/rest/v1/rpc/gang_action",async route=>{calls++;if(calls===1){original=route.request().postData()??"";await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(original);await route.continue();}});
 await page.getByRole("button",{name:"Deposit money",exact:true}).click();await page.getByLabel("Amount ($)",{exact:true}).fill("1000");await page.getByRole("button",{name:"Confirm deposit"}).click();await page.getByRole("button",{name:"Retry safely"}).click();await expect(page.getByRole("dialog")).toHaveCount(0);await expect(page.locator(".gh-balance")).toHaveText("$1,000");await expect(page.locator(".header-cash")).toContainText("$9,000");await expect(page.locator(".gh-statement tbody tr")).toHaveCount(1);
});
test("member permissions, stale ranks and season changes fail safely",async({page,request})=>{
 await page.goto("/gangs?tab=members");const jack=page.locator(".gh-members article").filter({hasText:"HarborJack"});await jack.getByRole("button",{name:"Change rank"}).click();await page.getByLabel("Member rank",{exact:true}).selectOption("capo");await request.post(setup,{headers,data:{stale:true}});await page.getByRole("button",{name:"Save rank"}).click();await expect(page.getByRole("dialog")).toContainText("member changed");await page.getByRole("button",{name:"Close gang action"}).click();
 await request.post(setup,{headers,data:{role:"member"}});await page.reload();await expect(page.getByRole("button",{name:"Change rank"})).toHaveCount(0);await expect(page.getByRole("button",{name:"Gang settings",exact:true})).toHaveCount(0);
 await page.getByRole("navigation",{name:"Gang sections"}).getByRole("button",{name:"Gang bank",exact:true}).click();await expect(page.getByRole("button",{name:"Withdraw funds"})).toHaveCount(0);
 await page.getByRole("button",{name:"Deposit money",exact:true}).click();await page.getByLabel("Amount ($)",{exact:true}).fill("100");await request.post(setup,{headers,data:{nextSeason:true}});await page.getByRole("button",{name:"Confirm deposit"}).click();await expect(page.getByRole("dialog")).toContainText("season changed");
});
test("statements paginate and the gang layout works on mobile and desktop",async({page,request})=>{
 await request.post(setup,{headers,data:{history:true,application:true}});await page.setViewportSize({width:1672,height:1100});await page.goto("/gangs");await capture(page,"gangs-desktop");
 await page.getByRole("navigation",{name:"Gang sections"}).getByRole("button",{name:"Gang bank",exact:true}).click();await expect(page.locator(".gh-statement tbody tr")).toHaveCount(10);await page.getByRole("button",{name:"Next →",exact:true}).click();await expect(page.locator(".gh-statement tbody tr")).toHaveCount(4);await capture(page,"gangs-bank-desktop");
 for(const width of [1448,1200,1024,850,768,650,580,390,360]){await page.setViewportSize({width,height:1100});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"Overflow at "+width).toBe(true);}
 await page.setViewportSize({width:390,height:844});await page.getByRole("navigation",{name:"Gang sections"}).getByRole("button",{name:"members",exact:true}).click();await page.evaluate(()=>scrollTo(0,0));await capture(page,"gangs-mobile-members");await page.getByRole("button",{name:"Change rank"}).first().click();expect(await page.getByRole("dialog").evaluate(e=>e.getBoundingClientRect().width)).toBeLessThan(390);
});
