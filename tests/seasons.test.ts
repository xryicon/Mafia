import {test} from "node:test";
import {strict as assert} from "node:assert";
import {seasonPlayable,resetConfirmation} from "../lib/seasons";
test("closed, prepared and expired seasons disable gameplay",()=>{
 for(const status of ["draft","locked","finalized","archived"] as const)assert.equal(seasonPlayable({status,ends_at:null},0),false);
 assert.equal(seasonPlayable({status:"open",ends_at:null},0),true);
 assert.equal(seasonPlayable({status:"open",ends_at:"2026-01-01T00:00:00Z"},Date.parse("2026-01-01T00:00:00Z")),false);
});
test("reset confirmation includes exact season identity",()=>assert.equal(resetConfirmation("Blackwater 2"),"RESET Blackwater 2"));
