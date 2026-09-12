import {test,expect} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const headers={Authorization:"Bearer "+token};
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixture");await request.post("http://127.0.0.1:54329/__reset_world",{headers});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);});
test("twenty saved slots, six equipment spaces, drag swaps and touch movement",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{full:true,storage:true}});await page.goto("/inventory");
 await expect(page.locator(".inv-slot")).toHaveCount(20);await expect(page.locator(".inv-gear-slot")).toHaveCount(6);await expect(page.locator(".inv-carry-capacity")).toContainText("100 kg");
 for(const label of ["Primary weapon","Secondary weapon","Ammo","Armor","Utility","Medical"])await expect(page.locator(".inv-gear-slot").filter({hasText:label})).toBeVisible();
 const pickaxe=page.locator(".inv-slot .inv-item").filter({hasText:"Pickaxe"});await pickaxe.dragTo(page.locator('[data-slot="20"]'));await expect(page.locator('[data-slot="20"]')).toContainText("Pickaxe");
 await page.reload();await expect(page.locator('[data-slot="20"]')).toContainText("Pickaxe");
 await page.locator('[data-slot="20"] .inv-item').dragTo(page.locator('[data-slot="1"]'));await expect(page.locator('[data-slot="1"]')).toContainText("Pickaxe");
 await page.setViewportSize({width:390,height:844});await page.locator('[data-slot="1"] .inv-item').click();await page.getByRole("button",{name:"Move",exact:true}).click();await page.locator('[data-slot="19"] button').click();await expect(page.locator('[data-slot="19"]')).toContainText("Pickaxe");
 await page.reload();await expect(page.locator('[data-slot="19"]')).toContainText("Pickaxe");expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
test("equipment drag, wear, unequip, safe storage and retrieval",async({page,request})=>{
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers,data:{full:true,storage:true}});await page.goto("/inventory");
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
