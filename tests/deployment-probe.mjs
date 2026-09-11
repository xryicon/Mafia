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
console.log(JSON.stringify({deployedLayout:styles.includes(".estate-city")&&styles.includes(".property-layout")?"reference-property-screen":"previous-layout",stylesheets:sheets.length}));
