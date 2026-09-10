export type Good = { id: string; name: string; business_name: string; business_cost: number; batch_size: number; cycle_seconds: number };
export type Listing = { id: string; seller_id: string; seller_handle: string; good_id: string; quantity: number; unit_price: number; status: string; created_at: string };
export type Business = { player_id: string; good_id: string; collected_at: string };
export type Job = {id:string;name:string;district:string;description:string;reward:number;xp:number;cooldown:number};
export type Settings = Record<string,number>;
export type GameState = {
 season: import('./seasons').Season;
 jobs: Job[]; settings:Settings; permissions:string[];
 ledger:{id:number;reason:string;delta:number;balance_after:number;created_at:string}[];
  player: { id: string; handle: string; cash: number; xp: number; job_ready_at: string; created_at: string };
  goods: Good[];
  inventory: { good_id: string; quantity: number }[];
  businesses: Business[];
  market: Listing[];
  my_listings: Listing[];
  events: { id: string; description: string; cash_delta: number; created_at: string }[];
  server_time: string;
};
export const money = (value: number) => "$" + Math.round(value).toLocaleString("en-US");
export function rank(xp: number, settings: Settings) {
  if (xp >= settings.rank_underboss) return "Underboss";
  if (xp >= settings.rank_caporegime) return "Caporegime";
  if (xp >= settings.rank_soldier) return "Soldier";
  return "Associate";
}
export function readyUnits(business: Business, good: Good, now: number, cap: number) {
  return Math.max(0, Math.min(cap, Math.floor((now - Date.parse(business.collected_at)) / (good.cycle_seconds * 1000)))) * good.batch_size;
}
export function remaining(until: string, now: number) {
  return Math.max(0, Math.ceil((Date.parse(until) - now) / 1000));
}
export function duration(seconds: number) {
  return Math.floor(seconds / 60).toString().padStart(2, "0") + ":" + (seconds % 60).toString().padStart(2, "0");
}
