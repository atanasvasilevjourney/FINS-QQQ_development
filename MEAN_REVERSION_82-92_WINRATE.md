# Mean Reversion Strategy - 82-92% Win Rate

## 📊 Strategy Overview

This is a mean reversion trading strategy based on Jared Goodwin's video tutorial. The strategy achieves a **win rate between 82-92%** depending on profit target selection, with optimal settings producing **84% win rate** and **83,000 GBP net profit** over the test period.

### Performance Summary (EUR/GBP Daily, Jan 2008 - Sep 2023)
- **Win Rate**: 82-92% (depending on profit target)
- **Optimal Win Rate**: 84% (with 125 pip profit target)
- **Net Profit**: ~83,000 GBP
- **Average Trade**: 75-267 GBP (depending on settings)
- **Largest Losing Trade**: 3,000 GBP (with 300 pip stop loss)
- **Total Trades**: ~300 trades

## 🎯 Strategy Rules

### Entry Conditions

#### LONG (BUY) Entry
Both conditions must be met:
1. **Close is in the lower 20% of the bar's range**
   - Calculation: `Close < Low + (High - Low) × 20%`
2. **Close is below the 50-period Simple Moving Average**

Entry: Buy on the close of the bar

#### SHORT (SELL) Entry
Both conditions must be met:
1. **Close is in the upper 20% of the bar's range**
   - Calculation: `Close > High - (High - Low) × 20%`
2. **Close is above the 50-period Simple Moving Average**

Entry: Sell short on the close of the bar

### Exit Conditions

The strategy uses **multiple exit methods** (in priority order):

1. **Stop & Reverse**
   - Exit long position when a short signal appears
   - Exit short position when a long signal appears
   - This is the primary exit mechanism

2. **Moving Average Cross Exit**
   - Exit long when close crosses **above** the 50 SMA
   - Exit short when close crosses **below** the 50 SMA

3. **Stop Loss** (Optional)
   - **Optimal**: 300 pips
   - Can be disabled by setting `UseStopLoss = false`

4. **Profit Target** (Optional)
   - **Optimal for net profit**: 125 pips
   - **Optimal for win rate**: 25 pips (94% win rate)
   - Can be disabled by setting `UseProfitTarget = false`

## 📈 Optimization Results

### Stop Loss Optimization
- **Test Range**: 0 to 500 pips (increments of 20)
- **Best Value**: 300 pips
- **Result**: Net profit of ~82,000 GBP
- **Wide Range**: Values from 125-500 pips all perform well

### Profit Target Optimization
- **Test Range**: 0 to 1,000 pips (increments of 25)
- **Best for Net Profit**: 125 pips
- **Best for Win Rate**: 25 pips (94% win rate)
- **Note**: Targets above ~350 pips rarely trigger (exits occur via MA cross or stop & reverse first)

## ⚙️ Default Settings

```
Symbol: EUR/GBP (Euro/Pound)
Timeframe: Daily (D1)
MA Period: 50
Range Percent: 20%
Stop Loss: 300 pips
Profit Target: 125 pips
Lot Size: 1.0
```

## 🚀 Quick Start Guide

### 1. Installation
1. Copy `MeanReversionDaily_82-92WinRate.mq5` to `MQL5/Experts/`
2. Compile in MetaEditor (F7)
3. Restart MetaTrader 5

### 2. Backtesting Setup
```
Symbol: EURGBP
Timeframe: D1 (Daily)
Period: 2008-01-01 to 2023-09-30
Model: Every tick (most accurate)
Initial Deposit: 10,000
Lot Size: 1.0
```

### 3. Recommended Settings
- **For Maximum Win Rate**: Set `ProfitTargetPips = 25`
- **For Maximum Net Profit**: Set `ProfitTargetPips = 125`
- **For Conservative Trading**: Set `ProfitTargetPips = 125` and `StopLossPips = 300`

### 4. Live Trading Considerations

⚠️ **Important**: The strategy enters on bar close. For live trading:

1. **Use Intraday Chart**: Program to enter 10 minutes before daily close
   - Use M5 or M15 chart
   - Enter at 23:50 (10 min before 00:00 close)
   - This avoids widened spreads at session open

2. **Alternative**: Enter 90 minutes after session open
   - Spreads normalize after initial volatility

3. **Spread Impact**: Results won't differ dramatically between:
   - Entering on close (backtest)
   - Entering 10 min before close (live)
   - Entering 90 min after open (live)

## 📊 Expected Performance Metrics

### With 125 Pip Profit Target (Optimal Net Profit)
- **Win Rate**: 84%
- **Net Profit**: ~83,000 GBP
- **Average Trade**: 75 GBP
- **Largest Loss**: 3,000 GBP (stop loss)
- **Total Trades**: ~300

### With 25 Pip Profit Target (Maximum Win Rate)
- **Win Rate**: 94%
- **Net Profit**: Lower than 125 pip target
- **Average Trade**: Smaller (more frequent exits)
- **Total Trades**: More trades (earlier exits)

### With No Profit Target (Stop & Reverse Only)
- **Win Rate**: 82%
- **Net Profit**: ~79,000 GBP
- **Average Trade**: 267 GBP (26.7 pips)
- **Largest Loss**: 6,700 GBP (675 pips) - **Use stop loss!**

## 🔍 Strategy Logic Explained

### Why It Works
1. **Mean Reversion**: Price extremes (close in upper/lower 20% of range) tend to revert
2. **Trend Filter**: 50 SMA ensures we're fading in the correct direction
   - Long only when below MA (expecting bounce up)
   - Short only when above MA (expecting pullback down)
3. **Stop & Reverse**: Captures trend changes quickly
4. **MA Cross Exit**: Takes profit as price returns to mean

### Visual Example
```
Price Chart with 50 SMA (cyan line):

[Above MA] ← Short entries here (close in upper 20% of range)
     |
     | 50 SMA
     |
[Below MA] ← Long entries here (close in lower 20% of range)
```

## ⚠️ Risk Warnings

### When Strategy Works Best
✅ Ranging/sideways markets  
✅ Mean-reverting currency pairs (EUR/GBP, EUR/USD)  
✅ Low to moderate volatility periods  
✅ Daily timeframe (reduces noise)

### When Strategy May Struggle
❌ Strong trending markets (can cause repeated losses)  
❌ High volatility breakouts  
❌ Major news events / gaps  
❌ Very small profit targets (high win rate but lower net profit)

### Risk Management Recommendations
- **Start Small**: Use 0.1-0.5 lots initially
- **Diversify**: Test on multiple pairs (EUR/USD, GBP/USD, etc.)
- **Monitor Drawdown**: Set daily/weekly loss limits
- **Use Stop Loss**: Always enable 300 pip stop loss
- **Position Size**: Risk 1-2% per trade maximum

## 🐛 Troubleshooting

### No Trades Opening
- ✅ Check AutoTrading is enabled (Ctrl+E in MT5)
- ✅ Verify symbol is EURGBP (or your test symbol)
- ✅ Ensure timeframe is Daily (D1)
- ✅ Check that range percent isn't too restrictive (try 15-25%)

### Too Many Trades
- ✅ Increase `RangePercent` to 25-30%
- ✅ Add additional filters (spread, time, etc.)

### Different Results vs Video
- ✅ Ensure using Daily timeframe (not M15/H1)
- ✅ Verify stop loss is set to 300 pips
- ✅ Check profit target matches your preference (125 for net profit, 25 for win rate)
- ✅ Use quality historical data (Dukascopy, etc.)

### Stop Loss Not Working
- ✅ Verify `UseStopLoss = true`
- ✅ Check `StopLossPips > 0`
- ✅ Ensure broker allows stop loss orders
- ✅ Check minimum stop level requirements

## 📝 Code Structure

### Key Functions
- `OnInit()`: Initializes moving average indicator
- `OnTick()`: Main trading logic (runs on each tick)
- `ManagePositions()`: Handles exit conditions (MA cross)
- `CheckEntrySignals()`: Checks for entry conditions
- `OpenBuy()` / `OpenSell()`: Opens positions with SL/TP

### Entry Logic
```mql5
// Long Entry
if (close < lower20Percent && close < ma[0])
    OpenBuy();

// Short Entry  
if (close > upper20Percent && close > ma[0])
    OpenSell();
```

### Exit Logic
```mql5
// Stop & Reverse (handled in CheckEntrySignals)
if (longSignal && hasShort) CloseShort();
if (shortSignal && hasLong) CloseLong();

// MA Cross Exit (handled in ManagePositions)
if (close crosses above MA && hasLong) CloseLong();
if (close crosses below MA && hasShort) CloseShort();
```

## 📚 References

- **Source**: Jared Goodwin's Mean Reversion Strategy Video Tutorial
- **Testing Software**: MultiCharts (PowerLanguage/EasyLanguage)
- **Similar Software**: TradeStation (compatible code structure)
- **Data Source**: OANDA Forex data

## 🔄 Comparison with Other Mean Reversion Strategies

### This Strategy vs. Rene's Mean Reversion EA
| Feature | This Strategy | Rene's EA |
|---------|--------------|-----------|
| Timeframe | Daily | M15 |
| MA Period | 50 | 360 |
| Entry Filter | Range % | MA Gap % |
| Additional Filters | None | RSI, ATR, Trend MA |
| Win Rate | 82-92% | 45-55% |
| Complexity | Simple | Complex |

### When to Use Each
- **This Strategy**: Simple, high win rate, daily timeframe, fewer trades
- **Rene's EA**: More filters, intraday, more trades, lower win rate but potentially higher profit factor

## 📞 Support

For issues or questions:
1. Check this documentation first
2. Review the code comments in the .mq5 file
3. Test in Strategy Tester before live trading
4. Verify all input parameters are set correctly

---

**Disclaimer**: Past performance does not guarantee future results. Always test thoroughly in demo accounts before live trading. Use proper risk management.
