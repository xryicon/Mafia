import {test,expect,type Page} from "@playwright/test";
import {readFile} from "node:fs/promises";
import {token} from "../fixtures/identity.mjs";
const valid="a".repeat(64);
async function capture(page:Page,name:string){const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:73,fullPage:true});if(process.env.VISUAL_REVIEW==="1"){const b=shot.toString("base64");for(let n=0;n<b.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+b.slice(n,n+12000));}}
test.beforeEach(async({request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated confirmation fixture");await request.post("http://127.0.0.1:54329/__reset_confirmation",{headers:{Authorization:"Bearer "+token}});});
test("email confirmation works on a fresh browser and leads into the game",async({page})=>{
 await page.setViewportSize({width:1100,height:1000});
 await page.goto("/auth/confirm?token_hash="+valid+"&type=email&next=https://evil.example");
 await expect(page).toHaveURL(/\/auth\/confirmed$/);await expect(page.getByRole("heading",{name:"Account confirmed.",exact:true})).toBeVisible();
 await expect.poll(()=>page.locator(".confirmation-backdrop").evaluate((el:HTMLImageElement)=>el.complete&&el.naturalWidth>0)).toBe(true);
 await capture(page,"confirmation-desktop");await page.getByRole("link",{name:"ENTER BLACKWATER",exact:true}).click();await expect(page).toHaveURL(/\/dashboard$/);
 await page.goto("/auth/confirmed");await page.setViewportSize({width:375,height:812});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await capture(page,"confirmation-mobile");
});
test("invalid or reused email links never display successful confirmation",async({page,request})=>{
 const pending=await request.get("/auth/confirmed?confirmed=true");expect(await pending.text()).toContain("Check your invitation.");expect(await pending.text()).not.toContain("Account confirmed.");
 for(const query of ["","?token_hash="+valid+"&type=recovery","?token_hash="+"b".repeat(64)+"&type=email"]){
  await page.goto("/auth/confirm"+query);await expect(page).toHaveURL(/\/auth\/confirmed\?error=invalid-link$/);await expect(page.getByRole("heading",{name:"This link has expired.",exact:true})).toBeVisible();
 }
 await page.getByText("Need a new confirmation link?",{exact:true}).click();await page.getByLabel("Email address").fill("player@example.test");await page.getByRole("button",{name:"Send a new confirmation link"}).click();await expect(page.getByRole("status")).toContainText("If this account is waiting");
 await page.goto("/auth/confirm?token_hash="+valid+"&type=email");await expect(page.getByRole("heading",{name:"Account confirmed.",exact:true})).toBeVisible();
 await page.goto("/auth/confirm?token_hash="+valid+"&type=email");await expect(page.getByRole("heading",{name:"This link has expired.",exact:true})).toBeVisible();
});
test("confirmation response clears tokens and preserves reset callback destination",async({request})=>{
 const response=await request.get("/auth/confirm?token_hash="+valid+"&type=email",{maxRedirects:0});
 expect(response.headers()["location"]).toMatch(/\/auth\/confirmed$/);expect(response.headers()["cache-control"]).toContain("no-store");expect(response.headers()["referrer-policy"]).toBe("no-referrer");expect(response.headers()["set-cookie"]).toContain("sb-127");
 const reset=await request.get("/auth/callback?code=fixture-reset&next=/update-password",{maxRedirects:0});expect(reset.headers()["location"]).toMatch(/\/update-password$/);
 const signup=await request.get("/auth/callback?code=fixture-signup",{maxRedirects:0});expect(signup.headers()["location"]).toMatch(/\/auth\/confirmed$/);
});
test("branded confirmation email renders on desktop and mobile with working links",async({page})=>{
 const html=(await readFile("supabase/templates/confirmation.html","utf8")).replaceAll("{{ .SiteURL }}","http://localhost:3000").replaceAll("{{ .TokenHash }}",valid);
 await page.setViewportSize({width:750,height:1100});await page.setContent(html);
 await expect(page.getByRole("heading",{name:"Almost there.",exact:true})).toBeVisible();
 await expect.poll(()=>page.locator("img").evaluateAll(imgs=>imgs.every(i=>(i as HTMLImageElement).complete&&(i as HTMLImageElement).naturalWidth>0))).toBe(true);
 await capture(page,"confirmation-email-desktop");await page.setViewportSize({width:375,height:812});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await capture(page,"confirmation-email-mobile");
 await page.getByRole("link",{name:/CONFIRM ACCOUNT/}).click();await expect(page.getByRole("heading",{name:"Account confirmed.",exact:true})).toBeVisible();
});
