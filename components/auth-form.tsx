"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { safeNext } from "@/lib/auth-paths";

export type AuthMode = "login" | "signup" | "forgot-password" | "update-password";
const labels = {
  login: ["Welcome back, boss.", "Blackwater is still moving. Log in and pick up where you left off.", "Log in"],
  signup: ["Make your name.", "Start with $10,000 and five whiskey crates. What you build next is up to you.", "Create account"],
  "forgot-password": ["Let's get you back.", "Enter your email and we'll send a password reset link.", "Send reset link"],
  "update-password": ["A fresh start.", "Choose a new password for your account.", "Save new password"],
};

export function AuthForm({ mode, next = "/dashboard", initialMessage = "" }: { mode: AuthMode; next?: string; initialMessage?: string }) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(initialMessage);
  const [failed, setFailed] = useState(false);
  const [title, subtitle, button] = labels[mode];
  const hasPassword = mode !== "forgot-password";
  const newPassword = mode === "signup" || mode === "update-password";

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    const values = new FormData(event.currentTarget);
    const email = String(values.get("email") ?? "").trim();
    const password = String(values.get("password") ?? "");
    setMessage("");
    setFailed(false);
    if (newPassword && (password.length < 12 || password !== values.get("confirm"))) {
      setFailed(true);
      setMessage("Use at least 12 characters and make sure both passwords match.");
      return;
    }
    setBusy(true);
    try {
      const supabase = createClient();
      if (mode === "login") {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw new Error("Unable to log in. Check your details and confirm your email, then try again.");
        window.location.assign(safeNext(next));
        return;
      }
      if (mode === "signup") {
        const { data, error } = await supabase.auth.signUp({
          email, password,
          options: { emailRedirectTo: window.location.origin + "/auth/callback" },
        });
        if (error) throw new Error("Unable to create an account right now. Try again later, or log in if you already have one.");
        if (data.session) { window.location.assign("/dashboard"); return; }
        setMessage("Check your email to confirm your account. If you already have an account, log in or reset your password.");
      } else if (mode === "forgot-password") {
        const { error } = await supabase.auth.resetPasswordForEmail(email, {
          redirectTo: window.location.origin + "/auth/callback?next=/update-password",
        });
        if (error) throw new Error("Unable to send a reset link right now. Please try again later.");
        setMessage("If an account exists for that email, a reset link is on its way. Open it in this browser.");
      } else {
        const { data: { user }, error: userError } = await supabase.auth.getUser();
        if (userError || !user) throw new Error("Your session has expired. Request a new password reset link.");
        const { error } = await supabase.auth.updateUser({ password });
        if (error) throw new Error("Unable to update your password. Try a different password or request a new reset link.");
        window.location.assign("/dashboard?updated=1");
        return;
      }
    } catch (error) {
      setFailed(true);
      setMessage(error instanceof Error ? error.message : "Something went wrong. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return <section className="auth-shell">
    <div className="auth-intro"><p className="eyebrow">BLACKWATER / PLAYER ACCESS</p><h1>{title}</h1><p>{subtitle}</p><div className="auth-symbol" aria-hidden="true">♠</div></div>
    <div className="auth-panel"><form onSubmit={submit} aria-busy={busy}>
      <p className="eyebrow">ENTER THE CITY</p>
      {mode !== "update-password" && <label htmlFor="email">Email address<input id="email" name="email" type="email" autoComplete="email" placeholder="you@example.com" required maxLength={254} /></label>}
      {hasPassword && <label htmlFor="password">{newPassword ? "New password" : "Password"}<input id="password" name="password" type="password" autoComplete={newPassword ? "new-password" : "current-password"} required minLength={newPassword ? 12 : 1} maxLength={128} aria-describedby={newPassword ? "password-hint" : undefined} /></label>}
      {newPassword && <><p className="hint" id="password-hint">At least 12 characters. A memorable passphrase works well.</p><label htmlFor="confirm">Confirm password<input id="confirm" name="confirm" type="password" autoComplete="new-password" required minLength={12} maxLength={128} /></label></>}
      {mode === "login" && <Link className="forgot" href="/forgot-password">Forgot password?</Link>}
      {message && <p className={failed ? "notice error" : "notice"} role={failed ? "alert" : "status"}>{message}</p>}
      <button className="button full" type="submit" disabled={busy}>{busy ? "Please wait…" : button}<span aria-hidden="true">↗</span></button>
      <p className="form-bottom">{mode === "login" ? <>New to Blackwater? <Link href="/signup">Create an account</Link></> : <Link href="/login">Back to log in</Link>}</p>
    </form></div>
  </section>;
}
