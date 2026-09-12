import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
async function capture(page:Page,name:string){await page.evaluate(()=>window.scrollTo(0,0));const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:65,fullPage:true});if(process.env.VISUAL_REVIEW==="1"){const encoded=shot.toString("base64");for(let n=0;n<encoded.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+encoded.slice(n,n+12000));}}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated Telegram fixture");await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
test("private mailbox sends a priced telegram and supports drafts and folders",async({page})=>{
 await page.setViewportSize({width:1448,height:1086});await page.goto("/telegrams");
 await expect(page.getByRole("heading",{name:"Telegrams",exact:true})).toBeVisible();
 await page.locator(".tg-conversations").getByRole("button").first().click();
 await expect(page.locator(".tg-message-feed")).toContainText("The docks are ready");
 await capture(page,"telegrams-desktop");
 await page.getByLabel("Your reply").fill("Confirm 200 crates. Delivery to the Waterfront.");
 await expect(page.locator(".tg-send-terms")).toContainText("$25");await page.getByRole("button",{name:"Send Telegram",exact:true}).click();
 await expect(page.locator(".tg-message-feed")).toContainText("Confirm 200 crates");
 await expect(page.locator(".header-cash")).toContainText("$9,975");
 await page.getByRole("button",{name:"New Telegram",exact:true}).click();await page.getByLabel("Recipient",{exact:true}).fill("HarborJack");
 await page.getByLabel("Subject",{exact:true}).fill("Warehouse partnership");await page.getByLabel("Message",{exact:true}).fill("Let us discuss warehouse capacity.");
 await page.getByRole("button",{name:"Save draft",exact:true}).click();await expect(page.locator(".tg-notice")).toContainText("Draft saved");
 await page.getByRole("navigation",{name:"Telegram folders"}).getByRole("button",{name:/Drafts/}).click();
 await page.locator(".tg-conversations").getByRole("button").first().click();await expect(page.getByLabel("Subject",{exact:true})).toHaveValue("Warehouse partnership");
 await page.getByRole("button",{name:"Send Telegram",exact:true}).click();await expect(page.locator(".tg-notice")).toContainText("delivered instantly");
 await page.getByLabel("Conversation options").click();await page.getByRole("button",{name:"Archive conversation",exact:true}).click();
 await page.getByRole("navigation",{name:"Telegram folders"}).getByRole("button",{name:"Archive",exact:true}).click();await expect(page.locator(".tg-conversations")).toContainText("Warehouse partnership");
});
test("mobile Telegrams supports reports, blocks and office management",async({page})=>{
 await page.setViewportSize({width:375,height:812});await page.goto("/telegrams");
 await page.locator(".tg-conversations").getByRole("button").first().click();
 await page.getByRole("button",{name:"Report telegram",exact:true}).click();await page.getByLabel("Why are you reporting this telegram?").fill("Please review this message.");
 await page.getByRole("button",{name:"Submit report",exact:true}).click();await expect(page.locator(".tg-notice")).toContainText("Report submitted");
 await page.getByLabel("Conversation options").click();await page.getByRole("button",{name:"Block player",exact:true}).click();await expect(page.locator(".tg-unavailable")).toContainText("Unblock this player");
 await expect(page.getByRole("button",{name:"Send Telegram",exact:true})).toBeDisabled();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await capture(page,"telegrams-mobile");
 await page.getByRole("button",{name:"Manage Office",exact:true}).click();const dialog=page.getByRole("dialog");
 await expect(dialog).toBeVisible();await dialog.getByLabel("Fee per telegram",{exact:true}).fill("0");await dialog.getByLabel("Reason for this change").first().fill("Free city telegrams");
 await dialog.getByRole("button",{name:"Save office terms",exact:true}).click();await expect(dialog).toContainText("Office updated");
 await page.getByRole("button",{name:"Close office management"}).click();await expect(page.locator(".tg-send-terms")).toContainText("Free");
 await page.goto("/owner?section=telegrams");await expect(page.getByRole("heading",{name:"City Telegram Office",exact:true})).toBeVisible();
 await expect(page.getByLabel("Minimum fee",{exact:true})).toHaveValue("0");
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
test("a closed office prevents sending while existing conversations remain readable",async({page})=>{
 await page.goto("/telegrams");await page.getByRole("button",{name:"Manage Office",exact:true}).click();const dialog=page.getByRole("dialog");
 await dialog.getByLabel("Business status").selectOption("closed");await dialog.getByLabel("Reason for this change").first().fill("Maintenance closure");
 await dialog.getByRole("button",{name:"Save office terms",exact:true}).click();await expect(dialog).toContainText("Office updated");
 await page.getByRole("button",{name:"Close office management"}).click();await page.locator(".tg-conversations").getByRole("button").first().click();
 await expect(page.locator(".tg-message-feed")).toContainText("The docks are ready");
 await expect(page.locator(".tg-unavailable")).toContainText("Telegram service is currently unavailable.");
 await expect(page.getByRole("button",{name:"Send Telegram",exact:true})).toBeDisabled();
});


test("groups invite players, send one priced message and keep member controls private",async({page,request})=>{
 await page.setViewportSize({width:1672,height:1000});await page.goto("/telegrams");
 await page.getByRole("button",{name:"New Group",exact:true}).click();
 await page.getByRole("dialog").getByLabel("Group name",{exact:true}).fill("Waterfront Trading Circle");
 await page.getByRole("button",{name:"Create group",exact:true}).click();
 await expect(page.getByRole("heading",{name:"Waterfront Trading Circle",exact:true})).toBeVisible();
 await expect(page.getByRole("button",{name:"Send Telegram",exact:true})).toBeDisabled();
 await page.getByLabel("Invite player",{exact:true}).fill("HarborJack");await page.getByRole("button",{name:"Send invitation",exact:true}).click();
 await expect(page.getByLabel("Conversation members")).toContainText("Invitation pending");
 await request.post("http://127.0.0.1:54329/__accept_telegram_invites",{headers:{Authorization:"Bearer "+token}});
 await page.getByRole("button",{name:"Refresh mailbox",exact:true}).click();
 await expect(page.getByLabel("Conversation members")).toContainText("2 members");
 await page.getByRole("button",{name:"Close members",exact:true}).click();
 await page.getByLabel("Your reply").fill("Our warehouses are ready for the next shipment.");
 await page.getByRole("button",{name:"Send Telegram",exact:true}).click();
 await expect(page.locator(".tg-message-feed")).toContainText("Our warehouses are ready");
 await expect(page.locator(".header-cash")).toContainText("$9,975");
 await expect(page.locator(".tg-send-terms")).toContainText("$25 per group telegram");
 await expect(page.getByRole("button",{name:"Send Telegram",exact:true})).toBeEnabled();await capture(page,"telegrams-groups-desktop");
 await page.getByRole("button",{name:/2 members · View members/}).click();
 await page.getByLabel("Manage HarborJack").click();await page.getByRole("button",{name:"Make group owner",exact:true}).click();
 await expect(page.getByLabel("Invite player",{exact:true})).toHaveCount(0);
 await page.getByRole("button",{name:"Leave group",exact:true}).click();
 await expect(page.getByRole("heading",{name:"Waterfront Trading Circle",exact:true})).toHaveCount(0);
});
test("mobile gang correspondence uses dashboard styling without overflowing",async({page})=>{
 await page.setViewportSize({width:375,height:812});await page.goto("/telegrams");
 await page.getByRole("navigation",{name:"Telegram folders"}).getByRole("button",{name:"Gang",exact:true}).click();
 await page.getByRole("button",{name:"Open gang conversation",exact:true}).click();
 await expect(page.getByRole("heading",{name:"Cobalto Family",exact:true})).toBeVisible();
 await expect(page.getByRole("button",{name:"Mailbox",exact:false})).toBeVisible();
 await page.getByLabel("Your reply").fill("Meet at the harbor. Bring the crew.");
 await page.getByRole("button",{name:"Send Telegram",exact:true}).click();
 await expect(page.locator(".tg-message-feed")).toContainText("Meet at the harbor");
 await page.getByRole("button",{name:/2 members · View members/}).click();
 await expect(page.getByLabel("Conversation members")).toContainText("Access follows your current gang membership");
 await expect(page.getByLabel("Invite player",{exact:true})).toHaveCount(0);
 await capture(page,"telegrams-gang-mobile");
 for(const width of [375,768,1024,1448]){await page.setViewportSize({width,height:1000});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);}
});
test("profile pictures stay consistent in the header, profile, dashboard and sent telegrams",async({page})=>{
 const photo="https://images.example.test/harbor-boss.jpg";
 await page.route(photo,async route=>{const r=await page.request.get("/art/command-portrait.jpg");await route.fulfill({body:await r.body(),contentType:"image/jpeg"});});
 await page.goto("/account");await page.getByLabel("Profile image URL").fill(photo);await page.getByRole("button",{name:"Save picture",exact:true}).click();
 await expect(page.getByRole("status")).toContainText("Profile picture saved");
 await expect(page.locator(".don-portrait")).toHaveAttribute("src",photo);
 await page.goto("/dashboard");await expect(page.locator(".command-portrait")).toHaveAttribute("src",photo);
 await page.goto("/profile");await expect(page.locator(".pp-portrait")).toHaveAttribute("src",photo);
 await page.goto("/telegrams");await page.locator(".tg-conversations").getByRole("button").first().click();
 await expect(page.locator(".tg-thread-header .tg-seal")).toHaveAttribute("src","/art/command-portrait.jpg");
 await page.getByLabel("Your reply").fill("My portrait follows my messages.");await page.getByRole("button",{name:"Send Telegram",exact:true}).click();
 await expect(page.locator(".tg-message.outgoing .tg-seal").last()).toHaveAttribute("src",photo);
});
test("group creation reports errors and safely retries a lost confirmation",async({page})=>{
 await page.goto("/telegrams");await page.getByRole("button",{name:"New Group",exact:true}).click();
 const dialog=page.getByRole("dialog");await dialog.getByLabel("Group name",{exact:true}).fill("BlockedGroup");
 await dialog.getByRole("button",{name:"Create group",exact:true}).click();await expect(dialog.getByRole("status")).toContainText("group ownership limit");
 await dialog.getByLabel("Group name",{exact:true}).fill("Retry Partners");
 let failed=false;await page.route("**/rest/v1/rpc/telegram_room_action",async route=>{if(!failed){failed=true;await route.fetch();await route.abort("failed");}else await route.continue();});
 await dialog.getByRole("button",{name:"Create group",exact:true}).click();
 await expect(dialog.getByRole("button",{name:"Retry group change",exact:true})).toBeVisible();
 await dialog.getByRole("button",{name:"Retry group change",exact:true}).click();
 await expect(page.getByRole("heading",{name:"Retry Partners",exact:true})).toBeVisible();
 await expect(page.locator(".tg-conversations").getByRole("button").filter({hasText:"Retry Partners"})).toHaveCount(1);
});

