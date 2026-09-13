import {strict as assert} from "node:assert";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {RANGE_AUDIO} from "../lib/range-audio";

test("recorded range sounds ship as bounded, self-hosted MP3 assets with source credits",()=>{
 const credits=readFileSync("public/audio/range/CREDITS.md","utf8");
 for(const path of Object.values(RANGE_AUDIO)){
  assert.ok(path.startsWith("/audio/range/"));
  const bytes=readFileSync("public"+path);
  assert.ok(bytes.length>20000&&bytes.length<1200000);
  assert.ok(bytes.subarray(0,3).toString()==="ID3"||(bytes[0]===255&&(bytes[1]&224)===224),"MP3 header");
  assert.ok(credits.includes(path.split("/").at(-1)!));
 }
 assert.ok(credits.includes("CC0 1.0")&&credits.includes("740897")&&credits.includes("396331")&&credits.includes("811818"));
});
