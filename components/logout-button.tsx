"use client";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export function LogoutButton() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function logout() {
    setBusy(true); setError("");
    try {
      const db = createClient();
      await Promise.race([db.rpc("presence_leave").then(() => null, () => null), new Promise(resolve => setTimeout(resolve, 1500))]);
      const { error } = await db.auth.signOut({ scope: "local" });
      if (error) throw error;
      window.location.assign("/login");
    } catch {
      setError("Unable to log out. Please try again.");
      setBusy(false);
    }
  }
  return <div><button className="button secondary" onClick={logout} disabled={busy}>{busy ? "Logging out…" : "Log out"}</button>{error && <p role="alert" className="notice error">{error}</p>}</div>;
}
