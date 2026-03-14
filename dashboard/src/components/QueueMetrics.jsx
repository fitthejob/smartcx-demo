export default function QueueMetrics({ metrics, loading }) {
  function fmtDuration(seconds) {
    if (seconds == null) return "--";
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  const cards = [
    {
      label: "Contacts Today",
      value: loading ? null : (metrics?.contactsToday ?? "--"),
      color: "text-white",
    },
    {
      label: "Avg Handle Time",
      value: loading ? null : fmtDuration(metrics?.avgHandleTimeSeconds),
      color: "text-white",
    },
    {
      label: "Positive Sentiment",
      value: loading ? null : (metrics?.positivePct != null ? `${metrics.positivePct}%` : "--"),
      color: "text-emerald-400",
    },
    {
      label: "Flagged Contacts",
      value: loading ? null : (metrics?.flaggedToday ?? "--"),
      color: metrics?.flaggedToday > 0 ? "text-red-400" : "text-white",
    },
  ];

  return (
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
      {cards.map(({ label, value, color }) => (
        <div key={label} className="rounded-lg bg-slate-800 p-4">
          <p className="text-xs font-medium uppercase tracking-wide text-slate-400">{label}</p>
          {value == null ? (
            <div className="mt-2 h-8 w-20 animate-pulse rounded bg-slate-700" />
          ) : (
            <p className={`mt-1 text-3xl font-bold ${color}`}>{value}</p>
          )}
        </div>
      ))}
    </div>
  );
}
