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
 await expect(page.getByLabel("Inventory stock")).toHaveCount(0);
 const inventory=await request.post("http://127.0.0.1:54329/rest/v1/rpc/inventory_state",{headers:{Authorization:"Bearer "+token},data:{}});
 expect((await inventory.json()).carried.reduce((n:number,x:{quantity:number})=>n+x.quantity,0)).toBe(15);
 await page.getByLabel("Search goods or seller").fill("nonexistent commodity");
 await expect(page.locator(".market-empty")).toContainText(["You haven't listed any goods","No auctions here yet."]);
 await page.getByLabel("Search goods or seller").fill("");
 await request.post("http://127.0.0.1:54329/__visual_world",{headers:{Authorization:"Bearer "+token}});
 await page.goto("/market");await expect(page.getByRole("heading",{name:"The Exchange",exact:true})).toBeVisible();
 await expect.poll(()=>page.locator(".market-stock-preview img").evaluate((img:HTMLImageElement)=>img.complete&&img.naturalWidth>0)).toBe(true);
 await capture(page,"market-exchange-desktop");
 await sections.getByRole("button",{name:"Inventory",exact:true}).click();
 await expect(page.locator(".market-inventory .commodity-art img")).toHaveCount(10);
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

test('buy orders show ten per page, accept partial sales and retry safely',async({page,request})=>{
 await request.post('http://127.0.0.1:54329/__buy_orders_setup',{headers:{Authorization:'Bearer '+token},data:{count:12}});
 await page.goto('/market?view=orders');const book=page.locator('.district-order-book');await expect(book.locator('.local-market-order')).toHaveCount(10);
 const pages=page.getByRole('navigation',{name:'Buy orders pages'});await pages.getByRole('button',{name:'Next',exact:true}).click();await expect(book.locator('.local-market-order')).toHaveCount(2);await pages.getByRole('button',{name:'Previous',exact:true}).click();
 let original='';await page.route('**/rest/v1/rpc/district_market_order',async route=>{if(!original){original=route.request().postData()!;await route.fetch();await route.abort();}else{expect(route.request().postData()).toBe(original);await route.continue();}});
 const first=book.locator('.local-market-order').first();await first.getByLabel('Quantity to sell').fill('2');await first.getByRole('button',{name:'Sell to this order'}).click();await book.getByRole('button',{name:'Retry same order request'}).click();await expect(first).toContainText('2 of 5 filled');await expect(first).toContainText('3 remaining');await expect(first).toContainText('$300 reserved');
 await page.reload();await expect(book.locator('.local-market-order').first()).toContainText('2 of 5 filled');
});
test('buy orders can be funded from all districts and cancelled for a refund',async({page})=>{
 await page.goto('/market?view=orders');const book=page.locator('.district-order-book');await book.getByLabel('Units wanted').fill('3');await book.getByLabel('Your unit price').fill('100');await book.getByRole('button',{name:'Fund buy order'}).click();await expect(book).toContainText('0 of 3 filled');await expect(page.locator('.market-wallet-stats')).toContainText('$9,700');await book.getByRole('button',{name:'Cancel & refund $300'}).click();await expect(page.locator('.market-wallet-stats')).toContainText('$10,000');
});

test('fixed-price market lists ten offers and resets pagination with filters',async({page,request})=>{
 await request.post('http://127.0.0.1:54329/__buy_orders_setup',{headers:{Authorization:'Bearer '+token},data:{listings:12}});
 await page.goto('/market');await expect(page.locator('.market-lot')).toHaveCount(10);const pages=page.getByRole('navigation',{name:'Fixed-price offers pages'});await pages.getByRole('button',{name:'Next',exact:true}).click();await expect(page.locator('.market-lot')).toHaveCount(2);await page.getByRole('textbox',{name:'Search goods or seller'}).fill('Silk');await expect(page.locator('.market-lot')).toHaveCount(10);
 await page.setViewportSize({width:390,height:844});await page.goto('/market?view=orders');await expect(page.locator('.local-market-order')).toHaveCount(10);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await page.locator('.district-order-book').screenshot({path:'test-results/buy-orders-mobile.png'});
});
