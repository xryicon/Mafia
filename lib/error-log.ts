export function errorRecord(error:{name?:string;digest?:string},method:string,route:string){
 return {event:"request_error",error_type:error.name==="TypeError"?"TypeError":"Error",digest:error.digest?.replace(/[^a-zA-Z0-9_-]/g,"").slice(0,80),
 method:["GET","POST","PUT","PATCH","DELETE"].includes(method)?method:"OTHER",
 route:route.split("?")[0].replace(/[\r\n]/g,"").slice(0,160)};
}
