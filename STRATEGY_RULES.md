# Mean Reversion EA - Strategy Rules (from Video Tutorial)

## Source
Video tutorial by Rene - Mean Reversion Expert Advisor for MetaTrader 5

## Core Concept
Fade price extremes away from a long-term moving average, expecting price to revert to the mean. Best suited for ranging/sideways markets like EUR/USD, GBP/USD.

## Indicators Used
1. **MA1** (Signal timeframe): 360-period SMA on M15 (default)
2. **MA2** (Trend filter): 20-period SMA on D1 (changed to 15 in final test)
3. **RSI**: 20-period RSI on M15
4. **ATR1**: 10-period ATR on M15
5. **ATR2**: 20-period ATR on M15

## Entry Conditions

### LONG (BUY) Entry
All conditions must be met:
1. **Distance check**: Close < MA1 - (MA1 × MinGap%) — price is at least MinGap% below MA1 (default 0.6%)
2. **Trend filter**: Close > MA2 (D1) — price above higher timeframe MA
3. **RSI momentum**: RSI[1] > RSI[0] — RSI is rising (upward momentum)
4. **Volatility filter**: ATR1 < ATR2 — fast ATR below slow ATR (volatility declining)
5. **Position check**: No existing BUY position open

### SHORT (SELL) Entry
All conditions must be met:
1. **Distance check**: Close > MA1 + (MA1 × MinGap%) — price is at least MinGap% above MA1
2. **Trend filter**: Close < MA2 (D1) — price below higher timeframe MA
3. **RSI momentum**: RSI[1] < RSI[0] — RSI is falling (downward momentum)
4. **Volatility filter**: ATR1 < ATR2 — fast ATR below slow ATR (volatility declining)
5. **Position check**: No existing SELL position open

## Exit Conditions

### BUY Exit
- **Target exit**: Price crosses above MA1 AND position in profit
- **Stop loss**: Price drops by SL% from entry
- **Take profit**: Price rises by TP% from entry

### SELL Exit
- **Target exit**: Price crosses below MA1 AND position in profit
- **Stop loss**: Price rises by SL% from entry
- **Take profit**: Price drops by TP% from entry

## Default Parameters (from video)
- **MA1 Period**: 360
- **MA1 Timeframe**: M15
- **MA2 Period**: 20 (changed to 15 in final test)
- **MA2 Timeframe**: D1
- **RSI Period**: 20
- **RSI Timeframe**: M15
- **ATR1 Period**: 10
- **ATR2 Period**: 20
- **ATR Timeframe**: M15
- **Min MA Gap**: 0.6%
- **Lots**: 1.0 (adjustable)
- **TP Percent**: (user defined)
- **SL Percent**: (user defined)

## Key Implementation Notes

### Non-Repaint Logic
- **CRITICAL**: All signals must be evaluated on bar close (completed bar)
- Use bar counting to ensure code executes only once per new bar
- Never use current bar [0] for entry signals — always use closed bar [1]

### Trade Management
- Maximum 1 BUY position at a time
- Maximum 1 SELL position at a time
- Count positions before opening new trades
- Close positions at MA1 touch only if in profit

### Risk Management
- Fixed lot size (input parameter)
- Percentage-based SL and TP
- Optional: Add time-based exit if position stale

## Backtest Results (from video)
- **Symbol**: EUR/USD
- **Period**: 2015-2025
- **Timeframe**: M15
- **Result**: Profitable long-term with consistent equity curve
- **Note**: Not every year profitable, but overall positive expectancy

## Recommended Improvements (OI's additions)
1. **ATR-based SL/TP**: Use ATR multiples instead of percentage
2. **Max spread filter**: Skip entries if spread too wide
3. **Time filter**: Avoid low-liquidity hours
4. **Cooldown period**: Wait X bars after closing a trade
5. **Walk-forward optimization**: Validate parameters OOS
6. **Portfolio approach**: Run on multiple pairs simultaneously
