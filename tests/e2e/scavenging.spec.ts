import {test,expect} from '@playwright/test';
import {cookie,token} from '../fixtures/identity.mjs';
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=='1','Isolated fixture only');await request.post('http://127.0.0.1:54329/__reset_world',{headers:{Authorization:'Bearer '+token}});await context.addCookies([{name:'sb-127-auth-token',value:cookie,domain:'localhost',path:'/',sameSite:'Lax'}]);});
test('walk to cars, require a tool, consume it once and award Lockpicking XP',async({page,request})=>{
 await page.goto('/bin-diving?view=aerial&district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();
 await expect(page.getByRole('group',{name:/scavenging street map/})).toBeVisible();
 await page.locator('.scav-target[aria-label^="Car"]').first().click();await expect(page.getByRole('button',{name:'Lockpick required'})).toBeDisabled();
 // Acquire the real tool through the existing loot fixture rather than fake UI balances.
 await request.post('http://127.0.0.1:54329/__bin_setup',{headers:{Authorization:'Bearer '+token},data:{next:'lockpick',ready:true}});
 await page.locator('.scav-target[aria-label^="Bin"]').first().click();await page.getByRole('button',{name:'Search the bins',exact:true}).click();await page.waitForResponse(r=>r.url().includes("/rpc/scavenging_action")&&r.request().postDataJSON().p_action==="finish");
 await request.post('http://127.0.0.1:54329/__bin_setup',{headers:{Authorization:'Bearer '+token},data:{next:'cash',ready:true}});await page.getByRole('button',{name:'Refresh bin diving'}).click();
 await page.locator('.scav-target[aria-label^="Car"]').first().click();await page.getByRole('button',{name:'Lockpick car',exact:true}).click();
 await expect(page.locator('.scav-desk-actions')).toContainText('0 lockpicks carried');
 await page.reload();await page.waitForResponse(r=>r.url().includes("/rpc/scavenging_action")&&r.request().postDataJSON().p_action==="finish");
 await expect(page.locator('.bin-notice')).toContainText('+25 Lockpicking XP');await expect(page.locator('.scav-target.searched')).toHaveCount(2);
 await page.goto('/skills');await expect(page.locator('.skills-workspace')).toContainText('Lockpicking');await expect(page.locator('.skill-card.scavenging')).toContainText('20 XP earned');await page.getByRole('tab',{name:/Scavenging/}).click();await expect(page.getByRole('link',{name:'Go scavenging'})).toHaveAttribute('href','/bin-diving');
});
test('named streets, keyboard movement, map zoom and phone layout',async({page})=>{
 await page.setViewportSize({width:1440,height:1000});await page.goto('/bin-diving?view=aerial&district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();
 await expect(page.locator('.scav-map')).toContainText('Harbor Road');
 await expect(page.locator('.scav-map-art')).toHaveAttribute('href','/art/scavenging/blackwater-streets.webp');
 await expect.poll(()=>page.evaluate(async()=>{const image=new Image();image.src='/art/scavenging/blackwater-streets.webp';await image.decode();return image.naturalWidth;})).toBeGreaterThan(1000);
 await page.locator('.scav-map').scrollIntoViewIfNeeded();
 const desktop=await page.screenshot({path:'test-results/scavenging-real-map-desktop.jpg',type:'jpeg',quality:70});
 if(process.env.VISUAL_REVIEW==='1'){const b=desktop.toString('base64');for(let n=0;n<b.length;n+=12000)console.log('VISUAL_REVIEW_scavenging-real-map-desktop_'+Math.floor(n/12000)+':'+b.slice(n,n+12000));}
 const destination=page.getByRole('button',{name:'Walk to Harbor Road, block 2',exact:true});await destination.focus();await page.keyboard.press('Enter');
 await expect(page.locator('.scav-action-desk')).toContainText('Choose your next stop');const fittedWidth=await page.locator('.scav-map').evaluate(el=>el.getBoundingClientRect().width);await page.getByRole('button',{name:'Zoom in',exact:true}).click();await expect.poll(()=>page.locator('.scav-map').evaluate(el=>el.getBoundingClientRect().width)).toBeCloseTo(fittedWidth*1.25,0);
 for(const width of [1440,1024,768,390,360]){await page.setViewportSize({width,height:900});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);}
 await page.locator('.scav-workspace').scrollIntoViewIfNeeded();const image=await page.screenshot({path:'test-results/scavenging-mobile.jpg',type:'jpeg',quality:65});
 if(process.env.VISUAL_REVIEW==='1'){const b=image.toString('base64');for(let n=0;n<b.length;n+=12000)console.log('VISUAL_REVIEW_scavenging-mobile_'+Math.floor(n/12000)+':'+b.slice(n,n+12000));}
});
test('free street clicks send fractional destinations and street activity can be paused',async({page})=>{
 await page.goto('/bin-diving?view=aerial&district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();
 const map=page.locator('.scav-map');await expect(map).toBeVisible();
 const box=await map.boundingBox();if(!box)throw new Error('Map not visible');
 const request=page.waitForRequest(r=>r.url().includes('/rpc/scavenging_action')&&r.postDataJSON().p_action==='move');
 await page.mouse.click(box.x+181/1000*box.width,box.y+114/680*box.height);
 const payload=(await request).postDataJSON().p_payload;
 expect(payload.x).toBeCloseTo(.5,1);expect(payload.y).toBe(0);expect(payload).not.toHaveProperty('seconds');
 await expect.poll(()=>page.locator('[aria-label="Your position"] circle').last().getAttribute('cx')).not.toBe('73');
 await expect(page.locator('.scav-street-life')).toBeVisible();
 await page.getByRole('button',{name:'Street activity',exact:true}).click();await expect(page.locator('.scav-street-life')).toHaveCount(0);
 await page.getByRole('button',{name:'Street activity',exact:true}).click();await page.emulateMedia({reducedMotion:'reduce'});
 await expect(page.locator('.scav-traffic').first()).toBeHidden();
});

test('police patrols leave walking players alone and send caught searches to prison',async({page,request})=>{
 await request.post('http://127.0.0.1:54329/__patrol_setup',{headers:{Authorization:'Bearer '+token},data:{enabled:true,catchSearch:true}});
 await page.goto('/bin-diving?view=aerial&district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();
 await expect(page.getByRole('group',{name:'1 police patrols',exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Street activity',exact:true}).click();await expect(page.locator('.scav-police')).toBeVisible();
 await page.locator('.scav-target[aria-label^="Bin"]').first().click();await expect(page.getByRole('button',{name:'Search the bins',exact:true})).toBeEnabled();
 const custody=await request.post('http://127.0.0.1:54329/rest/v1/rpc/prison_state',{headers:{Authorization:'Bearer '+token},data:{}});expect(custody.ok()).toBe(true);expect((await custody.json()).jailed).toBe(false);
 await page.getByRole('button',{name:'Search the bins',exact:true}).click();await expect(page).toHaveURL(/districts\/blackwater-island/);
 await expect(page.getByText('Caught by a police patrol while scavenging', {exact:true})).toBeVisible();
 await page.reload();await expect(page).toHaveURL(/districts\/blackwater-island/);
});

test('entering a district fits the entire map and search button on screen',async({page,request})=>{
 await request.post('http://127.0.0.1:54329/__patrol_setup',{headers:{Authorization:'Bearer '+token},data:{enabled:true}});
 for(const viewport of [{width:1440,height:900},{width:1366,height:768},{width:390,height:844}]){
  await page.setViewportSize(viewport);await page.goto('/bin-diving?view=aerial&district=the-waterfront');const enter=page.getByRole('button',{name:'Enter The Waterfront'});if(await enter.count())await enter.click();
  await expect(page.locator('.scav-map')).toBeVisible();
  await expect.poll(()=>page.evaluate(()=>{const map=document.querySelector('.scav-map')!.getBoundingClientRect(),desk=document.querySelector('.scav-action-desk')!.getBoundingClientRect(),header=document.querySelector('.estate-header')!.getBoundingClientRect();return map.top>=header.bottom-1&&map.bottom<=innerHeight&&desk.bottom<=innerHeight;})).toBe(true);
  expect(await page.locator('.scav-map-scroll').evaluate(el=>el.scrollHeight<=el.clientHeight+1&&el.scrollWidth<=el.clientWidth+1)).toBe(true);
 }
});
