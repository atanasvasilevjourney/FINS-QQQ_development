# Go Long Strategy – Summary

## 1. Overview

- **Name:** Go Long (Goong EA)
- **Type:** Daily long-only index CFD strategy
- **Main instrument:** US30 (Dow Jones Industrial Average)
- **Idea:** Replicate long-term index performance by going long each day and closing before the end of the day to avoid swap, paying only spread. Use a low-spread broker so that cost is manageable.

---

## 2. Why Not Buy-and-Hold on CFD?

- **Swap:** Holding US30 overnight costs about **$7.65 per contract per day** (broker-dependent).
- **Rough math:** ~300 days/year × $7.65 ≈ **$2,300/year** per contract; over 10 years ≈ **$22,000**.
- **Conclusion:** Swap alone can erase all profits; buy-and-hold on CFD is not viable.
- **Spread** is typically smaller than swap, so the approach is: **trade intraday only** (open and close the same day) and pay spread instead of swap.

---

## 3. How the Strategy Works

1. **Open:** Open a **long** position at a fixed time after the session start (e.g. **1:05 AM**).
2. **Hold:** Keep the position for the whole day (no overnight).
3. **Close:** Close at a fixed time before session end (e.g. **22:00 or 22:50**), so no overnight = **no swap**.
4. **Cost:** Only the **spread** on open (and possibly on close) is paid.

Result: You capture most of the daily move of the index while avoiding swap; performance is similar to the index over time but with spread drag and no compounding in the basic version.

---

## 4. Broker and Spread

- Strategy **depends on low spread**; high-spread brokers make it unprofitable.
- **IC Markets / IC Trading** (or similar) is used as reference:
  - **Morning (e.g. 1:05):** ~**120 points** (1.2 index points) for US30
  - **European hours:** ~110 points (1.1 index points)
  - **US hours:** ~50 points (0.5 index points)
- **Dukascopy** (or similar) data often shows **400–550 points** in the morning → not suitable for this strategy; backtests should use **realistic low spread** (e.g. 120 points) for the open time.
- **S&P 500** was tested; spread was too high for this approach. **German index, US tech index**, etc. can be tested separately.

---

## 5. Expert Advisor (EA) Inputs and Logic

### 5.1 Main inputs

| Input            | Example / note |
|------------------|----------------|
| Base money       | Account size for simulation, e.g. **50,000** |
| Start time       | **1:00 AM + 5 min** (1:05) – trading allowed only after 1:00 |
| Close time       | **22:00 or 22:50** (Tick Data Suite data ends at 23:00) |
| Risk / position  | Optional: TP/SL; author uses **no TP, no SL** |
| Wait new high    | Optional filter (see below) |

### 5.2 Position sizing (as in video)

- **Risk:** Sized as if risking **100% of account** per trade (no SL in the classic version).
- **Formula (conceptual):**  
  `Lots ≈ Base money / Index price`  
  Example: 50,000 / 40,000 ≈ **1.25 lots**.
- **Rationale:** US30 falling to zero in one day is treated as unrealistic, so the author is comfortable with “100% risk” and no stop for this specific system. **You can change risk, add TP/SL, or reduce size**; the strategy summary does not recommend any specific risk level.

### 5.3 Optional: “Wait for new high”

- **Input:** “Wait new high” (e.g. true/false).
- **Logic:** Open **only when price makes a new high for that day**; then hold until the same end-of-day close time.
- **Use with later start:** e.g. start at **9:05 AM** (not 1:05), then wait for the first new high of the day.
- **Effect:**
  - **Fewer trades:** Many days no trade (save spread; avoid bad days).
  - **COVID-style crash days:** Whole day negative → often no new high → no trade → **large drawdowns avoided**.
  - **Trade-off:** Some days you miss part of the move (later entry or no trade).
- **Backtest (2013–2024):** “Wait new high” reduced impact of the worst COVID days but underperformed in long sideways periods compared to the simple daily open.

---

## 6. Backtesting Setup (Realistic)

- **Spread:** For open at 1:05, use **120 points** (1.2 index points) in the backtester if your broker offers similar conditions; optionally **130 points** for slippage.
- **Data:** Custom symbol or modified spread so backtest spread matches broker (e.g. 120 pts) instead of default Dukascopy-style high spread.
- **Slippage:** Low expected at 1:05 AM; strategy does not rely on fast execution.

---

## 7. Backtest Results (From Video, 2013–2024)

- **Simple version (daily open 1:05, close end of day):**
  - With **high spread** (e.g. Dukascopy): Equity follows index but **sideways periods hurt** (spread cost).
  - With **120-point spread**: **Clearly better**; curve closer to index, though EA does not fully match index (no compounding, spread and costs).
- **“Wait new high” + start 9:05:**
  - **COVID crash:** Very small impact (many bad days skipped).
  - **Long sideways period:** Recently underperformed vs simple daily open.
- **Conclusion:** All variants have trade-offs; choice depends on preference (simplicity vs drawdown control).

---

## 8. Why Use CFDs Instead of an Index ETF?

- **Leverage:** Same capital can control larger notional (e.g. 50k account, multiple lots).
- **Capital efficiency:** Can run **several strategies or instruments** (e.g. Go Long on several indices, or mix with other EAs) with the same account; ETF would tie full capital in one product.
- **Cost:** CFD has swap (avoided here) and spread; ETF has no swap and usually lower implicit cost. So CFD version will not match ETF return 1:1, but offers flexibility and leverage.

---

## 9. Possible Extensions (Mentioned in Video)

- **Market timing:** Enable the EA only after a **setback** in index markets.
- **Trend filter:** Trade only when price is **above a moving average** (or similar).
- **Other instruments:** Apply same logic to **German index, US tech index**, etc., with broker-specific spread checks.

---

## 10. Disclaimer and Availability

- **EA:** Free for users of the video author’s partner broker; direct download and details on the author’s website.
- **Responsibility:** Only risk capital you can afford to lose; adjust risk, TP/SL, and position size to your own rules. This summary is for education only, not advice.

---

## 11. One-Sentence Summary

**Go Long:** Open a long US30 (or similar index) CFD at a fixed time each day (e.g. 1:05), close before the end of the session to avoid swap; pay only spread by using a low-spread broker; optionally reduce bad days by opening only after a “new high” that day.
