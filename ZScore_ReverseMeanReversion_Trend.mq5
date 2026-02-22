//+------------------------------------------------------------------+
//|                              ZScore_ReverseMeanReversion_Trend.mq5 |
//| Reverse Mean Reversion: trade pullback in trend → higher high    |
//| or lower low. Buy dip in uptrend, sell rally in downtrend.       |
//+------------------------------------------------------------------+
#property copyright "Z-Score Reverse Mean Reversion (Trend)"
#property version   "1.00"
#include <Trade/Trade.mqh>

//--- Inputs
input group "=== Symbol & Timeframe ==="
input string   InpSymbols     = "EURUSD,XAUUSD,GBPUSD";
input ENUM_TIMEFRAMES InpTF   = PERIOD_H1;

input group "=== Sigma (Z-Score) pullback trigger ==="
input int      InpLookback    = 20;   // Lookback for sigma
input double   InpSigmaPullbackLong  = -0.5;  // Buy when sigma at or below (pullback in uptrend)
input double   InpSigmaPullbackShort = 0.5;  // Sell when sigma at or above (pullback in downtrend)
input bool     InpRequireExtremeFirst = true; // Require prior extreme (sigma >2 or <-2) before pullback

input group "=== Trend filter ==="
input int      InpTrendMAPeriod = 50;  // Trend MA period (price vs MA)
input ENUM_MA_METHOD InpTrendMAMethod = MODE_EMA;

input group "=== Risk ==="
input double   InpRiskPct     = 1.0;
input double   InpATR_SL      = 1.5;
input double   InpATR_TP      = 2.0;   // Target continuation (e.g. higher high)
input int      InpMagic       = 60102;

input group "=== Behavior ==="
input int      InpMaxPosPerSymbol = 1;

//--- Globals
string   g_symbList[];
int      g_numSymbs = 0;
int      g_atrHndl[];
int      g_maHndl[];
CTrade   g_trade;

//+------------------------------------------------------------------+
//| Sigma score at bar (log-return z-score)                           |
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
//| Check if sigma was recently extreme (for pullback confirmation)   |
//+------------------------------------------------------------------+
bool HadRecentExtreme(string symbol, ENUM_TIMEFRAMES tf, int lookback, bool forLong, int barsBack = 10) {
    for(int b = 1; b <= barsBack; b++) {
        double s = GetSigmaScore(symbol, tf, lookback, b);
        if(s == EMPTY_VALUE) continue;
        if(forLong  && s <= -2.0) return true;  // Was oversold → now pullback buy valid
        if(!forLong && s >= 2.0) return true;   // Was overbought → now pullback sell valid
    }
    return false;
}

//+------------------------------------------------------------------+
//| Count positions                                                    |
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

double NormalizeLots(string symbol, double lots) {
    double minL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    if(step > 0) lots = MathRound(lots / step) * step;
    return MathMax(minL, MathMin(maxL, lots));
}

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
    ArrayResize(g_maHndl, g_numSymbs);
    ArrayResize(g_lastBar, g_numSymbs);
    ArrayInitialize(g_lastBar, 0);

    for(int i = 0; i < g_numSymbs; i++) {
        StringTrimLeft(g_symbList[i]);
        StringTrimRight(g_symbList[i]);
        string s = g_symbList[i];
        g_atrHndl[i] = iATR(s, InpTF, 14);
        g_maHndl[i]  = iMA(s, InpTF, InpTrendMAPeriod, 0, InpTrendMAMethod, PRICE_CLOSE);
        if(g_atrHndl[i] == INVALID_HANDLE || g_maHndl[i] == INVALID_HANDLE) {
            Print("Indicator failed ", s);
            return INIT_FAILED;
        }
    }

    g_trade.SetExpertMagicNumber(InpMagic);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    for(int i = 0; i < g_numSymbs; i++) {
        if(g_atrHndl[i] != INVALID_HANDLE) IndicatorRelease(g_atrHndl[i]);
        if(g_maHndl[i] != INVALID_HANDLE)  IndicatorRelease(g_maHndl[i]);
    }
}

//+------------------------------------------------------------------+
//| Uptrend: price > MA. Downtrend: price < MA.                       |
//+------------------------------------------------------------------+
int GetTrend(string symbol, int idx) {
    double close[], ma[];
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(ma, true);
    if(CopyClose(symbol, InpTF, 0, 1, close) < 1) return 0;
    if(CopyBuffer(g_maHndl[idx], 0, 0, 1, ma) < 1) return 0;
    if(close[0] > ma[0]) return 1;   // Uptrend
    if(close[0] < ma[0]) return -1; // Downtrend
    return 0;
}

void TryOpenBuy(string symbol, int idx, double atr) {
    if(CountPositions(symbol, InpMagic) >= InpMaxPosPerSymbol) return;
    double lots = LotSize(symbol, atr, InpMagic);
    if(lots <= 0) return;
    double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double sl = price - atr * InpATR_SL;
    double tp = price + atr * InpATR_TP;
    if(!g_trade.Buy(lots, symbol, price, sl, tp, "ZScore Reverse MR Trend"))
        Print("Buy failed ", GetLastError());
}

void TryOpenSell(string symbol, int idx, double atr) {
    if(CountPositions(symbol, InpMagic) >= InpMaxPosPerSymbol) return;
    double lots = LotSize(symbol, atr, InpMagic);
    if(lots <= 0) return;
    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    double sl = price + atr * InpATR_SL;
    double tp = price - atr * InpATR_TP;
    if(!g_trade.Sell(lots, symbol, price, sl, tp, "ZScore Reverse MR Trend"))
        Print("Sell failed ", GetLastError());
}

//+------------------------------------------------------------------+
//| OnTick: in uptrend buy pullback (low sigma); in downtrend sell   |
//| pullback (high sigma). Target continuation (higher high / lower low). |
//+------------------------------------------------------------------+
void OnTick() {
    for(int i = 0; i < g_numSymbs; i++) {
        string symbol = g_symbList[i];
        if(!IsNewBar(symbol, InpTF, i)) continue;

        double sigma = GetSigmaScore(symbol, InpTF, InpLookback, 0);
        if(sigma == EMPTY_VALUE) continue;

        int trend = GetTrend(symbol, i);
        if(trend == 0) continue;

        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(g_atrHndl[i], 0, 0, 1, atr) < 1) continue;
        double atrVal = atr[0];

        // Uptrend: buy pullback (sigma at or below threshold) → target higher high
        if(trend == 1 && sigma <= InpSigmaPullbackLong) {
            if(InpRequireExtremeFirst && !HadRecentExtreme(symbol, InpTF, InpLookback, true))
                continue;
            TryOpenBuy(symbol, i, atrVal);
        }
        // Downtrend: sell pullback (sigma at or above threshold) → target lower low
        if(trend == -1 && sigma >= InpSigmaPullbackShort) {
            if(InpRequireExtremeFirst && !HadRecentExtreme(symbol, InpTF, InpLookback, false))
                continue;
            TryOpenSell(symbol, i, atrVal);
        }
    }
}
