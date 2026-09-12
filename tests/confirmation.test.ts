import {strict as assert} from "node:assert";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {confirmationToken,callbackDestination} from "../lib/confirmation";
test("confirmation accepts only supported email token links",()=>{
 const token="a".repeat(64);
 assert.equal(confirmationToken(new URLSearchParams({token_hash:token,type:"email"})),token);
 for(const params of [{token_hash:token,type:"recovery"},{token_hash:"",type:"email"},{token_hash:"<script>",type:"email"},{token_hash:"a".repeat(2049),type:"email"}])assert.equal(confirmationToken(new URLSearchParams(params)),null);
});
test("signup lands on confirmation while reset and safe redirects remain supported",()=>{
 assert.equal(callbackDestination(null),"/auth/confirmed");
 assert.equal(callbackDestination("/auth/confirmed"),"/auth/confirmed");
 assert.equal(callbackDestination("/update-password"),"/update-password");
 assert.equal(callbackDestination("//evil.example"),"/dashboard");
});
test("email has a real token link, readable fallback, and email-safe images",()=>{
 const html=readFileSync("supabase/templates/confirmation.html","utf8");
 assert.match(html,/\/auth\/confirm\?token_hash=\{\{ \.TokenHash \}\}&amp;type=email/);
 assert.match(html,/Button not working/);assert.match(html,/bgcolor="#081215"/);
 assert.ok(Buffer.byteLength(html)<102400,"Gmail should not clip the confirmation button");
 assert.doesNotMatch(html,/<script|<iframe|\.webp|unsubscribe|24 hours/i);
 for(const asset of ["waterfront.jpg","brand.png","economy.png","empire.png","gangs.png","browser.png"])assert.ok(html.includes("/art/email/"+asset));
});
