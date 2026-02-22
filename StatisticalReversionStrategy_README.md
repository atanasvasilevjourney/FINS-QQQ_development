# Statistical Reversion Strategy EA — Detailed Summary

**File:** `StatisticalReversionStrategy.mq5`  
**Platform:** MetaTrader 5 (MQL5)  
**Source:** Part 39 — "Automating Trading Strategies in MQL5" (Allan Munene Mutiiria).  
**Purpose:** Mean reversion Expert Advisor that uses distribution statistics (mean, variance, skewness, kurtosis, Jarque–Bera), confidence intervals, and optional higher-timeframe confirmation to open and manage positions, with an on-chart dashboard.

---

## 1. Strategy Overview

The EA assumes **price tends to revert to its recent mean** after large moves. It:

- Computes **statistical moments** over the last **InpPeriod** close prices (mean, variance, skewness, kurtosis).
- Builds **confidence intervals (CI)** around the mean; trades when price breaks **below** (buy) or **above** (sell) the CI.
- Uses **skewness** to favor buys in oversold (negative skew) and sells in overbought (positive skew).
- Uses **Jarque–Bera** to require **non-normality** (JB > threshold) so that reversion setups are considered statistically meaningful.
- Caps **kurtosis** so it does not trade in extremely fat-tailed regimes (optional filter).
- Can **confirm** with a higher timeframe (HTF): alignment of price vs HTF mean and sign of skewness.

**Important:** It trades **only the chart symbol** (`_Symbol`) on **one chart**. It is **single-symbol, single-timeframe** (plus optional HTF). No multi-symbol loop.

---

## 2. Input Parameters (Reference)

### Statistical Parameters
| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `InpPeriod` | int | 50 | Number of closed bars used for mean, variance, skewness, kurtosis, and CI. |
| `InpConfidenceLevel` | double | 0.95 | Confidence level for CI (0.90–0.99). Clamped in code to [0.90, 0.99]. |
| `InpJBThreshold` | double | 2.0 | Minimum Jarque–Bera statistic to allow a trade (non-normality filter). |
| `InpKurtosisThreshold` | double | 5.0 | Maximum allowed excess kurtosis; no new trades if kurtosis > this. |
| `InpHigherTF` | ENUM_TIMEFRAMES | 0 | Higher timeframe for confirmation. 0 = disabled. |

### Trading Parameters
| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `InpRiskPercent` | double | 1.0 | Risk per trade as % of equity. 0 = use fixed lots. Clamped to [0, 10] in code. |
| `InpFixedLots` | double | 0.01 | Lot size when `InpRiskPercent` = 0. |
| `InpBaseStopLossPips` | int | 50 | Base stop loss in pips (interpreted with broker digits, see below). |
| `InpBaseTakeProfitPips` | int | 100 | Base take profit in pips. |
| `InpMagicNumber` | int | 123456 | Magic number for this EA’s positions. |
| `InpMaxTradeHours` | int | 48 | Max time a position can stay open (hours). 0 = no time exit. |

### Risk Management
| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `InpUseTrailingStop` | bool | true | Enable trailing stop. |
| `InpTrailingStopPips` | int | 30 | Distance (pips) of SL from current price when trailing. |
| `InpTrailingStepPips` | int | 10 | Minimum move (pips) before SL is updated again. |
| `InpUsePartialClose` | bool | true | Enable partial close at 50% of way to TP. |
| `InpPartialClosePercent` | double | 0.5 | Fraction of position volume to close at that level (e.g. 0.5 = half). |

### Dashboard Parameters
| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `InpShowDashboard` | bool | true | Show the on-chart dashboard. |
| `InpDashboardX` | int | 30 | Dashboard left position (pixels). |
| `InpDashboardY` | int | 30 | Dashboard top position (pixels). |
| `InpFontSize` | int | 10 | Font size for dashboard text. |

---

## 3. Statistical Logic (Detailed)

### 3.1 Data and Moments
- **Data:** `CopyClose(_Symbol, _Period, 1, InpPeriod, prices)` — last `InpPeriod` **closed** bars (indices 1 to InpPeriod). Bar 0 (current) is used only for `current_price`.
- **Moments:** `MathMoments(prices, mean, variance, skewness, kurtosis, 0, InpPeriod)` from `<Math\Stat\Math.mqh>`. Kurtosis is **excess kurtosis** (0 for normal).
- **Standard deviation:** `std_dev = MathSqrt(variance)`.

### 3.2 Jarque–Bera
- Formula: `jb_stat = n * (skewness²/6 + kurtosis²/24)` with `n = InpPeriod`.
- Used as filter: trade only if `jb_stat > InpJBThreshold` (distribution is non-normal enough to consider reversion).

### 3.3 Confidence Intervals
- **z-score:** `z_score = NormalInverse(0.5 + confidenceLevel/2)` (e.g. 0.95 → 0.975 → approximate standard normal quantile).
- **NormalInverse:** Polynomial approximation for inverse CDF of N(0,1); see `NormalInverse()` in the source.
- **CI half-width (in price):** `ci_mult = z_score / MathSqrt(n)`; then:
  - `lower_ci = mean - ci_mult * std_dev`
  - `upper_ci = mean + ci_mult * std_dev`

### 3.4 Adaptive Skewness Thresholds
- `skew_buy_threshold  = -0.3 - 0.05 * kurtosis`
- `skew_sell_threshold =  0.3 + 0.05 * kurtosis`
- **Buy:** requires skewness **below** buy threshold (more negative = more oversold bias).
- **Sell:** requires skewness **above** sell threshold (more positive = more overbought bias).

### 3.5 Higher Timeframe (HTF) Confirmation
- If `InpHigherTF != 0`: same `InpPeriod` closes are copied from `InpHigherTF`, and `MathMoments` gives `htf_mean`.
- **htf_valid** is true if:
  - `(current_price <= htf_mean && skewness <= 0)` **or**
  - `(current_price >= htf_mean && skewness >= 0)`
- So: for a buy context we expect price below HTF mean and negative skew; for sell, above HTF mean and positive skew.

### 3.6 Signal Conditions (Primary)
- **Buy:** `htf_valid && (current_price < lower_ci) && (skewness < skew_buy_threshold) && (jb_stat > InpJBThreshold)`.
- **Sell:** `htf_valid && (current_price > upper_ci) && (skewness > skew_sell_threshold) && (jb_stat > InpJBThreshold)`.

### 3.7 Fallback Signals (When No CI Signal)
- **Buy:** `htf_valid && (current_price < mean - 0.3 * std_dev)`.
- **Sell:** `htf_valid && (current_price > mean + 0.3 * std_dev)`.
- Fallback does **not** use JB or skew thresholds; it only requires price beyond 0.3 standard deviations from the mean and HTF alignment.

### 3.8 Kurtosis Filter
- If `kurtosis > InpKurtosisThreshold`, the EA **does not open new trades** on that bar (dashboard still updates). No position is opened and no opposite position is closed by signal logic (only trailing/partial/time exit apply).

---

## 4. Execution Flow (OnTick)

1. **Every tick**
   - If `InpUseTrailingStop`: run `ManageTrailingStop()`.
   - If `InpUsePartialClose`: run `ManagePartialClose()`.
   - Always run `ManageTimeBasedExit()` (no-op if `InpMaxTradeHours == 0`).

2. **New bar check**
   - If `iTime(_Symbol, _Period, 0) == g_lastBarTime`: only update dashboard (with zeros for stats if no new bar yet), then return. So **signal and entry logic run only on the first tick of a new bar**.

3. **Update** `g_lastBarTime = iTime(_Symbol, _Period, 0)`.

4. **Market check**
   - If no valid `SYMBOL_BID` or `SYMBOL_ASK`, update dashboard and return.

5. **Copy closes** for `_Period` and `InpHigherTF` (if used); compute moments, JB, CI, skew thresholds, `htf_valid`, and **buy_signal** / **sell_signal** as above.

6. **Position management**
   - If there is a **buy** position and **sell_signal**: close all positions of type **buy** for `_Symbol` and `InpMagicNumber`.
   - If there is a **sell** position and **buy_signal**: close all positions of type **sell** for `_Symbol` and `InpMagicNumber`.
   - Then, if **no position** and **buy_signal**: open buy (SL/TP set; see below). Else if **no position** and **sell_signal**: open sell.
   - At most **one** position at a time (one buy or one sell); opening a new one requires no current position after the possible close above.

7. **Lot size**
   - If `InpRiskPercent > 0`:  
     `loss_per_lot = sl_price_dist * (tick_value / tick_size)`  
     with `sl_price_dist = InpBaseStopLossPips * _Point * g_pointMultiplier`.  
     Then `lot_size = (equity * riskPercent/100) / loss_per_lot`, normalized to symbol min/max/step.
   - Else: `lot_size = InpFixedLots`.

8. **SL/TP for new orders**
   - Buy: `sl = current_price - InpBaseStopLossPips * _Point * g_pointMultiplier`, `tp = current_price + InpBaseTakeProfitPips * _Point * g_pointMultiplier`.
   - Sell: `sl = current_price + ...`, `tp = current_price - ...`.

9. **Dashboard**
   - `UpdateDashboard(...)` is called with current stats, CIs, position status, lot, profit, duration, and last signal (Buy/Sell/None).

---

## 5. Broker Digits and Pips (g_pointMultiplier)

- In **OnInit**: if `_Digits == 5` or `_Digits == 3`, then `g_pointMultiplier = 10.0`; else `g_pointMultiplier = 1.0`.
- So “pips” in inputs are interpreted as **1 pip = 10 points** for 5/3-digit brokers; for 4/2-digit, 1 pip = 1 point.
- All SL/TP/trailing distances in price use: `... * _Point * g_pointMultiplier`.

---

## 6. Position and Order APIs (MQL5)

- **Positions:** The EA iterates with `PositionGetTicket(i)` for `i = PositionsTotal()-1` down to `0`. After `PositionGetTicket(i)`, the “current” position for property calls is that position, so:
  - `PositionGetString(POSITION_SYMBOL)`, `PositionGetInteger(POSITION_MAGIC)`, `PositionGetInteger(POSITION_TYPE)`, `PositionGetDouble(POSITION_SL)`, `PositionGetDouble(POSITION_TP)`, `PositionGetDouble(POSITION_VOLUME)`, `PositionGetDouble(POSITION_PRICE_OPEN)`, `PositionGetDouble(POSITION_PROFIT)`, `PositionGetInteger(POSITION_TIME)` are used without an explicit `PositionSelectByTicket`.
- **Only** positions with `POSITION_SYMBOL == _Symbol` and `POSITION_MAGIC == InpMagicNumber` are considered.
- **Closing:** `trade.PositionClose(ticket)` for full close; `trade.PositionClosePartial(ticket, volume)` for partial close.
- **Modify:** `trade.PositionModify(ticket, new_sl, new_tp)` for trailing stop.

---

## 7. Trailing Stop Logic

- For each position (symbol + magic match):
  - **Buy:** `new_sl = current_price - trail_distance`. Update SL only if `new_sl > current_sl + trail_step` or `current_sl == 0`.
  - **Sell:** `new_sl = current_price + trail_distance`. Update SL only if `new_sl < current_sl - trail_step` or `current_sl == 0`.
- `trail_distance` and `trail_step` are in price (pips × _Point × g_pointMultiplier).

---

## 8. Partial Close Logic

- When price has moved **halfway to TP** from open:
  - **Buy:** `current_price >= open_price + 0.5 * (tp - open_price)`.
  - **Sell:** `current_price <= open_price - 0.5 * (tp - open_price)`.
- Close volume = `volume * InpPartialClosePercent`, normalized to 2 decimals; must be >= `SYMBOL_VOLUME_MIN`. Then `trade.PositionClosePartial(ticket, close_volume)`.

---

## 9. Time-Based Exit

- If `InpMaxTradeHours > 0`: for each EA position, if `(TimeCurrent() - open_time) / 3600 >= InpMaxTradeHours`, the position is closed.

---

## 10. Dashboard

- **Objects:** `CChartObjectRectLabel` for background and header; `CChartObjectLabel` for title and for 17 static + 17 value labels (from `ChartObjects\ChartObjectsTxtControls.mqh`).
- **Static labels:** Symbol, Timeframe, Price, Skewness, Jarque-Bera, Kurtosis, Mean, Lower CI, Upper CI, Position, Lot Size, Profit, Duration, Signal, Equity, Balance, Free Margin.
- **Values:** Filled in `UpdateDashboard()` from current stats, `GetPositionStatus()`, `GetCurrentLotSize()`, `GetCurrentProfit()`, `GetPositionDuration()`, and `GetSignalStatus(buy_signal, sell_signal)`; account Equity, Balance, Free Margin from `AccountInfoDouble`.
- **Cleanup:** `DeleteDashboard()` in `OnDeinit()` deletes and frees all objects and redraws the chart.

---

## 11. Dependencies

- `#include <Trade\Trade.mqh>` — `CTrade` (Buy, Sell, PositionClose, PositionModify, PositionClosePartial, SetExpertMagicNumber, etc.).
- `#include <Math\Stat\Math.mqh>` — `MathMoments()`.
- `#include <ChartObjects\ChartObjectsTxtControls.mqh>` — `CChartObjectRectLabel`, `CChartObjectLabel` for dashboard.

Standard MQL5 terminal libraries; no custom includes.

---

## 12. Usage Notes (For AI or New Machine)

- **Chart:** Attach the EA to **one** chart. It trades **only** `_Symbol` on **that** chart’s timeframe `_Period`; optional HTF is `InpHigherTF`.
- **Backtest:** Strategy Tester, “Every tick” or “1 minute OHLC”; single symbol; ensure “Allow Algo Trading” is on.
- **Magic:** Use a unique `InpMagicNumber` if multiple EAs or manual trades use the same account.
- **Risk:** With `InpRiskPercent > 0`, lot size depends on equity and SL distance; verify symbol’s `SYMBOL_TRADE_TICK_VALUE` and `SYMBOL_TRADE_TICK_SIZE` for correct sizing.
- **Dashboard:** If the panel does not appear or is misdrawn, set `InpShowDashboard = false` to run without it; the EA still trades.

---

## 13. File and Version

- **Single file:** `StatisticalReversionStrategy.mq5`.
- **Version in code:** `#property version "1.00"`.
- **Author/Copyright:** Allan Munene Mutiiria (Part 39); implementation details and MQL5 fixes (position iteration, lot formula, broker digits) as in this codebase.

This document is the main reference for the bot’s behavior so that an AI or developer can understand, replicate, or modify it after a git pull on another computer.
