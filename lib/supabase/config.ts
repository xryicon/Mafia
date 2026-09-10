// These are public connection details, not admin credentials.
// Keeping them together makes a fresh Cloudflare deployment work without .env.local.
const defaultProject = {
  url: "https://pyyyceomujtzfzkytizd.supabase.co",
  key: "sb_publishable_kinPqCxB8f6i0OMDohknNQ_ElauF1Wz",
};

export function supabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url && !key) return { ...defaultProject };
  // Never combine an override URL with credentials from a different project.
  if (!url || !key) {
    throw new Error("Set both NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, or remove both to use the connected Mafia project.");
  }
  return { url, key };
}
