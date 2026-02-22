//+------------------------------------------------------------------+
//|                                            MeanReversionEA.mq5   |
//|                                  Based on Rene's Video Tutorial  |
//|                        Mean Reversion Strategy - Non-Repaint     |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA - Tutorial Implementation"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input parameters
input group "=== Moving Average Settings ==="
input ENUM_TIMEFRAMES MA1_Timeframe = PERIOD_M15;      // MA1 Timeframe (Signal)
input int             MA1_Period = 360;                 // MA1 Period
input ENUM_TIMEFRAMES MA2_Timeframe = PERIOD_D1;       // MA2 Timeframe (Trend Filter)
input int             MA2_Period = 15;                  // MA2 Period

input group "=== RSI Settings ==="
input ENUM_TIMEFRAMES RSI_Timeframe = PERIOD_M15;      // RSI Timeframe
input int             RSI_Period = 20;                  // RSI Period

input group "=== ATR Settings ==="
input ENUM_TIMEFRAMES ATR_Timeframe = PERIOD_M15;      // ATR Timeframe
input int             ATR1_Period = 10;                 // ATR1 Period (Fast)
input int             ATR2_Period = 20;                 // ATR2 Period (Slow)

input group "=== Entry Settings ==="
input double          MinMAGap = 0.6;                   // Min MA Gap (%)
input double          Lots = 0.1;                       // Lot Size
input double          TPPercent = 1.5;                  // Take Profit (%)
input double          SLPercent = 1.0;                  // Stop Loss (%)

input group "=== Trade Management ==="
input bool            CloseAtMA = true;                 // Close at MA Touch (in profit)
input bool            UseBarCloseSignals = true;        // Use Bar Close Signals (No Repaint)
input int             MagicNumber = 123456;             // Magic Number

//--- Global variables
int handleMA1;
int handleMA2;
int handleRSI;
int handleATR1;
int handleATR2;

int barsTotal = 0;

CTrade trade;
CPositionInfo position;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set magic number
   trade.SetExpertMagicNumber(MagicNumber);
   
   //--- Create indicator handles
   handleMA1 = iMA(_Symbol, MA1_Timeframe, MA1_Period, 0, MODE_SMA, PRICE_CLOSE);
   if(handleMA1 == INVALID_HANDLE)
   {
      Print("Error creating MA1 handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   handleMA2 = iMA(_Symbol, MA2_Timeframe, MA2_Period, 0, MODE_SMA, PRICE_CLOSE);
   if(handleMA2 == INVALID_HANDLE)
   {
      Print("Error creating MA2 handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   handleRSI = iRSI(_Symbol, RSI_Timeframe, RSI_Period, PRICE_CLOSE);
   if(handleRSI == INVALID_HANDLE)
   {
      Print("Error creating RSI handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   handleATR1 = iATR(_Symbol, ATR_Timeframe, ATR1_Period);
   if(handleATR1 == INVALID_HANDLE)
   {
      Print("Error creating ATR1 handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   handleATR2 = iATR(_Symbol, ATR_Timeframe, ATR2_Period);
   if(handleATR2 == INVALID_HANDLE)
   {
      Print("Error creating ATR2 handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   Print("Mean Reversion EA initialized successfully");
   Print("Use Bar Close Signals: ", UseBarCloseSignals ? "YES (No Repaint)" : "NO (Live Tick)");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(handleMA1 != INVALID_HANDLE) IndicatorRelease(handleMA1);
   if(handleMA2 != INVALID_HANDLE) IndicatorRelease(handleMA2);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleATR1 != INVALID_HANDLE) IndicatorRelease(handleATR1);
   if(handleATR2 != INVALID_HANDLE) IndicatorRelease(handleATR2);
   
   Print("Mean Reversion EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for new bar (non-repaint logic)
   if(UseBarCloseSignals)
   {
      int bars = iBars(_Symbol, MA1_Timeframe);
      if(bars == barsTotal)
         return; // No new bar, exit
      barsTotal = bars;
   }
   
   //--- Manage existing positions first
   ManagePositions();
   
   //--- Check for entry signals
   CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManagePositions()
{
   //--- Get current prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Get MA1 value for exit logic
   double ma1[];
   ArraySetAsSeries(ma1, true);
   if(CopyBuffer(handleMA1, 0, 1, 1, ma1) <= 0)
      return;
   
   //--- Loop through all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i))
         continue;
      
      if(position.Symbol() != _Symbol)
         continue;
      
      if(position.Magic() != MagicNumber)
         continue;
      
      //--- Check BUY position
      if(position.PositionType() == POSITION_TYPE_BUY)
      {
         if(CloseAtMA && position.Profit() > 0)
         {
            // Close if price crosses above MA1
            if(bid > ma1[0])
            {
               trade.PositionClose(position.Ticket());
               Print("BUY position closed at MA touch. Profit: ", position.Profit());
            }
         }
      }
      
      //--- Check SELL position
      if(position.PositionType() == POSITION_TYPE_SELL)
      {
         if(CloseAtMA && position.Profit() > 0)
         {
            // Close if price crosses below MA1
            if(ask < ma1[0])
            {
               trade.PositionClose(position.Ticket());
               Print("SELL position closed at MA touch. Profit: ", position.Profit());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   //--- Count existing positions
   int counterBuy = 0;
   int counterSell = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i))
         continue;
      
      if(position.Symbol() != _Symbol)
         continue;
      
      if(position.Magic() != MagicNumber)
         continue;
      
      if(position.PositionType() == POSITION_TYPE_BUY)
         counterBuy++;
      
      if(position.PositionType() == POSITION_TYPE_SELL)
         counterSell++;
   }
   
   //--- Get indicator values (use closed bar [1] for non-repaint)
   int shift = UseBarCloseSignals ? 1 : 0;
   
   double ma1[], ma2[], rsi[], atr1[], atr2[];
   ArraySetAsSeries(ma1, true);
   ArraySetAsSeries(ma2, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr1, true);
   ArraySetAsSeries(atr2, true);
   
   if(CopyBuffer(handleMA1, 0, shift, 2, ma1) <= 0) return;
   if(CopyBuffer(handleMA2, 0, shift, 1, ma2) <= 0) return;
   if(CopyBuffer(handleRSI, 0, shift, 2, rsi) <= 0) return;
   if(CopyBuffer(handleATR1, 0, shift, 1, atr1) <= 0) return;
   if(CopyBuffer(handleATR2, 0, shift, 1, atr2) <= 0) return;
   
   //--- Get close price of the signal bar
   double close = iClose(_Symbol, MA1_Timeframe, shift);
   
   //--- Get current prices for order placement
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Check volatility filter (ATR1 < ATR2)
   if(atr1[0] >= atr2[0])
      return; // Volatility too high, skip
   
   //--- Calculate distance thresholds
   double buyThreshold = ma1[0] - (ma1[0] * MinMAGap / 100.0);
   double sellThreshold = ma1[0] + (ma1[0] * MinMAGap / 100.0);
   
   //--- Check BUY signal
   if(counterBuy < 1)
   {
      // 1. Price below MA1 by at least MinMAGap%
      if(close < buyThreshold)
      {
         // 2. Price above MA2 (trend filter)
         if(close > ma2[0])
         {
            // 3. RSI rising (momentum filter)
            if(rsi[1] > rsi[0])
            {
               // All conditions met - open BUY
               OpenBuy(ask);
            }
         }
      }
   }
   
   //--- Check SELL signal
   if(counterSell < 1)
   {
      // 1. Price above MA1 by at least MinMAGap%
      if(close > sellThreshold)
      {
         // 2. Price below MA2 (trend filter)
         if(close < ma2[0])
         {
            // 3. RSI falling (momentum filter)
            if(rsi[1] < rsi[0])
            {
               // All conditions met - open SELL
               OpenSell(bid);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open BUY position                                                |
//+------------------------------------------------------------------+
void OpenBuy(double price)
{
   double sl = 0;
   double tp = 0;
   
   //--- Calculate SL
   if(SLPercent > 0)
   {
      sl = price - (price * SLPercent / 100.0);
      sl = NormalizeDouble(sl, _Digits);
   }
   
   //--- Calculate TP
   if(TPPercent > 0)
   {
      tp = price + (price * TPPercent / 100.0);
      tp = NormalizeDouble(tp, _Digits);
   }
   
   //--- Open position
   if(trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, Lots, price, sl, tp, "Mean Reversion BUY"))
   {
      Print("BUY order opened at ", price, " | SL: ", sl, " | TP: ", tp);
   }
   else
   {
      Print("Error opening BUY order: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open SELL position                                               |
//+------------------------------------------------------------------+
void OpenSell(double price)
{
   double sl = 0;
   double tp = 0;
   
   //--- Calculate SL
   if(SLPercent > 0)
   {
      sl = price + (price * SLPercent / 100.0);
      sl = NormalizeDouble(sl, _Digits);
   }
   
   //--- Calculate TP
   if(TPPercent > 0)
   {
      tp = price - (price * TPPercent / 100.0);
      tp = NormalizeDouble(tp, _Digits);
   }
   
   //--- Open position
   if(trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, Lots, price, sl, tp, "Mean Reversion SELL"))
   {
      Print("SELL order opened at ", price, " | SL: ", sl, " | TP: ", tp);
   }
   else
   {
      Print("Error opening SELL order: ", GetLastError());
   }
}
//+------------------------------------------------------------------+
