export type PlayerVitals={season_id:string;health:number;health_max:number;health_cap:number;armour:number;armour_max:number;decay_seconds:number;server_time:string};
// Display projection only. Future game actions must read/materialize the server value.
export function displayedHealth(v:PlayerVitals,now:number){
 const value=Math.max(0,Math.min(v.health_cap,v.health));
 return value>v.health_max?Math.max(v.health_max,value-Math.max(0,now-Date.parse(v.server_time))/1000/v.decay_seconds):value;
}
