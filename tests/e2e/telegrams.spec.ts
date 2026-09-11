import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
async function capture(page:Page,name:string){const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:65,fullPage:true});if(process.env.VISUAL_REVIEW==="1"){const encoded=shot.toString("base64");for(let n=0;n<encoded.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+encoded.slice(n,n+12000));}}
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

