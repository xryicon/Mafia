import {test,expect} from '@playwright/test';
import {cookie,token} from '../fixtures/identity.mjs';
const base='http://127.0.0.1:54329',headers={Authorization:'Bearer '+token};
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=='1','Isolated fixture only');await request.post(base+'/__reset_world',{headers});await context.addCookies([{name:'sb-127-auth-token',value:cookie,domain:'localhost',path:'/',sameSite:'Lax'}]);});
test('simple searches collect automatically without loading a 3D map',async({page,request})=>{
 await page.goto('/bin-diving?district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();await expect(page.locator('.simple-scav-grid')).toBeVisible();await expect(page.locator('.fp-canvas,.scav-map')).toHaveCount(0);
 await expect(page.getByRole('button',{name:'Lockpick required'}).first()).toBeDisabled();
 await request.post(base+'/__bin_setup',{headers,data:{next:'lockpick',ready:true}});await page.getByRole('button',{name:'Search bin',exact:true}).first().click();await expect(page.locator('.bin-result')).toContainText('Lockpick');
 await request.post(base+'/__bin_setup',{headers,data:{next:'cash',ready:true}});await page.getByRole('button',{name:'Refresh bin diving'}).click();await page.getByRole('button',{name:'Lockpick car',exact:true}).first().click();
 await expect(page.locator('.bin-notice')).toContainText('+25 Lockpicking XP');await expect(page.locator('.bin-history li')).toHaveCount(2);
});
test('text choices remain readable on desktop and phone',async({page})=>{
 await page.goto('/bin-diving');await page.getByRole('button',{name:/^Enter /}).click();for(const width of [1440,768,390,360]){await page.setViewportSize({width,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await expect(page.getByRole('button',{name:'Search bin',exact:true}).first()).toBeVisible();}await page.screenshot({path:'test-results/simple-scavenging-mobile.png'});
});
test('police still arrest players caught searching',async({page,request})=>{
 await request.post(base+'/__patrol_setup',{headers,data:{enabled:true,catchSearch:true}});await page.goto('/bin-diving');await page.getByRole('button',{name:/^Enter /}).click();await expect(page.locator('.simple-risk')).toContainText('1 police patrols');await page.getByRole('button',{name:'Search bin',exact:true}).first().click();await expect(page).toHaveURL(/districts\/blackwater-island/);
});

test('heat and skill are readable while supporting panels stay collapsed',async({page})=>{
 await page.route('**/rest/v1/rpc/bin_diving_state',async route=>{const response=await route.fetch();const data=await response.json();data.scavenging.district_risk=Object.fromEntries(data.districts.map((d:{id:string})=>[d.id,{level:10,heat:48,searches:6,skill_reduction_percent:23.7,detection_multiplier:1.12,heat_per_search:8,cooling_per_minute:1}]));await route.fulfill({response,json:data});});
 await page.goto('/bin-diving');await expect(page.getByLabel('District heat and skill')).toContainText('Level 10');await expect(page.getByLabel('District heat',{exact:true})).toHaveAttribute('value','48');
 await expect(page.locator('.street-loot-guide[open]')).toHaveCount(0);
 await page.getByRole('button',{name:/^Enter /}).click();await expect(page.getByRole('button',{name:'Search bin',exact:true}).first()).toBeVisible();
 await page.setViewportSize({width:360,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:'test-results/scavenging-heat-mobile.png'});
 await page.locator('summary').filter({hasText:'Loot guide & current chances'}).click();await expect(page.locator('.bin-odds')).toBeVisible();
});
