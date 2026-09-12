import {safeNext} from "./auth-paths";
export const CONFIRMED_PATH="/auth/confirmed";
export function confirmationToken(params:URLSearchParams):string|null{
 const type=params.get("type"),token=params.get("token_hash");
 return (type===null||type==="email"||type==="signup")&&token&&/^[A-Za-z0-9_-]{20,2048}$/.test(token)?token:null;
}
export function callbackDestination(value:string|null):string{
 return value===null||value===CONFIRMED_PATH?CONFIRMED_PATH:safeNext(value);
}
