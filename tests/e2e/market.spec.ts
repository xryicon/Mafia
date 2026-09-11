import {test,expect,type Page} from "@playwright/test";
import {cookie,token} from "../fixtures/identity.mjs";
async function capture(page:Page,name:string){
 const shot=await page.screenshot({path:"test-results/"+name+".jpg",type:"jpeg",quality:65});
 if(process.env.VISUAL_REVIEW==="1"){const b=shot.toString("base64");for(let n=0;n<b.length;n+=12000)console.log("VISUAL_REVIEW_"+name+"_"+Math.floor(n/12000)+":"+b.slice(n,n+12000));}
}
test.beforeEach(async({context,request})=>{
 test.skip(process.env.GAME_TEST_FIXTURE!=="1","Isolated market fixture");
 await request.post("http://127.0.0.1:54329/__reset_world",{headers:{Authorization:"Bearer "+token}});
 await context.addCookies([{name:"sb-127-auth-token",value:cookie,domain:"localhost",path:"/",sameSite:"Lax"}]);
});
test("players create auctions, reserve bids, receive goods, and keep the command HUD",async({page,request})=>{
 await page.setViewportSize({width:1672,height:941});await page.goto("/market");
 const ticket=page.locator(".market-ticket"),sections=page.getByRole("navigation",{name:"Market sections"});
 await ticket.getByRole("button",{name:"Auction",exact:true}).click();
 await ticket.getByLabel("Quantity",{exact:true}).fill("2");
 await ticket.getByLabel("Starting bid for whole lot ($)",{exact:true}).fill("400");
 await ticket.getByLabel("Duration (minutes)",{exact:true}).fill("5");
 await ticket.getByRole("button",{name:"Start auction",exact:true}).click();
 await expect(page.locator(".market-notice")).toContainText("Auction opened");
 await expect(ticket.locator(".market-stock-note")).toContainText("3 units available");
 await sections.getByRole("button",{name:"My listings",exact:true}).click();
 await page.getByRole("button",{name:"Withdraw auction",exact:true}).click();
 await expect(ticket.locator(".market-stock-note")).toContainText("5 units available");
 await sections.getByRole("button",{name:"Auctions",exact:true}).click();
 await page.getByRole("button",{name:/Place bid/}).click();
 await page.getByLabel("Your bid for the whole lot").fill("350");
 await page.getByRole("button",{name:"Confirm bid",exact:true}).click();
 await expect(page.getByRole("dialog")).not.toBeVisible();
 await expect(page.locator(".market-auction")).toContainText("YOU'RE LEADING");
 await expect(page.locator(".header-cash")).toContainText("$9,650");
 await expect(page.locator(".market-wallet-stats")).toContainText("$350");
 await sections.getByRole("button",{name:"My listings",exact:true}).click();
 await expect(page.locator(".market-auction.leading")).toContainText("Silk bolts");
 await request.post("http://127.0.0.1:54329/__close_auctions",{headers:{Authorization:"Bearer "+token}});
 await page.getByRole("button",{name:"Refresh market",exact:true}).click();
 await expect(page.locator(".market-auction.leading")).toContainText("Won · goods delivered");
 await expect(page.getByLabel("Inventory stock")).toContainText("15");
 await page.getByLabel("Search goods or seller").fill("nonexistent commodity");
 await expect(page.locator(".market-empty")).toContainText(["You haven't listed any goods","No auctions here yet."]);
 await page.getByLabel("Search goods or seller").fill("");
 await request.post("http://127.0.0.1:54329/__visual_world",{headers:{Authorization:"Bearer "+token}});
 await page.goto("/market");await expect(page.getByRole("heading",{name:"The Exchange",exact:true})).toBeVisible();
 await expect.poll(()=>page.locator(".market-stock-preview img").evaluate((img:HTMLImageElement)=>img.complete&&img.naturalWidth>0)).toBe(true);
 await capture(page,"market-exchange-desktop");
 await sections.getByRole("button",{name:"Inventory",exact:true}).click();
 await expect(page.locator(".market-inventory .commodity-art img")).toHaveCount(3);
 await expect.poll(()=>page.locator(".market-inventory .commodity-art img").evaluateAll(imgs=>imgs.every(img=>(img as HTMLImageElement).complete&&(img as HTMLImageElement).naturalWidth>0))).toBe(true);
 await capture(page,"market-commodity-inventory");
 await sections.getByRole("button",{name:"Auctions",exact:true}).click();
 await capture(page,"market-commodity-auctions");
 await sections.getByRole("button",{name:"Trading floor",exact:true}).click();
 for(const width of [1448,1024,768,375]){
  await page.setViewportSize({width,height:width===375?812:1000});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),"Market overflow at "+width).toBe(true);
  if(width===375){await capture(page,"market-exchange-mobile");await page.getByRole("button",{name:"Create a listing",exact:true}).click();await expect(ticket.getByLabel("Commodity")).toBeFocused();}
 }
});
test("an interrupted auction creation retries the same request without duplicating stock",async({page})=>{
 await page.goto("/market?view=mine");
 const ticket=page.locator(".market-ticket");await ticket.getByRole("button",{name:"Auction",exact:true}).click();
 await ticket.getByLabel("Quantity",{exact:true}).fill("2");
 let interrupted=false;
 await page.route("**/rest/v1/rpc/market_auction_action",async route=>{
  if(!interrupted){interrupted=true;await route.fetch();await route.abort("failed");}else await route.continue();
 });
 await ticket.getByRole("button",{name:"Start auction",exact:true}).click();
 await expect(page.getByRole("button",{name:"Retry same request"})).toBeVisible();
 await page.getByRole("button",{name:"Retry same request"}).click();
 await expect(page.locator(".market-notice")).toContainText("Auction opened");
 await expect(page.locator(".market-auction")).toHaveCount(1);
 await expect(ticket.locator(".market-stock-note")).toContainText("3 units available");
});

