import { useState } from "react";
import { useContactsData } from "./hooks/useContactsData";
import QueueMetrics from "./components/QueueMetrics";
import SentimentChart from "./components/SentimentChart";
import QueueLivePanel from "./components/QueueLivePanel";
import ContactsTable from "./components/ContactsTable";
import AlertBanner from "./components/AlertBanner";

function fmtTimestamp(date) {
  if (!date) return "--";
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

export default function App() {
  const [autoRefresh, setAutoRefresh] = useState(true);
  const { metrics, contacts, loading, error, lastRefreshed } = useContactsData(autoRefresh);

  return (
    <div className="min-h-screen bg-slate-900 text-slate-100">
      {/* Header */}
      <header className="border-b border-slate-700 bg-slate-900/80 px-6 py-4 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center justify-between">
          <div className="flex items-center gap-3">
            <span className="text-xl font-bold tracking-tight text-white">SmartCX</span>
            <span className="rounded bg-slate-700 px-2 py-0.5 text-xs font-medium text-slate-300">
              Demo
            </span>
          </div>
          <div className="flex items-center gap-4 text-sm text-slate-400">
            <span>Refreshed: {fmtTimestamp(lastRefreshed)}</span>
            <label className="flex cursor-pointer items-center gap-2">
              <input
                type="checkbox"
                checked={autoRefresh}
                onChange={(e) => setAutoRefresh(e.target.checked)}
                className="h-4 w-4 rounded border-slate-600 bg-slate-700 accent-emerald-500"
              />
              Auto-refresh
            </label>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl space-y-8 px-6 py-8">
        {/* Error state */}
        {error && (
          <div className="rounded-lg border border-red-700 bg-red-950/40 px-4 py-3 text-sm text-red-300">
            Unable to reach the dashboard API. Check that the stack is deployed and{" "}
            <code className="text-red-200">VITE_API_BASE_URL</code> is set correctly.
          </div>
        )}

        {/* Alert banner */}
        <AlertBanner flaggedCount={metrics?.flaggedToday} />

        {/* Metrics cards */}
        <section>
          <QueueMetrics metrics={metrics} loading={loading} />
        </section>

        {/* Sentiment chart + Live queues */}
        <section className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <div className="rounded-lg bg-slate-800 p-5 lg:col-span-1">
            <h2 className="mb-4 text-lg font-semibold text-white">Sentiment Breakdown</h2>
            <SentimentChart metrics={metrics} loading={loading} />
          </div>
          <div className="lg:col-span-2">
            <QueueLivePanel />
          </div>
        </section>

        {/* Recent contacts */}
        <section className="rounded-lg bg-slate-800 p-5">
          <h2 className="mb-4 text-lg font-semibold text-white">Recent Contacts</h2>
          <ContactsTable contacts={contacts} loading={loading} />
        </section>
      </main>
    </div>
  );
}
