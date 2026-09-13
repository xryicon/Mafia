import {strict as assert} from "node:assert";
import {test} from "node:test";
import {rangeSound,type RangeSound} from "../lib/range-audio";
for(const kind of ["shot","reload","ambient"] as RangeSound[])test(`${kind} effect is audible, finite, bounded and fades at endpoints`,()=>{const samples=rangeSound(kind,24000);assert.ok(samples.length>10000);assert.ok(samples.every(Number.isFinite));const peak=samples.reduce((n,s)=>Math.max(n,Math.abs(s)),0);assert.ok(peak>.01&&peak<=.9);assert.ok(Math.abs(samples[0])<.001&&Math.abs(samples.at(-1)!)<.001);});
