import {test,expect} from '@playwright/test';
import {cookie,token} from '../fixtures/identity.mjs';
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=='1','Isolated fixture only');await request.post('http://127.0.0.1:54329/__reset_world',{headers:{Authorization:'Bearer '+token}});await context.addCookies([{name:'sb-127-auth-token',value:cookie,domain:'localhost',path:'/',sameSite:'Lax'}]);});
test('walk to cars, require a tool, consume it once and award Lockpicking XP',async({page,request})=>{
 await page.goto('/bin-diving?district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();
 await expect(page.getByRole('group',{name:/scavenging street map/})).toBeVisible();
 await page.locator('.scav-target[aria-label^="Car"]').first().click();await expect(page.getByRole('button',{name:'Lockpick required'})).toBeDisabled();
 // Acquire the real tool through the existing loot fixture rather than fake UI balances.
 await request.post('http://127.0.0.1:54329/__bin_setup',{headers:{Authorization:'Bearer '+token},data:{next:'lockpick',ready:true}});
 await page.locator('.scav-target[aria-label^="Bin"]').first().click();await page.getByRole('button',{name:'Search the bins',exact:true}).click();await page.getByRole('button',{name:'Collect search'}).click();
 await request.post('http://127.0.0.1:54329/__bin_setup',{headers:{Authorization:'Bearer '+token},data:{next:'cash',ready:true}});await page.getByRole('button',{name:'Refresh bin diving'}).click();
 await page.locator('.scav-target[aria-label^="Car"]').first().click();await page.getByRole('button',{name:'Lockpick car',exact:true}).click();
 await expect(page.locator('.scav-desk-actions')).toContainText('0 lockpicks carried');
 await page.reload();await expect(page.getByRole('button',{name:'Collect search'})).toBeVisible();await page.getByRole('button',{name:'Collect search'}).click();
 await expect(page.locator('.bin-notice')).toContainText('+25 Lockpicking XP');await expect(page.locator('.scav-target.searched')).toHaveCount(2);
 await page.goto('/skills');await expect(page.locator('.skills-workspace')).toContainText('Lockpicking');
});
test('named streets, keyboard movement, map zoom and phone layout',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await page.goto('/bin-diving?district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();
 await expect(page.locator('.scav-map')).toContainText('Harbor Road');
 const destination=page.getByRole('button',{name:'Walk to Harbor Road, block 2',exact:true});await destination.focus();await page.keyboard.press('Enter');
 await expect(page.locator('.scav-action-desk')).toContainText('Choose your next stop');await page.getByRole('button',{name:'Zoom in',exact:true}).click();await expect(page.locator('.scav-map')).toHaveAttribute('style',/125%/);
 for(const width of [1440,1024,768,390,360]){await page.setViewportSize({width,height:900});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);}
 await page.locator('.scav-workspace').scrollIntoViewIfNeeded();const image=await page.screenshot({path:'test-results/scavenging-mobile.jpg',type:'jpeg',quality:65});
 if(process.env.VISUAL_REVIEW==='1'){const b=image.toString('base64');for(let n=0;n<b.length;n+=12000)console.log('VISUAL_REVIEW_scavenging-mobile_'+Math.floor(n/12000)+':'+b.slice(n,n+12000));}
});
