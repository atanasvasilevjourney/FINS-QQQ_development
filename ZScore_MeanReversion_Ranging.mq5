//+------------------------------------------------------------------+
//|                                    ZScore_MeanReversion_Ranging.mq5 |
//| Z-score Mean Reversion: trade local high→pullback / low→pullback |
//| For ranging markets (Forex, Gold). Fade extremes.                  |
//+------------------------------------------------------------------+
#property copyright "Z-Score Mean Reversion (Ranging)"
#property version   "1.00"
#include <Trade/Trade.mqh>

//--- Inputs
input group "=== Symbol & Timeframe ==="
input string   InpSymbols     = "EURUSD,XAUUSD,GBPUSD";  // Symbols (Forex, Gold)
input ENUM_TIMEFRAMES InpTF   = PERIOD_H1;               // Timeframe

input group "=== Sigma (Z-Score) ==="
input int      InpLookback    = 20;    // Lookback bars for sigma
input double   InpUpperSigma  = 2.0;   // Sell when sigma above (overbought)
input double   InpLowerSigma  = -2.0;  // Buy when sigma below (oversold)

input group "=== Ranging Filter (optional) ==="
input bool     InpUseADX      = true;  // Use ADX to filter ranging only
input int      InpADXPeriod   = 14;     // ADX period
input double   InpADXMax      = 25.0;  // Max ADX = ranging (no trade if ADX > this)

input group "=== Risk ==="
input double   InpRiskPct     = 1.0;   // Risk per trade (% of balance)
input double   InpATR_SL      = 1.5;   // SL in ATR multiples
input double   InpATR_TP      = 1.5;   // TP in ATR multiples (pullback target)
input int      InpMagic       = 60101; // Magic number

input group "=== Behavior ==="
input int      InpMaxPosPerSymbol = 1; // Max positions per symbol

//--- Globals
string   g_symbList[];
int      g_numSymbs = 0;
int      g_atrHndl[];
int      g_adxHndl[];
CTrade   g_trade;

//+------------------------------------------------------------------+
//| Compute current bar sigma score (log-return z-score)             |
//+------------------------------------------------------------------+
double GetSigmaScore(string symbol, ENUM_TIMEFRAMES tf, int lookback, int barIdx = 0) {
    double close[];
    ArraySetAsSeries(close, true);
    if(CopyClose(symbol, tf, 0, lookback + 2 + barIdx, close) < lookback + 2 + barIdx)
        return EMPTY_VALUE;

    int i = barIdx;
    if(i + lookback + 1 >= ArraySize(close)) return EMPTY_VALUE;

    double sum_returns = 0, sum_squared = 0;
    int valid = 0;
    for(int j = 0; j < lookback; j++) {
        int idx1 = i + j, idx2 = i + j + 1;
        if(idx2 < ArraySize(close) && close[idx1] > 0 && close[idx2] > 0) {
            double lr = MathLog(close[idx1] / close[idx2]);
            sum_returns += lr;
            sum_squared += lr * lr;
            valid++;
        }
    }
    if(valid < lookback) return EMPTY_VALUE;

    double current_return = (close[i] > 0 && close[i+1] > 0) ? MathLog(close[i] / close[i+1]) : 0;
    double mean = sum_returns / valid;
    double var = (sum_squared / valid) - (mean * mean);
    if(var < 0) var = 0;
    double stdev = MathSqrt(var);
    if(stdev < 1e-10) return 0;
    return (current_return - mean) / stdev;
}

//+------------------------------------------------------------------+
//| Get ADX from handle (buffer 0 = main ADX)                         |
//+------------------------------------------------------------------+
double GetADX(int adxHandle, int bar = 0) {
    if(adxHandle == INVALID_HANDLE) return 0;
    double buf[];
    ArraySetAsSeries(buf, true);
    if(CopyBuffer(adxHandle, 0, bar, 1, buf) < 1) return 0;
    return buf[0];
}

//+------------------------------------------------------------------+
//| Count positions for symbol and magic                              |
//+------------------------------------------------------------------+
int CountPositions(string symbol, int magic) {
    int n = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionGetTicket(i) == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
        n++;
    }
    return n;
}

//+------------------------------------------------------------------+
//| Normalize lot size                                                |
//+------------------------------------------------------------------+
double NormalizeLots(string symbol, double lots) {
    double minL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    if(step > 0) lots = MathRound(lots / step) * step;
    return MathMax(minL, MathMin(maxL, lots));
}

//+------------------------------------------------------------------+
//| Position size from risk % and ATR                                 |
//+------------------------------------------------------------------+
double LotSize(string symbol, double atr, int magic) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmt = balance * (InpRiskPct / 100.0);
    double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
    double tickSz  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tickSz <= 0 || tickVal <= 0) return 0;
    double slDist = atr * InpATR_SL;
    double lossPerLot = slDist * (tickVal / tickSz);
    if(lossPerLot <= 0) return 0;
    return NormalizeLots(symbol, riskAmt / lossPerLot);
}

//+------------------------------------------------------------------+
//| New bar on TF for symbol (per-symbol to allow multi-symbol)       |
//+------------------------------------------------------------------+
datetime g_lastBar[];
bool IsNewBar(string symbol, ENUM_TIMEFRAMES tf, int symbolIndex) {
    datetime t[];
    if(CopyTime(symbol, tf, 0, 1, t) < 1) return false;
    if(t[0] == g_lastBar[symbolIndex]) return false;
    g_lastBar[symbolIndex] = t[0];
    return true;
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit() {
    ushort sep = StringGetCharacter(",", 0);
    StringSplit(InpSymbols, sep, g_symbList);
    g_numSymbs = ArraySize(g_symbList);
    if(g_numSymbs <= 0) { Print("No symbols"); return INIT_FAILED; }

    ArrayResize(g_atrHndl, g_numSymbs);
    ArrayResize(g_adxHndl, g_numSymbs);
    ArrayResize(g_lastBar, g_numSymbs);
    ArrayInitialize(g_lastBar, 0);

    for(int i = 0; i < g_numSymbs; i++) {
        StringTrimLeft(g_symbList[i]);
        StringTrimRight(g_symbList[i]);
        string s = g_symbList[i];
        g_atrHndl[i] = iATR(s, InpTF, 14);
        g_adxHndl[i] = InpUseADX ? iADX(s, InpTF, InpADXPeriod) : INVALID_HANDLE;
        if(g_atrHndl[i] == INVALID_HANDLE) { Print("ATR failed ", s); return INIT_FAILED; }
    }

    g_trade.SetExpertMagicNumber(InpMagic);
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    for(int i = 0; i < g_numSymbs; i++) {
        if(g_atrHndl[i] != INVALID_HANDLE) IndicatorRelease(g_atrHndl[i]);
        if(g_adxHndl[i] != INVALID_HANDLE) IndicatorRelease(g_adxHndl[i]);
    }
}

//+------------------------------------------------------------------+
//| Open sell: overbought (local high) → target pullback below        |
//+------------------------------------------------------------------+
void TryOpenSell(string symbol, int idx, double sigma, double atr) {
    if(CountPositions(symbol, InpMagic) >= InpMaxPosPerSymbol) return;

    double lots = LotSize(symbol, atr, InpMagic);
    if(lots <= 0) return;

    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    double sl = price + atr * InpATR_SL;
    double tp = price - atr * InpATR_TP;

    if(g_trade.Sell(lots, symbol, price, sl, tp, "ZScore MR Ranging"))
        return;
    Print("Sell failed ", GetLastError());
}

//+------------------------------------------------------------------+
//| Open buy: oversold (local low) → target pullback above            |
//+------------------------------------------------------------------+
void TryOpenBuy(string symbol, int idx, double sigma, double atr) {
    if(CountPositions(symbol, InpMagic) >= InpMaxPosPerSymbol) return;

    double lots = LotSize(symbol, atr, InpMagic);
    if(lots <= 0) return;

    double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double sl = price - atr * InpATR_SL;
    double tp = price + atr * InpATR_TP;

    if(g_trade.Buy(lots, symbol, price, sl, tp, "ZScore MR Ranging"))
        return;
    Print("Buy failed ", GetLastError());
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick() {
    for(int i = 0; i < g_numSymbs; i++) {
        string symbol = g_symbList[i];
        if(!IsNewBar(symbol, InpTF, i)) continue;

        double sigma = GetSigmaScore(symbol, InpTF, InpLookback, 0);
        if(sigma == EMPTY_VALUE) continue;

        if(InpUseADX && g_adxHndl[i] != INVALID_HANDLE) {
            double adx = GetADX(g_adxHndl[i], 0);
            if(adx > InpADXMax) continue; // Trending: skip mean reversion
        }

        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(g_atrHndl[i], 0, 0, 1, atr) < 1) continue;
        double atrVal = atr[0];

        // Overbought → sell (local high to pullback)
        if(sigma >= InpUpperSigma)
            TryOpenSell(symbol, i, sigma, atrVal);
        // Oversold → buy (local low to pullback)
        else if(sigma <= InpLowerSigma)
            TryOpenBuy(symbol, i, sigma, atrVal);
    }
}
