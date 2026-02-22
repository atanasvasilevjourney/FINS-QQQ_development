//+------------------------------------------------------------------+
//|                                   MeanReversionEA_Enhanced.mq5   |
//|                          Enhanced with Spread, Time, Cooldown    |
//|                        Mean Reversion Strategy - Production Ready|
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA - Enhanced Version"
#property link      ""
#property version   "1.10"
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
input bool            UseATRforSLTP = false;            // Use ATR for SL/TP
input double          TPPercent = 1.5;                  // Take Profit (%) - if not ATR
input double          SLPercent = 1.0;                  // Stop Loss (%) - if not ATR
input double          ATRMultiplierSL = 1.5;            // ATR SL Multiplier
input double          ATRMultiplierTP = 2.0;            // ATR TP Multiplier

input group "=== Filters ==="
input bool            UseSpreadFilter = true;           // Use Spread Filter
input double          MaxSpreadPoints = 30;             // Max Spread (points)
input bool            UseTimeFilter = false;            // Use Time Filter
input int             StartHour = 8;                    // Start Hour (broker time)
input int             EndHour = 20;                     // End Hour (broker time)
input int             CooldownBars = 10;                // Cooldown After Trade (bars)

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
datetime lastTradeTime = 0;

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
   
   Print("=== Mean Reversion EA Enhanced ===");
   Print("Non-Repaint Mode: ", UseBarCloseSignals ? "ON" : "OFF");
   Print("Spread Filter: ", UseSpreadFilter ? "ON" : "OFF");
   Print("Time Filter: ", UseTimeFilter ? "ON" : "OFF");
   Print("Cooldown: ", CooldownBars, " bars");
   Print("ATR-based SL/TP: ", UseATRforSLTP ? "ON" : "OFF");
   
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
   
   Print("Mean Reversion EA Enhanced deinitialized");
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
               Print("BUY closed at MA. Profit: ", DoubleToString(position.Profit(), 2));
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
               Print("SELL closed at MA. Profit: ", DoubleToString(position.Profit(), 2));
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
   //--- Spread filter
   if(UseSpreadFilter)
   {
      long spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spreadPoints > MaxSpreadPoints)
      {
         Print("Spread too high: ", spreadPoints, " points (max: ", MaxSpreadPoints, ")");
         return;
      }
   }
   
   //--- Time filter
   if(UseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < StartHour || dt.hour >= EndHour)
      {
         return; // Outside trading hours
      }
   }
   
   //--- Cooldown filter
   if(CooldownBars > 0 && lastTradeTime > 0)
   {
      datetime cooldownEnd = lastTradeTime + (PeriodSeconds(MA1_Timeframe) * CooldownBars);
      if(TimeCurrent() < cooldownEnd)
      {
         return; // Still in cooldown
      }
   }
   
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
               OpenBuy(ask, atr1[0]);
               lastTradeTime = TimeCurrent();
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
               OpenSell(bid, atr1[0]);
               lastTradeTime = TimeCurrent();
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open BUY position                                                |
//+------------------------------------------------------------------+
void OpenBuy(double price, double atr)
{
   double sl = 0;
   double tp = 0;
   
   //--- Calculate SL/TP
   if(UseATRforSLTP)
   {
      sl = price - (atr * ATRMultiplierSL);
      tp = price + (atr * ATRMultiplierTP);
   }
   else
   {
      if(SLPercent > 0)
         sl = price - (price * SLPercent / 100.0);
      if(TPPercent > 0)
         tp = price + (price * TPPercent / 100.0);
   }
   
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   //--- Open position
   if(trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, Lots, price, sl, tp, "MR_BUY"))
   {
      Print("✅ BUY @ ", price, " | SL: ", sl, " | TP: ", tp, 
            UseATRforSLTP ? " (ATR)" : " (%)");
   }
   else
   {
      Print("❌ BUY failed: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Open SELL position                                               |
//+------------------------------------------------------------------+
void OpenSell(double price, double atr)
{
   double sl = 0;
   double tp = 0;
   
   //--- Calculate SL/TP
   if(UseATRforSLTP)
   {
      sl = price + (atr * ATRMultiplierSL);
      tp = price - (atr * ATRMultiplierTP);
   }
   else
   {
      if(SLPercent > 0)
         sl = price + (price * SLPercent / 100.0);
      if(TPPercent > 0)
         tp = price - (price * TPPercent / 100.0);
   }
   
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   
   //--- Open position
   if(trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, Lots, price, sl, tp, "MR_SELL"))
   {
      Print("✅ SELL @ ", price, " | SL: ", sl, " | TP: ", tp,
            UseATRforSLTP ? " (ATR)" : " (%)");
   }
   else
   {
      Print("❌ SELL failed: ", GetLastError());
   }
}
//+------------------------------------------------------------------+
