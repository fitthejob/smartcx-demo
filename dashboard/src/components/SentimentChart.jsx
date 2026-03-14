import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer } from "recharts";

const COLORS = {
  POSITIVE: "#34d399",
  NEUTRAL: "#94a3b8",
  NEGATIVE: "#f87171",
};

export default function SentimentChart({ metrics, loading }) {
  if (loading) {
    return (
      <div className="flex h-48 items-center justify-center">
        <div className="h-32 w-32 animate-pulse rounded-full bg-slate-700" />
      </div>
    );
  }

  const breakdown = metrics?.sentimentBreakdown ?? {};
  const data = ["POSITIVE", "NEUTRAL", "NEGATIVE"]
    .map((key) => ({ name: key, value: breakdown[key] ?? 0 }))
    .filter((d) => d.value > 0);

  if (data.length === 0) {
    return (
      <div className="flex h-48 items-center justify-center text-slate-500">
        No sentiment data yet
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={220}>
      <PieChart>
        <Pie
          data={data}
          cx="50%"
          cy="50%"
          innerRadius={55}
          outerRadius={85}
          paddingAngle={3}
          dataKey="value"
        >
          {data.map((entry) => (
            <Cell key={entry.name} fill={COLORS[entry.name]} />
          ))}
        </Pie>
        <Tooltip
          formatter={(value, name) => [value, name.charAt(0) + name.slice(1).toLowerCase()]}
          contentStyle={{ backgroundColor: "#1e293b", border: "none", borderRadius: "6px" }}
          labelStyle={{ color: "#cbd5e1" }}
          itemStyle={{ color: "#f1f5f9" }}
        />
        <Legend
          formatter={(value) => value.charAt(0) + value.slice(1).toLowerCase()}
          wrapperStyle={{ color: "#94a3b8", fontSize: "12px" }}
        />
      </PieChart>
    </ResponsiveContainer>
  );
}
