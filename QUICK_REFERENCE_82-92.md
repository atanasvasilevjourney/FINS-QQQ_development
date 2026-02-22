# Quick Reference - Mean Reversion 82-92% Win Rate Strategy

## 🎯 One-Page Summary

### Entry Rules
**LONG**: Close < Lower 20% of Range AND Close < 50 SMA  
**SHORT**: Close > Upper 20% of Range AND Close > 50 SMA

### Exit Rules (Priority Order)
1. Stop & Reverse (opposite signal)
2. MA Cross (close crosses MA)
3. Stop Loss: 300 pips
4. Profit Target: 125 pips (or 25 for max win rate)

### Optimal Settings
```
Symbol: EUR/GBP
Timeframe: Daily (D1)
MA Period: 50
Stop Loss: 300 pips
Profit Target: 125 pips (net profit) OR 25 pips (win rate)
```

### Performance
- **Win Rate**: 84% (125 pip target) to 94% (25 pip target)
- **Net Profit**: ~83,000 GBP (125 pip target)
- **Trades**: ~300 over 15 years

## ⚡ Quick Setup

1. **Load EA**: `MeanReversionDaily_82-92WinRate.mq5`
2. **Set Symbol**: EURGBP
3. **Set Timeframe**: D1
4. **Set Parameters**:
   - `StopLossPips = 300`
   - `ProfitTargetPips = 125` (or 25)
   - `Lots = 1.0`
5. **Enable AutoTrading**: Ctrl+E
6. **Backtest First**: Strategy Tester (2008-2023)

## 🔧 Parameter Guide

| Parameter | Default | Range | Purpose |
|-----------|---------|-------|---------|
| `MA_Period` | 50 | 30-100 | Moving average length |
| `RangePercent` | 20 | 15-30 | Range threshold % |
| `StopLossPips` | 300 | 0-500 | Stop loss distance |
| `ProfitTargetPips` | 125 | 0-1000 | Take profit distance |
| `Lots` | 1.0 | 0.01+ | Position size |

## 📊 Win Rate vs Profit Target

| Profit Target | Win Rate | Net Profit | Use Case |
|---------------|----------|------------|----------|
| 25 pips | 94% | Lower | Maximum win rate |
| 125 pips | 84% | Highest | Optimal balance |
| 350+ pips | 82% | Similar | Rarely triggers |

## ⚠️ Important Notes

- ✅ **Always use Daily timeframe** (D1)
- ✅ **Enter on bar close** (non-repaint)
- ✅ **Use stop loss** (300 pips optimal)
- ✅ **Test before live trading**
- ❌ **Don't use on trending markets**
- ❌ **Don't disable stop loss**

## 🚨 Common Issues

**No trades?** → Check AutoTrading, verify symbol/timeframe  
**Too many trades?** → Increase `RangePercent` to 25-30%  
**Different results?** → Verify Daily timeframe, check data quality  
**SL not working?** → Enable `UseStopLoss = true`, check broker settings

---

For full documentation, see `MEAN_REVERSION_82-92_WINRATE.md`
