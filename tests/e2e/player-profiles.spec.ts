import {test,expect,type Page} from "@playwright/test";
import {cookie,token,playerId} from "../fixtures/identity.mjs";
const headers={Authorization:"Bearer "+token},other="33333333-3333-4333-8333-333333333333";
async function capture(page:Page,name:string){const s=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:70,fullPage:true});if(process.env.VISUAL_REVIEW==="1"){const b=s.toString("base64");for(let i=0;i<b.length;i+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(i/12000)+":"+b.slice(i,i+12000));}}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated profile world");await request.post("http://127.0.0.1:54329/__reset_world",{headers});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
test("public player profile follows the reference without health or achievements",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__profile_setup",{headers,data:{archived:true}});await page.setViewportSize({width:1550,height:1100});await page.goto("/players/"+other);
 await expect(page.getByRole("heading",{name:"HarborJack",exact:true})).toBeVisible();await expect(page.locator(".pp-description")).toContainText("Trade fairly");await expect(page.locator(".pp-page")).not.toContainText(/Health|Achievements|Hall of Fame/);await expect(page.getByRole("button",{name:"Edit profile",exact:true})).toHaveCount(0);
 await expect(page.locator(".pp-empire")).toContainText("Backroom distillery");await expect(page.locator(".pp-previous")).toContainText("The First Light");await capture(page,"profile-desktop");
 for(const width of [1448,1150,1024,900,768,650,580,390,360]){await page.setViewportSize({width,height:1000});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"Profile overflow at "+width).toBe(true);}
 await page.setViewportSize({width:390,height:844});await capture(page,"profile-mobile");
 await page.getByRole("link",{name:"Send Telegram",exact:true}).click();await expect(page).toHaveURL(/telegrams\?to=HarborJack/);await expect(page.getByLabel("To",{exact:true})).toHaveValue("HarborJack");await expect(page.getByRole("button",{name:"Send Telegram",exact:true})).toBeVisible();
});
test("description edits persist, render as text, and can be cleared",async({page})=>{
 await page.goto("/profile");await expect(page).toHaveURL("/players/"+playerId);await page.getByRole("button",{name:"Edit profile",exact:true}).click();
 const dialog=page.getByRole("dialog"),body='<img src=x onerror="alert(1)">\nI trade ore at the docks.';
 await dialog.getByLabel("Profile description",{exact:true}).fill(body);await dialog.getByRole("button",{name:"Save description",exact:true}).click();await expect(dialog.getByRole("status")).toContainText("Profile description saved");
 await dialog.getByRole("button",{name:"Close profile editor"}).click();await expect(page.locator(".pp-description")).toHaveText(body);await expect(page.locator(".pp-description img")).toHaveCount(0);
 await page.reload();await expect(page.locator(".pp-description")).toHaveText(body);await page.getByRole("button",{name:"Edit profile",exact:true}).click();await dialog.getByLabel("Profile description",{exact:true}).fill("");await dialog.getByRole("button",{name:"Save description",exact:true}).click();await expect(dialog.getByRole("status")).toContainText("saved");
 await dialog.getByRole("button",{name:"Close profile editor"}).click();await expect(page.locator(".pp-description")).toContainText("hasn’t added a description");
});
test("stale description edits are rejected and the editor is usable on mobile",async({page,request})=>{
 await page.setViewportSize({width:390,height:844});await page.goto("/profile");await page.getByRole("button",{name:"Edit profile",exact:true}).click();const dialog=page.getByRole("dialog");
 await dialog.getByLabel("Profile description",{exact:true}).fill("My unsaved draft");await request.post("http://127.0.0.1:54329/__profile_setup",{headers,data:{description:"Saved in another tab"}});
 await dialog.getByRole("button",{name:"Save description",exact:true}).click();await expect(dialog.getByRole("status")).toContainText("changed in another tab");await expect(dialog.getByRole("button",{name:"Save description",exact:true})).toBeDisabled();await capture(page,"profile-mobile-editor");
 await dialog.getByRole("button",{name:"Close profile editor"}).click();await expect(page.locator(".pp-description")).toHaveText("Saved in another tab");await page.getByRole("button",{name:"Edit profile",exact:true}).click();await expect(dialog.getByLabel("Profile description",{exact:true})).toHaveValue("Saved in another tab");expect(await dialog.evaluate(el=>el.getBoundingClientRect().width)).toBeLessThan(390);
});
test("profile pictures update on the dossier and player directory",async({page})=>{
 const photo="https://images.example.test/profile-owner.jpg";await page.route(photo,async route=>{const r=await page.request.get("/art/command-portrait.jpg");await route.fulfill({body:await r.body(),contentType:"image/jpeg"});});
 await page.goto("/profile");await page.getByRole("button",{name:"Edit profile",exact:true}).click();const dialog=page.getByRole("dialog");await dialog.getByLabel("Profile image URL").fill(photo);await dialog.getByRole("button",{name:"Save picture",exact:true}).click();await expect(dialog.getByRole("status")).toContainText("Profile picture saved");await dialog.getByRole("button",{name:"Close profile editor"}).click();await expect(page.locator(".pp-portrait")).toHaveAttribute("src",photo);await expect(page.locator(".don-portrait")).toHaveAttribute("src",photo);
 await page.goto("/players");await expect(page.locator(".directory-name").filter({hasText:"HarborBoss"}).locator("img")).toHaveAttribute("src",photo);await page.locator(".directory-name").filter({hasText:"HarborJack"}).click();await expect(page.locator(".pp-identity h1")).toHaveText("HarborJack");
});
test("unknown profiles do not fall back to the signed-in player",async({page})=>{
 const r=await page.goto("/players/00000000-0000-4000-8000-000000000000");expect(r?.status()).toBe(404);await expect(page.locator(".pp-page")).toHaveCount(0);
});
