import test from "node:test";
import assert from "node:assert/strict";
import {usernameError} from "../lib/usernames";
test("usernames accept distinct player names",()=>{for(const name of ["HarborJack","Ada_42","Dock-Boss","  FairTrader  "])assert.equal(usernameError(name),null);});
test("usernames reject reserved identities and ambiguous input",()=>{for(const name of ["ab","1boss","Harbor Jack","<script>","a".repeat(25),"OWNER","Rookie-test","Player-test","support","Mafiá"])assert.ok(usernameError(name),name);});
