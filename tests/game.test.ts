import { strict as assert } from "node:assert";
import { test } from "node:test";
import { rank, readyUnits, remaining, duration, money } from "../lib/game";
const good = { id: "whiskey", name: "Whiskey", business_name: "Distillery", business_cost: 3000, batch_size: 3, cycle_seconds: 300 };
const business = { player_id: "test", good_id: "whiskey", collected_at: "2026-09-10T00:00:00Z" };
const start = Date.parse(business.collected_at);
test("production counts complete cycles and caps offline accumulation", () => {
 assert.equal(readyUnits(business,good,start+299000),0);
 assert.equal(readyUnits(business,good,start+300000),3);
 assert.equal(readyUnits(business,good,start+600000),6);
 assert.equal(readyUnits(business,good,start+999999999),72);
 assert.equal(readyUnits(business,good,start-1000),0);
});
test("cooldown display clamps expiry and respects the server clock", () => {
 assert.equal(remaining("2026-09-10T00:01:00Z",start),60);
 assert.equal(remaining("2026-09-10T00:01:00Z",start+61000),0);
 assert.equal(duration(61),"01:01");
});
test("rank thresholds and cash formatting", () => {
 assert.equal(rank(0),"Associate");assert.equal(rank(250),"Soldier");
 assert.equal(rank(800),"Caporegime");assert.equal(rank(2000),"Underboss");
 assert.equal(money(10000),"$10,000");
});
