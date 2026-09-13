import test from "node:test";
import assert from "node:assert/strict";
import {displayedHealth,type PlayerVitals} from "../lib/vitals";
const now=Date.parse("2026-09-13T16:00:00Z");
const state:PlayerVitals={season_id:"test",health:120,health_max:100,health_cap:120,armour:0,armour_max:100,decay_seconds:60,server_time:new Date(now).toISOString()};
test("temporary overheal falls from 120 to 100, never below normal maximum",()=>{
 assert.equal(displayedHealth(state,now),120);
 assert.equal(displayedHealth(state,now+600000),110);
 assert.equal(displayedHealth(state,now+1200000),100);
 assert.equal(displayedHealth(state,now+86400000),100);
 assert.equal(displayedHealth(state,now-600000),120);
});
test("ordinary health, injuries and zero health remain unchanged by overheal decay",()=>{
 for(const health of [0,37,100])assert.equal(displayedHealth({...state,health},now+86400000),health);
});
