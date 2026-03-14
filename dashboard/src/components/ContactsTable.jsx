import { useState } from "react";

function fmtDuration(seconds) {
  if (seconds == null) return "--";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

function fmtTime(ts) {
  if (!ts) return "--";
  return new Date(ts).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function SentimentBadge({ label }) {
  const colors = {
    POSITIVE: "bg-emerald-900/50 text-emerald-400",
    NEUTRAL: "bg-slate-700 text-slate-300",
    NEGATIVE: "bg-red-900/50 text-red-400",
  };
  return (
    <span className={`rounded px-2 py-0.5 text-xs font-medium ${colors[label] ?? colors.NEUTRAL}`}>
      {label ? label.charAt(0) + label.slice(1).toLowerCase() : "--"}
    </span>
  );
}

function ChannelBadge({ channel }) {
  return (
    <span
      className={`rounded px-2 py-0.5 text-xs font-medium ${
        channel === "VOICE"
          ? "bg-blue-900/50 text-blue-400"
          : "bg-purple-900/50 text-purple-400"
      }`}
    >
      {channel === "VOICE" ? "Voice" : "Chat"}
    </span>
  );
}

function DetailModal({ contact, onClose }) {
  const mockTranscriptUrl = `https://s3.console.aws.amazon.com/s3/buckets/smartcx-demo-recordings?prefix=${contact.contactId}`;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60"
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg rounded-xl bg-slate-800 p-6 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-lg font-semibold text-white">Contact Detail</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white">
            ✕
          </button>
        </div>
        <dl className="space-y-3 text-sm">
          {[
            ["Contact ID", contact.contactId],
            ["Timestamp", contact.timestamp ? new Date(contact.timestamp).toLocaleString() : "--"],
            ["Channel", contact.channel],
            ["Queue", contact.queueName],
            ["Sentiment", contact.sentimentLabel],
            ["Sentiment Score", contact.sentimentScore ?? "--"],
            ["Duration", fmtDuration(contact.durationSeconds)],
            ["Agent", contact.agentId ?? "--"],
          ].map(([label, value]) => (
            <div key={label} className="flex justify-between">
              <dt className="text-slate-400">{label}</dt>
              <dd className="font-medium text-white">{value}</dd>
            </div>
          ))}
          <div className="flex justify-between">
            <dt className="text-slate-400">Transcript</dt>
            <dd>
              <a
                href={mockTranscriptUrl}
                target="_blank"
                rel="noreferrer"
                className="text-blue-400 hover:underline"
              >
                View in S3
              </a>
            </dd>
          </div>
        </dl>
      </div>
    </div>
  );
}

export default function ContactsTable({ contacts, loading }) {
  const [selected, setSelected] = useState(null);

  if (loading) {
    return (
      <div className="space-y-2">
        {[...Array(5)].map((_, i) => (
          <div key={i} className="h-10 animate-pulse rounded bg-slate-700" />
        ))}
      </div>
    );
  }

  if (contacts.length === 0) {
    return (
      <p className="py-8 text-center text-sm text-slate-500">No contacts in the last 48 hours</p>
    );
  }

  return (
    <>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-slate-700 text-left text-xs font-medium uppercase tracking-wide text-slate-400">
              <th className="pb-2 pr-4">Time</th>
              <th className="pb-2 pr-4">Channel</th>
              <th className="pb-2 pr-4">Queue</th>
              <th className="pb-2 pr-4">Sentiment</th>
              <th className="pb-2 pr-4">Duration</th>
              <th className="pb-2">Agent</th>
            </tr>
          </thead>
          <tbody>
            {contacts.map((c) => (
              <tr
                key={c.contactId}
                onClick={() => setSelected(c)}
                className={`cursor-pointer border-b border-slate-700/50 transition-colors hover:bg-slate-700/40 ${
                  c.sentimentLabel === "NEGATIVE" ? "bg-red-950/20" : ""
                }`}
              >
                <td className="py-2 pr-4 text-slate-300">{fmtTime(c.timestamp)}</td>
                <td className="py-2 pr-4">
                  <ChannelBadge channel={c.channel} />
                </td>
                <td className="py-2 pr-4 text-slate-300">{c.queueName ?? "--"}</td>
                <td className="py-2 pr-4">
                  <SentimentBadge label={c.sentimentLabel} />
                </td>
                <td className="py-2 pr-4 text-slate-300">{fmtDuration(c.durationSeconds)}</td>
                <td className="py-2 text-slate-300">{c.agentId ?? "--"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {selected && <DetailModal contact={selected} onClose={() => setSelected(null)} />}
    </>
  );
}
