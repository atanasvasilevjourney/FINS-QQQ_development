# BTC Previous Day Breakout EA – Technical Summary

**File:** `BTC_PreviousDayBreakout_EA.mq5`  
**Platform:** MetaTrader 5 (MQL5)  
**Purpose:** Automated Expert Advisor that trades breakouts above the previous bar’s high (buy) or below the previous bar’s low (sell) on a configurable timeframe (default daily). Designed for volatile instruments (e.g. Bitcoin); includes risk management, trailing stop, optional time-based exit, entry visuals, performance panel, and optional funded-account (prop firm) rules.

---

## 1. Strategy Logic (No Repaint)

- **Signal timeframe:** Configurable (`InpTimeframe`, default `PERIOD_D1`). The “previous bar” is always the **last closed bar** on this timeframe (shift 1).
- **Buy:** When **bid** crosses **above** the previous bar’s **high** → open buy (market order).
- **Sell:** When **bid** crosses **below** the previous bar’s **low** → open sell (market order).
- **One trade per bar:** At most one new position per signal bar; tracked via `g_LastOpenBarTime` (bar time when last order was opened). No repaint: signals use only closed-bar high/low and current bid.

---

## 2. File Location and Dependencies

- **Path:** `CRT/MT5 ORB/BTC_PreviousDayBreakout_EA.mq5`
- **Include:** `#include <Trade\Trade.mqh>` (standard MT5 trade library).
- **Chart objects prefix:** `BTCPDB_` (all drawn objects use this so they can be cleaned up safely).

---

## 3. Input Parameters (Groups)

### 3.1 Symbol & Timeframe
| Input             | Type              | Default   | Description |
|-------------------|-------------------|-----------|-------------|
| InpTimeframe      | ENUM_TIMEFRAMES   | PERIOD_D1 | Timeframe for “previous bar” (high/low). Chart can be any TF; EA uses this for signals. |

### 3.2 Risk & Money
| Input             | Type   | Default | Description |
|-------------------|--------|---------|-------------|
| InpLotSize        | double | 0.01    | Fixed lot size when InpUseRiskMoney = false. |
| InpUseRiskMoney   | bool   | true    | If true, lot size is computed from InpRiskMoney and SL distance. |
| InpRiskMoney      | double | 100.0   | Risk per trade in account currency (used when InpUseRiskMoney = true). |

### 3.3 Stop Loss & Take Profit
| Input           | Type   | Default | Description |
|-----------------|--------|---------|-------------|
| InpSLPercent    | double | 2.0     | Stop loss as % of **entry price** (e.g. 2 = 2%). |
| InpTPPercent    | double | 1.0     | Take profit as % of **entry price**. |

SL/TP are set at order placement (buy: SL below entry, TP above; sell: opposite).

### 3.4 Trailing Stop
| Input                 | Type   | Default | Description |
|-----------------------|--------|---------|-------------|
| InpUseTrailingStop    | bool   | true    | Enable trailing stop. |
| InpTSLTriggerPercent | double | 0.5     | Trigger: price must move this % in profit before trailing starts (from open price). |
| InpTSLPercent        | double | 0.25    | Trail distance: new SL is this % behind current price (bid for buy, ask for sell). |

Trailing only **tightens** SL (never moves it against the position). Applied in `ManagePositions()` every tick.

### 3.5 Session
| Input                              | Type | Default | Description |
|------------------------------------|------|---------|-------------|
| InpCloseMinutesBeforeNextCandle   | int  | 30      | Close all EA positions this many **minutes before the next signal-timeframe bar**. 0 = disabled. |

Uses current bar start + period length − this offset; when `TimeCurrent() >= that time`, positions are closed.

### 3.6 Trade Execution
| Input          | Type | Default | Description |
|----------------|------|---------|-------------|
| InpMagic       | int  | 30030   | Magic number for orders/positions. |
| InpSlippagePts | int  | 10      | Max slippage in points. |

### 3.7 Filters & Confluence
| Input               | Type   | Default | Description |
|---------------------|--------|---------|-------------|
| InpMaxSpreadPts     | double | 0       | Max spread (points) to allow new entry. 0 = no filter. |
| InpMinRangePercent  | double | 0       | Min previous bar range (high−low) as % of mid price to allow trade. 0 = no filter. |

### 3.8 Visualization
| Input                 | Type | Default | Description |
|-----------------------|------|---------|-------------|
| InpShowEntryVisuals   | bool | true    | Draw entry level line + arrow after fill; removed when position closes. |
| InpShowPerfTable      | bool | true    | Show performance panel on chart. |
| InpPerfPanelX / Y     | int  | 10, 25  | Panel position (pixels from corner). |

### 3.9 Funded Account (Prop Firm)
| Input                    | Type   | Default   | Description |
|--------------------------|--------|-----------|-------------|
| InpFundedAccount         | bool   | false     | Enable funded-account rules. |
| InpAccountSize           | double | 100000.0  | Account size for % calculations. 0 = use balance at EA start. |
| InpPhase1TargetPct       | double | 10.0      | Phase 1 profit target (%). Informational + print. |
| InpPhase2TargetPct       | double | 5.0       | Phase 2 profit target (%). Informational + print. |
| InpDailyLossLimitPct     | double | 5.0       | Daily loss limit (%) from daily start balance. |
| InpMaxLossLimitPct       | double | 10.0      | Max loss (%) from initial balance. |
| InpMaxDDFromHighPct      | double | 0.0       | Max drawdown (%) from equity high (trailing). 0 = off. |
| InpMinTradingDays        | int    | 0         | Min trading days (0 = not enforced; only counted). |
| InpPhase1Complete        | bool   | false     | Manual: set true when Phase 1 passed (for Phase 2 target). |

When limits are breached, **no new orders** are placed; existing positions are still managed (trailing, time close).

---

## 4. Global State

- **Trade / bar:** `g_Trade` (CTrade), `g_LastOpenBarTime`, `g_LastBarTime`.
- **Performance (from history):** `g_TotalTrades`, `g_Wins`, `g_TotalProfit`, `g_GrossProfit`, `g_GrossLoss`, `g_DailyPL`.
- **Funded account:** `g_InitialBalance`, `g_DailyStartBalance`, `g_HighestEquity`, `g_LastDayTime`, `g_DailyLimitBreached`, `g_MaxLimitBreached`, `g_Phase1Complete`, `g_TradingDaysCount`.
- **Object prefix:** `g_Prefix = "BTCPDB_"`.

---

## 5. Execution Flow

### 5.1 OnInit()
- Set magic, slippage, filling mode.
- Reset `g_LastOpenBarTime`, `g_LastBarTime`.
- `ValidateInputs()` → return `INIT_PARAMETERS_INCORRECT` if invalid.
- If `InpFundedAccount`: init `g_InitialBalance` (from InpAccountSize or balance), `g_DailyStartBalance`, `g_HighestEquity`, `g_Phase1Complete`, breach flags, `g_LastDayTime`, `g_TradingDaysCount`.
- `LoadPerformanceFromHistory()` (deals with DEAL_ENTRY_OUT, this magic/symbol).
- If `InpShowPerfTable`, `CreatePerfPanel()`.

### 5.2 OnTick()
1. Update `g_LastBarTime` from current bar time (signal TF).
2. **If funded:** `IsNewDay()` → `ResetDailyFundedTracking()`. Then `CheckFundedLimits()`. If `g_DailyLimitBreached` or `g_MaxLimitBreached`: run `ManagePositions()`, update panel, return (no new entries).
3. `ManagePositions()`: for each position (this symbol, this magic): apply “close before next candle” if enabled; apply trailing stop (trigger % then trail %).
4. If `HasOpenPosition()`: update panel, return (no new entries).
5. If funded and `!CanPlaceNewOrder()`: update panel, return.
6. `GetPreviousBarLevels(prevHigh, prevLow, rangePct)` from **shift 1** (last closed bar). If `InpMinRangePercent` > 0, check `IsRangeOk(rangePct)`. Check `IsSpreadOk()`.
7. **Buy:** if `bid > prevHigh` and `!AlreadyTradedThisBar()` → `OpenBuy(prevHigh, barTime)` then `MarkBarAsTraded()`.
8. **Sell:** if `bid < prevLow` and `!AlreadyTradedThisBar()` → `OpenSell(prevLow, barTime)` then `MarkBarAsTraded()`.
9. Update performance panel if enabled.

### 5.3 OnTradeTransaction()
- Only processes `TRADE_TRANSACTION_DEAL_ADD` with `DEAL_ENTRY_OUT` (position close), this magic and symbol.
- `DeleteEntryVisualsForPosition(DEAL_POSITION_ID)` → remove chart objects for that position (reset visual after close).
- Update performance stats: `g_TotalTrades`, `g_TotalProfit`, `g_Wins`, `g_GrossProfit`, `g_GrossLoss`, and today’s P/L; then `UpdatePerfPanel()` if enabled.

### 5.4 OnDeinit()
- `DeleteAllEntryVisuals()`, delete perf panel object, `ChartRedraw(0)`.

---

## 6. Key Functions (Index)

| Function | Purpose |
|----------|---------|
| `ValidateInputs()` | Check all input ranges; funded params when InpFundedAccount = true. |
| `IsNewDay()` | True when calendar day changes; updates `g_LastDayTime`. |
| `CheckFundedLimits()` | Update `g_HighestEquity`; set daily/max/trailing DD breach flags; print phase targets when reached. |
| `ResetDailyFundedTracking()` | On new day: set `g_DailyStartBalance`, clear daily breach, optionally count trading days. |
| `CanPlaceNewOrder()` | False if funded and (daily breach \| max loss breach \| trailing DD breach). |
| `LoadPerformanceFromHistory()` | Scan history for exit deals (this magic/symbol), fill g_TotalTrades, g_Wins, g_TotalProfit, g_GrossProfit, g_GrossLoss, g_DailyPL. |
| `GetPreviousBarLevels(prevHigh, prevLow, rangePct)` | iHigh/iLow shift 1; rangePct = 100*(high−low)/mid. Returns false if invalid. |
| `AlreadyTradedThisBar()` | True if `g_LastOpenBarTime == iTime(..., 0)` and ≠ 0 (one trade per bar). |
| `MarkBarAsTraded()` | Set `g_LastOpenBarTime = iTime(..., 0)`. |
| `CalculateLots(entry, sl)` | If InpUseRiskMoney: lots = InpRiskMoney / (SL distance in ticks × tick value); else InpLotSize. |
| `NormalizeLots(lots)` | Clamp to symbol min/max/step. |
| `IsSpreadOk()` | True if InpMaxSpreadPts ≤ 0 or current spread ≤ InpMaxSpreadPts. |
| `IsRangeOk(rangePct)` | True if InpMinRangePercent ≤ 0 or rangePct ≥ InpMinRangePercent. |
| `OpenBuy(prevHigh, barTime)` | Compute SL/TP %, lots; g_Trade.Buy(); draw entry visuals for new position; MarkBarAsTraded(). |
| `OpenSell(prevLow, barTime)` | Same for sell. |
| `GetLastOpenedPositionId()` | First position with this symbol+magic; return POSITION_IDENTIFIER. |
| `ManagePositions()` | Close before next candle if time reached; trailing stop (trigger then trail %). |
| `HasOpenPosition()` | True if any position this symbol+magic. |
| `DrawEntryVisuals(posId, barTime, level1, level2, isBuy)` | Draw trend line(s) and arrow at level1 (prefix `BTCPDB_ENT_` + posId). |
| `DeleteEntryVisualsForPosition(posId)` | Delete objects `..._L1`, `..._L2`, `..._ARR` for that posId. |
| `DeleteAllEntryVisuals()` | Delete all objects whose name starts with `BTCPDB_ENT_`. |
| `CreatePerfPanel()` | Create label object for performance text if not exists. |
| `UpdatePerfPanel()` | Recompute daily P/L from history; format Trades, Win%, PF, Total P/L, Daily P/L; set label text. |

---

## 7. Funded Account Rules (When Enabled)

- **Daily loss:** From `g_DailyStartBalance` (reset each calendar day). If (daily loss / daily start) ≥ `InpDailyLossLimitPct` → `g_DailyLimitBreached = true` → no new trades until next day.
- **Max loss:** From `g_InitialBalance`. If (initial − equity) / initial ≥ `InpMaxLossLimitPct` → `g_MaxLimitBreached = true` → no new trades for rest of run.
- **Trailing DD:** If `InpMaxDDFromHighPct` > 0 and (g_HighestEquity − equity) / g_HighestEquity ≥ that % → same as max loss (no new orders).
- **Phase 1/2:** Only logged when profit % crosses targets; `InpPhase1Complete` is manual for “Phase 1 passed” (Phase 2 target = Phase1 + Phase2 %).

---

## 8. Visualization and No-Repaint

- **Entry visuals:** Drawn **only after** a position is opened (in `OpenBuy`/`OpenSell`), using the breakout level and bar time. Objects are named `BTCPDB_ENT_<positionId>_L1`, `_L2`, `_ARR`. No repaint: nothing is drawn on “potential” signal.
- **Reset on close:** `OnTradeTransaction` (DEAL_ENTRY_OUT) calls `DeleteEntryVisualsForPosition(DEAL_POSITION_ID)` so visuals are removed when the trade closes.
- **Performance panel:** Built from **closed** history deals only (DEAL_ENTRY_OUT). Daily P/L is recomputed in `UpdatePerfPanel()` from today’s deals.

---

## 9. Backtest / Live Usage

- **Chart:** Any symbol (e.g. BTCUSD); chart timeframe can be any (e.g. H1); EA uses `InpTimeframe` for the “previous bar”.
- **Strategy Tester:** “Every tick” or “1 minute OHLC”; symbol and server time aligned with broker.
- **Live:** Attach to chart; ensure magic is unique if multiple EAs run. For funded accounts set `InpFundedAccount = true` and match your provider’s % (daily loss, max loss, trailing DD, phase targets).

---

## 10. Version and Maintenance

- **Version in code:** 1.00.
- **Copyright:** BTC Previous Day Breakout.
- Changing logic: preserve one-trade-per-bar (`g_LastOpenBarTime`), closed-bar-only levels (shift 1), and “visuals only after fill + delete on close” to keep no-repaint and clear behaviour across machines.

This document is the single source of truth for the EA’s design and behaviour when moving the project (e.g. git push to another computer) so an AI or developer can understand and extend it without reading the full source first.
