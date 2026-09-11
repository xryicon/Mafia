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

for(const path of ["/dashboard","/districts","/districts/the-waterfront","/districts/manage","/telegrams"]){
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
console.log(JSON.stringify({commandDashboardDeployed}));
if(commandDashboardDeployed){
 for(const name of ["command-city","command-portrait"]){
  const art=await fetch(origin+"/art/"+name+".jpg",{signal:AbortSignal.timeout(20000)});
  const bytes=(await art.arrayBuffer()).byteLength;
  console.log(JSON.stringify({art:name,status:art.status,contentType:art.headers.get("content-type"),bytes}));
  if(!art.ok||bytes<10000||!art.headers.get("content-type")?.includes("image/jpeg"))process.exitCode=1;
 }
}
