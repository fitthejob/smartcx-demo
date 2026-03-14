import { useQueueLive } from "../hooks/useQueueLive";

function fmtSeconds(s) {
  if (s == null) return "--";
  const m = Math.floor(s / 60);
  const sec = Math.floor(s % 60);
  return `${m}:${String(sec).padStart(2, "0")}`;
}

function fmtTime(date) {
  if (!date) return "--";
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

function QueueCard({ q }) {
  const waitingColor =
    q.contactsInQueue > 3
      ? "text-red-400"
      : q.contactsInQueue > 0
      ? "text-amber-400"
      : "text-white";

  const oldestColor =
    q.oldestContactAgeSeconds > 120 ? "text-red-400" : "text-white";

  return (
    <div className="rounded-lg bg-slate-800 p-4">
      <div className="mb-3 flex items-center gap-2">
        <span className="font-semibold text-white">{q.queueName}</span>
        <span className="rounded bg-slate-700 px-2 py-0.5 text-xs font-medium text-slate-300">
          {q.channel}
        </span>
      </div>
      <div className="grid grid-cols-2 gap-y-2 text-sm">
        <span className="text-slate-400">Waiting</span>
        <span className={`font-bold ${waitingColor}`}>{q.contactsInQueue ?? 0}</span>

        <span className="text-slate-400">Oldest wait</span>
        <span className={`font-medium ${oldestColor}`}>
          {fmtSeconds(q.oldestContactAgeSeconds)}
        </span>

        <span className="text-slate-400">Available</span>
        <span className="font-medium text-emerald-400">{q.agentsAvailable ?? 0}</span>

        <span className="text-slate-400">On contact</span>
        <span className="font-medium text-slate-300">{q.agentsOnContact ?? 0}</span>

        <span className="text-slate-400">ACW</span>
        <span className="font-medium text-slate-300">{q.agentsAfterContactWork ?? 0}</span>
      </div>
    </div>
  );
}

export default function QueueLivePanel() {
  const { queues, asOf, unavailable } = useQueueLive();

  return (
    <div>
      <div className="mb-4 flex items-center gap-3">
        <h2 className="text-lg font-semibold text-white">Live Queue Status</h2>
        {!unavailable && (
          <span className="flex items-center gap-1.5 rounded-full bg-emerald-900/40 px-2.5 py-0.5 text-xs font-medium text-emerald-400">
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-75" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-500" />
            </span>
            Live
          </span>
        )}
        {asOf && (
          <span className="ml-auto text-xs text-slate-500">As of {fmtTime(asOf)}</span>
        )}
      </div>

      {unavailable ? (
        <div className="rounded-lg bg-slate-800 p-6 text-center text-sm text-slate-500">
          Live data unavailable
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          {queues.map((q) => (
            <QueueCard key={`${q.queueName}-${q.channel}`} q={q} />
          ))}
        </div>
      )}
    </div>
  );
}
