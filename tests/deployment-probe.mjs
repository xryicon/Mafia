// Read-only smoke probe. No cookies, credentials, or game mutations.
const origin = "https://mafia.xryicon.workers.dev";
let landing="";
for (const path of ["/","/login","/signup","/forgot-password"]) {
 try {
  const response=await fetch(origin+path,{redirect:"follow",signal:AbortSignal.timeout(20000)});
  const html=await response.text();if(path==="/")landing=html;
  console.log(JSON.stringify({path,status:response.status,url:response.url,title:html.match(/<title>([^<]*)<\/title>/i)?.[1],heading:html.match(/<h1[^>]*>(.*?)<\/h1>/is)?.[1]?.replace(/<[^>]*>/g,""),errorExcerpt:response.ok?undefined:html.replace(/<[^>]*>/g," ").slice(0,400)}));
  if(!response.ok)process.exitCode=1;
 } catch(error) {console.log(JSON.stringify({path,error:error.message}));process.exitCode=1;}
}
const sheets=[...new Set([...landing.matchAll(/href="([^"]+\.css(?:\?[^"]*)?)"/g)].map(m=>m[1]))];
let styles="";
for(const href of sheets){
 const url=new URL(href,origin);if(url.origin!==origin)continue;
 const response=await fetch(url,{signal:AbortSignal.timeout(20000)});
 if(!response.ok)throw new Error("Deployed stylesheet failed to load");styles+=await response.text();
}
console.log(JSON.stringify({deployedLayout:styles.includes(".header-power")&&styles.includes(".brand-online")?"clear-city-header":styles.includes(".fresh-canvas")&&styles.includes(".header-wallet")?"fresh-icon-header":styles.includes(".estate-city")?"reference-property-screen":"previous-layout",stylesheets:sheets.length}));

for(const path of ["/dashboard","/market","/properties","/gangs","/seasons","/support","/players","/districts","/districts/the-waterfront","/districts/mines-and-quarries","/districts/manage","/telegrams"]){
 const response=await fetch(origin+path,{redirect:"manual",signal:AbortSignal.timeout(20000)});
 const location=response.headers.get("location")||"";
 const protectedRoute=[302,303,307,308].includes(response.status)&&new URL(location,origin).pathname==="/login";
 console.log(JSON.stringify({path,status:response.status,protectedRoute}));
 if(!protectedRoute)process.exitCode=1;
}
const districtsDeployed=styles.includes(".district-tabs")&&styles.includes(".city-district-zone");
console.log(JSON.stringify({districtsDeployed}));
if(districtsDeployed){
 const art=await fetch(origin+"/art/city-map.webp",{signal:AbortSignal.timeout(20000)});
 const bytes=(await art.arrayBuffer()).byteLength;
 console.log(JSON.stringify({cityArtwork:art.status,contentType:art.headers.get("content-type"),bytes}));
 if(!art.ok||bytes<10000||!art.headers.get("content-type")?.includes("image/webp"))process.exitCode=1;
}

const telegramsDeployed=styles.includes(".tg-correspondence")&&styles.includes(".tg-office");
console.log(JSON.stringify({telegramsDeployed}));
if(telegramsDeployed){
 const art=await fetch(origin+"/art/telegram-office.jpg",{signal:AbortSignal.timeout(20000)});
 const bytes=(await art.arrayBuffer()).byteLength;
 console.log(JSON.stringify({telegramArtwork:art.status,contentType:art.headers.get("content-type"),bytes}));
 if(!art.ok||bytes<10000||!art.headers.get("content-type")?.includes("image/jpeg"))process.exitCode=1;
}

const commandDashboardDeployed=styles.includes(".command-dashboard")&&styles.includes(".command-atlas");
console.log(JSON.stringify({telegramGroupsDeployed:styles.includes(".tg-command")&&styles.includes(".tg-members"),marketExchangeDeployed:styles.includes(".market-workspace"),commandDashboardDeployed,sharedCommandHudDeployed:styles.includes(".command-city.command-dashboard-page"),cityWideOfficeMarkerRemoved:!styles.includes(".command-office-marker")}));
if(commandDashboardDeployed){
 for(const name of ["command-city","command-portrait"]){
  const art=await fetch(origin+"/art/"+name+".jpg",{signal:AbortSignal.timeout(20000)});
  const bytes=(await art.arrayBuffer()).byteLength;
  console.log(JSON.stringify({art:name,status:art.status,contentType:art.headers.get("content-type"),bytes}));
  if(!art.ok||bytes<10000||!art.headers.get("content-type")?.includes("image/jpeg"))process.exitCode=1;
 }
}

const commodityArtworkDeployed=styles.includes(".commodity-art");
console.log(JSON.stringify({commodityArtworkDeployed}));
if(commodityArtworkDeployed){
 for(const name of ["whiskey","silk","steel"]){
  for(const suffix of ["","-256","-96"]){
   const art=await fetch(origin+"/art/commodities/"+name+suffix+".webp",{signal:AbortSignal.timeout(20000)});
   const bytes=(await art.arrayBuffer()).byteLength;
   console.log(JSON.stringify({commodity:name+suffix,status:art.status,contentType:art.headers.get("content-type"),bytes}));
   if(!art.ok||bytes<1000||!art.headers.get("content-type")?.includes("image/webp"))process.exitCode=1;
  }
 }
}

const miningDeployed=styles.includes('.mining-district');
console.log(JSON.stringify({miningDeployed}));
if(miningDeployed){for(const name of ['map','map-small','mine','mine-small','quarry','quarry-small']){
 const art=await fetch(origin+'/art/mining/'+name+'.webp',{signal:AbortSignal.timeout(20000)});
 const bytes=(await art.arrayBuffer()).byteLength;
 console.log(JSON.stringify({miningArtwork:name,status:art.status,bytes}));
 if(!art.ok||bytes<1000||!art.headers.get('content-type')?.includes('image/webp'))process.exitCode=1;
}}

const resourceArtworkDeployed=styles.includes('.mining-refined');console.log(JSON.stringify({resourceArtworkDeployed}));
if(resourceArtworkDeployed){for(const good of ['iron-ore','copper-ore','coal','stone','limestone'])for(const size of ['', '-256','-96']){
 const response=await fetch(origin+'/art/resources/'+good+size+'.webp',{signal:AbortSignal.timeout(20000)});const bytes=(await response.arrayBuffer()).byteLength;
 console.log(JSON.stringify({resourceArt:good+size,status:response.status,bytes}));if(!response.ok||bytes<1000||!response.headers.get('content-type')?.includes('image/webp'))process.exitCode=1;
}}

const confirmationDeployed=styles.includes(".confirmation-frame");
console.log(JSON.stringify({confirmationDeployed}));
if(confirmationDeployed){
 for(const [path,text] of [["/auth/confirmed","Check your invitation."],["/auth/confirm","This link has expired."]]){
  const response=await fetch(origin+path,{signal:AbortSignal.timeout(20000)});const body=await response.text();
  console.log(JSON.stringify({confirmationPage:path,status:response.status,url:response.url}));
  if(!response.ok||!body.includes(text)||body.includes("Account confirmed."))throw new Error("Invalid public confirmation state");
 }
 for(const asset of ["waterfront.jpg","waterfront.webp","brand.png","economy.png","empire.png","gangs.png","browser.png"]){
  const response=await fetch(origin+"/art/email/"+asset,{signal:AbortSignal.timeout(20000)});const bytes=(await response.arrayBuffer()).byteLength;
  console.log(JSON.stringify({confirmationArtwork:asset,status:response.status,bytes}));
  if(!response.ok||!response.headers.get("content-type")?.startsWith("image/")||bytes<300)throw new Error("Confirmation artwork unavailable");
 }
}
