export type Good = { id: string; name: string; business_name: string; business_cost: number; batch_size: number; cycle_seconds: number };
export type Listing = { id: string; seller_id: string; seller_handle: string; good_id: string; quantity: number; unit_price: number; status: string; created_at: string };
export type Business = { player_id: string; good_id: string; collected_at: string };
export type GameState = {
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
export function rank(xp: number) {
  if (xp >= 2000) return "Underboss";
  if (xp >= 800) return "Caporegime";
  if (xp >= 250) return "Soldier";
  return "Associate";
}
export function readyUnits(business: Business, good: Good, now: number) {
  return Math.max(0, Math.min(24, Math.floor((now - Date.parse(business.collected_at)) / (good.cycle_seconds * 1000)))) * good.batch_size;
}
export function remaining(until: string, now: number) {
  return Math.max(0, Math.ceil((Date.parse(until) - now) / 1000));
}
export function duration(seconds: number) {
  return Math.floor(seconds / 60).toString().padStart(2, "0") + ":" + (seconds % 60).toString().padStart(2, "0");
}
export const jobs = [
  { id: "docks", name: "Dock errand", district: "THE DOCKS", description: "Put in a favor. Get your name known around the waterfront.", reward: 250, xp: 10, cooldown: 60 },
  { id: "warehouse", name: "Warehouse shift", district: "INDUSTRIAL QUARTER", description: "Keep the goods moving and the warehouse crew on your side.", reward: 600, xp: 20, cooldown: 180 },
  { id: "courier", name: "Night courier", district: "OLD TOWN", description: "Work the night shift. A reliable name opens the right doors.", reward: 1100, xp: 40, cooldown: 360 },
];
