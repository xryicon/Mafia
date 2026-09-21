import {test,expect} from '@playwright/test';
import {cookie,token} from '../fixtures/identity.mjs';
test.beforeEach(async({context,request})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=='1','Isolated game world');
 await request.post('http://127.0.0.1:54329/__reset_world',{headers:{Authorization:'Bearer '+token}});
 await context.addCookies([{name:'sb-127-auth-token',value:cookie,domain:'localhost',path:'/',sameSite:'Lax'}]);
});
test('tutorial saves progress, explains warehouses, and can be replayed',async({page})=>{
 await page.goto('/dashboard');await page.getByRole('button',{name:'Start tutorial',exact:true}).click();
 const dialog=page.getByRole('dialog');await expect(dialog).toBeVisible();
 await expect(dialog.getByRole('heading')).toHaveText('Welcome to Blackwater');
 await expect(page.locator('.tutorial-highlight')).toHaveClass(/command-player-stats/);
 await dialog.getByRole('button',{name:'Mute narration',exact:true}).click();
 await expect(dialog.locator('audio')).toHaveJSProperty('paused',true);
 for(let i=0;i<4;i++)await dialog.getByRole('button',{name:'Next',exact:true}).click();
 await expect(dialog.getByRole('heading')).toHaveText('Give your operation room');
 await expect(dialog).toContainText('lease terms');
 await page.keyboard.press('Escape');await expect(dialog).toHaveCount(0);
 await page.reload();await page.getByRole('button',{name:'Resume tutorial',exact:true}).click();
 await expect(dialog.getByRole('heading')).toHaveText('Give your operation room');
 for(let i=0;i<3;i++)await dialog.getByRole('button',{name:'Next',exact:true}).click();
 await dialog.getByRole('button',{name:'Finish tutorial',exact:true}).click();
 await page.reload();await page.getByRole('button',{name:'Replay tutorial',exact:true}).click();
 await expect(dialog.getByRole('heading')).toHaveText('Welcome to Blackwater');
});
test('mobile tutorial fits screen and audio assets load',async({page,request})=>{
 await page.setViewportSize({width:390,height:844});await page.goto('/dashboard');
 await page.getByRole('button',{name:'Start tutorial',exact:true}).click();
 const dialog=page.getByRole('dialog');const box=await dialog.boundingBox();expect(box!.x).toBeGreaterThanOrEqual(0);expect(box!.x+box!.width).toBeLessThanOrEqual(390);
 await expect(dialog.getByRole('button',{name:'Next',exact:true})).toBeVisible();
 const response=await request.get('/audio/tutorial/welcome.wav');expect(response.ok()).toBeTruthy();expect((await response.body()).subarray(0,4).toString()).toBe('RIFF');
 await page.screenshot({path:'test-results/tutorial-mobile.png'});
});
