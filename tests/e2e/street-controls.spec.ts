import {test,expect} from '@playwright/test';
import {cookie,token} from '../fixtures/identity.mjs';
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=='1','Isolated fixture only');await request.post('http://127.0.0.1:54329/__reset_world',{headers:{Authorization:'Bearer '+token}});await context.addCookies([{name:'sb-127-auth-token',value:cookie,domain:'localhost',path:'/',sameSite:'Lax'}]);});
test('default street entry, stance, hotbar and in-place inventory',async({page})=>{
 test.setTimeout(90000);await page.setViewportSize({width:960,height:720});await page.addInitScript(()=>localStorage.setItem('blackwater:street-quality','performance'));
 await page.route('**/rest/v1/rpc/street_combat_state',route=>route.fulfill({json:{players:[]}}));
 await page.goto('/bin-diving?district=the-waterfront');
 await expect(page.locator('.fp-street')).toBeVisible({timeout:30000});await expect(page.locator('.fp-loading')).toHaveCount(0,{timeout:30000});
 await page.getByRole('button',{name:'Walk the streets',exact:true}).click();await expect(page.locator('.fp-crosshair')).toBeVisible();
 await page.keyboard.press('KeyC');await expect(page.locator('.fp-canvas canvas')).toHaveAttribute('data-stance','crouched');await page.keyboard.press('KeyC');
 await page.keyboard.down('KeyQ');await expect(page.locator('.fp-canvas canvas')).toHaveAttribute('data-lean','1');await page.keyboard.up('KeyQ');
 await page.keyboard.press('Digit3');await expect(page.locator('.fp-equipment-slots button').nth(2)).toHaveAttribute('data-active','true');
 await page.mouse.wheel(0,120);await expect(page.locator('.fp-equipment-slots button').nth(3)).toHaveAttribute('data-active','true');
 await page.keyboard.press('Tab');await expect(page.getByRole('dialog',{name:'Inventory and equipment',exact:true})).toBeVisible();await expect(page.locator('.inv-loadout-page')).toBeVisible();
 await page.getByRole('button',{name:'Return to streets · Tab',exact:true}).click();await expect(page.locator('.fp-inventory-dialog')).toHaveCount(0);await expect(page).toHaveURL(/bin-diving/);
});
