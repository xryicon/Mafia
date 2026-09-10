import {strict as assert} from "node:assert";
import {test} from "node:test";
import {validateConfig} from "../lib/supabase/config";
const key="sb_publishable_fixture";
test("production defaults remain paired",()=>{assert.equal(validateConfig(undefined,undefined).url,"https://pyyyceomujtzfzkytizd.supabase.co");});
test("reject partial configuration",()=>{assert.throws(()=>validateConfig("https://test.supabase.co",undefined),/Set both/);});
test("non-production requires isolation",()=>{assert.throws(()=>validateConfig(undefined,undefined,"staging"));assert.throws(()=>validateConfig("https://pyyyceomujtzfzkytizd.supabase.co",key,"test"));});
test("allow explicit test loopback",()=>{assert.equal(validateConfig("http://localhost:54329",key,"test").url,"http://localhost:54329");});
test("reject credentials, insecure hosts, malformed URLs, secret keys and unknown environments",()=>{
 for(const url of ["bad","http://remote.example","https://user:pass@example.com","https://example.com/path","https://example.com?secret=x"])assert.throws(()=>validateConfig(url,key));
 assert.throws(()=>validateConfig("https://test.supabase.co","sb_secret_hidden"));
 assert.throws(()=>validateConfig("https://test.supabase.co",key,"unknown"));
});
