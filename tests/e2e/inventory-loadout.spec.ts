import {test,expect} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const headers={Authorization:"Bearer "+token};
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixture");await request.post("http://127.0.0.1:54329/__reset_world",{headers});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
test("twenty saved slots, six equipment spaces, drag swaps and touch movement",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{full:true,storage:true}});await page.setViewportSize({width:1672,height:1600});await page.goto("/inventory");
 await expect(page.locator(".inv-slot")).toHaveCount(20);await expect(page.locator(".inv-gear-slot")).toHaveCount(6);await expect(page.locator(".inv-carry-capacity")).toContainText("100 kg");
 for(const label of ["Primary weapon","Secondary weapon","Ammo","Armor","Utility","Medical"])await expect(page.locator(".inv-gear-slot").filter({hasText:label})).toBeVisible();
 const pickaxe=page.locator(".inv-slot .inv-item").filter({hasText:"Pickaxe"});await pickaxe.dragTo(page.locator('[data-slot="20"]'));await expect(page.locator('[data-slot="20"]')).toContainText("Pickaxe");
 await page.reload();await expect(page.locator('[data-slot="20"]')).toContainText("Pickaxe");
 await page.locator('[data-slot="20"] .inv-item').dragTo(page.locator('[data-slot="1"]'));await expect(page.locator('[data-slot="1"]')).toContainText("Pickaxe");
 await page.setViewportSize({width:390,height:844});await page.locator('[data-slot="1"] .inv-item').click();await page.getByRole("button",{name:"Move",exact:true}).click();await page.locator('[data-slot="19"] button').click();await expect(page.locator('[data-slot="19"]')).toContainText("Pickaxe");
 await page.reload();await expect(page.locator('[data-slot="19"]')).toContainText("Pickaxe");expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
test("equipment drag, wear, unequip, safe storage and retrieval",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{full:true,storage:true}});await page.setViewportSize({width:1672,height:1600});await page.goto("/inventory");
 await page.locator(".inv-slot .inv-item").filter({hasText:"Pickaxe"}).dragTo(page.getByRole("button",{name:"Utility, empty",exact:true}));
 await expect(page.getByRole("button",{name:"Utility: Pickaxe",exact:true})).toBeVisible();
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{condition:37}});await page.reload();
 await page.getByRole("button",{name:"Utility: Pickaxe",exact:true}).click();await page.getByRole("button",{name:"Unequip",exact:true}).click();
 await expect(page.getByRole("button",{name:"Utility, empty",exact:true})).toBeVisible();const worn=page.locator(".inv-slot .inv-item").filter({hasText:"Condition 37"});await worn.click();
 await page.getByRole("button",{name:"Store",exact:true}).click();await page.getByRole("button",{name:"Confirm storage"}).click();await expect(page.getByRole("dialog")).toHaveCount(0);
 await page.getByRole("navigation",{name:"Inventory locations"}).getByRole("button",{name:/Secure storage/}).click();await page.locator(".inv-item").filter({hasText:"Condition 37"}).click();
 await page.getByRole("button",{name:"Retrieve",exact:true}).click();await page.getByRole("button",{name:"Confirm retrieval"}).click();await expect(page.getByRole("dialog")).toHaveCount(0);
 await page.getByRole("navigation",{name:"Inventory locations"}).getByRole("button",{name:/Carried/}).click();await page.locator(".inv-item").filter({hasText:"Condition 37"}).click();await page.getByRole("button",{name:"Equip pickaxe",exact:true}).click();await page.getByRole("button",{name:"Confirm equipment"}).click();
 await expect(page.getByRole("button",{name:"Utility: Pickaxe",exact:true})).toContainText("Condition 37");
});
test("full carried weight blocks delivery collection until room is freed",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{storage:true,quantity:50,delivery:true}});await page.goto("/inventory");
 await page.locator(".inv-deliveries").getByRole("button",{name:"Collect",exact:true}).click();await expect(page.getByRole("button",{name:"Collect goods",exact:true})).toBeDisabled();await page.getByRole("button",{name:"Close delivery collection"}).click();
 await page.getByLabel("Search inventory").fill("Whiskey");await page.getByRole("button",{name:"Store",exact:true}).click();await page.getByLabel("Quantity",{exact:true}).fill("20");await page.getByRole("button",{name:"Confirm storage"}).click();await expect(page.getByRole("dialog")).toHaveCount(0);
 await page.locator(".inv-deliveries").getByRole("button",{name:"Collect",exact:true}).click();await page.getByLabel("Quantity",{exact:true}).fill("10");await page.getByRole("button",{name:"Collect goods",exact:true}).click();await expect(page.getByRole("dialog")).toHaveCount(0);await expect(page.locator(".inv-deliveries")).toHaveCount(0);
});


test("unequipped pristine equipment rejoins its carried stack",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{full:true}});await page.setViewportSize({width:1672,height:1600});await page.goto("/inventory");
 const stack=()=>page.locator(".inv-slot .inv-item").filter({hasText:"Pickaxe"});
 await stack().dragTo(page.getByRole("button",{name:"Utility, empty",exact:true}));await expect(stack()).toContainText("×2");
 await page.getByRole("button",{name:"Utility: Pickaxe",exact:true}).dragTo(stack());
 await expect(page.getByRole("button",{name:"Utility, empty",exact:true})).toBeVisible();await expect(stack()).toHaveCount(1);await expect(stack()).toContainText("×3");
 await page.reload();await expect(stack()).toHaveCount(1);await expect(stack()).toContainText("×3");
});
test("choose ammunition quantity, top up by drag, and restack on mobile",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__crafting_setup",{headers,data:{grant:{"homemade-bullets":100}}});await page.setViewportSize({width:1672,height:1600});await page.goto("/inventory");
 const rounds=()=>page.locator(".inv-slot .inv-item").filter({hasText:"Homemade bullets"});
 await rounds().click();await page.getByRole("button",{name:"Equip Ammo",exact:false}).click();await page.getByLabel("Amount to equip").fill("30");await page.getByRole("button",{name:"Confirm equipment",exact:true}).click();
 const ammo=page.getByRole("button",{name:"Ammo: Homemade bullets",exact:true});await expect(ammo).toContainText("×30 equipped");await expect(rounds()).toContainText("×70");
 await rounds().dragTo(ammo);await expect(page.getByRole("dialog")).toBeVisible();await page.getByLabel("Amount to equip").fill("71");await expect(page.getByRole("button",{name:"Confirm equipment",exact:true})).toBeDisabled();
 await page.getByLabel("Amount to equip").fill("20");await page.getByRole("button",{name:"Confirm equipment",exact:true}).click();await expect(ammo).toContainText("×50 equipped");await expect(rounds()).toContainText("×50");
 await page.reload();await expect(ammo).toContainText("×50 equipped");await page.setViewportSize({width:390,height:844});await ammo.click();await page.getByRole("button",{name:"Unequip",exact:true}).click();
 await expect(page.getByRole("button",{name:"Ammo, empty",exact:true})).toBeVisible();await expect(rounds()).toHaveCount(1);await expect(rounds()).toContainText("×100");
 await rounds().click();await page.getByRole("button",{name:"Move",exact:true}).click();await page.getByRole("button",{name:"Ammo, empty",exact:true}).click();await page.getByRole("button",{name:"Use maximum",exact:true}).click();await expect(page.getByLabel("Amount to equip")).toHaveValue("100");await page.getByRole("button",{name:"Confirm equipment",exact:true}).click();await expect(ammo).toContainText("×100 equipped");await expect(rounds()).toHaveCount(0);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});

test("broken weapon scrapping confirms destruction and safely retries without duplicate scrap",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{brokenWeapon:true}});await page.goto("/inventory");await page.getByRole("button",{name:"Secondary weapon: Homemade pistol",exact:true}).click();
 page.once("dialog",d=>d.dismiss());await page.getByRole("button",{name:"Scrap weapon",exact:true}).click();await expect(page.getByRole("button",{name:"Secondary weapon: Homemade pistol",exact:true})).toBeVisible();
 let first=true;await page.route("**/rest/v1/rpc/inventory_action",async route=>{if(route.request().postDataJSON().p_action==="scrap_weapon"&&first){first=false;await route.fetch();await route.abort();}else await route.continue();});
 page.once("dialog",d=>d.accept());await page.getByRole("button",{name:"Scrap weapon",exact:true}).click();await page.getByRole("button",{name:"Retry safely",exact:true}).click();await expect(page.getByRole("button",{name:"Secondary weapon, empty",exact:true})).toBeVisible();
 await expect(page.locator(".inv-slot .inv-item").filter({hasText:"Scrap metal"})).toContainText("×1");await page.reload();await expect(page.locator(".inv-slot .inv-item").filter({hasText:"Scrap metal"})).toContainText("×1");
});

test("inventory coalesces refresh bursts and ignores an older read after equipment changes",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{full:true,storage:true}});await page.goto("/inventory");
 let reads=0,captured=false;let release!:()=>void;const hold=new Promise<void>(resolve=>{release=resolve;});
 await page.route("**/rest/v1/rpc/inventory_state",async route=>{reads++;if(reads===1){const response=await route.fetch();const json=await response.json();captured=true;await hold;await route.fulfill({response,json});}else await route.continue();});
 await page.getByRole("button",{name:"Refresh inventory",exact:true}).click();await expect.poll(()=>captured).toBe(true);
 await page.evaluate(()=>{for(let i=0;i<8;i++)window.dispatchEvent(new Event('focus'));});expect(reads).toBe(1);
 await page.locator(".inv-slot .inv-item").filter({hasText:"Pickaxe"}).click();await page.getByRole("button",{name:"Equip pickaxe",exact:true}).click();await page.getByRole("button",{name:"Confirm equipment",exact:true}).click();
 await expect(page.getByRole("button",{name:"Utility: Pickaxe",exact:true})).toBeVisible();expect(reads).toBe(2);
 const oldResponse=page.waitForResponse(r=>r.url().endsWith('/rpc/inventory_state'));release();await (await oldResponse).finished();await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
 await expect(page.getByRole("button",{name:"Utility: Pickaxe",exact:true})).toBeVisible();await expect(page.getByRole("button",{name:"Refresh inventory",exact:true})).toBeEnabled();
});
