import {test,expect,type Page,type APIRequestContext} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
const headers={Authorization:"Bearer "+token},base="http://127.0.0.1:54329";
async function capture(page:Page,name:string){const b=(await page.screenshot({type:"jpeg",quality:72,path:"test-results/"+name+".jpg"})).toString("base64");if(process.env.VISUAL_REVIEW==="1")for(let i=0;i<b.length;i+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(i/12000)+":"+b.slice(i,i+12000));}
const rpc=async(request:APIRequestContext,fn:string,data={})=>(await request.post(base+"/rest/v1/rpc/"+fn,{headers,data})).json();
async function equip(request:APIRequestContext,n=3){
 await request.post(base+"/__crafting_setup",{headers,data:{grant:{"homemade-pistol":1,"homemade-bullets":n}}});const d=await rpc(request,"range_state");
 for(const [id,slot,quantity]of [["homemade-pistol","secondary",1],["homemade-bullets","ammo",n]]){const r=await rpc(request,"inventory_action",{p_action:"equip",p_payload:{season_id:d.season.id,request_id:crypto.randomUUID(),item_key:"good:"+id,equipment_slot:slot,quantity}});expect(r.error).toBeUndefined();}
}
async function equipM4(request:APIRequestContext,n=35){
 await request.post(base+"/__crafting_setup",{headers,data:{grant:{"m4-carbine":1,"556x45mm-ammo":n}}});const d=await rpc(request,"range_state");
 for(const [id,slot,quantity]of [["m4-carbine","primary",1],["556x45mm-ammo","ammo",n]]){const r=await rpc(request,"inventory_action",{p_action:"equip",p_payload:{season_id:d.season.id,request_id:crypto.randomUUID(),item_key:"good:"+id,equipment_slot:slot,quantity}});expect(r.error).toBeUndefined();}
}
async function start(page:Page){await page.goto("/shooting-range");await page.getByRole("button",{name:/Start session/}).click();await expect(page.locator(".range-intro")).toHaveCount(0);await expect(page.locator(".range-action-state")).toHaveText("Ready to fire");}
async function aim(page:Page,lane:number){const el=page.getByRole("button",{name:"Shooting lane",exact:true});await el.scrollIntoViewIfNeeded();const b=await el.boundingBox();const t=await page.locator(`[data-lane="${lane}"]`).getAttribute("transform");const xy=t!.match(/[\d.]+/g)!.map(Number);await page.mouse.click(b!.x+xy[0]/1000*b!.width,b!.y+xy[1]/600*b!.height);}
test.beforeEach(async({context,request})=>{test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixtures");await request.post(base+"/__reset_world",{headers});await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/"}]);});

test("range shares game HUD, requires equipment and is reachable from dashboard",async({page})=>{
 await page.goto("/dashboard");await page.locator(".command-quick").getByRole("link",{name:/Shooting Range/i}).click();await expect(page).toHaveURL(/shooting-range/);
 await expect(page.getByRole("navigation",{name:"Game navigation"})).toBeVisible();await expect(page.getByRole("link",{name:/Prepare your loadout/})).toBeVisible();await expect(page.locator(".range-loadout")).toContainText("No weapon equipped");await expect(page.locator(".range-best:not(.range-advanced-average) strong")).toHaveText("0");
});

test("M4 uses its own sounds, automatic fire, 5.56 ammunition and thirty-round magazine",async({page,request})=>{
 await equipM4(request);await page.addInitScript(()=>{const w=window as any;w.__m4Sounds=[];const start=AudioBufferSourceNode.prototype.start;AudioBufferSourceNode.prototype.start=function(...args:any[]){if(!this.loop)w.__m4Sounds.push({duration:this.buffer?.duration,channels:this.buffer?.numberOfChannels,rate:this.playbackRate.value});return(start as any).apply(this,args);};});await page.goto("/shooting-range");
 await expect(page.locator(".range-loadout h3")).toHaveText("M4 carbine");await expect(page.getByLabel("Range weapon")).toHaveValue("primary");
 const art=page.locator('.range-weapon-art img[src*="/art/weapons/m4-carbine"]');await expect.poll(()=>art.evaluate((img:HTMLImageElement)=>img.complete&&img.naturalWidth>0)).toBe(true);
 await expect(page.locator(".range-condition strong")).toHaveText("250 / 250");await expect(page.locator(".range-loadout")).toContainText("5.56x45mm ammunition");
 await expect(page.getByRole("link",{name:"Visit player market"})).toHaveAttribute("href","/market?view=inventory&good=556x45mm-ammo");
 await page.getByRole("button",{name:/Start session/}).click();await expect(page.locator(".range-magazine-counter b")).toHaveText("30 / 30");await expect(page.locator(".range-firebar")).toContainText("Hold to fire automatically");
 const lane=page.locator(".range-lane"),box=await lane.boundingBox();await page.mouse.move(box!.x+8,box!.y+100);await page.mouse.down();await page.waitForTimeout(1300);await page.mouse.up();
 await expect(page.locator(".range-action-state")).toHaveText("Ready to fire");const stopped=(await rpc(request,"range_state")).session.shots;expect(stopped).toBeGreaterThanOrEqual(2);expect(stopped).toBeLessThanOrEqual(4);await page.waitForTimeout(700);expect((await rpc(request,"range_state")).session.shots).toBe(stopped);
 await expect(page.locator(".range-condition strong")).toHaveText(`${250-stopped} / 250`);await expect(page.locator(".range-magazine-counter b")).toHaveText(`${30-stopped} / 30`);await expect(page.locator(".range-firebar strong")).toHaveText(String(35-stopped));
 await expect.poll(()=>page.evaluate(()=>(window as any).__m4Sounds.filter((s:any)=>s.duration>2.6&&s.duration<2.7&&s.channels===1&&s.rate===1).length)).toBe(stopped);
 await page.getByRole("button",{name:"Reload weapon",exact:true}).click();await expect.poll(()=>page.evaluate(()=>(window as any).__m4Sounds.filter((s:any)=>s.duration>1.8&&s.duration<1.95&&s.channels===1&&s.rate>.7&&s.rate<.85).length)).toBe(1);await expect(page.locator(".range-magazine-counter b")).toHaveText("30 / 30");
 const d=await rpc(request,"range_state");expect(d.weapons[0].good_id).toBe("m4-carbine");expect(d.weapons[0].ammo_good_id).toBe("556x45mm-ammo");expect(d.weapons[0].magazine.capacity).toBe(30);expect(d.weapons[0].magazine.reload_ms).toBe(2400);
});

test("moving targets, verified hits and misses consume actual equipped ammunition and condition",async({page,request})=>{
 await equip(request,3);await page.setViewportSize({width:1672,height:1120});await page.goto("/shooting-range");await expect.poll(()=>page.locator(".range-backdrop").evaluate((i:HTMLImageElement)=>i.complete&&i.naturalWidth>0)).toBe(true);await capture(page,"range-desktop");
 await page.getByRole("button",{name:/Start session/}).click();await expect(page.locator(".range-intro")).toHaveCount(0);const t=await page.locator('[data-lane="0"]').getAttribute("transform");await expect.poll(()=>page.locator('[data-lane="0"]').getAttribute("transform")).not.toBe(t);
 await aim(page,0);await expect(page.locator(".range-condition strong")).toHaveText("99 / 100");await expect(page.locator(".range-firebar strong")).toHaveText("2");await expect(page.locator(".range-target.scored")).toHaveCount(1);await capture(page,"range-active");
 await expect(page.locator(".range-action-state")).toHaveText("Ready to fire");const box=await page.locator(".range-lane").boundingBox();await page.locator(".range-lane").click({position:{x:10,y:box!.height-10}});await expect(page.locator(".range-feedback")).toContainText("Miss.");await expect(page.locator(".range-condition strong")).toHaveText("98 / 100");await expect(page.locator(".range-firebar strong")).toHaveText("1");
 await expect(page.locator(".range-action-state")).toHaveText("Ready to fire");await page.locator(".range-lane").focus();await page.keyboard.press("Space");await expect(page.locator(".range-firebar strong")).toHaveText("0");await expect(page.locator(".range-condition strong")).toHaveText("97 / 100");await expect(page.locator(".range-lane")).toHaveAttribute("aria-disabled","true");
 await page.getByRole("button",{name:"End session",exact:true}).click();await expect(page.locator(".range-recent li")).toHaveCount(1);
 const r=await rpc(request,"range_state");expect(r.stats.shots).toBe(3);expect(r.stats.hits).toBe(1);expect(r.ammo).toBeNull();expect(r.weapons[0].condition).toBe(97);
 await page.goto("/inventory");await page.getByRole("button",{name:"Secondary weapon: Homemade pistol",exact:true}).click();await page.getByRole("button",{name:"Unequip",exact:true}).click();await expect(page.locator(".inv-slot .inv-item").filter({hasText:"Condition 97"})).toHaveCount(1);
});

test("interrupted shot response safely retries without firing again",async({page,request})=>{
 await equip(request,5);await start(page);let first="";await page.route("**/rest/v1/rpc/range_action",async route=>{if(!first){first=route.request().postData()!;await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(first);await route.continue();}});
 await aim(page,0);await expect(page.getByRole("button",{name:"Retry safely"})).toBeVisible();await expect(page.locator(".range-lane")).toHaveAttribute("aria-disabled","true");await page.getByRole("button",{name:"Retry safely"}).click();await expect(page.locator(".range-firebar strong")).toHaveText("4");await expect(page.locator(".range-condition strong")).toHaveText("99 / 100");const d=await rpc(request,"range_state");expect(d.session.shots).toBe(1);
});

test("Owner weapon wear applies at the range and broken weapons stop mobile shots",async({page,request})=>{
 await equip(request,5);await page.goto("/owner?section=shooting-range");await page.getByLabel("Edit range weapon").selectOption("homemade-pistol");await page.getByLabel("Condition lost per shot").fill("100");await page.getByLabel("Weapon audit reason").fill("Test broken weapon protection");await page.getByRole("button",{name:"Save weapon rules",exact:true}).click();await expect(page.locator(".range-owner [role=status]")).toContainText("saved");await page.setViewportSize({width:1536,height:1080});await capture(page,"range-owner");
 await page.setViewportSize({width:390,height:844});await start(page);await expect.poll(()=>page.evaluate(()=>document.querySelector('.range-scoreboard')!.getBoundingClientRect().top-document.querySelector('.estate-header')!.getBoundingClientRect().bottom)).toBeGreaterThanOrEqual(0);await capture(page,"range-mobile");await page.locator(".range-lane").click({position:{x:10,y:100}});await expect(page.locator(".range-condition strong")).toHaveText("0 / 100");await expect(page.locator(".range-firebar strong")).toHaveText("4");await expect(page.locator(".range-loadout-status")).toContainText("broken");await expect(page.locator(".range-lane")).toHaveAttribute("aria-disabled","true");
 for(const width of [360,390,768,1024,1536]){await page.setViewportSize({width,height:1000});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"range width "+width).toBe(true);}
 await page.getByRole("button",{name:"End session",exact:true}).click();await expect(page.getByRole("link",{name:/Prepare your loadout/})).toBeVisible();const d=await rpc(request,"range_state");expect(d.stats.shots).toBe(1);expect(d.ammo.quantity).toBe(4);
});

test("ten shots require reload, R works, and a refresh cannot refill the magazine",async({page,request})=>{
 await equip(request,14);await page.setViewportSize({width:1536,height:1150});await start(page);await expect(page.locator('.range-magazine-counter b')).toHaveText('10 / 10');
 for(let i=0;i<10;i++){await expect(page.locator('.range-action-state')).toHaveText('Ready to fire');await page.locator('.range-lane').click({position:{x:8,y:100},force:true});await expect(page.locator('.range-magazine-counter b')).toHaveText(`${9-i} / 10`);}
 await expect(page.locator('.range-lane')).toHaveAttribute('aria-disabled','true');await expect(page.locator('.range-firebar strong')).toHaveText('4');await page.reload();await expect(page.locator('.range-magazine-counter b')).toHaveText('0 / 10');
 await page.locator('.range-lane').focus();await page.keyboard.press('r');await expect(page.locator('.range-reload-progress')).toBeVisible();await expect(page.locator('.range-lane')).toHaveAttribute('aria-disabled','true');await page.locator('.range-lane').click({position:{x:8,y:100},force:true});await capture(page,'range-reloading');
 await expect(page.locator('.range-magazine-counter b')).toHaveText('4 / 10');await expect(page.locator('.range-firebar strong')).toHaveText('4');await expect(page.locator('.range-condition strong')).toHaveText('90 / 100');await expect(page.locator('.range-action-state')).toHaveText('Ready to fire');
 const r=await rpc(request,'range_state');expect(r.session.shots).toBe(10);expect(r.ammo.quantity).toBe(4);
 await page.setViewportSize({width:390,height:844});await page.locator('.range-firebar').scrollIntoViewIfNeeded();await capture(page,'range-reload-mobile');expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});

test("sounds play on accepted shots and reloads; mute persists and leaving closes audio",async({page,request})=>{
 await equip(request,14);let closed=0;await page.exposeFunction('__closedAudio',()=>closed++);
 await page.addInitScript(()=>{const w=window as any;w.__rangeSounds=[];const start=AudioBufferSourceNode.prototype.start;AudioBufferSourceNode.prototype.start=function(...args:any[]){w.__rangeAudioContext=this.context;w.__rangeSounds.push({duration:this.buffer?.duration,channels:this.buffer?.numberOfChannels,loop:this.loop,rate:this.playbackRate.value});return (start as any).apply(this,args);};const close=AudioContext.prototype.close;AudioContext.prototype.close=function(){void w.__closedAudio();return close.call(this);};});
 await start(page);await expect.poll(()=>page.evaluate(()=>(window as any).__rangeSounds.filter((s:any)=>s.duration>59&&s.duration<61&&s.loop&&s.channels===2).length)).toBe(1);
 await page.locator('.range-lane').click({position:{x:8,y:100},force:true});await expect.poll(()=>page.evaluate(()=>(window as any).__rangeSounds.filter((s:any)=>s.duration>1.9&&s.duration<2&&s.rate===1&&s.channels===2).length)).toBe(1);
 await page.getByRole('button',{name:'Reload weapon',exact:true}).click();await expect.poll(()=>page.evaluate(()=>(window as any).__rangeSounds.filter((s:any)=>Math.abs(s.duration-1.8)<.05&&!s.loop).length)).toBe(1);await expect(page.locator('.range-magazine-counter b')).toHaveText('10 / 10');
 await page.getByRole('button',{name:'Mute range sound',exact:true}).click();await expect(page.getByRole('button',{name:'Enable range sound',exact:true})).toHaveAttribute('aria-pressed','false');
 await expect(page.locator('.range-action-state')).toHaveText('Ready to fire');await page.locator('.range-lane').click({position:{x:8,y:100},force:true});await expect(page.locator('.range-firebar strong')).toHaveText('12');expect(await page.evaluate(()=>(window as any).__rangeSounds.filter((s:any)=>s.duration>1.9&&s.duration<2&&s.rate===1&&s.channels===2).length)).toBe(1);
 await page.locator('.range-heading a').click();await expect.poll(()=>closed).toBe(1);await page.locator('.command-quick').getByRole('link',{name:/Shooting Range/i}).click();await expect(page.getByRole('button',{name:'Enable range sound',exact:true})).toHaveAttribute('aria-pressed','false');
 await page.getByRole('button',{name:'Enable range sound',exact:true}).click();await expect.poll(()=>page.evaluate(()=>(window as any).__rangeSounds.filter((s:any)=>s.duration>59&&s.duration<61&&s.loop&&s.channels===2).length)).toBe(2);
 await page.evaluate(()=>{Object.defineProperty(document,'hidden',{configurable:true,value:true});document.dispatchEvent(new Event('visibilitychange'));});await expect.poll(()=>page.evaluate(()=>(window as any).__rangeAudioContext.state)).toBe('suspended');await page.evaluate(()=>{Object.defineProperty(document,'hidden',{configurable:true,value:false});document.dispatchEvent(new Event('visibilitychange'));});await expect.poll(()=>page.evaluate(()=>(window as any).__rangeSounds.filter((s:any)=>s.duration>59&&s.duration<61&&s.loop&&s.channels===2).length)).toBe(3);
});

test("an interrupted reload reply keeps the original timer and bullets",async({page,request})=>{
 await equip(request,14);await start(page);await page.locator('.range-lane').click({position:{x:8,y:100}});await expect(page.locator('.range-magazine-counter b')).toHaveText('9 / 10');
 let first='';await page.route('**/rest/v1/rpc/range_action',async route=>{if(!first){first=route.request().postData()!;await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(first);await route.continue();}});
 await page.getByRole('button',{name:'Reload weapon',exact:true}).click();await expect(page.getByRole('button',{name:'Retry safely'})).toBeVisible();const before=await rpc(request,'range_state');await page.getByRole('button',{name:'Retry safely'}).click();const after=await rpc(request,'range_state');expect(after.weapons[0].magazine.ready_at).toBe(before.weapons[0].magazine.ready_at);
 await expect(page.locator('.range-magazine-counter b')).toHaveText('10 / 10');await expect(page.locator('.range-firebar strong')).toHaveText('13');
});

test("bullet holes stay on moving paper, repeated hits leave holes, and fresh targets clear them",async({page,request})=>{
 await rpc(request,"range_manage",{p_action:"settings",p_payload:{settings:{range_round_seconds:12},reason:"Verify paper damage across moving rounds"}});
 await equip(request,8);await start(page);await aim(page,1);
 const target=page.locator('.range-target[data-lane="1"]'),holes=target.locator('.range-bullet-hole');
 await expect(holes).toHaveCount(1);
 const local=await holes.first().getAttribute("transform"),position=await target.getAttribute("transform");
 await expect.poll(()=>target.getAttribute("transform")).not.toBe(position);
 expect(await holes.first().getAttribute("transform")).toBe(local);
 await expect(page.locator('.range-action-state')).toHaveText('Ready to fire');await aim(page,1);
 await expect(holes).toHaveCount(2);
 const state=await rpc(request,"range_state");expect(state.session.hits).toBe(1);expect(state.session.shots).toBe(2);
 await page.getByRole("button",{name:"Refresh shooting range"}).click();await expect(holes).toHaveCount(2);
 await page.setViewportSize({width:390,height:844});await page.locator(".range-lane").scrollIntoViewIfNeeded();await page.mouse.move(0,0);await expect(holes.first()).toBeVisible();await capture(page,"range-paper-holes-mobile");
 await expect(page.locator(".range-bullet-hole")).toHaveCount(0,{timeout:15000});
});

test("a delayed range recording respects mute, and missing audio cannot block shooting",async({page,request})=>{
 await equip(request,4);let release!:()=>void;const gate=new Promise<void>(resolve=>{release=resolve;});
 await page.route("**/audio/range/indoor-range.mp3",async route=>{await gate;await route.continue();});
 await page.route("**/audio/range/colt-1911-shot.mp3",route=>route.fulfill({status:503,body:"Unavailable"}));
 await page.addInitScript(()=>{const w=window as any;w.__ambientStarts=0;const start=AudioBufferSourceNode.prototype.start;AudioBufferSourceNode.prototype.start=function(...args:any[]){if(this.loop)w.__ambientStarts++;return(start as any).apply(this,args);};});
 await start(page);await page.getByRole("button",{name:"Mute range sound",exact:true}).click();
 const fetched=page.waitForResponse("**/audio/range/indoor-range.mp3");release();await fetched;
 await page.locator(".range-lane").click({position:{x:8,y:100},force:true});await expect(page.locator(".range-firebar strong")).toHaveText("3");
 expect(await page.evaluate(()=>(window as any).__ambientStarts)).toBe(0);
 await page.getByRole("button",{name:"Enable range sound",exact:true}).click();
 await expect.poll(()=>page.evaluate(()=>(window as any).__ambientStarts)).toBe(1);
 await expect(page.locator(".range-action-state")).toHaveText("Ready to fire");
 await page.locator(".range-lane").click({position:{x:8,y:100},force:true});await expect(page.locator(".range-firebar strong")).toHaveText("2");
});

test("Beginner and Advanced selection controls target distance, speed and XP on desktop and mobile",async({page,request})=>{
 await equip(request,12);await page.setViewportSize({width:1536,height:1180});await page.goto('/shooting-range');
 const beginner=page.getByRole('radio',{name:/Beginner/}),advanced=page.getByRole('radio',{name:/Advanced/});
 await expect(beginner).toHaveAttribute('aria-checked','true');await expect(beginner).toContainText('Up to 50 XP');await expect(advanced).toContainText('Up to 150 XP');
 const width=Number(await page.locator('[data-lane="0"] ellipse').first().getAttribute('rx'));
 await advanced.click();await expect(advanced).toHaveAttribute('aria-checked','true');expect(Number(await page.locator('[data-lane="0"] ellipse').first().getAttribute('rx'))).toBeCloseTo(width*.65);
 await capture(page,'range-difficulty-desktop');await page.getByRole('button',{name:/Start session/}).click();
 let d=await rpc(request,'range_state');expect(d.session.difficulty).toBe('advanced');expect(d.session.config.move_speed).toBe(d.config.move_speed*2.5);expect(d.session.config.completion_xp).toBe(150);await expect(page.locator('.range-difficulties')).toBeHidden();
 await page.getByRole('button',{name:'End session',exact:true}).click();await expect(page.locator('.range-session-result')).toContainText('+0 XP');
 await expect(page.getByRole('timer',{name:'Range cooldown'})).toContainText(/09:5|10:00/);await expect(page.getByRole('button',{name:/Start session/})).toBeDisabled();
 await beginner.click();await expect(page.getByRole('button',{name:/Start session/})).toBeDisabled();await page.reload();await expect(page.getByRole('timer',{name:'Range cooldown'})).toBeVisible();
 await page.setViewportSize({width:390,height:1100});await page.locator('.range-entry').scrollIntoViewIfNeeded();await expect(beginner).toBeVisible();await expect(advanced).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await capture(page,'range-difficulty-mobile');
});

test("completed sessions show earned XP once and recovery expiry enables the next attempt",async({page,request})=>{
 await equip(request,8);await request.post(base+'/__range_setup',{headers,data:{config:{rounds:1,round_seconds:4,move_amplitude:0,move_vertical:0,cooldown_seconds:3}}});
 await start(page);await aim(page,1);await expect(page.locator('.range-entry')).toContainText('1 / 1 rounds practised');
 await expect(page.getByRole('button',{name:/Record session/})).toBeVisible();await page.getByRole('button',{name:/Record session/}).click();
 await expect(page.locator('.range-session-result')).toContainText('+16 XP');await expect(page.getByRole('button',{name:/Start session/})).toBeDisabled();
 let d=await rpc(request,'range_state');expect(d.stats.xp_earned).toBe(16);expect(d.session.xp_awarded).toBe(16);
 await page.reload();d=await rpc(request,'range_state');expect(d.stats.xp_earned).toBe(16);
 await expect(page.getByRole('button',{name:/Start session/})).toBeEnabled({timeout:7000});await page.getByRole('radio',{name:/Advanced/}).click();await page.getByRole('button',{name:/Start session/}).click();
 await aim(page,1);await expect(page.getByRole('button',{name:/Record session/})).toBeVisible();await page.getByRole('button',{name:/Record session/}).click();
 await expect(page.locator('.range-session-result')).toContainText('+50 XP');expect((await rpc(request,'range_state')).stats.xp_earned).toBe(66);expect((await rpc(request,'skills_state')).skills.find((s:any)=>s.id==='sharpshooting').xp).toBe(66);
});

test("bullseye precision drives live accuracy, saved Advanced averages and score XP",async({page,request})=>{
 await equip(request,12);await request.post(base+'/__range_setup',{headers,data:{config:{rounds:1,round_seconds:8,move_amplitude:0,move_vertical:0,cooldown_seconds:3}}});
 const display=(n:number)=>n.toFixed(1).replace(/\.0$/,"")+"%";
 await page.setViewportSize({width:1536,height:1150});await page.goto('/shooting-range');await expect(page.locator('.range-advanced-average strong')).toHaveText('—');
 await page.getByRole('radio',{name:/Advanced/}).click();await page.getByRole('button',{name:/Start session/}).click();await expect(page.locator('.range-action-state')).toHaveText('Ready to fire');
 await aim(page,0);await expect(page.locator('.range-xp-preview')).toContainText('50 XP');
 await expect(page.locator('.range-action-state')).toHaveText('Ready to fire');
 const lane=page.locator('.range-lane');await lane.scrollIntoViewIfNeeded();const box=await lane.boundingBox(),transform=await page.locator('[data-lane="1"]').getAttribute('transform'),xy=transform!.match(/[\d.]+/g)!.map(Number),rx=Number(await page.locator('[data-lane="1"] ellipse').first().getAttribute('rx'));
 await page.mouse.click(box!.x+(xy[0]+rx*.5)/1000*box!.width,box!.y+xy[1]/600*box!.height);
 await expect(page.locator('.range-condition strong')).toHaveText('98 / 100');let d=await rpc(request,'range_state');
 expect(d.session.last_shot.accuracy_percent).toBeGreaterThan(47);expect(d.session.last_shot.accuracy_percent).toBeLessThan(53);expect(d.session.accuracy_percent).toBeGreaterThan(72);expect(d.session.accuracy_percent).toBeLessThan(78);
 await expect(page.locator('.range-scoreboard>div').filter({hasText:'Accuracy'})).toContainText(display(d.session.accuracy_percent));await expect(page.locator('.range-xp-preview')).toContainText('Last shot '+display(d.session.last_shot.accuracy_percent));
 await expect(page.locator('.range-action-state')).toHaveText('Ready to fire');await lane.click({position:{x:8,y:100}});await expect(page.locator('.range-condition strong')).toHaveText('97 / 100');
 d=await rpc(request,'range_state');expect(d.session.last_shot.accuracy_percent).toBe(0);const average=d.session.accuracy_percent,earned=Math.floor(d.session.score/300*150);expect(average).toBeGreaterThan(48);expect(average).toBeLessThan(52);expect(earned).toBeGreaterThan(85);expect(earned).toBeLessThan(89);
 await expect(page.locator('.range-scoreboard>div').filter({hasText:'Accuracy'})).toContainText(display(average));await expect(page.locator('.range-xp-preview')).toContainText(earned+' XP');
 await expect(page.getByRole('button',{name:/Record session/})).toBeVisible({timeout:10000});await page.getByRole('button',{name:/Record session/}).click();
 await expect(page.locator('.range-session-result')).toContainText('+'+earned+' XP');await expect(page.locator('.range-advanced-average strong')).toHaveText(display(average));await expect(page.locator('.header-power strong')).toHaveText(String(earned));
 await page.reload();await expect(page.locator('.range-advanced-average strong')).toHaveText(display(average));expect((await rpc(request,'range_state')).stats.xp_earned).toBe(earned);
 await expect(page.getByRole('button',{name:/Start session/})).toBeEnabled({timeout:7000});await page.getByRole('radio',{name:/Advanced/}).click();await page.getByRole('button',{name:/Start session/}).click();await expect(page.locator('.range-action-state')).toHaveText('Ready to fire');await aim(page,1);await expect(page.locator('.range-condition strong')).toHaveText('96 / 100');
 await page.getByRole('button',{name:'End session',exact:true}).click();await expect(page.locator('.range-session-result')).toContainText('+0 XP');d=await rpc(request,'range_state');expect(d.advanced_stats.average_accuracy).toBeGreaterThan(60);expect(d.advanced_stats.average_accuracy).toBeLessThan(65);await expect(page.locator('.range-advanced-average strong')).toHaveText(display(d.advanced_stats.average_accuracy));
 await page.locator('.range-advanced-record').scrollIntoViewIfNeeded();await capture(page,'range-advanced-accuracy');
 expect(d.advanced_stats.sessions).toBe(2);expect(d.advanced_stats.shots).toBe(4);expect(d.advanced_stats.xp_earned).toBe(earned);
});
