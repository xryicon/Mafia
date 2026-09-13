export const PRISON_PATH = "/districts/blackwater-island";
export type PrisonSentence = {id:string; reason:string; started_at:string; release_at:string};
export type PrisonInmate = {sentence_id:string;player_id:string;handle:string;release_at:string};
export type PrisonBreakAttempt = {id:string;sentence_id:string;inmate_id:string;inmate_handle:string;attempts_left:number;last_turn:number;started_at:string;expires_at:string};
export type BreakoutLeader = {player_id:string;handle:string;breakouts:number;rank:number};
export type PrisonState = {
 season_id:string;player_id:string;jailed:boolean;sentence:PrisonSentence|null;district_slug:string;server_time:string;can_manage:boolean;
 reward_power:number;lockpicks:number;inmates:PrisonInmate[];attempt:PrisonBreakAttempt|null;leaderboard:BreakoutLeader[];my_breakouts:number;my_rank:number|null;
};
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
export function attemptCountdown(expiresAt:string,now:number) {
 const seconds=Math.min(90,Math.max(0,Math.ceil((Date.parse(expiresAt)-now)/1000)));
 return `0:${String(seconds).padStart(2,"0")}`;
}
