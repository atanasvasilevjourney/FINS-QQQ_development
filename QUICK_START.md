# Quick Start Guide - Mean Reversion EA

## 🚀 5-Minute Setup

### Step 1: Install
1. Copy `MeanReversionEA.mq5` (or `MeanReversionEA_Enhanced.mq5`) to:
   ```
   MT5 Data Folder → MQL5 → Experts
   ```
2. Restart MetaTrader 5 or press F4 to refresh

### Step 2: Backtest (Recommended First)
1. Press `Ctrl+R` to open Strategy Tester
2. Select `MeanReversionEA` from Expert Advisor dropdown
3. **Symbol**: EUR/USD
4. **Timeframe**: M15
5. **Period**: 2020.01.01 - 2024.12.31
6. **Model**: Every tick based on real ticks
7. Click **Start**

### Step 3: Review Results
✅ **Good signs**:
- Profit Factor > 1.3
- Equity curve steadily rising
- Max Drawdown < 30%
- Win rate 45-55%

❌ **Bad signs**:
- Profit Factor < 1.1
- Huge drawdown spikes
- Very few trades (< 10/year)

### Step 4: Optimize (Optional)
1. In Strategy Tester, click **Optimization**
2. Enable optimization for:
   - `MA1_Period`: 200 to 500, step 50
   - `MinMAGap`: 0.3 to 1.5, step 0.1
   - `TPPercent`: 0.5 to 3.0, step 0.5
3. **Optimization criterion**: Balance
4. Click **Start**

### Step 5: Demo Test
1. Open EUR/USD M15 chart
2. Drag `MeanReversionEA` onto chart
3. **Set inputs**:
   - `Lots`: 0.01 (micro lot)
   - `UseBarCloseSignals`: **true** (critical!)
   - `UseSpreadFilter`: true (Enhanced version)
   - `CloseAtMA`: true
4. Click **OK**
5. Enable AutoTrading (Ctrl+E)

### Step 6: Monitor
- Check **Experts** tab for logs
- Wait for signals (may take hours/days)
- Verify trades match backtest behavior

## 📋 Default Settings (Tutorial)

```
MA1_Period = 360
MA1_Timeframe = M15
MA2_Period = 15
MA2_Timeframe = D1
RSI_Period = 20
ATR1_Period = 10
ATR2_Period = 20
MinMAGap = 0.6%
Lots = 0.1
TPPercent = 1.5%
SLPercent = 1.0%
```

## ⚠️ Critical Settings

### MUST BE TRUE
- `UseBarCloseSignals = true` → Prevents repainting

### RECOMMENDED TRUE (Enhanced version)
- `UseSpreadFilter = true` → Avoids high-spread entries
- `CloseAtMA = true` → Exits at mean reversion

### OPTIONAL
- `UseTimeFilter = false` → Enable if you want to avoid Asian session
- `UseATRforSLTP = false` → Enable for adaptive risk

## 🎯 Expected Performance (EUR/USD, M15, 2015-2025)

| Metric | Expected |
|--------|----------|
| Total Trades | 200-400 |
| Win Rate | 45-55% |
| Profit Factor | 1.2-1.8 |
| Max Drawdown | 15-30% |
| Avg Trade | 0.5-1.5% |
| Trades/Year | 20-50 |

## 🐛 Troubleshooting

### No Trades Opening
- ✅ AutoTrading enabled? (Ctrl+E)
- ✅ Check Experts log for errors
- ✅ Reduce `MinMAGap` to 0.4-0.5%
- ✅ Verify indicators loading (no errors in log)

### Too Many Trades
- ✅ Increase `MinMAGap` to 0.8-1.0%
- ✅ Enable `UseSpreadFilter` (Enhanced)
- ✅ Increase `CooldownBars` (Enhanced)

### Trades Not Closing at MA
- ✅ Set `CloseAtMA = true`
- ✅ Check if trades are in profit (only closes if profit > 0)

### Different Results vs Backtest
- ✅ Ensure `UseBarCloseSignals = true`
- ✅ Use quality tick data (Dukascopy)
- ✅ Match spread settings to live conditions

## 📊 Recommended Symbols

| Symbol | Timeframe | Reason |
|--------|-----------|--------|
| EUR/USD | M15 | Low spread, ranging |
| GBP/USD | M15 | Good volatility |
| AUD/CAD | M15 | Ranging behavior |
| NZD/CAD | M15 | Mean-reverting |
| EUR/GBP | M15 | Low volatility |

**Avoid**: USD/JPY (trending), exotic pairs (high spread)

## 🔐 Risk Management

### Position Sizing
- **Conservative**: 0.01 lots per $1000
- **Moderate**: 0.05 lots per $1000
- **Aggressive**: 0.1 lots per $1000

### Portfolio Approach
Run on 3-5 pairs simultaneously:
```
EUR/USD: 0.1 lots
GBP/USD: 0.1 lots
AUD/CAD: 0.1 lots
```

### Daily Limits
- Max 3 trades per symbol per day
- Stop trading if daily loss > 3%

## 📞 Next Steps

1. ✅ Backtest on EUR/USD M15 (2020-2024)
2. ✅ Optimize key parameters
3. ✅ Forward test on demo (1-2 weeks)
4. ✅ Walk-forward validation
5. ✅ Start live with micro lots (0.01)
6. ✅ Scale up after 1 month of consistent results

## 📚 Full Documentation
- `USER_GUIDE.md` → Complete parameter reference
- `CODE_REVIEW.md` → Logic verification
- `STRATEGY_RULES.md` → Entry/exit conditions
- `README.md` → Strategy overview

---

**Remember**: This is a mean-reversion strategy. It works best in ranging markets and struggles in strong trends. Always test thoroughly before live trading! [[memory:8148547]]
