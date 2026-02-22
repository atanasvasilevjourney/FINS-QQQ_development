# Martingale Grid EA – Detailed Summary (for Git / AI context)

**File:** `MartingaleGrid_EA.mq5`  
**Platform:** MetaTrader 5 (MQL5)  
**Purpose:** Automated grid/martingale-style trading: open buy after X points down from high, sell after X points up from low; add positions every X points with lot multiplier; close entire grid at take-profit from volume-weighted average (break-even) price. Designed for no repaint, prop firm risk limits, optional trailing stop, and reset on closed entry.

---

## 1. Strategy logic (what the bot does)

### 1.1 Price tracking (global state)

- **g_HighestPrice** – Tracks the highest Bid seen since last “buy grid” was closed (or since start). Updated every tick: `if (bid > g_HighestPrice) g_HighestPrice = bid`.
- **g_LowestPrice** – Tracks the lowest Bid seen since last “sell grid” was closed (or since start). Updated every tick: `if (bid < g_LowestPrice) g_LowestPrice = bid`.
- **Reset on closed entry:** When all buy positions are closed at TP, `ResetAfterClose(true, false)` sets `g_HighestPrice = bid` (and keeps/lowest as-is). When all sell positions are closed at TP, `ResetAfterClose(false, true)` sets `g_LowestPrice = bid`. So the next grid cycle starts from current price; no repaint (only current Bid and positions are used).

### 1.2 Buy side

- **First buy:** When there are **no** open buy positions (`buyCount <= 0`) and `bid <= g_HighestPrice - (InpGridPoints * point)`, open one market buy with `InpStartLots`. After sending the order, set `g_HighestPrice = bid` to avoid opening another “first” buy on the same/next tick before position appears.
- **Additional buys:** When there **are** buy positions, find the **lowest** open buy price (that is the “last” / furthest down level). If `bid <= lastBuyPrice - (InpGridPoints * point)`, open another buy with lot = `lastBuyLots * InpLotsMultiplier` (normalized). After sending, set `g_HighestPrice = bid` to avoid duplicate add on same tick.
- **Close buy grid:** Compute **volume-weighted average** buy price: `avgBuyPrice = sum(openPrice * volume) / totalBuyLots`. If `bid >= avgBuyPrice + (InpTPPoints * point)`, close **all** buy positions and call `ResetAfterClose(true, false)`.

### 1.3 Sell side

- **First sell:** When there are **no** open sell positions (`sellCount <= 0`) and `bid >= g_LowestPrice + (InpGridPoints * point)`, open one market sell with `InpStartLots`. After sending, set `g_LowestPrice = bid`.
- **Additional sells:** When there **are** sell positions, find the **highest** open sell price (last level). If `bid >= lastSellPrice + (InpGridPoints * point)`, open another sell with lot = `lastSellLots * InpLotsMultiplier`. After sending, set `g_LowestPrice = bid`.
- **Close sell grid:** `avgSellPrice = sum(openPrice * volume) / totalSellLots`. If `bid <= avgSellPrice - (InpTPPoints * point)`, close all sell positions and call `ResetAfterClose(false, true)`.

### 1.4 Points and symbol

- All distances use **points**: `point = SymbolInfoDouble(_Symbol, SYMBOL_POINT)` (e.g. 0.01 for 2-digit, 0.00001 for 5-digit). So the same inputs (e.g. 1000 points) work across symbols; no repaint (only current Bid and open positions, no future bars).

---

## 2. Input parameters (all in one place)

| Group | Parameter | Type | Default | Description |
|-------|-----------|------|---------|-------------|
| **Grid & Lots** | InpGridPoints | int | 1000 | Grid distance in points (step between entries). |
| | InpStartLots | double | 0.01 | Lot size for the first position of each side. |
| | InpLotsMultiplier | double | 3.0 | Multiply previous level’s lot by this (e.g. 0.01 → 0.03 → 0.09). |
| | InpTPPoints | int | 200 | Take profit in points **above** avg buy price (buys) or **below** avg sell price (sells). |
| **Trade Execution** | InpMagic | int | 77100 | Magic number; only positions/orders with this magic are managed. |
| | InpSlippagePoints | int | 10 | Slippage in points for market orders. |
| | InpMaxSpreadPoints | double | 0 | Max spread to allow new orders (0 = disabled). |
| **Risk (Prop Firm)** | InpUseRiskLimits | bool | true | Enable max positions, max lot, daily loss %, max drawdown %. |
| | InpMaxPositions | int | 20 | Max total open positions (buy + sell) for this EA. |
| | InpMaxLotSize | double | 1.0 | Max lot per single order. |
| | InpDailyLossPct | double | 5.0 | Daily loss limit as % of **daily start balance** (no new orders if exceeded). |
| | InpMaxDrawdownPct | double | 10.0 | Max drawdown % from **highest equity** (no new orders if exceeded). |
| | InpChallengeSize | double | 100000 | Reference account size in $ (used for % calculations if needed; daily/drawdown use balance/equity). |
| **Trailing Stop** | InpUseTrailing | bool | false | Enable trailing stop. |
| | InpTrailStartPoints | int | 100 | Start trailing after profit in points from **open price** (not BE). |
| | InpTrailStepPoints | int | 50 | Distance in points to place SL behind price when trailing. |
| **Visualization** | InpShowComment | bool | true | Show info panel in chart corner (Comment). |
| | InpShowLevels | bool | false | Draw horizontal lines for BE and TP (buy/sell). |

---

## 3. No-repaint policy

- **Only current Bid** from `SymbolInfoDouble(_Symbol, SYMBOL_BID)` and **current open positions** (by magic and symbol) are used.
- No future bars, no unconfirmed candle data, no recalculation of past high/low from history. High/low are updated live and reset only when a grid is closed (reset on closed entry).

---

## 4. Prop firm risk management

- **CanOpenNewOrder()** is called before any new Buy/Sell. When `InpUseRiskLimits == true` it:
  - Resets **daily start balance** at the start of each new calendar day (server time).
  - Tracks **highest equity** and computes drawdown as `(highestEquity - currentEquity) / highestEquity * 100`.
  - Blocks new orders if:
    - `(dailyStartBalance - equity) / dailyStartBalance * 100 >= InpDailyLossPct`, or
    - `(highestEquity - equity) / highestEquity * 100 >= InpMaxDrawdownPct`, or
    - Total positions (this symbol + magic) >= InpMaxPositions.
- **NormalizeLots()** caps lot at `InpMaxLotSize` when risk limits are on.
- **InitPropFirmState()** is called in OnInit when risk limits are enabled (sets daily start balance and highest equity from current account).

---

## 5. Trailing stop

- **ManageTrailingStop()** runs every tick. Only if `InpUseTrailing == true` and `InpTrailStepPoints > 0`.
- **Buy:** If `bid - openPrice >= InpTrailStartPoints * point`, sets SL = `bid - InpTrailStepPoints * point` (only if new SL > current SL and > open price). Uses `PositionModify(ticket, newSL, TP)`.
- **Sell:** If `openPrice - ask >= InpTrailStartPoints * point`, sets SL = `ask + InpTrailStepPoints * point` (only if new SL < current SL and < open price).
- TP is preserved when modifying (existing TP from open is kept; EA opens with 0 SL/0 TP by default).

---

## 6. Position counting and averages

- **CountPositions(...)** loops over `PositionsTotal()`, filters by `_Symbol` and `InpMagic`, and returns:
  - **outBuyCount / outSellCount** – number of buy and sell positions.
  - **outSumBuyPriceLots, outTotalBuyLots** – for weighted average buy: `avgBuy = sum(price*volume)/totalLots`.
  - **outSumSellPriceLots, outTotalSellLots** – same for sells.
  - **outLastBuyPrice, outLastBuyLots** – open price and lot of the **lowest** buy (furthest down); used for “next” buy level.
  - **outLastSellPrice, outLastSellLots** – open price and lot of the **highest** sell (furthest up); used for “next” sell level.

---

## 7. Main flow (OnTick)

1. Get **bid** and **point**; update **g_HighestPrice** and **g_LowestPrice** from current Bid (no repaint).
2. **CountPositions** → buy/sell counts, weighted sums, totals, last buy/sell price and lots.
3. Compute **avgBuyPrice**, **avgSellPrice**, **tpPriceBuy** (avgBuy + TP points), **tpPriceSell** (avgSell - TP points).
4. **ManageTrailingStop()** – optional trailing.
5. **Close at TP:**  
   - If buy grid in profit: `bid >= tpPriceBuy` → **ClosePositions(true, false)** → **ResetAfterClose(true, false)**.  
   - If sell grid in profit: `bid <= tpPriceSell` → **ClosePositions(false, true)** → **ResetAfterClose(false, true)**.
6. **CountPositions** again (after possible close).
7. If **!CanOpenNewOrder()** or **!CheckSpread()**: only update comment/levels and return (no new orders).
8. **Grid distance** = `InpGridPoints * point`.
9. **Buy logic:**  
   - No buys: if `bid <= g_HighestPrice - gridDist` → Buy(InpStartLots), then `g_HighestPrice = bid`.  
   - Has buys: if `bid <= lastBuyPrice - gridDist` → Buy(lastBuyLots * InpLotsMultiplier), then `g_HighestPrice = bid`.
10. **Sell logic:**  
    - No sells: if `bid >= g_LowestPrice + gridDist` → Sell(InpStartLots), then `g_LowestPrice = bid`.  
    - Has sells: if `bid >= lastSellPrice + gridDist` → Sell(lastSellLots * InpLotsMultiplier), then `g_LowestPrice = bid`.
11. **UpdateComment** and **DrawLevels** if enabled.

---

## 8. Important functions (quick reference)

| Function | Purpose |
|----------|--------|
| **OnInit()** | Set magic, deviation, filling; init g_HighestPrice/g_LowestPrice; validate inputs; optionally InitPropFirmState(). |
| **OnDeinit()** | Delete level objects (if InpShowLevels), Comment(""), print reason. |
| **ValidateInputs()** | Grid/TP/lots/multiplier; if risk limits: max positions, max lot, daily%, drawdown%, challenge size; trailing params. |
| **NormalizeLots(lots)** | Clamp to symbol min/max/step; if risk limits, cap at InpMaxLotSize; return 2-decimal. |
| **NormalizePrice(price)** | NormalizeDouble(price, _Digits). |
| **CheckSpread()** | If InpMaxSpreadPoints > 0, allow orders only when current spread <= that (points). |
| **CountPositions(...)** | One loop over positions (symbol + magic); fills counts, weighted sums, last buy/sell price and lots. |
| **InitPropFirmState()** | s_DailyStartBalance = balance, s_HighestEquity = equity, s_LastDay = 0. |
| **CanOpenNewOrder()** | Daily/drawdown/max positions checks; returns false to block new orders. |
| **ClosePositions(closeBuy, closeSell)** | Loop positions; close buy and/or sell by magic/symbol via g_Trade.PositionClose(ticket). |
| **ResetAfterClose(resetBuy, resetSell)** | Set g_HighestPrice/g_LowestPrice to current Bid when a grid is closed (reset on closed entry). |
| **ManageTrailingStop()** | Optional: move SL for buy/sell by trail start/step (points). |
| **DrawLevels(avgBuy, avgSell, tpBuy, tpSell)** | Create/update OBJ_TREND objects "MG_BE_Buy", "MG_TP_Buy", "MG_BE_Sell", "MG_TP_Sell"; delete when no level. |
| **DeleteLevelObjects()** | Remove the four "MG_" objects. |
| **UpdateComment(...)** | Build string with grid params, position counts, avg/TP/lots, high/low, Bid; Comment(c). |

---

## 9. Global and static state

- **g_HighestPrice, g_LowestPrice** – Global; updated every tick; reset when grid closes (see ResetAfterClose).
- **s_DailyStartBalance, s_HighestEquity, s_LastDay** – Static in CanOpenNewOrder(); daily reset at start of new day; highest equity tracked for drawdown.
- **g_Trade** – CTrade instance; magic and deviation set in OnInit.

---

## 10. Dependencies and build

- **Include:** `#include <Trade\Trade.mqh>` (standard MQL5).
- **Compile:** MetaEditor (F7). Output: `MartingaleGrid_EA.ex5` in the same folder as the .mq5.
- **Attach:** Chart → Navigator → Expert Advisors → MartingaleGrid_EA → drag onto chart; configure inputs and enable AutoTrading.
- **Strategy Tester:** View → Strategy Tester; select Expert MartingaleGrid_EA, symbol, period, model (e.g. “Every tick based on real ticks”), run.

---

## 11. File layout (repo)

- **MartingaleGrid_EA.mq5** – Single-file EA; all logic in one MQ5.
- **MartingaleGrid_EA_SUMMARY.md** – This document (for git push and AI/developer context).

---

## 12. Prop firms (usage note)

This EA is built with prop firm style limits (daily loss %, max drawdown %, max positions, max lot). Whether a given prop firm **allows** grid/martingale EAs is determined by their rules, not by this code. Set **InpUseRiskLimits = true** and align **InpDailyLossPct**, **InpMaxDrawdownPct**, **InpMaxPositions**, and **InpMaxLotSize** with the firm’s rules. Confirm strategy permission with the prop firm’s current terms before using.

---

*End of summary. For changes or extensions, keep this document in sync with MartingaleGrid_EA.mq5.*
