import { useState } from "react";

const COLORS = {
  bg: "#0F1117",
  card: "#1A1D2E",
  cardBorder: "#2A2D3E",
  primary: "#C9942A",
  primaryLight: "#E8B84B",
  flame: "#FF6B35",
  green: "#2E7D5E",
  greenLight: "#3DA87D",
  red: "#C0392B",
  text: "#F0EDE8",
  textMuted: "#8A8799",
  textDim: "#5A5768",
  indigo: "#2D3A8C",
  indigoBright: "#4A5FD4",
};

const FREE_FEATURES = [
  { label: "Spark Mode (90-sec sessions)", included: true },
  { label: "Daily Reading", included: true },
  { label: "1 Bible version (KJV, CSB, or NIV)", included: true },
  { label: "Basic AI study questions (3/day)", included: true },
  { label: "Streaks & XP system", included: true },
  { label: "Memory Verse Game (5 verses/month)", included: true },
  { label: "Topic Quiz (3/week)", included: true },
  { label: "Random Spark button", included: true },
  { label: "Focus Companion notifications", included: true },
  { label: "Group Study (join & create)", included: true },
  { label: "Shareable XP milestone badges", included: true },
  { label: "Sermon Notes (1 AI Debrief/month)", included: true },
  { label: "Word of the Day", included: true },
  { label: "Multi-version comparison (KJV, CSB, NIV)", included: false },
  { label: "Unlimited AI questions & prompts", included: false },
  { label: "Full Greek/Hebrew Explorer", included: false },
  { label: "Unlimited Memory Verse + Spaced Repetition", included: false },
  { label: "Unlimited AI Sermon Debrief", included: false },
  { label: "Streak Freeze (3-day pause)", included: false },
  { label: "Downloadable study notes (PDF export)", included: false },
];

// Cost model assumptions — OPTIMIZED
const COSTS = {
  // Claude Haiku 4.5 — $1.00 input / $5.00 output per million tokens
  claudeInputPerMToken: 1.0,
  claudeOutputPerMToken: 5.0,

  // Avg tokens per AI call: ~800 input (passage + prompt), ~400 output
  avgInputTokens: 800,
  avgOutputTokens: 400,

  // Firestore Standard: $0.06 per 100K reads, $0.18 per 100K writes
  firestoreReadPer100k: 0.06,
  firestoreWritePer100k: 0.18,

  // API.Bible: near-zero after full Bible pre-loaded into Firestore
  // Only keyword search hits API — estimated <500 calls/month total
  apiBibleFreeMonthly: 5000,

  // Firebase Cloud Functions: ~$0.40 per million invocations
  functionsPer1M: 0.40,

  // Apple App Store: 15% for small developers under $1M/yr
  appleCutPercent: 0.15,

  // Firebase free tier: 50K reads/day, 20K writes/day
  firestoreFreeReadsPerDay: 50000,
  firestoreFreeWritesPerDay: 20000,
};

function costPerClaudeCall() {
  const inputCost = (COSTS.avgInputTokens / 1_000_000) * COSTS.claudeInputPerMToken;
  const outputCost = (COSTS.avgOutputTokens / 1_000_000) * COSTS.claudeOutputPerMToken;
  return inputCost + outputCost;
}

function formatCents(val) {
  if (val < 0.01) return `< $0.01`;
  if (val < 1) return `$${val.toFixed(3)}`;
  return `$${val.toFixed(2)}`;
}

function formatDollar(val) {
  return `$${val.toFixed(2)}`;
}

export default function App() {
  const [freeUsers, setFreeUsers] = useState(1000);
  const [paidMonthly, setPaidMonthly] = useState(50);
  const [paidAnnual, setPaidAnnual] = useState(30);
  const [paidStudent, setPaidStudent] = useState(20);
  const [tab, setTab] = useState("features");

  const totalUsers = freeUsers + paidMonthly + paidAnnual + paidStudent;
  const totalPaid = paidMonthly + paidAnnual + paidStudent;

  // --- REVENUE ---
  const monthlyRevenue = paidMonthly * 3.99 + (paidAnnual * 29.99) / 12 + (paidStudent * 19.99) / 12;
  const afterApple = monthlyRevenue * (1 - COSTS.appleCutPercent);
  const revenuePerPaidUser = totalPaid > 0 ? monthlyRevenue / totalPaid : 0;

  const aiCostPerCall = costPerClaudeCall();

  // --- AI COSTS ---
  // FREE users: Spark question pre-cached server-side each morning
  // Cost = ~30 unique passages/month × 1 call each (shared across ALL free users)
  // Non-cached on-demand calls: 1 AI call/day cap, but most served from cache
  // Effective free user AI calls: ~30/month total (not per user)
  const freeAICallsPerMonth = 30; // pre-cached daily Spark — fixed cost regardless of free user count
  const freeOnDemandCalls = freeUsers * 0.2 * 15; // ~20% use on-demand, 15 active days
  const totalFreeAICalls = freeAICallsPerMonth + freeOnDemandCalls;

  // PAID users: unlimited, real-time, assume 4 calls/day, 20 active days/month
  const paidAICallsPerMonth = totalPaid * 4 * 20;

  // Batch API (50% discount) for nightly pre-generation: quiz, Word of Day, reading plan
  const batchCallsPerMonth = 30 * 3; // 3 batch items per day at 50% cost
  const batchAICost = batchCallsPerMonth * aiCostPerCall * 0.5;

  const totalAICalls = totalFreeAICalls + paidAICallsPerMonth;
  const totalAICost = totalAICalls * aiCostPerCall + batchAICost;

  // --- FIRESTORE COSTS ---
  // Full Bible pre-loaded: reads served from Firestore, not API.Bible
  // Free user: ~50 reads/session (from Firestore bible cache), 15 sessions/month
  //   Write batching: 2 writes/session (batched XP + stats), no live listeners
  // Paid user: ~80 reads/session, 20 sessions/month, live listeners add ~20 reads/session
  const freeReadsMonth = freeUsers * 50 * 15;
  const paidReadsMonth = totalPaid * 100 * 20; // includes live listener reads
  const freeWritesMonth = freeUsers * 2 * 15; // batched writes
  const paidWritesMonth = totalPaid * 4 * 20; // batched writes + more features
  const totalReads = freeReadsMonth + paidReadsMonth;
  const totalWrites = freeWritesMonth + paidWritesMonth;

  // Firebase free tier: 50K reads/day * 30 = 1.5M reads/month, 20K writes/day * 30 = 600K writes/month
  const freeReadsAllowance = 1_500_000;
  const freeWritesAllowance = 600_000;
  const billableReads = Math.max(0, totalReads - freeReadsAllowance);
  const billableWrites = Math.max(0, totalWrites - freeWritesAllowance);
  const firestoreCost = (billableReads / 100_000) * COSTS.firestoreReadPer100k +
    (billableWrites / 100_000) * COSTS.firestoreWritePer100k;

  // --- API.BIBLE COSTS ---
  // Full Bible pre-loaded into Firestore — API.Bible only used for keyword search
  // Estimated <500 calls/month total — well within 5,000 free tier
  const apiBibleCallsMonth = Math.min(500 + totalUsers * 0.1, COSTS.apiBibleFreeMonthly);
  const apiBibleOverage = Math.max(0, apiBibleCallsMonth - COSTS.apiBibleFreeMonthly);
  const apiBibleCost = apiBibleOverage * 0.001;

  // --- FUNCTIONS COSTS ---
  const functionInvocations = totalAICalls + totalUsers * 5;
  const functionCost = (functionInvocations / 1_000_000) * COSTS.functionsPer1M;

  // --- TOTALS ---
  const totalInfraCost = totalAICost + firestoreCost + apiBibleCost + functionCost;

  // Free user cost: fixed AI cache cost spread across all free users + Firestore + functions
  const freeAICostShare = (totalFreeAICalls * aiCostPerCall + batchAICost * 0.5);
  const costPerFreeUser = freeUsers > 0
    ? freeAICostShare / freeUsers + (firestoreCost * (freeReadsMonth / Math.max(totalReads, 1))) / freeUsers
    : 0;

  const paidAICostShare = paidAICallsPerMonth * aiCostPerCall + batchAICost * 0.5;
  const costPerPaidUser = totalPaid > 0
    ? paidAICostShare / totalPaid + (firestoreCost * (paidReadsMonth / Math.max(totalReads, 1))) / totalPaid
    : 0;

  const netRevenueAfterCosts = afterApple - totalInfraCost;
  const margin = afterApple > 0 ? (netRevenueAfterCosts / afterApple) * 100 : 0;
  const conversionRate = totalUsers > 0 ? (totalPaid / totalUsers) * 100 : 0;

  const sliderStyle = {
    width: "100%",
    accentColor: COLORS.primary,
    cursor: "pointer",
  };

  const cardStyle = {
    background: COLORS.card,
    border: `1px solid ${COLORS.cardBorder}`,
    borderRadius: 12,
    padding: "20px",
  };

  const statCard = (label, value, sub, color = COLORS.primary) => (
    <div style={{ ...cardStyle, textAlign: "center" }}>
      <div style={{ color: COLORS.textMuted, fontSize: 11, textTransform: "uppercase", letterSpacing: 1, marginBottom: 6 }}>{label}</div>
      <div style={{ color: color, fontSize: 26, fontWeight: 700, marginBottom: 2 }}>{value}</div>
      {sub && <div style={{ color: COLORS.textDim, fontSize: 11 }}>{sub}</div>}
    </div>
  );

  return (
    <div style={{ background: COLORS.bg, minHeight: "100vh", color: COLORS.text, fontFamily: "Inter, system-ui, sans-serif", padding: "24px 16px" }}>
      <div style={{ maxWidth: 720, margin: "0 auto" }}>

        {/* Header */}
        <div style={{ marginBottom: 28, textAlign: "center" }}>
          <div style={{ fontSize: 28, marginBottom: 4 }}>🔥</div>
          <h1 style={{ fontSize: 22, fontWeight: 700, color: COLORS.text, margin: "0 0 4px" }}>StudyFire</h1>
          <p style={{ color: COLORS.textMuted, fontSize: 13, margin: 0 }}>Unit Economics & Feature Comparison</p>
        </div>

        {/* Tabs */}
        <div style={{ display: "flex", gap: 8, marginBottom: 24, background: COLORS.card, borderRadius: 10, padding: 4 }}>
          {[["features", "Free vs Paid"], ["costs", "Cost Per User"], ["sustainability", "Sustainability"]].map(([key, label]) => (
            <button key={key} onClick={() => setTab(key)} style={{
              flex: 1, padding: "8px 4px", borderRadius: 8, border: "none", cursor: "pointer", fontSize: 12, fontWeight: 600,
              background: tab === key ? COLORS.primary : "transparent",
              color: tab === key ? "#000" : COLORS.textMuted,
              transition: "all 0.2s"
            }}>{label}</button>
          ))}
        </div>

        {/* FEATURES TAB */}
        {tab === "features" && (
          <div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginBottom: 16 }}>
              <div style={{ ...cardStyle, borderColor: COLORS.cardBorder }}>
                <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.textMuted, marginBottom: 12, textTransform: "uppercase", letterSpacing: 1 }}>Free</div>
                <div style={{ fontSize: 11, color: COLORS.textDim, marginBottom: 12 }}>$0/month</div>
                {FREE_FEATURES.filter(f => f.included).map((f, i) => (
                  <div key={i} style={{ display: "flex", alignItems: "flex-start", gap: 8, marginBottom: 8 }}>
                    <span style={{ color: COLORS.greenLight, fontSize: 12, marginTop: 1, flexShrink: 0 }}>✓</span>
                    <span style={{ fontSize: 12, color: COLORS.text, lineHeight: 1.4 }}>{f.label}</span>
                  </div>
                ))}
              </div>
              <div style={{ ...cardStyle, borderColor: COLORS.primary, position: "relative" }}>
                <div style={{ position: "absolute", top: -10, left: "50%", transform: "translateX(-50%)", background: COLORS.primary, color: "#000", fontSize: 10, fontWeight: 700, padding: "2px 10px", borderRadius: 20 }}>PREMIUM</div>
                <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.primary, marginBottom: 4, textTransform: "uppercase", letterSpacing: 1 }}>Everything in Free +</div>
                <div style={{ fontSize: 11, color: COLORS.textDim, marginBottom: 12 }}>$3.99/mo · $29.99/yr · $19.99/yr student</div>
                {FREE_FEATURES.filter(f => !f.included).map((f, i) => (
                  <div key={i} style={{ display: "flex", alignItems: "flex-start", gap: 8, marginBottom: 8 }}>
                    <span style={{ color: COLORS.primary, fontSize: 12, marginTop: 1, flexShrink: 0 }}>✦</span>
                    <span style={{ fontSize: 12, color: COLORS.text, lineHeight: 1.4 }}>{f.label}</span>
                  </div>
                ))}
                <div style={{ marginTop: 16, padding: "10px 12px", background: "#1E1A0E", borderRadius: 8, border: `1px solid ${COLORS.primary}33` }}>
                  <div style={{ fontSize: 11, color: COLORS.primary, fontWeight: 600 }}>Best value</div>
                  <div style={{ fontSize: 12, color: COLORS.textMuted, marginTop: 2 }}>Annual plan = ~$2.50/month</div>
                  <div style={{ fontSize: 11, color: COLORS.textDim, marginTop: 2 }}>Student = $1.67/month with .edu</div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* COSTS TAB */}
        {tab === "costs" && (
          <div>
            {/* Sliders */}
            <div style={{ ...cardStyle, marginBottom: 16 }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.textMuted, marginBottom: 16, textTransform: "uppercase", letterSpacing: 1 }}>Adjust User Numbers</div>
              {[
                ["Free Users", freeUsers, setFreeUsers, 100, 10000, COLORS.textMuted],
                ["Paid Monthly ($3.99)", paidMonthly, setPaidMonthly, 0, 1000, COLORS.primary],
                ["Paid Annual ($29.99/yr)", paidAnnual, setPaidAnnual, 0, 1000, COLORS.primaryLight],
                ["Student Annual ($19.99/yr)", paidStudent, setPaidStudent, 0, 500, COLORS.indigoBright],
              ].map(([label, val, setter, min, max, color]) => (
                <div key={label} style={{ marginBottom: 16 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 6 }}>
                    <span style={{ fontSize: 12, color: COLORS.textMuted }}>{label}</span>
                    <span style={{ fontSize: 12, fontWeight: 700, color }}>{val.toLocaleString()}</span>
                  </div>
                  <input type="range" min={min} max={max} value={val} onChange={e => setter(Number(e.target.value))} style={sliderStyle} />
                </div>
              ))}
              <div style={{ display: "flex", justifyContent: "space-between", padding: "10px 12px", background: "#0F1117", borderRadius: 8, marginTop: 4 }}>
                <span style={{ fontSize: 12, color: COLORS.textMuted }}>Total users</span>
                <span style={{ fontSize: 12, fontWeight: 700, color: COLORS.text }}>{totalUsers.toLocaleString()}</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", padding: "6px 12px" }}>
                <span style={{ fontSize: 12, color: COLORS.textMuted }}>Conversion rate</span>
                <span style={{ fontSize: 12, fontWeight: 700, color: conversionRate < 3 ? COLORS.red : conversionRate < 6 ? COLORS.primary : COLORS.greenLight }}>{conversionRate.toFixed(1)}%</span>
              </div>
            </div>

            {/* Cost Breakdown */}
            <div style={{ ...cardStyle, marginBottom: 16 }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.textMuted, marginBottom: 16, textTransform: "uppercase", letterSpacing: 1 }}>Monthly Cost Breakdown</div>
              {[
                ["🤖 Claude AI (Haiku 4.5)", totalAICost, `${totalAICalls.toLocaleString()} calls · $${aiCostPerCall.toFixed(4)}/call`],
                ["🔥 Firestore reads/writes", firestoreCost, `${(totalReads / 1000).toFixed(0)}K reads · ${(totalWrites / 1000).toFixed(0)}K writes`],
                ["📖 API.Bible", apiBibleCost, `${apiBibleCallsMonth.toFixed(0)} calls · 5K free/month`],
                ["⚡ Cloud Functions", functionCost, `${(functionInvocations / 1000).toFixed(0)}K invocations`],
              ].map(([label, cost, sub]) => (
                <div key={label} style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 12, paddingBottom: 12, borderBottom: `1px solid ${COLORS.cardBorder}` }}>
                  <div>
                    <div style={{ fontSize: 13, color: COLORS.text }}>{label}</div>
                    <div style={{ fontSize: 11, color: COLORS.textDim, marginTop: 2 }}>{sub}</div>
                  </div>
                  <div style={{ fontSize: 14, fontWeight: 700, color: COLORS.primary, flexShrink: 0 }}>{formatDollar(cost)}</div>
                </div>
              ))}
              <div style={{ display: "flex", justifyContent: "space-between", paddingTop: 4 }}>
                <span style={{ fontSize: 14, fontWeight: 700, color: COLORS.text }}>Total infra / month</span>
                <span style={{ fontSize: 16, fontWeight: 700, color: COLORS.flame }}>{formatDollar(totalInfraCost)}</span>
              </div>
            </div>

            {/* Per User Cost */}
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 16 }}>
              {statCard("Cost / Free User", formatCents(costPerFreeUser), "per month", COLORS.textMuted)}
              {statCard("Cost / Paid User", formatCents(costPerPaidUser), "per month", COLORS.flame)}
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
              {statCard("Revenue / Paid User", formatDollar(revenuePerPaidUser), "before Apple cut", COLORS.greenLight)}
              {statCard("Net / Paid User", formatDollar(revenuePerPaidUser * (1 - COSTS.appleCutPercent) - costPerPaidUser), "after Apple + infra", margin > 50 ? COLORS.greenLight : margin > 20 ? COLORS.primary : COLORS.red)}
            </div>

            {/* Claude model note */}
            <div style={{ marginTop: 16, padding: "12px 14px", background: COLORS.card, borderRadius: 10, border: `1px solid ${COLORS.cardBorder}` }}>
              <div style={{ fontSize: 12, fontWeight: 600, color: COLORS.primary, marginBottom: 4 }}>💡 Using Claude Haiku 4.5</div>
              <div style={{ fontSize: 11, color: COLORS.textMuted, lineHeight: 1.6 }}>
                At $1.00/$5.00 per million tokens, Haiku 4.5 is the right model for StudyFire's AI features — study questions, sermon debrief, quiz generation. Quality is strong enough for these tasks. Upgrading to Sonnet 4.6 ($3/$15) would triple AI costs with marginal user-facing benefit.
              </div>
            </div>
          </div>
        )}

        {/* SUSTAINABILITY TAB */}
        {tab === "sustainability" && (
          <div>
            {/* Sliders duplicated for context */}
            <div style={{ ...cardStyle, marginBottom: 16 }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.textMuted, marginBottom: 16, textTransform: "uppercase", letterSpacing: 1 }}>Adjust User Numbers</div>
              {[
                ["Free Users", freeUsers, setFreeUsers, 100, 10000, COLORS.textMuted],
                ["Paid Monthly ($3.99)", paidMonthly, setPaidMonthly, 0, 1000, COLORS.primary],
                ["Paid Annual ($29.99/yr)", paidAnnual, setPaidAnnual, 0, 1000, COLORS.primaryLight],
                ["Student Annual ($19.99/yr)", paidStudent, setPaidStudent, 0, 500, COLORS.indigoBright],
              ].map(([label, val, setter, min, max, color]) => (
                <div key={label} style={{ marginBottom: 14 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                    <span style={{ fontSize: 12, color: COLORS.textMuted }}>{label}</span>
                    <span style={{ fontSize: 12, fontWeight: 700, color }}>{val.toLocaleString()}</span>
                  </div>
                  <input type="range" min={min} max={max} value={val} onChange={e => setter(Number(e.target.value))} style={sliderStyle} />
                </div>
              ))}
            </div>

            {/* P&L Summary */}
            <div style={{ ...cardStyle, marginBottom: 16 }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.textMuted, marginBottom: 16, textTransform: "uppercase", letterSpacing: 1 }}>Monthly P&L</div>
              {[
                ["Gross Revenue", monthlyRevenue, COLORS.greenLight],
                ["Apple App Store (15%)", -monthlyRevenue * COSTS.appleCutPercent, COLORS.red],
                ["Net Revenue", afterApple, COLORS.text],
                ["Infrastructure Costs", -totalInfraCost, COLORS.red],
                ["Net Profit / Loss", netRevenueAfterCosts, netRevenueAfterCosts >= 0 ? COLORS.greenLight : COLORS.red],
              ].map(([label, val, color]) => (
                <div key={label} style={{
                  display: "flex", justifyContent: "space-between", padding: "10px 0",
                  borderBottom: label === "Net Profit / Loss" ? "none" : `1px solid ${COLORS.cardBorder}`,
                  fontWeight: label === "Net Profit / Loss" || label === "Net Revenue" ? 700 : 400
                }}>
                  <span style={{ fontSize: 13, color: label === "Net Profit / Loss" ? COLORS.text : COLORS.textMuted }}>{label}</span>
                  <span style={{ fontSize: 14, color, fontWeight: 700 }}>{val >= 0 ? formatDollar(val) : `-${formatDollar(Math.abs(val))}`}</span>
                </div>
              ))}
            </div>

            {/* Key Metrics */}
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 16 }}>
              {statCard("Gross Margin", `${Math.max(0, margin).toFixed(0)}%`, "after Apple + infra", margin > 60 ? COLORS.greenLight : margin > 30 ? COLORS.primary : COLORS.red)}
              {statCard("Conversion Rate", `${conversionRate.toFixed(1)}%`, "free → paid", conversionRate >= 5 ? COLORS.greenLight : conversionRate >= 3 ? COLORS.primary : COLORS.red)}
            </div>

            {/* Break-even */}
            <div style={{ ...cardStyle, marginBottom: 16 }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.textMuted, marginBottom: 12, textTransform: "uppercase", letterSpacing: 1 }}>Sustainability Analysis</div>
              {[
                {
                  label: "Pricing verdict",
                  status: revenuePerPaidUser * (1 - COSTS.appleCutPercent) > costPerPaidUser * 3 ? "✅ Healthy" : "⚠️ Watch closely",
                  detail: `Each paid user generates ${formatDollar(revenuePerPaidUser * (1 - COSTS.appleCutPercent))} net revenue vs ${formatCents(costPerPaidUser)} in infra costs. Strong unit economics.`,
                  good: revenuePerPaidUser * (1 - COSTS.appleCutPercent) > costPerPaidUser * 3,
                },
                {
                  label: "Free user sustainability",
                  status: costPerFreeUser < 0.05 ? "✅ Manageable" : "⚠️ Monitor",
                  detail: `Free users cost ${formatCents(costPerFreeUser)}/month in infra. At scale, aggressive Firestore caching is critical to keep this low.`,
                  good: costPerFreeUser < 0.05,
                },
                {
                  label: "API.Bible call budget",
                  status: apiBibleCallsMonth <= COSTS.apiBibleFreeMonthly * 1.5 ? "✅ Within budget" : "⚠️ Upgrade tier needed",
                  detail: `Estimated ${apiBibleCallsMonth.toFixed(0)} API calls/month. Free tier covers 5,000. Cache aggressively — target 70%+ cache hit rate.`,
                  good: apiBibleCallsMonth <= COSTS.apiBibleFreeMonthly * 1.5,
                },
                {
                  label: "Profitability threshold",
                  status: netRevenueAfterCosts > 0 ? "✅ Profitable" : "⚠️ Not yet profitable",
                  detail: netRevenueAfterCosts > 0
                    ? `You're profitable at this user mix. Scale paid users to grow margin.`
                    : `Need ~${Math.ceil(totalInfraCost / (revenuePerPaidUser * (1 - COSTS.appleCutPercent) - costPerPaidUser))} more paid users to break even.`,
                  good: netRevenueAfterCosts > 0,
                },
              ].map(({ label, status, detail, good }) => (
                <div key={label} style={{ marginBottom: 14, paddingBottom: 14, borderBottom: `1px solid ${COLORS.cardBorder}` }}>
                  <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4 }}>
                    <span style={{ fontSize: 12, fontWeight: 600, color: COLORS.text }}>{label}</span>
                    <span style={{ fontSize: 11, fontWeight: 700, color: good ? COLORS.greenLight : COLORS.primary }}>{status}</span>
                  </div>
                  <div style={{ fontSize: 11, color: COLORS.textMuted, lineHeight: 1.5 }}>{detail}</div>
                </div>
              ))}
            </div>

            {/* Recommendations */}
            <div style={{ padding: "16px", background: "#0D1A14", borderRadius: 12, border: `1px solid ${COLORS.green}44` }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.greenLight, marginBottom: 12 }}>💡 Pricing Recommendations</div>
              {[
                "Pre-load the full Bible (KJV, CSB, NIV) into Firestore at setup — one-time ~$0.17 write cost eliminates API.Bible calls almost entirely. Only keyword search hits the API.",
                "Pre-cache the daily Spark question each morning via a single Cloud Function — cost becomes 1 Claude call per passage per day, not 1 per user. Biggest single cost reduction.",
                "Use Anthropic Batch API (50% cheaper) for nightly pre-generation of quizzes, Word of the Day, and reading plan questions.",
                "Batch all Firestore writes to 1–2 per session end. Free users get no live listeners — pull-to-refresh only. Real-time feeds are Premium-only.",
                "Set a Firebase billing alert at $20/month and a hard cap at $50/month. A bug causing a read loop can turn a $5 month into $500 overnight.",
              ].map((tip, i) => (
                <div key={i} style={{ display: "flex", gap: 10, marginBottom: 10 }}>
                  <span style={{ color: COLORS.greenLight, fontSize: 12, flexShrink: 0, marginTop: 1 }}>→</span>
                  <span style={{ fontSize: 12, color: COLORS.textMuted, lineHeight: 1.5 }}>{tip}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        <div style={{ textAlign: "center", marginTop: 24, fontSize: 11, color: COLORS.textDim }}>
          Estimates based on Claude Haiku 4.5 pricing · Firebase Standard pricing · June 2026
        </div>
      </div>
    </div>
  );
}
