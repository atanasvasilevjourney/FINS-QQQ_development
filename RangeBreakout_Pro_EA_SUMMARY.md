# RangeBreakout_Pro_EA – Detailed Summary for AI & Developers

This document describes **RangeBreakout_Pro_EA.mq5** so that an AI or developer can understand, modify, and run it on another machine after a git pull. All times are in **server time** (broker/MT5 server).

---

## 1. What This EA Does (Strategy)

- **Range:** Each day, the EA defines a “range” as the **highest high** and **lowest low** of **M1 (1-minute) bars** between two fixed times: **RangeStart** (e.g. 03:00) and **RangeEnd** (e.g. 06:00).
- **No repaint:** The range is computed **only after** `RangeEnd` has passed, using **fully closed** M1 bars. It is never recalculated for that day; levels are fixed.
- **Entries:**
  - **Pending mode (default):** After the range is set, the EA places a **Buy Stop** at the range high and a **Sell Stop** at the range low. SL is the opposite side of the range (buy SL = range low, sell SL = range high). Optional TP.
  - **Market mode:** If `UsePendingOrders = false`, it opens market buy when price is above range high, market sell when below range low (same SL/TP logic).
- **One trade per day (OCO):** When one order fills, the opposite pending order is cancelled. Only one position per day from this EA (when `OneTradePerDay = true`).
- **Session end:** At **TradingEnd** (e.g. 18:00), the EA **closes all positions** and **deletes all pending orders** that belong to it (by magic number).
- **Trailing stop:** Optional. When profit reaches `TrailStartPct` from entry, SL is moved in favor by `TrailStepPct`. Movement is **limited** to `TrailMaxMoves` modifications per position (prop-style “limited” trailing).
- **Prop firm:** Optional daily loss limit, max drawdown, phase 1/2 profit targets, and a **magic randomizer** (base magic + random offset at init) for multi-run or prop-style testing.

---

## 2. File and Dependencies

| Item | Details |
|------|--------|
| **Main file** | `RangeBreakout_Pro_EA.mq5` |
| **Platform** | MetaTrader 5 (MQL5) |
| **Includes** | `Trade\Trade.mqh`, `Trade\OrderInfo.mqh`, `Trade\PositionInfo.mqh` (standard MT5) |
| **Chart** | Can be attached to any symbol; M1 data is used internally for range. Strategy Tester: M1 or M5, “Every tick” or “1 minute OHLC” recommended. |

---

## 3. Input Parameters (Groups)

All inputs are in the EA’s Inputs tab; groups are for UI only.

### 3.1 Range (Server Time)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `RangeStartHour` | int | 3 | Hour when range period starts (0–23). |
| `RangeStartMinute` | int | 0 | Minute. |
| `RangeEndHour` | int | 6 | Hour when range period ends (must be after start). |
| `RangeEndMinute` | int | 0 | Minute. |

Range = high/low of M1 bars between `RangeStart` and `RangeEnd`. Range is **fixed only after** `RangeEnd`.

### 3.2 Session End

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `TradingEndHour` | int | 18 | Hour when all positions are closed and pendings deleted. |
| `TradingEndMinute` | int | 0 | Minute. |

### 3.3 Risk Management

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `RiskMoney` | double | 50.0 | Risk per trade in account currency. If > 0, used for lot calculation. |
| `RiskPercent` | double | 1.0 | Risk per trade as % of balance. Used only when `RiskMoney = 0`. |
| `FixedLotSize` | double | 0.0 | If > 0, this lot is used; risk inputs are ignored. |

Lot size (when not fixed) = risk amount / (risk per lot). Risk per lot is derived from **range size** (SL distance) and symbol tick value/tick size.

### 3.4 Filters & Confluence

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `MinRangeSize` | double | 0.0 | Minimum range size in price. If > 0 and range smaller, no trade that day. |
| `MinRangePct` | double | 0.0 | Min range size as % of range mid price. 0 = disabled. |
| `MaxSpreadPoints` | double | 0.0 | Max spread (points) to allow placing orders. 0 = no filter. |

### 3.5 Orders & Behavior

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `MagicNumber` | int | 23456 | Base magic number. All orders/positions use effective magic (see Prop Firm randomizer). |
| `SlippagePoints` | int | 10 | Slippage in points for market/pending orders. |
| `OneTradePerDay` | bool | true | When one order fills, cancel the other (OCO). |
| `UsePendingOrders` | bool | true | true = Buy/Sell Stop at range high/low; false = market orders on breakout. |
| `UseTakeProfit` | bool | false | Use TP. |
| `TakeProfitFactor` | double | 1.0 | TP distance = range size × factor. Buy: entry + (range × factor); Sell: entry − (range × factor). |

### 3.6 Trailing Stop

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `UseTrailingStop` | bool | true | Enable trailing SL. |
| `TrailStartPct` | double | 0.3 | Start trailing when profit ≥ this % of entry price. |
| `TrailStepPct` | double | 0.15 | Each move: SL is set to price ± this % (buy: price − step; sell: price + step). |
| `TrailMaxMoves` | int | 10 | Max number of SL modifications per position. 0 = unlimited. |

Trailing is **limited**: after `TrailMaxMoves` modifications, that position is no longer trailed (prop-style “limit hits of SL”).

### 3.7 Prop Firm (Challenge)

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `EnablePropRules` | bool | false | Enable daily loss, max DD, phase targets. |
| `ChallengeAccountSize` | double | 100000 | Account size used for % calculations. |
| `Phase1ProfitTarget` | double | 10.0 | Phase 1 profit target (%). |
| `Phase2ProfitTarget` | double | 5.0 | Phase 2 profit target (%). |
| `DailyLossLimitPct` | double | 5.0 | Daily loss limit (% of balance at day start). |
| `MaxDrawdownPct` | double | 10.0 | Max drawdown (% from initial or from equity high). |
| `MinTradingDays` | int | 5 | Informational only (not enforced in code). |
| `PropMagicRandomizer` | bool | false | If true, effective magic = MagicNumber + random(0 .. PropMagicOffset) at init. |
| `PropMagicOffset` | int | 99 | Max random added to MagicNumber when randomizer is on (0–999). |

When limits are breached, the EA stops opening new orders and can close session; it does not reverse or open new trades.

### 3.8 Performance Table

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ShowPerfTable` | bool | true | Show performance panel on chart. |
| `PerfPanelX` | int | 10 | Panel X (pixels from left). |
| `PerfPanelY` | int | 30 | Panel Y (pixels from top). |

Stats are computed from **history** (closed deals with this EA’s magic/symbol only) – no repaint.

### 3.9 Visualization

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ShowRangeVisual` | bool | true | Draw range rectangle and entry level lines. |
| `RangeColor` | color | clrDodgerBlue | Range rectangle. |
| `BuyLevelColor` | color | clrLime | Buy entry level line. |
| `SellLevelColor` | color | clrOrangeRed | Sell entry level line. |

All chart objects created by the EA have names starting with **`RBP_`**.

---

## 4. Global State Variables (Important for Logic)

| Variable | Type | Purpose |
|----------|------|---------|
| `g_Magic` | int | Effective magic (MagicNumber or MagicNumber + random). Set in OnInit. |
| `g_RangeTimeStart`, `g_RangeTimeEnd`, `g_TradingTimeEnd` | datetime | Today’s range start/end and session end (recalculated each tick). |
| `g_RangeHigh`, `g_RangeLow` | double | Current day’s range. Set only after RangeEnd from closed M1 bars. |
| `g_RangeValid` | bool | true when range for the day has been computed and passed filters. |
| `g_LastRangeDate` | datetime | Date of current range (for new-day reset and object names). |
| `g_OrdersPlaced` | bool | true after pending orders have been sent (or market path taken). |
| `g_TradeExecuted` | bool | true when at least one side has filled (OCO / one trade per day). |
| `g_BuyStopTicket`, `g_SellStopTicket` | ulong | Ticket of Buy Stop / Sell Stop (0 if none). |
| `g_LastSessionCloseDate` | datetime | Last date on which CloseSession ran (avoid closing twice same day). |
| `g_ObjectPrefix` | string | `"RBP_"` – prefix for all chart objects. |
| `g_TrailTicket` | ulong | Position ticket currently being trailed. |
| `g_TrailMoveCount` | int | Number of SL modifications for that position (capped by TrailMaxMoves). |
| Prop firm: `g_InitialBalance`, `g_DailyStartBalance`, `g_HighestBalance`, `g_DailyLimitBreached`, `g_MaxLimitBreached`, `g_Phase1Complete`, `g_TradingDaysCount` | various | Challenge tracking. |
| `g_TotalTrades`, `g_Wins`, `g_GrossProfit`, `g_GrossLoss`, `g_DailyPL` | double | Filled from history for performance panel. |

---

## 5. Main Functions (Execution Flow)

### 5.1 OnInit

1. Set **effective magic**: `g_Magic = MagicNumber`; if prop randomizer is on, `g_Magic = MagicNumber + (MathRand() % (PropMagicOffset+1))`.
2. Configure **CTrade**: magic, slippage, filling mode.
3. Initialize all globals (range, orders, trail, prop, perf).
4. If prop rules on: set `g_InitialBalance`, `g_DailyStartBalance`, `g_HighestBalance`.
5. **ValidateInputs()** – return `INIT_PARAMETERS_INCORRECT` if invalid.
6. **RecalculateTimes()** – set `g_RangeTimeStart`, `g_RangeTimeEnd`, `g_TradingTimeEnd` for today.
7. **SyncStateWithExistingOrders()** – restore `g_OrdersPlaced`, ticket vars, `g_TradeExecuted` from current orders/positions with `g_Magic`.
8. If `ShowPerfTable`, **CreatePerfPanel()** (single label object `RBP_PerfPanel`).

### 5.2 OnTick (High-Level Order)

1. **RecalculateTimes()** (so times always reflect “today” in server time).
2. If **EnablePropRules**: **CheckPropRules()**; if daily or max DD breached, optionally close session and return (no new trades).
3. If **HasAnyPosition()**: **TrailPositions()** (respects TrailMaxMoves).
4. **IsNewDay()**: if new day, **ResetDayState()** (range, orders, trail, visuals, daily prop reset).
5. If **TimeCurrent() >= g_TradingTimeEnd**: if not already done today, **CloseSession()** (close all positions, delete pendings, **ResetVisualsAfterClose()**); then update perf panel and return.
6. If **TimeCurrent() < g_RangeTimeEnd**: update perf if needed and return (no range yet).
7. If **!g_RangeValid**: call **UpdateRangeFromClosedBars()**. If it returns true, then:
   - If **UsePendingOrders**: **PlacePendingOrders()**.
   - Else **CheckBreakoutMarketOrder()**. Then return.
8. If **UsePendingOrders**: **MonitorPendingOrders()** (OCO: cancel opposite when one fills).
   - Else **CheckBreakoutMarketOrder()** (only opens if !g_TradeExecuted).
9. If **ShowPerfTable**: **UpdatePerfStats()**, ChartRedraw(0).

### 5.3 Key Helper Functions

- **UpdateRangeFromClosedBars()**: Only runs when `TimeCurrent() >= g_RangeTimeEnd`. Uses `CopyRates(_Symbol, PERIOD_M1, g_RangeTimeStart, minutesInRange, rates)`; computes high/low; applies MinRangeSize/MinRangePct; sets `g_RangeValid`, `g_LastRangeDate`; draws range/levels if `ShowRangeVisual`. **No repaint**: only closed bars.
- **PlacePendingOrders()**: Buy Stop at `g_RangeHigh` (SL `g_RangeLow`), Sell Stop at `g_RangeLow` (SL `g_RangeHigh`). Optional TP from TakeProfitFactor. Uses **CalculateLotSize()** and **CanPlaceNewOrder()** (prop checks).
- **CheckBreakoutMarketOrder()**: If bid > g_RangeHigh → Buy; if bid < g_RangeLow → Sell; SL/TP same as above. Only if !g_TradeExecuted and (if prop) CanPlaceNewOrder().
- **MonitorPendingOrders()**: If OneTradePerDay and HasAnyPosition(), cancel both pendings and set g_TradeExecuted. Else refresh ticket from OrdersTotal and, if a position exists, cancel the opposite pending.
- **TrailPositions()**: For each position with g_Magic: if new ticket, reset g_TrailMoveCount; if TrailMaxMoves > 0 and g_TrailMoveCount >= TrailMaxMoves, skip. Else, if profit >= TrailStartPct, compute new SL (entry ± TrailStepPct), modify position, increment g_TrailMoveCount.
- **CloseSession()**: Close all positions with g_Magic, delete all orders with g_Magic, clear pending tickets, **ResetVisualsAfterClose()** (deletes all objects with prefix RBP_).
- **ResetVisualsAfterClose()**: If ShowRangeVisual, **DeleteAllVisuals()** (all object names starting with g_ObjectPrefix).
- **OnPositionClosed(ticket)**: Called when a position is closed (from CloseSession or OnTradeTransaction). Resets g_TrailTicket and g_TrailMoveCount if the closed ticket was the trailed one.

### 5.4 OnTradeTransaction

- Only reacts to **TRADE_TRANSACTION_DEAL_ADD**.
- Checks deal magic == g_Magic, symbol == _Symbol, **DEAL_ENTRY_OUT** (close).
- Calls **OnPositionClosed(trans.position)** and **ResetVisualsAfterClose()**. So: **on every close of our position, chart objects (range + entry levels) are removed**; they are redrawn when a new range is formed next day.

### 5.5 OnDeinit

- **DeleteAllVisuals()** (all RBP_ objects).
- Delete performance panel object `RBP_PerfPanel`.

---

## 6. No-Repaint and Visualization Rules

- **Range:** Computed only when `TimeCurrent() >= g_RangeTimeEnd`, from **closed** M1 bars. Never updated after that for the same day.
- **Entry levels:** Drawn at fixed prices (g_RangeHigh, g_RangeLow). No repaint.
- **Performance table:** Built from **HistoryDeals** (closed deals only), filtered by g_Magic and _Symbol. No repaint.
- **Visuals:** Objects are named `RBP_Rect_<date>`, `RBP_Buy_<date>`, `RBP_Sell_<date>`, `RBP_PerfPanel`. They are **removed** when:
  - A position is closed (OnTradeTransaction or CloseSession → ResetVisualsAfterClose),
  - A new day starts (ResetDayState → DeleteAllVisuals),
  - EA is removed (OnDeinit → DeleteAllVisuals).
- **“Keep entry as is when exited, reset after closed trade”:** Entry levels stay on chart until the trade closes; as soon as the close is processed, **ResetVisualsAfterClose()** runs and all RBP_ visuals are deleted.

---

## 7. Prop Firm and Magic

- **Effective magic:** All orders and positions use **g_Magic**. It is set once in OnInit (MagicNumber or MagicNumber + random).
- **Prop rules:** When EnablePropRules is true, the EA checks daily loss % vs DailyLossLimitPct and drawdown % vs MaxDrawdownPct. If breached, it sets flags and does not open new orders; it can close the session (CloseSession).
- **Randomizer:** PropMagicRandomizer + PropMagicOffset change the effective magic at init so different runs or instances can use different magics (e.g. for strategy tester or multi-symbol without conflict).

---

## 8. How to Use on Another Machine

1. **Copy/git:** Ensure `RangeBreakout_Pro_EA.mq5` (and this summary) are in the repo and pulled on the other PC.
2. **MT5:** Install MetaTrader 5. Place the EA in the Experts folder (e.g. `MQL5\Experts\` or a subfolder), or open the project from your repo and compile in MetaEditor.
3. **Compile:** Open the file in MetaEditor, press F7. Fix any path/include issues if the project layout differs.
4. **Attach:** Attach to a chart (any symbol). Set inputs (range/session in **server time**).
5. **Strategy Tester:** Symbol M1 or M5; model “Every tick” or “1 minute OHLC”; set date range. All times in inputs are server time (tester uses broker server time by default).
6. **Prop / multi-run:** To test with different magics each run, set EnablePropRules = true and PropMagicRandomizer = true with PropMagicOffset (e.g. 99).

---

## 9. Quick Reference: Where Things Are in Code

| Logic | Function / Location |
|-------|----------------------|
| Range calculation (M1, no repaint) | `UpdateRangeFromClosedBars()` |
| Place Buy/Sell Stop at range | `PlacePendingOrders()` |
| Market breakout entries | `CheckBreakoutMarketOrder()` |
| OCO / one trade per day | `MonitorPendingOrders()`, and checks on g_TradeExecuted |
| Lot size (risk money or %) | `CalculateLotSize()` |
| Trailing with max moves | `TrailPositions()`, `g_TrailMoveCount`, `TrailMaxMoves` |
| Close all at session end | `CloseSession()` |
| Prop checks | `CheckPropRules()`, `CanPlaceNewOrder()`, `ResetDailyPropTracking()` |
| Magic randomizer | OnInit: `g_Magic = MagicNumber + (MathRand() % (PropMagicOffset + 1))` |
| Draw range + levels | `DrawRangeAndEntryLevels()` |
| Remove visuals on close | `ResetVisualsAfterClose()` → `DeleteAllVisuals()` |
| Performance from history | `UpdatePerfStats()` |
| New day reset | `IsNewDay()`, `ResetDayState()` |
| On close event | `OnTradeTransaction()` (DEAL_ENTRY_OUT) → `OnPositionClosed()`, `ResetVisualsAfterClose()` |

---

## 10. Version and Contact

- **Version in EA:** 1.00 (`#property version "1.00"`).
- **Object prefix:** All chart objects: **RBP_**. Do not rely on object names from other EAs.

This summary is intended for AI and developers to quickly learn the EA’s behavior, inputs, state, and flow when opening the project on a new machine or in a new environment.
