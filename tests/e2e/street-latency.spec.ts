import {test,expect} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";

type StepPayload={controller:string;sequence:number;dx:number;dy:number;sprint:boolean};
const moving=(step:StepPayload)=>Math.hypot(step.dx,step.dy)>.001;

test.beforeEach(async({context,request})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated fixture only");
 await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
});

test("delayed movement replies keep the latest input, restart from idle, and stop on exit",async({page})=>{
 test.setTimeout(90_000);
 const steps:StepPayload[]=[],actions:string[]=[];
 let concurrent=0,maxConcurrent=0,leaving=false,holdFirst=true,releaseFirst=()=>{};
 const firstReply=new Promise<void>(resolve=>{releaseFirst=resolve;});
 page.on("request",request=>{
  if(request.url().includes("/rpc/scavenging_action"))actions.push(request.postDataJSON().p_action);
 });
 await page.route("**/rest/v1/rpc/street_motion",async route=>{
  const body=route.request().postDataJSON();
  if(body.p_action==="step")steps.push(body.p_payload as StepPayload);
  concurrent++;maxConcurrent=Math.max(maxConcurrent,concurrent);
  try{
   const response=await route.fetch();
   await new Promise(resolve=>setTimeout(resolve,180));
   if(holdFirst&&body.p_action==='step'&&moving(body.p_payload)){holdFirst=false;await firstReply;}
   await route.fulfill({response});
  }catch(error){if(!leaving&&!page.isClosed())throw error;}
  finally{concurrent--;}
 });

 // This scenario measures transport, not GPU throughput; visual coverage uses larger viewports.
 await page.setViewportSize({width:800,height:600});
 await page.addInitScript(()=>localStorage.setItem("blackwater:street-quality","performance"));
 await page.goto("/bin-diving?district=the-waterfront");
 await page.getByRole("button",{name:"Enter The Waterfront"}).click();
 await page.locator('.scav-target[aria-label^="Bin"]').first().click();
 await expect(page.getByRole("button",{name:"Search the bins",exact:true})).toBeEnabled();
 await page.getByRole("button",{name:"First-person streets"}).click();
 await expect(page.getByRole("button",{name:"Walk the streets",exact:true})).toBeVisible({timeout:30_000});
 await page.getByLabel("Street graphics quality").selectOption("performance");
 await page.getByRole("button",{name:"Walk the streets",exact:true}).click();
 await expect(page.locator(".fp-crosshair")).toBeVisible();

 const firstCount=steps.length;
 await page.keyboard.down("KeyW");
 await expect.poll(()=>steps.slice(firstCount).some(moving)).toBe(true);
 const first=steps.slice(firstCount).find(moving)!;
 // Change direction and release while the first response is delayed. Only the latest
 // stopped state may follow it; an intermediate key must not be replayed.
 // Dispatch this short burst in the browser: separate automation calls can take
 // seconds under software WebGL and would accidentally test the 6s network timeout.
 await page.evaluate(()=>new Promise<void>(resolve=>{
  window.dispatchEvent(new KeyboardEvent('keyup',{code:'KeyW',bubbles:true}));
  window.dispatchEvent(new KeyboardEvent('keydown',{code:'KeyD',bubbles:true}));
  requestAnimationFrame(()=>{window.dispatchEvent(new KeyboardEvent('keyup',{code:'KeyD',bubbles:true}));requestAnimationFrame(()=>resolve());});
 }));
 releaseFirst();await page.keyboard.up("KeyW");
 await expect.poll(()=>steps.some(step=>step.sequence>first.sequence&&!moving(step))).toBe(true);
 const firstStop=steps.find(step=>step.sequence>first.sequence&&!moving(step))!;
 expect(steps.filter(step=>step.sequence>first.sequence&&step.sequence<=firstStop.sequence).every(step=>!moving(step))).toBe(true);
 expect(maxConcurrent).toBe(1);

 // Let the accepted lease expire, then prove a fresh start is sent immediately and
 // its release is acknowledged instead of remaining frozen at idle.
 await page.waitForTimeout(700);
 const restartCount=steps.length;
 await page.keyboard.down("KeyS");
 await expect.poll(()=>steps.slice(restartCount).some(moving)).toBe(true);
 const restart=steps.slice(restartCount).find(moving)!;
 expect(restart.sequence).toBeGreaterThan(firstStop.sequence);
 await page.keyboard.up("KeyS");
 await expect.poll(()=>steps.some(step=>step.sequence>restart.sequence&&!moving(step))).toBe(true);

 await page.keyboard.press("Escape");
 await expect(page.getByRole("button",{name:"Walk the streets",exact:true})).toBeVisible();
 const searches=actions.filter(action=>action==="search").length;
 await page.getByRole("button",{name:"Search bin",exact:true}).click();
 await expect.poll(()=>actions.filter(action=>action==="search").length).toBe(searches+1);
 await page.waitForTimeout(250);
 expect(actions.filter(action=>action==="search").length).toBe(searches+1);

 await page.getByRole("button",{name:"Walk the streets",exact:true}).click();
 const exitCount=steps.length;
 await page.keyboard.down("KeyW");
 await expect.poll(()=>steps.slice(exitCount).some(moving)).toBe(true);
 const exitMove=steps.slice(exitCount).find(moving)!;
 leaving=true;
 await page.getByRole("button",{name:"Exit street view"}).evaluate((button:HTMLButtonElement)=>button.click());
 await page.keyboard.up("KeyW");
 await expect(page.locator(".scav-map")).toBeVisible();
 await expect.poll(()=>steps.some(step=>step.sequence>exitMove.sequence&&!moving(step))).toBe(true);
 await page.waitForTimeout(250);
 const exitStopIndex=steps.findIndex(step=>step.sequence>exitMove.sequence&&!moving(step));
 expect(exitStopIndex).toBeGreaterThan(-1);
 expect(steps.slice(exitStopIndex).every(step=>!moving(step))).toBe(true);
 expect(new Set(steps.map(step=>step.controller)).size).toBe(1);
 expect(steps.map(step=>step.sequence)).toEqual([...new Set(steps.map(step=>step.sequence))].sort((a,b)=>a-b));
});
