# Keltner Channel EA – Detailed Summary (for Git / AI / Other Machines)

This document is the single source of truth for understanding, deploying, and modifying the **KeltnerChannel_EA** MetaTrader 5 Expert Advisor. Use it when pushing to git, moving to another computer, or when an AI needs to learn the bot.

---

## 1. File and Environment

| Item | Value |
|------|--------|
| **Main file** | `KeltnerChannel_EA.mq5` |
| **Location** | `CRT/MT5 ORB/` (relative to repo root) |
| **Platform** | MetaTrader 5 (MQL5) |
| **Version** | 1.10 |
| **Dependencies** | Standard library: `#include <Trade\Trade.mqh>`. Built-in indicator: **FreeIndicators\Keltner Channel.ex5** (must exist under `MQL5/Indicators/`). |

**On a new computer:** Copy `KeltnerChannel_EA.mq5` into `MQL5/Experts/` (or your Experts folder). Ensure MT5 has the default **FreeIndicators** folder with **Keltner Channel.ex5**. If the indicator path differs, change the `#define KC_PATH` at the top of the EA (e.g. `"FreeIndicators\\Keltner Channel.ex5"`).

---

## 2. Purpose and Strategy Type

- **Purpose:** Automated **mean reversion** (and optional breakout) trading using the **Keltner Channel** indicator. Trades only on **closed bar** data to avoid repainting.
- **Logic:** Price interaction with upper/middle/lower Keltner bands on the chosen timeframe; two strategy modes (see below). Optional trend filter using the middle line slope. Optional **Prop Firm Guard** layer for challenge/funded rules.

---

## 3. Indicator and Buffers

- **Indicator:** `iCustom(_Symbol, InpTimeframe, KC_PATH, InpKcEmaPeriod, InpKcAtrPeriod, InpKcAtrMultiplier, false)`.
- **Path:** `KC_PATH` = `"FreeIndicators\\Keltner Channel.ex5"` (relative to `MQL5/Indicators/`).
- **Buffers (order matters):**
  - **Buffer 0** = Upper Keltner line  
  - **Buffer 1** = Middle (EMA)  
  - **Buffer 2** = Lower Keltner line  
- **Data used:** Only **closed bars**. The EA copies from bar index **1** (last closed) and **2** (previous closed). No current bar (index 0) is used for signals → **no repaint**.

---

## 4. Strategy Modes (Enum: `ENUM_KC_STRATEGY`)

### 4.1 `KC_IMMEDIATE` (0) – Breakout / immediate

- **Buy:** Last closed bar’s close **below** lower band, and previous bar’s close **above** lower band (price just broke below). Optional: middle line rising (`kMid1 > kMid2`) if trend filter on.
- **Sell:** Last closed bar’s close **above** upper band, and previous bar’s close **below** upper band (price just broke above). Optional: middle line falling if trend filter on.

### 4.2 `KC_REENTRY` (1) – Mean reversion / re-entry (default)

- **Buy:** Last closed bar’s close **above** lower band, and previous bar’s close **below** lower band (price was outside, now back inside from below). Optional: middle rising if trend filter on.
- **Sell:** Last closed bar’s close **below** upper band, and previous bar’s close **above** upper band (price was outside, now back inside from above). Optional: middle falling if trend filter on.

**Trend filter (`InpUseTrendFilter`):** When true, buy only if `kMid1 > kMid2`, sell only if `kMid1 < kMid2`.

---

## 5. Input Parameters (Complete List)

### Symbol & Timeframe
- **InpTimeframe** – Timeframe for Keltner and signals (default H1).

### Keltner Channel
- **InpKcEmaPeriod** – EMA period (default 20).  
- **InpKcAtrPeriod** – ATR period (default 10).  
- **InpKcAtrMultiplier** – ATR multiplier (default 2.0).

### Strategy
- **InpStrategy** – `KC_IMMEDIATE` or `KC_REENTRY`.  
- **InpUseTrendFilter** – Use middle line slope as filter (default false).

### Risk & Money
- **InpLotSize** – Fixed lot size when not using risk %.  
- **InpUseRiskPct** – If true, lot size from risk % and SL distance.  
- **InpRiskPct** – Risk per trade as % of balance (used when InpUseRiskPct = true).  
- **InpSlPoints** – Stop loss in points.  
- **InpTpPoints** – Take profit in points.

### Trade Execution
- **InpMagic** – Magic number for this EA (default 20020).  
- **InpSlippagePoints** – Slippage in points.  
- **InpMaxSpreadPoints** – Max spread to allow new orders (0 = disabled).  
- **InpMaxPositions** – Max concurrent open positions (default 1).

### Visualization
- **InpShowEntryMarks** – Draw entry arrows on chart (removed when position closes).  
- **InpShowPerfTable** – Show performance label (trades, W/L, Win%, P/L).

### Prop Firm Guard
- **InpPropFirmGuard** – Enable/disable prop firm rules (default false).  
- **InpChallengeSize** – Account size for % calculations ($). 0 = use balance at EA start.  
- **InpPhase1TargetPct** – Phase 1 profit target (%).  
- **InpPhase2TargetPct** – Phase 2 profit target (%).  
- **InpDailyLossLimitPct** – Daily loss limit (%; breach = no new trades that day).  
- **InpMaxLossLimitPct** – Max loss from initial balance (%; breach = no new trades ever).  
- **InpMaxDDFromHighPct** – Trailing max drawdown from equity high (%). 0 = off.  
- **InpMinTradingDays** – Min trading days (0 = not enforced).  
- **InpPhase1Complete** – Manual flag: Phase 1 passed (for Phase 2).  
- **InpMaxDailyRiskPct** – Self-imposed max daily loss %; block new trades when reached (0 = off). E.g. 1.5 for “riskier but under 5% DD”.  
- **InpMaxTradesPerDay** – Max new positions per calendar day (0 = no limit). Resets at midnight; on EA start, today’s count is loaded from history.

---

## 6. Global State Variables

- **g_handleKc** – Handle of the Keltner indicator.  
- **g_lastBarTime** – Time of last processed bar (for `IsNewBar()`).  
- **g_trade** – `CTrade` instance for order execution.  
- **g_objPrefix** – `"KC_"` for chart object names.  
- **g_totalTrades, g_wins, g_losses, g_totalProfit** – Performance stats (updated only on position close).  
- **g_initialBalance, g_dailyStartBalance, g_highestEquity** – Prop Firm: initial and daily start balance; highest equity for trailing DD.  
- **g_lastDayTime** – Last processed calendar day (for `IsNewDay()`).  
- **g_tradingDaysCount** – Number of trading days (incremented on new day when positions/orders exist).  
- **g_dailyLimitBreached, g_maxLimitBreached, g_phase1Complete** – Prop Firm breach and phase flags.  
- **g_tradesOpenedToday** – Number of positions opened today (for InpMaxTradesPerDay); reset each midnight; on init set from history.

---

## 7. Execution Flow

### OnInit
1. Configure `CTrade` (magic, slippage, filling).  
2. Create Keltner handle via `iCustom`; on failure return `INIT_FAILED`.  
3. If Prop Firm Guard enabled: set initial/daily balance, highest equity, phase flag, and `g_tradesOpenedToday` from `CountTradesOpenedToday()`.  
4. Load performance stats from history (`LoadPerformanceFromHistory`).  
5. If enabled, draw performance table.

### OnTick
1. If Prop Firm Guard on: run `PropFirmCheckLimits()`; if new day run `PropFirmResetDaily()`; if daily or max limit breached, return (no new signals).  
2. If not a new bar (`!IsNewBar()`), return → **signals only on first tick of new bar** (no repaint).  
3. Read Keltner buffers (closed bars 1 and 2).  
4. Get close1, close2 and band values at indices 0 and 1 of the copied arrays.  
5. If spread too high, max positions reached, or `!PropFirmCanOpen()`, return.  
6. If `SignalBuy(...)` then `OpenBuy(barTime)` and return.  
7. If `SignalSell(...)` then `OpenSell(barTime)`.

### OnTradeTransaction
- On `TRADE_TRANSACTION_DEAL_ADD`: if deal is close (DEAL_ENTRY_OUT) for this magic, delete entry visual for that position ID, update performance stats, refresh performance table.

### OnDeinit
- Release indicator handle, delete all objects with name starting `KC_ENT_`, clear chart comment.

---

## 8. Key Functions (Short Reference)

| Function | Role |
|----------|------|
| **IsNewBar()** | True only on first tick of a new bar (uses `iTime(..., 0)` vs `g_lastBarTime`). |
| **IsNewDay()** | True when calendar day changes (for daily reset). |
| **GetKeltnerValues** | CopyBuffer for buffers 0,1,2 from bar 1, count 3; arrays as series. |
| **SignalBuy / SignalSell** | Implement KC_IMMEDIATE vs KC_REENTRY and optional trend filter. |
| **GetLotSize(entry, sl)** | Fixed lot or risk% from balance and SL distance (tick value/size). |
| **PropFirmCheckLimits** | Update daily/max/trailing DD breach and phase targets; print messages. |
| **PropFirmResetDaily** | On new day: update daily start balance, reset daily breach and `g_tradesOpenedToday`. |
| **PropFirmCanOpen** | False if Guard off or any breach; also checks InpMaxDailyRiskPct and InpMaxTradesPerDay. |
| **CountTradesOpenedToday** | History deals today with DEAL_ENTRY_IN, same symbol and magic. |
| **OpenBuy / OpenSell** | Check PropFirmCanOpen, compute SL/TP in points, get lot size, send market order; on success increment `g_tradesOpenedToday` and draw entry mark. |
| **DrawEntryMark(positionId, barTime, price, isBuy)** | Create OBJ_ARROW with name `KC_ENT_<positionId>` at bar time and price; green up for buy, red down for sell. |
| **DeleteEntryVisualsForPosition(positionId)** | Delete object `KC_ENT_<positionId>` (called when position closes). |
| **UpdatePerformanceTable** | Create/update label with trades, W, L, Win%, P/L. |
| **LoadPerformanceFromHistory** | Scan history for DEAL_ENTRY_OUT with this magic; fill g_totalTrades, g_wins, g_losses, g_totalProfit. |

---

## 9. Visualization and No-Repaint

- **Entry markers:** One arrow per position, at the **signal bar’s time** and entry price. Name: `KC_ENT_<positionId>`. Removed in `OnTradeTransaction` when that position is closed (visual reset after each closed trade).  
- **Performance table:** One label `KC_PerfTable` in top-left. Updated only when a position closes (and on init from history). No repaint: no change on every tick.  
- **Deletion:** `DeleteAllKeltnerObjects()` deletes only objects whose name starts with `KC_ENT_` (keeps table label intact until OnDeinit).

---

## 10. Prop Firm Guard (Smart Layer)

When **InpPropFirmGuard** is true:

- **Daily loss:** From `g_dailyStartBalance`. If equity loss ≥ `InpDailyLossLimitPct`, set `g_dailyLimitBreached`; no new trades until next day (reset in `PropFirmResetDaily`).  
- **Max loss:** From `g_initialBalance`. If loss ≥ `InpMaxLossLimitPct`, set `g_maxLimitBreached`; no new trades for rest of run.  
- **Trailing DD:** If `InpMaxDDFromHighPct` > 0, from `g_highestEquity`. If drawdown ≥ that %, set `g_maxLimitBreached`.  
- **Max daily risk (optional):** If `InpMaxDailyRiskPct` > 0, block new trades when today’s loss (from `g_dailyStartBalance`) ≥ that %.  
- **Max trades per day:** If `InpMaxTradesPerDay` > 0, block when `g_tradesOpenedToday >= InpMaxTradesPerDay` (reset at midnight; on init, `g_tradesOpenedToday` = `CountTradesOpenedToday()`).  
- **Phase targets:** Informational only; Phase 1 and Phase 2 messages printed when profit % crosses thresholds. `InpPhase1Complete` is manual for “Phase 2” display.

---

## 11. Related Files in Same Folder

- **PROPFIRM_STABILITY_2MONTH_GUIDE.md** – How to complete Stability-style challenges in ~2 months with drawdown under 5%; suggests EA settings (risk %, daily cap, max trades per day).  
- **GO_LONG_STRATEGY_SUMMARY.md** – Summary of a different EA (Go Long index strategy); not part of Keltner EA.

---

## 12. Quick Setup on Another Computer

1. Copy `KeltnerChannel_EA.mq5` to `MQL5/Experts/` (or compile in MetaEditor and ensure output is in Experts).  
2. Confirm **Keltner Channel.ex5** exists under `MQL5/Indicators/FreeIndicators/`. If not, install MT5 update or adjust `KC_PATH` in the EA.  
3. Attach EA to a chart; set symbol, timeframe, and inputs. For prop firm: set **InpPropFirmGuard** = true and fill challenge size, daily/max DD %, phase targets, and optionally **InpMaxDailyRiskPct**, **InpMaxTradesPerDay**.  
4. Backtest: Strategy Tester, “Every tick” or “1 minute OHLC”, symbol and timeframe matching EA.

---

## 13. One-Sentence Summary

**KeltnerChannel_EA** is an MQL5 Expert Advisor that trades Keltner Channel mean reversion or breakout (two modes) on closed bars only, with optional trend filter, risk % or fixed lot, optional Prop Firm Guard (daily/max/trailing DD, phase targets, max daily risk %, max trades per day), entry arrows removed when the trade closes, and a no-repaint performance table.
