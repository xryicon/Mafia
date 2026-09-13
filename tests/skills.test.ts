import test from 'node:test';
import assert from 'node:assert/strict';
import {skillThreshold,skillProgress,type Skill} from '../lib/skills';
test('Owner curve preview preserves endpoints and distinct levels for every valid total',()=>{
 for(const total of [19,20,100,10000,1000000000]){assert.equal(skillThreshold(1,total),0);assert.equal(skillThreshold(20,total),total);let last=0;for(let level=2;level<=20;level++){const next=skillThreshold(level,total);assert.ok(Number.isInteger(next)&&next>last);last=next;}}
});
test('progress uses earned XP within the current level and caps mastered skills',()=>{
 assert.equal(skillProgress({xp:150,level_xp:100,next_level_xp:200} as Skill),50);
 assert.equal(skillProgress({xp:20000,level_xp:10000,next_level_xp:null} as Skill),100);
});
