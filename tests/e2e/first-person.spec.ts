import {test,expect} from '@playwright/test';
import {cookie,token} from '../fixtures/identity.mjs';
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=='1','Isolated fixture only');await request.post('http://127.0.0.1:54329/__reset_world',{headers:{Authorization:'Bearer '+token}});await context.addCookies([{name:'sb-127-auth-token',value:cookie,domain:'localhost',path:'/',sameSite:'Lax'}]);});
test('3D streets render, movement sends directions only, and nearby bins use existing loot actions',async({page})=>{
 // CI uses software-rendered WebGL; this scenario also captures three viewport variants.
 test.setTimeout(90000);
 await page.setViewportSize({width:1440,height:900});await page.goto('/bin-diving?district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();
 await page.locator('.scav-target[aria-label^="Bin"]').first().click();await expect(page.getByRole('button',{name:'Search the bins',exact:true})).toBeEnabled();
 await page.getByRole('button',{name:'First-person streets'}).click();await expect(page.getByRole('button',{name:'Walk the streets',exact:true})).toBeVisible({timeout:30000});
 await expect(page.locator('.fp-canvas canvas')).toBeVisible();await expect(page.locator('.fp-canvas canvas')).toHaveAttribute('data-environment-ready','true',{timeout:15000});await expect(page.getByRole('img',{name:'Your district position'})).toBeVisible();await page.locator('.fp-street').scrollIntoViewIfNeeded();
 await page.getByRole('button',{name:'Walk the streets',exact:true}).click();await expect(page.locator('.fp-crosshair')).toBeVisible();
 const movement=page.waitForRequest(r=>r.url().includes('/rpc/street_motion')&&r.postDataJSON().p_action==='step'&&r.postDataJSON().p_payload.dx<0);
 await page.keyboard.down('KeyS');const request=(await movement).postDataJSON().p_payload;expect(request).not.toHaveProperty('x');expect(request).not.toHaveProperty('position');expect(request).not.toHaveProperty('speed');await page.keyboard.up('KeyS');
 await page.keyboard.press('Escape');await expect(page.getByRole('button',{name:'Walk the streets',exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Search bin',exact:true}).click();await page.getByRole('button',{name:'Collect find',exact:true}).click();await expect(page.locator('.bin-notice')).toBeVisible();
 await page.getByRole('button',{name:'Walk the streets',exact:true}).click();await expect(page.locator('.fp-canvas canvas')).toHaveAttribute('data-hands','unarmed');await page.screenshot({path:'test-results/first-person-streets-desktop.jpg',type:'jpeg',quality:85});await page.keyboard.press('Escape');
 await page.getByRole('button',{name:'Aerial view',exact:true}).click();await page.screenshot({path:'test-results/first-person-aerial.jpg',type:'jpeg',quality:80});
 await page.setViewportSize({width:390,height:844});await expect(page.locator('.fp-canvas canvas')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.screenshot({path:'test-results/first-person-mobile.jpg',type:'jpeg',quality:80});
 await page.getByRole('button',{name:'Exit street view'}).click();await expect(page.locator('.scav-map')).toBeVisible();
});
test('devices without WebGL keep a usable aerial map',async({page})=>{
 await page.addInitScript(()=>{const original=HTMLCanvasElement.prototype.getContext;HTMLCanvasElement.prototype.getContext=function(this:HTMLCanvasElement,type:string,...args:unknown[]){if(type==='webgl2')return null;return original.apply(this,[type,...args] as Parameters<typeof original>);} as typeof original;});
 await page.goto('/bin-diving?district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();await page.getByRole('button',{name:'First-person streets'}).click();await expect(page.getByRole('button',{name:'Return to aerial map'})).toBeVisible();await page.getByRole('button',{name:'Return to aerial map'}).click();await expect(page.locator('.scav-map')).toBeVisible();
});

test.describe('touch streets',()=>{
 test.use({hasTouch:true,isMobile:true,viewport:{width:390,height:844}});
 test('pursuit controls leave the mobile movement pad touchable',async({page,request})=>{
  test.setTimeout(90000);await request.post('http://127.0.0.1:54329/__street_setup',{headers:{Authorization:'Bearer '+token},data:{street:true,lockpicks:2}});
  await page.goto('/bin-diving');await page.getByRole('button',{name:/^Enter /}).click();await page.locator('.scav-target[aria-label^="Car"]').first().click();await page.getByRole('button',{name:/^Steal vehicle/}).click();await page.getByRole('button',{name:'Start getaway',exact:true}).click();
  await page.getByRole('button',{name:'First-person streets'}).click();await page.getByRole('button',{name:'Walk the streets',exact:true}).click();await expect(page.locator('.fp-objective')).toHaveClass(/wanted/);const pad=page.getByLabel('Movement pad');await expect(pad).toBeVisible();
  expect(await pad.evaluate(el=>{const r=el.getBoundingClientRect();return document.elementFromPoint(r.x+r.width/2,r.y+r.height/2)?.closest('.fp-stick')===el;})).toBe(true);
  const stick=await pad.boundingBox(),panel=await page.locator('.fp-objective').boundingBox();expect(stick!.x+stick!.width).toBeLessThan(panel!.x);await page.screenshot({path:'test-results/first-person-pursuit-touch.jpg',type:'jpeg',quality:80});
 });
 test('touch movement, release and viewport controls' ,async({page})=>{
  await page.goto('/bin-diving?district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();await page.getByRole('button',{name:'First-person streets'}).click();await page.getByRole('button',{name:'Walk the streets',exact:true}).click();await expect(page.getByLabel('Movement pad')).toBeVisible();
  const pad=await page.getByLabel('Movement pad').boundingBox();if(!pad)throw new Error('Missing touch controls');const x=pad.x+pad.width/2,y=pad.y+pad.height/2,cdp=await page.context().newCDPSession(page);
  const moved=page.waitForRequest(r=>r.url().includes('/rpc/street_motion')&&r.postDataJSON().p_action==='step'&&r.postDataJSON().p_payload.dx>.1);
  await cdp.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x,y}]});await cdp.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x,y:y-30}]});await moved;
  const stopped=page.waitForRequest(r=>r.url().includes('/rpc/street_motion')&&r.postDataJSON().p_action==='step'&&r.postDataJSON().p_payload.dx===0&&r.postDataJSON().p_payload.dy===0);await cdp.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await stopped;
  expect(await page.evaluate(()=>{const bounds=document.querySelector('.fp-street')!.getBoundingClientRect(),header=document.querySelector('.estate-header')!.getBoundingClientRect();return bounds.top>=header.bottom-2&&bounds.bottom<=innerHeight+2&&document.documentElement.scrollWidth<=innerWidth;})).toBe(true);
  await page.screenshot({path:'test-results/first-person-touch.jpg',type:'jpeg',quality:85});await page.getByRole('button',{name:'Exit street view'}).click();await expect(page.locator('.scav-map')).toBeVisible();
 });
});

test('graphics preferences persist and fullscreen keeps the street controls in view',async({page})=>{
 test.setTimeout(90000);
 await page.setViewportSize({width:1440,height:900});await page.goto('/bin-diving?district=the-waterfront');await page.getByRole('button',{name:'Enter The Waterfront'}).click();await page.getByRole('button',{name:'First-person streets'}).click();await expect(page.getByRole('button',{name:'Walk the streets',exact:true})).toBeVisible({timeout:30000});
 const canvas=page.locator('.fp-canvas canvas'),quality=page.getByLabel('Street graphics quality');
 await quality.selectOption('performance');await expect(canvas).toHaveAttribute('data-quality','performance');expect(Number(await canvas.getAttribute('data-pixel-ratio'))).toBeLessThanOrEqual(.8);
 await quality.selectOption('high');await expect(canvas).toHaveAttribute('data-quality','high');expect(Number(await canvas.getAttribute('data-pixel-ratio'))).toBeGreaterThan(.8);
 await expect(canvas).toHaveAttribute('data-draw-calls',/^[1-9][0-9]*$/);expect(Number(await canvas.getAttribute('data-draw-calls'))).toBeLessThan(260);
 // Software WebGL has verified High; exercise the remaining controls at bounded resolution.
 await quality.selectOption('performance');
 await page.getByRole('button',{name:'Full screen',exact:true}).click();await expect(page.getByRole('button',{name:'Exit full screen',exact:true})).toBeVisible();expect(await page.evaluate(()=>document.fullscreenElement?.classList.contains('fp-street'))).toBe(true);
 const bounds=await page.locator('.fp-street').boundingBox();expect(bounds!.width).toBeGreaterThanOrEqual(1438);await page.getByRole('button',{name:'Exit full screen',exact:true}).click();
 await page.getByRole('button',{name:'Mute street sound',exact:true}).click();await page.getByLabel('Street sound volume').focus();await page.getByLabel('Street sound volume').press('Home');await page.getByLabel('Street sound volume').press('ArrowRight');
 await quality.selectOption('performance');await page.getByRole('button',{name:'Exit street view',exact:true}).click();await page.getByRole('button',{name:'First-person streets'}).click();await expect(quality).toHaveValue('performance');await expect(canvas).toHaveAttribute('data-quality','performance');await expect(page.getByRole('button',{name:'Enable street sound',exact:true})).toBeVisible();await expect(page.getByLabel('Street sound volume')).toHaveValue('1');
 console.log('STREET_RENDER_BUDGET',JSON.stringify({calls:await canvas.getAttribute('data-draw-calls'),triangles:await canvas.getAttribute('data-triangles'),pixelRatio:await canvas.getAttribute('data-pixel-ratio')}));
});
