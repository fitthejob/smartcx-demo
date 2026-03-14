export default function AlertBanner({ flaggedCount }) {
  if (!flaggedCount || flaggedCount === 0) return null;

  return (
    <div className="flex items-center gap-3 rounded-lg border border-red-700 bg-red-950/50 px-4 py-3 text-sm text-red-300">
      <svg className="h-4 w-4 shrink-0 text-red-400" fill="currentColor" viewBox="0 0 20 20">
        <path
          fillRule="evenodd"
          d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
          clipRule="evenodd"
        />
      </svg>
      <span>
        <strong>{flaggedCount}</strong> flagged contact{flaggedCount !== 1 ? "s" : ""} today with
        negative sentiment
      </span>
    </div>
  );
}
