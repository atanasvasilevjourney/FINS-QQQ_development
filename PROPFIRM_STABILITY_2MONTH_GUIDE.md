# Prop Firm Stability (PF 1.8 / 2.0) – Complete in 2 Months with Drawdown Under 5%

Research-based guide: **riskier risk %** while **keeping drawdown under 5%** and finishing the challenge in **~2 months**.

---

## 1. What “Stability PF 1.8 / 2.0” Usually Means

- **Stability** = evaluation program focused on **consistency** (profits spread over many days, not one big day).
- **PF 1.8 / 2.0** = often **Profit Factor** (gross profit ÷ gross loss) target, e.g. ≥ 1.8 or ≥ 2.0, or a program tier name. Rules vary by firm; typical pattern:
  - **Phase 1:** e.g. **8%** profit target, **5%** daily loss limit, **10%** max drawdown (some firms use **5%** max DD).
  - **Phase 2:** e.g. **5%** profit target, same or similar DD rules.
  - **Minimum trading days:** often **5–10 days** per phase (no “one-day wonder”).
  - **Consistency rule:** e.g. no single day > 30–50% of total profit.

---

## 2. The Math: Why Drawdown Stays Under 5%

### 2.1 Risk per trade vs survival

Approximate **consecutive losses** before hitting a **5%** or **10%** drawdown (from research/simulations):

| Risk per trade | ~5% DD breach      | ~10% DD breach   |
|----------------|--------------------|------------------|
| **2.0%**       | ~2–3 losses        | ~5 losses        |
| **1.0%**       | ~5–6 losses        | ~10 losses       |
| **0.5%**       | ~10+ losses        | 20+ losses       |
| **0.25%**      | 20+ losses         | 40+ losses       |

So:
- To **keep drawdown under 5%**: use **0.25–0.5%** per trade (professional standard).
- If you want **“riskier”** but still **under 5% DD**: use **0.5–0.75%** per trade and **strict daily cap** (e.g. stop after 1–1.5% loss in a day).

### 2.2 Daily loss limit (usually 5%)

- Rule: **one instant breach = fail**. So your **real “capital at risk” per day** = 5% of account.
- Safe habit: **stop trading when daily loss reaches ~4%** (leave 1% buffer for spikes/slippage).
- “Riskier” approach: you can use **higher risk per trade** (e.g. 0.75%) but **cap total daily risk** (e.g. 1.5% max loss per day = 2 trades of 0.75%, then stop).

---

## 3. Strategy to Complete in 2 Months (Drawdown Under 5%)

### 3.1 Targets and timeline

- **Phase 1:** 8% in ~4–5 weeks (e.g. 15–20 trading days).
- **Phase 2:** 5% in ~2–3 weeks (e.g. 8–12 trading days).
- **Total:** ~25–35 trading days over 2 months.

Steady pace beats aggression: research suggests **~$400–500/day equivalent** on a $100k account (0.4–0.5% per day) has much higher pass rate than trying to do 2%+ per day.

### 3.2 Risk settings: “Riskier” but DD under 5%

**Option A – Conservative (safest, DD well under 5%)**

- **Risk per trade:** 0.25–0.5%.
- **Max trades per day:** 2–3.
- **Daily loss cap (self-imposed):** 1% (stop if day’s loss ≥ 1%).
- **Prop Firm Guard:** Daily limit 5%, Max DD 10% (or 5% if your firm uses 5%).

**Option B – “Riskier” but still under 5% DD**

- **Risk per trade:** 0.5–0.75% (max 1% only if you have strong edge and discipline).
- **Max trades per day:** 2–3 (strict).
- **Daily loss cap (self-imposed):** 1.5% (stop when day’s loss ≥ 1.5%).
- **Circuit breaker:** If equity drops **3% from today’s high** (or from high-water mark), **halve risk** for the rest of the day and/or next day.
- **Two-loss rule:** After **2 consecutive losses in one day**, stop trading that day.

This keeps **realized drawdown under 5%** while allowing slightly larger position size.

### 3.3 Phase-by-phase (2 months)

- **Days 1–5:** 0.25% risk, 0.5% daily cap. Only A+ setups. Goal: small positive, no breach.
- **Days 6–20:** 0.25–0.5% risk, 1% daily cap, 2–3 trades/day. Goal: reach Phase 1 target (8%).
- **Phase 2 (next ~2–3 weeks):** Same or 0.5% risk, 1.5% daily cap. Goal: 5% without touching daily/max DD.

When **within 1–2% of profit target**: reduce risk (e.g. halve) and avoid new big positions; protect the pass.

---

## 4. Consistency Rule (Profit Factor / Best Day)

- Many firms require **no single day** to be more than **30–50%** of total profit.
- Implication: **spread trades over many days**; avoid “one big day” that dominates.
- **PF 1.8 / 2.0:** If it’s a **Profit Factor** rule, keep **gross profit / gross loss ≥ 1.8 (or 2.0)**. That comes from edge + risk control, not from one huge win.

---

## 5. EA / Prop Firm Guard Settings (Stability 2-Month)

Use your **KeltnerChannel_EA** (or any EA) with **Prop Firm Guard** set to match your firm:

| Parameter            | Suggested (Stability, 2 months) |
|----------------------|----------------------------------|
| **Challenge size**   | Your account size (e.g. 100000) or 0 = use balance at start |
| **Phase 1 target**   | 8%                               |
| **Phase 2 target**   | 5%                               |
| **Daily loss limit** | 5%                               |
| **Max loss (initial)** | 10% (or 5% if firm rule is 5%) |
| **Max DD from high** | 10% trailing (or 5% if firm uses 5%) |
| **Risk per trade**   | 0.5% (“riskier”) or 0.25–0.35% (safer) |
| **Max positions**    | 1 (or 2 if you cap daily risk yourself) |

Enable **Prop Firm Guard** so the EA **blocks new trades** when:
- Daily loss ≥ 5%, or  
- Max loss / trailing DD is hit.

**In KeltnerChannel_EA:**  
- **InpMaxDailyRiskPct** = 1.5 → EA blocks new trades when today’s loss ≥ 1.5% (keeps DD under 5% with riskier per-trade size).  
- **InpMaxTradesPerDay** = 3 → max 3 new positions per day (Stability consistency).  
- **InpUseRiskPct** = true, **InpRiskPct** = 0.5 or 0.75 for “riskier” but controlled.

---

## 6. Summary: Riskier % vs Drawdown Under 5%

- **Under 5% DD:**  
  - **Per trade:** 0.25–0.5% (safe); 0.5–0.75% (riskier, with strict daily cap).  
  - **Per day:** Stop after 1–1.5% loss (never rely on using the full 5% daily limit).
- **Complete in 2 months:**  
  - ~25–35 trading days, 0.4–0.5% average daily return, Phase 1 then Phase 2.  
  - Use Prop Firm Guard (5% daily, 10% or 5% max DD, 8%+5% targets) and optional daily risk cap in the EA.
- **Consistency / PF 1.8–2.0:**  
  - Many trading days; no single day >> 30–50% of total profit; maintain profit factor ≥ 1.8 (or 2.0) if required.

Apply this with the Keltner (or any) strategy and your Prop Firm Guard so you can complete the Stability challenge in 2 months with drawdown under 5%.
