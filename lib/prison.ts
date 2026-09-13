export const PRISON_PATH = "/districts/blackwater-island";
export type PrisonSentence = {id:string; reason:string; started_at:string; release_at:string};
export type PrisonState = {jailed:boolean; sentence:PrisonSentence|null; district_slug:string; server_time:string; can_manage:boolean};
export function prisonAllowsPath(path:string) {
 const pathname=path.split("?")[0].replace(/\/$/, "");
 return [PRISON_PATH,"/support","/account","/update-password","/owner","/staff"].includes(pathname);
}
export function sentenceCountdown(releaseAt:string,now:number) {
 const seconds=Math.max(0,Math.ceil((Date.parse(releaseAt)-now)/1000));
 if(!seconds)return "Checking release…";
 const hours=Math.floor(seconds/3600),minutes=Math.floor(seconds%3600/60);
 return [hours,minutes,seconds%60].map(n=>String(n).padStart(2,"0")).join(":");
}
