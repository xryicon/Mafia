import { defineCloudflareConfig } from "@opennextjs/cloudflare";

const config = defineCloudflareConfig();
// The public build script produces the Worker; avoid calling it recursively.
config.buildCommand = "npm run build:next";
export default config;
