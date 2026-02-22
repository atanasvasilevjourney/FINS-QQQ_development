//+------------------------------------------------------------------+
//|                                                Dyna Mean&Mom.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade/Trade.mqh>
#include <Math/Stat/Math.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//|  Enhanced Mean-Reversion + Momentum EA                           |
//+------------------------------------------------------------------+

//--- Input settings
input string Symbols = "XAUUSD,GBPUSD,USDCAD,USDJPY";
input int    TakeProfit = 150;        // TP in points
input int    StopLoss = 100;           // SL in points
input int    MAPeriod = 20;
input int    MomentumPeriod = 5;
input double Z_Threshold = 2.0;
input double Mom_Threshold = 1.5;     // Price change in standard deviations
input double RiskPercent_High = 1.5, RiskPercent_Mod = 1.0, RiskPercent_Low = 0.5;
input int    MagicNumber = 54321;   // EA magic number

//--- Global parameters
string symb_List[];
int Num_symbs = 0;

// Indicator handles arrays
int MA_hndl[];
int STDev_hndl[];
int ATR_hndl[];

//+------------------------------------------------------------------+
//| Returns true on the first tick of a new H1 bar                    |
//+------------------------------------------------------------------+
bool isNewBar() {
    static datetime lastBar = 0;
    datetime t[];
    if(CopyTime(_Symbol, PERIOD_H1, 0, 1, t) < 1) return false;
    if(t[0] == lastBar) return false;
    lastBar = t[0];
    return true;
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
    //--- Split symbol list
    ushort separator = StringGetCharacter(",", 0);
    StringSplit(Symbols, separator, symb_List);
    Num_symbs = ArraySize(symb_List);

    //--- Resize arrays
    ArrayResize(MA_hndl, Num_symbs);
    ArrayResize(STDev_hndl, Num_symbs);
    ArrayResize(ATR_hndl, Num_symbs);

    //--- Prepare each symbol
    for (int i = 0; i < Num_symbs; i++) {
        string symbol = symb_List[i];
        StringTrimLeft(symbol);
        StringTrimRight(symbol);
        symb_List[i] = symbol;

        //--- Create indicator handles
        MA_hndl[i] = iMA(symbol, PERIOD_H1, MAPeriod, 0, MODE_SMA, PRICE_CLOSE);
        STDev_hndl[i] = iStdDev(symbol, PERIOD_H1, MAPeriod, 0, MODE_SMA, PRICE_CLOSE);
        ATR_hndl[i] = iATR(symbol, PERIOD_H1, 14);

        if (MA_hndl[i] == INVALID_HANDLE || STDev_hndl[i] == INVALID_HANDLE || ATR_hndl[i] == INVALID_HANDLE) {
            Print("Failed to create indicator handles for ", symbol);
            return INIT_FAILED;
        }
    }

    //--- Set magic number for trade identification
    trade.SetExpertMagicNumber(MagicNumber);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    for(int i = 0; i < Num_symbs; i++) {
        if(MA_hndl[i] != INVALID_HANDLE)   IndicatorRelease(MA_hndl[i]);
        if(STDev_hndl[i] != INVALID_HANDLE) IndicatorRelease(STDev_hndl[i]);
        if(ATR_hndl[i] != INVALID_HANDLE)   IndicatorRelease(ATR_hndl[i]);
    }
}

//+------------------------------------------------------------------+
//|          Mean and Momentum Signal Generator                      |
//+------------------------------------------------------------------+
void MeanAndMomentum(string symbol, int idx) {
    //--- Get current price data
    MqlRates current[];
    if(CopyRates(symbol, PERIOD_H1, 0, 1, current) < 1) return;
    double close = current[0].close;

    //--- Get historical price for momentum calculation
    MqlRates historical[];
    if(CopyRates(symbol, PERIOD_H1, MomentumPeriod, 1, historical) < 1) return;
    double histClose = historical[0].close;

    //--- Get indicator values
    double ma[1], stddev[1], atr[1];
    if(CopyBuffer(MA_hndl[idx], 0, 0, 1, ma) < 1) return;
    if(CopyBuffer(STDev_hndl[idx], 0, 0, 1, stddev) < 1) return;
    if(CopyBuffer(ATR_hndl[idx], 0, 0, 1, atr) < 1) return;

    //--- Calculate metrics
    double momentum = close - histClose;
    double zscore = (stddev[0] > 0) ? (close - ma[0]) / stddev[0] : 0;
    double momThreshold = Mom_Threshold * stddev[0]; // Dynamic momentum threshold

    //--- Determine signal type
    int signal = 0;
    double riskPercent = 0;

    bool meanReversionLong = (zscore < -Z_Threshold);
    bool meanReversionShort = (zscore > Z_Threshold);
    bool momentumLong = (momentum > momThreshold);
    bool momentumShort = (momentum < -momThreshold);

    //--- Signal priority: Momentum > Mean Reversion
    if(momentumLong && meanReversionLong) {
        signal = 1;
        riskPercent = RiskPercent_High; // Strong signal
    }
    else if(momentumShort && meanReversionShort) {
        signal = -1;
        riskPercent = RiskPercent_High;
    }
    else if(momentumLong) {
        signal = 1;
        riskPercent = RiskPercent_Mod;
    }
    else if(momentumShort) {
        signal = -1;
        riskPercent = RiskPercent_Mod;
    }
    else if(meanReversionLong) {
        signal = 1;
        riskPercent = RiskPercent_Low;
    }
    else if(meanReversionShort) {
        signal = -1;
        riskPercent = RiskPercent_Low;
    }

    //--- Exit if no signal
    if(signal == 0) return;

    //--- Check existing positions for this symbol and magic
    for(int p = PositionsTotal() - 1; p >= 0; p--) {
        ulong ticket = PositionGetTicket(p);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        long positionType = PositionGetInteger(POSITION_TYPE);
        if((positionType == POSITION_TYPE_BUY && signal == 1) ||
           (positionType == POSITION_TYPE_SELL && signal == -1)) {
            return; // Already in position in same direction
        }
        trade.PositionClose(ticket);
        Sleep(100);
        break; // One position per symbol for this EA
    }

    //--- Calculate position size
    double lotSize = CalculatePositionSize(symbol, riskPercent, atr[0]);
    if(lotSize <= 0) return;

    //--- Execute trade
    ExecuteTrade(signal == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, symbol, lotSize, idx);
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk and volatility             |
//+------------------------------------------------------------------+
double CalculatePositionSize(string symbol, double riskPercent, double atrValue) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (riskPercent / 100.0);

    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

    if(point <= 0 || tickValue <= 0 || tickSize <= 0) {
        Print("Invalid symbol parameters for ", symbol);
        return 0;
    }

    // Use ATR-based stop loss
    double slDistance = atrValue * 1.5;
    double lossPerLot = slDistance * (tickValue / tickSize);

    if(lossPerLot <= 0) {
        Print("Invalid loss calculation for ", symbol);
        return 0;
    }

    double lots = riskAmount / lossPerLot;
    lots = NormalizeLots(symbol, lots);

    return lots;
}

//+------------------------------------------------------------------+
//| Normalize lot size to broker requirements                        |
//+------------------------------------------------------------------+
double NormalizeLots(string symbol, double lots) {
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

    if(lotStep > 0) {
        lots = MathRound(lots / lotStep) * lotStep;
    }

    lots = MathMax(minLot, MathMin(maxLot, lots));
    return lots;
}

//+------------------------------------------------------------------+
//| Execute trade with proper risk management                        |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE tradeType, string symbol, double lotSize, int idx) {
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double price = (tradeType == ORDER_TYPE_BUY) ?
                   SymbolInfoDouble(symbol, SYMBOL_ASK) :
                   SymbolInfoDouble(symbol, SYMBOL_BID);

    // Get current ATR for dynamic stop levels
    double atr[1];
    if(idx >= 0 && CopyBuffer(ATR_hndl[idx], 0, 0, 1, atr) > 0) {
        double slDistance = atr[0] * 1.5;
        double tpDistance = atr[0] * 2.5;

        double sl = (tradeType == ORDER_TYPE_BUY) ?
                    price - slDistance :
                    price + slDistance;

        double tp = (tradeType == ORDER_TYPE_BUY) ?
                    price + tpDistance :
                    price - tpDistance;

        trade.PositionOpen(symbol, tradeType, lotSize, price, sl, tp, "MR-Mom System");
    }
    else {
        // Fallback to fixed stops if ATR fails
        double sl = (tradeType == ORDER_TYPE_BUY) ?
                    price - (StopLoss * point) :
                    price + (StopLoss * point);

        double tp = (tradeType == ORDER_TYPE_BUY) ?
                    price + (TakeProfit * point) :
                    price - (TakeProfit * point);

        trade.PositionOpen(symbol, tradeType, lotSize, price, sl, tp, "MR-Mom System");
    }
}

//+------------------------------------------------------------------+
//| Find symbol position in array                                    |
//+------------------------------------------------------------------+
int ArrayPosition(string symbol) {
    for(int i = 0; i < Num_symbs; i++) {
        if(symb_List[i] == symbol) return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if(isNewBar()) {
        for(int i = 0; i < Num_symbs; i++) {
            MeanAndMomentum(symb_List[i], i);
        }
    }
}
