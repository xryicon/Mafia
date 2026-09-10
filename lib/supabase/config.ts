// Public connection details; never use a service-role key in browser configuration.
const defaultProject={url:"https://pyyyceomujtzfzkytizd.supabase.co",key:"sb_publishable_kinPqCxB8f6i0OMDohknNQ_ElauF1Wz"};
export function validateConfig(url:string|undefined,key:string|undefined,environment="production"){
 if(!["development","test","staging","production"].includes(environment))throw new Error("Invalid NEXT_PUBLIC_APP_ENV.");
 url=url?.trim();key=key?.trim();
 if(!url&&!key){
  if(environment!=="production")throw new Error("Set both Supabase variables for non-production environments.");
  return {...defaultProject};
 }
 if(!url||!key)throw new Error("Set both NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY.");
 let parsed:URL;try{parsed=new URL(url);}catch{throw new Error("Invalid Supabase URL.");}
 const loopback=["localhost","127.0.0.1","[::1]"].includes(parsed.hostname);
 if(parsed.username||parsed.password||parsed.search||parsed.hash||parsed.pathname!=="/"||
 (parsed.protocol!=="https:"&&!(parsed.protocol==="http:"&&loopback&&["test","development"].includes(environment))))
 throw new Error("Supabase URL must use HTTPS, except loopback development/test.");
 if(environment!=="production"&&parsed.hostname===new URL(defaultProject.url).hostname)throw new Error("Non-production must not use the production database.");
 if(key.startsWith("sb_secret_"))throw new Error("Secret keys must never be public.");
 // Legacy JWT credentials are intentionally unsupported: use a publishable key.
 if(!key.startsWith("sb_publishable_"))throw new Error("Use a Supabase publishable key.");
 return {url:url.replace(/\/$/,""),key};
}
export function supabaseConfig(){
 return validateConfig(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,process.env.NEXT_PUBLIC_APP_ENV||"production");
}
