# Mean Reversion EA - User Guide

## Overview
This Expert Advisor implements a mean reversion strategy based on Rene's video tutorial. It fades price extremes away from a long-term moving average with multiple confirmation filters.

## ✅ Key Features
- **Non-Repaint Logic**: Uses bar-close signals (shift=1) to prevent repainting
- **Multiple Filters**: MA trend, RSI momentum, ATR volatility, distance threshold
- **Proper Trade Management**: One position per direction, SL/TP, MA touch exits
- **Fully Customizable**: All parameters exposed as inputs
- **Magic Number Support**: Can run multiple instances on different symbols

## 📋 Installation
1. Copy `MeanReversionEA.mq5` to `MQL5/Experts/` folder
2. Compile in MetaEditor (F7) or it will auto-compile when you drag to chart
3. Drag EA onto chart (recommended: M15 timeframe)
4. Configure inputs in the EA properties dialog
5. Enable AutoTrading (Ctrl+E)

## ⚙️ Input Parameters

### Moving Average Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| `MA1_Timeframe` | M15 | Signal MA timeframe |
| `MA1_Period` | 360 | Signal MA period (long-term mean) |
| `MA2_Timeframe` | D1 | Trend filter MA timeframe |
| `MA2_Period` | 15 | Trend filter MA period |

### RSI Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| `RSI_Timeframe` | M15 | RSI timeframe |
| `RSI_Period` | 20 | RSI period |

### ATR Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| `ATR_Timeframe` | M15 | ATR timeframe |
| `ATR1_Period` | 10 | Fast ATR period |
| `ATR2_Period` | 20 | Slow ATR period |

### Entry Settings
| Parameter | Default | Description |
|-----------|---------|-------------|
| `MinMAGap` | 0.6 | Min distance from MA1 (%) to trigger |
| `Lots` | 0.1 | Position size |
| `TPPercent` | 1.5 | Take profit (% from entry) |
| `SLPercent` | 1.0 | Stop loss (% from entry) |

### Trade Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| `CloseAtMA` | true | Close at MA1 touch if in profit |
| `UseBarCloseSignals` | true | **CRITICAL**: Use bar-close (no repaint) |
| `MagicNumber` | 123456 | Unique ID for this EA instance |

## 🎯 Strategy Logic

### BUY Entry (all must be true)
1. ✅ Close < MA1 - (MA1 × 0.6%) — price far below mean
2. ✅ Close > MA2 (D1) — uptrend on higher TF
3. ✅ RSI[1] > RSI[0] — RSI rising (momentum)
4. ✅ ATR1 < ATR2 — volatility declining
5. ✅ No existing BUY position

### SELL Entry (all must be true)
1. ✅ Close > MA1 + (MA1 × 0.6%) — price far above mean
2. ✅ Close < MA2 (D1) — downtrend on higher TF
3. ✅ RSI[1] < RSI[0] — RSI falling (momentum)
4. ✅ ATR1 < ATR2 — volatility declining
5. ✅ No existing SELL position

### Exit Logic
- **SL hit**: Fixed % stop loss
- **TP hit**: Fixed % take profit
- **MA touch**: Close if price crosses MA1 AND in profit

## 🔒 Non-Repaint Protection

### What is Repainting?
Repainting occurs when an indicator or EA uses the current incomplete bar (shift=0) for signals. As the bar develops, signals can appear/disappear, causing misleading backtests.

### How This EA Prevents It
```mql5
// ✅ CORRECT: Uses closed bar [1]
int shift = UseBarCloseSignals ? 1 : 0;
if(CopyBuffer(handleMA1, 0, shift, 2, ma1) <= 0) return;
double close = iClose(_Symbol, MA1_Timeframe, shift);

// ❌ WRONG: Would use current bar [0]
// This would repaint as the bar develops
```

**Always keep `UseBarCloseSignals = true`** unless you're testing live tick behavior.

## 📊 Recommended Symbols
Best suited for **ranging/sideways markets**:
- ✅ EUR/USD
- ✅ GBP/USD
- ✅ AUD/CAD
- ✅ NZD/CAD
- ✅ EUR/GBP

Avoid highly trending or volatile pairs during strong trends.

## 🧪 Backtesting Guide

### Strategy Tester Setup
1. Open Strategy Tester (Ctrl+R)
2. Select `MeanReversionEA`
3. **Symbol**: EUR/USD (or other ranging pair)
4. **Timeframe**: M15
5. **Period**: 2015.01.01 - 2025.01.01 (10 years)
6. **Model**: Every tick (most accurate)
7. **Optimization**: Genetic algorithm

### Parameters to Optimize
| Parameter | Range | Step |
|-----------|-------|------|
| `MA1_Period` | 200-500 | 50 |
| `MA2_Period` | 10-30 | 5 |
| `MinMAGap` | 0.3-1.5 | 0.1 |
| `RSI_Period` | 10-30 | 5 |
| `ATR1_Period` | 5-20 | 5 |
| `TPPercent` | 0.5-3.0 | 0.5 |
| `SLPercent` | 0.5-2.0 | 0.5 |

### What to Look For
- ✅ **Profit Factor** > 1.3
- ✅ **Sharpe Ratio** > 0.5
- ✅ **Max Drawdown** < 30%
- ✅ **Win Rate** > 45%
- ✅ **Consistent equity curve** (no huge spikes)

## ⚠️ Risk Warnings

### Known Risks
1. **Trend Risk**: Strategy fails in strong trending markets
2. **Whipsaw Risk**: Multiple false signals in choppy conditions
3. **Gap Risk**: Weekend gaps can bypass SL
4. **Slippage**: Real execution differs from backtest
5. **Overfitting**: Optimized parameters may not work OOS

### Risk Management
- Start with **0.01-0.1 lots** on live account
- Use **max 2-5% risk per trade**
- Run on **multiple pairs** for diversification
- Monitor **daily/weekly drawdown limits**
- **Walk-forward test** before going live

## 🔧 Troubleshooting

### EA Not Opening Trades
- ✅ Check AutoTrading is enabled (Ctrl+E)
- ✅ Verify all indicators loading (check Experts log)
- ✅ Ensure `MinMAGap` not too large (try 0.4-0.6%)
- ✅ Check if ATR filter too restrictive (ATR1 < ATR2)
- ✅ Verify sufficient margin/balance

### Too Many Trades
- Increase `MinMAGap` (e.g., 0.8-1.0%)
- Tighten ATR filter (increase ATR2 period)
- Add cooldown period (modify code)

### Trades Not Closing at MA
- Verify `CloseAtMA = true`
- Check if trades are in profit (only closes if profit > 0)
- Ensure MA1 handle valid

### Backtest Shows Different Results
- Ensure `UseBarCloseSignals = true`
- Use quality tick data (Dukascopy recommended)
- Check spread settings match live conditions
- Verify no "Every tick based on real ticks" vs "1 minute OHLC"

## 📈 Performance Tips

### Optimization Strategy
1. **Coarse grid search** on key parameters (MA1, MinMAGap)
2. **Lock stable ranges**, fine-tune others
3. **Walk-forward validation** (multiple folds)
4. **OOS testing** on different years
5. **Monte Carlo** simulation for robustness

### Portfolio Approach
Run EA on 3-5 pairs simultaneously:
- EUR/USD (0.1 lots)
- GBP/USD (0.1 lots)
- AUD/CAD (0.1 lots)

This diversifies risk and smooths equity curve.

## 🐛 Code Review Results

### ✅ What's Correct
- Bar-close logic prevents repainting
- Position counting prevents multiple entries
- Proper SL/TP calculation with normalization
- MA touch exit only if in profit
- Handle validation in OnInit
- Proper array indexing with ArraySetAsSeries

### ⚠️ Potential Improvements
1. **Add spread filter**: Skip if spread > X pips
2. **Add time filter**: Avoid low-liquidity hours
3. **Add cooldown**: Wait N bars after close
4. **ATR-based SL/TP**: More adaptive than fixed %
5. **Partial exits**: Scale out at MA, trail remainder
6. **Max daily loss**: Stop trading after -X%

## 📝 Version History

### v1.00 (Current)
- Initial release based on Rene's tutorial
- Non-repaint bar-close logic
- All filters implemented (MA, RSI, ATR)
- Proper trade management
- Full input customization

## 📞 Support & Resources
- Original tutorial: Rene's YouTube channel
- MQL5 Reference: https://www.mql5.com/en/docs
- Strategy testing: Use Strategy Tester in MT5
- Community: MQL5.com forums

## 📄 License
Educational purposes. Use at your own risk. Past performance does not guarantee future results.

---

**Remember**: Always test thoroughly on demo before live trading! [[memory:8148547]]
