import { useState } from "react";
import { useAuth } from "../auth/useAuth";

export default function LoginPage() {
  const { signIn, completeNewPassword, newPasswordRequired, error } = useAuth();

  const [email, setEmail]           = useState("");
  const [password, setPassword]     = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [submitting, setSubmitting]   = useState(false);

  async function handleSignIn(e) {
    e.preventDefault();
    setSubmitting(true);
    await signIn(email, password);
    setSubmitting(false);
  }

  async function handleNewPassword(e) {
    e.preventDefault();
    setSubmitting(true);
    await completeNewPassword(newPassword);
    setSubmitting(false);
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-900 px-4">
      <div className="w-full max-w-sm rounded-xl border border-slate-700 bg-slate-800 p-8 shadow-xl">
        {/* Logo / title */}
        <div className="mb-8 text-center">
          <span className="text-2xl font-bold tracking-tight text-white">SmartCX</span>
          <span className="ml-2 rounded bg-slate-700 px-2 py-0.5 text-xs font-medium text-slate-300">
            Demo
          </span>
          <p className="mt-2 text-sm text-slate-400">Sign in to continue</p>
        </div>

        {/* Error message */}
        {error && (
          <div className="mb-4 rounded-lg border border-red-700 bg-red-950/40 px-4 py-3 text-sm text-red-300">
            {error}
          </div>
        )}

        {/* First-login: set permanent password */}
        {newPasswordRequired ? (
          <form onSubmit={handleNewPassword} className="space-y-4">
            <p className="text-sm text-slate-400">
              Your temporary password has expired. Please set a permanent password.
            </p>
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-400">
                New password
              </label>
              <input
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                required
                minLength={12}
                className="w-full rounded-lg border border-slate-600 bg-slate-700 px-3 py-2 text-sm text-white placeholder-slate-500 focus:border-emerald-500 focus:outline-none"
                placeholder="At least 12 characters"
              />
            </div>
            <button
              type="submit"
              disabled={submitting}
              className="w-full rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-500 disabled:opacity-50"
            >
              {submitting ? "Setting password…" : "Set password"}
            </button>
          </form>
        ) : (
          /* Normal sign-in form */
          <form onSubmit={handleSignIn} className="space-y-4">
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-400">
                Email
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                className="w-full rounded-lg border border-slate-600 bg-slate-700 px-3 py-2 text-sm text-white placeholder-slate-500 focus:border-emerald-500 focus:outline-none"
                placeholder="you@example.com"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-400">
                Password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                autoComplete="current-password"
                className="w-full rounded-lg border border-slate-600 bg-slate-700 px-3 py-2 text-sm text-white placeholder-slate-500 focus:border-emerald-500 focus:outline-none"
                placeholder="••••••••••••"
              />
            </div>
            <button
              type="submit"
              disabled={submitting}
              className="w-full rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-500 disabled:opacity-50"
            >
              {submitting ? "Signing in…" : "Sign in"}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
