import {test,expect} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
test("street equipment reads real slots without mutating the loadout",async({page,context,request})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixture only");test.setTimeout(90_000);
 await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});
 await request.post("http://127.0.0.1:54329/__inventory_setup",{headers:{Authorization:"Bearer "+token},data:{condition:100}});
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
 const writes:string[]=[];page.on('request',r=>{if(r.url().includes('/rpc/inventory_action'))writes.push(r.postData()??'');});
 await page.goto('/bin-diving?view=aerial&district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();await page.getByRole('button',{name:'First-person streets'}).click();
 await expect(page.getByRole('button',{name:'Walk the streets',exact:true})).toBeVisible({timeout:30_000});await page.getByLabel('Street graphics quality').selectOption('performance');
 const bar=page.getByRole('complementary',{name:'Street equipment'});await expect(bar.getByRole('button',{name:'Primary weapon, empty'})).toBeVisible();await expect(bar.locator('.fp-equipment-slots button')).toHaveCount(6);
 await bar.getByRole('button',{name:/Utility:/}).click();await expect(page.getByRole('region',{name:'Selected equipment'})).toContainText('Pickaxe');await expect(bar.getByRole('link',{name:'Open Inventory →'})).toHaveAttribute('href','/inventory');
 await bar.getByRole('button',{name:'Close equipment details'}).click();await bar.getByRole('button',{name:'Primary weapon, empty'}).click();await expect(page.getByRole('region',{name:'Selected equipment'})).toContainText('Empty slot');expect(writes).toHaveLength(0);
 await page.setViewportSize({width:390,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);const bounds=await bar.locator('.fp-equipment-slots').boundingBox();expect(bounds!.width).toBeLessThanOrEqual(390);await page.screenshot({path:'test-results/first-person-equipment.jpg',type:'jpeg',quality:80});
});
