import {test} from "node:test";
import {strict as assert} from "node:assert";
import {errorRecord} from "../lib/error-log";
test("error records omit messages and query secrets",()=>{
 const record=errorRecord({name:"Error",digest:"abc"},"POST","/auth/callback?code=secret");
 assert.equal(record.route,"/auth/callback");assert.equal(JSON.stringify(record).includes("secret"),false);
});
