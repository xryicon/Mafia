// Read-only smoke probe for the user's public deployment. No cookies or credentials.
const origin = "https://mafia.xryicon.workers.dev";
for (const path of ["/","/login","/signup","/forgot-password"]) {
 try {
  const response=await fetch(origin+path,{redirect:"follow",signal:AbortSignal.timeout(20000)});
  const html=await response.text();
  console.log(JSON.stringify({path,status:response.status,url:response.url,title:html.match(/<title>([^<]*)<\/title>/i)?.[1],heading:html.match(/<h1[^>]*>(.*?)<\/h1>/is)?.[1]?.replace(/<[^>]*>/g,""),errorExcerpt:response.ok?undefined:html.replace(/<[^>]*>/g," ").slice(0,400)}));
 } catch(error) {console.log(JSON.stringify({path,error:error.message}));}
}
