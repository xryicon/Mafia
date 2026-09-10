export function errorRecord(input:unknown,method:string,route:string){
 const error=input&&typeof input==="object"?input as Record<string,unknown>:{};
 const digest=typeof error.digest==="string"?error.digest:undefined;
 return {event:"request_error",error_type:error.name==="TypeError"?"TypeError":"Error",digest:digest?.replace(/[^a-zA-Z0-9_-]/g,"").slice(0,80),
 method:["GET","POST","PUT","PATCH","DELETE"].includes(method)?method:"OTHER",
 route:route.split("?")[0].replace(/[\r\n]/g,"").slice(0,160)};
}
