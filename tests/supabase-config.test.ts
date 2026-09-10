import { strict as assert } from "node:assert";
import { test } from "node:test";
import { supabaseConfig } from "../lib/supabase/config";
function withConfig(url: string | undefined, key: string | undefined, run: () => void) {
 const originalUrl=process.env.NEXT_PUBLIC_SUPABASE_URL;
 const originalKey=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
 try {
  if(url===undefined)delete process.env.NEXT_PUBLIC_SUPABASE_URL;else process.env.NEXT_PUBLIC_SUPABASE_URL=url;
  if(key===undefined)delete process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;else process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=key;
  run();
 } finally {
  if(originalUrl===undefined)delete process.env.NEXT_PUBLIC_SUPABASE_URL;else process.env.NEXT_PUBLIC_SUPABASE_URL=originalUrl;
  if(originalKey===undefined)delete process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;else process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=originalKey;
 }
}
test("fresh deployments work without environment variables", () => withConfig(undefined,undefined,()=>{
 assert.deepEqual(supabaseConfig(),{url:"https://pyyyceomujtzfzkytizd.supabase.co",key:"sb_publishable_kinPqCxB8f6i0OMDohknNQ_ElauF1Wz"});
}));
test("empty Cloudflare variables use the same paired defaults", () => withConfig(" ","",()=>{
 assert.equal(supabaseConfig().url,"https://pyyyceomujtzfzkytizd.supabase.co");
}));
test("explicit deployment and CI overrides remain paired", () => withConfig(" http://localhost:54329 "," fixture-key ",()=>{
 assert.deepEqual(supabaseConfig(),{url:"http://localhost:54329",key:"fixture-key"});
}));
test("partial overrides never mix two Supabase projects", () => {
 withConfig("https://another.supabase.co",undefined,()=>assert.throws(supabaseConfig,/Set both/));
 withConfig(undefined,"another-key",()=>assert.throws(supabaseConfig,/Set both/));
});
