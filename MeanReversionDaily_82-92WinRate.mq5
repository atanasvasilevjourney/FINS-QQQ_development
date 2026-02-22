//+------------------------------------------------------------------+
//|                              MeanReversionDaily_82-92WinRate.mq5 |
//|                    Based on Jared Goodwin's Video Tutorial       |
//|              Mean Reversion Strategy - 82-92% Win Rate           |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA - Daily Chart Strategy"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input parameters
input group "=== Strategy Settings ==="
input int             MA_Period = 50;                    // Moving Average Period
input double          RangePercent = 20.0;               // Range Percent (20% = lower/upper 20%)
input double          StopLossPips = 300.0;               // Stop Loss (Pips)
input double          ProfitTargetPips = 125.0;          // Profit Target (Pips)
input double          Lots = 1.0;                         // Lot Size
input int             MagicNumber = 789123;               // Magic Number

input group "=== Trade Management ==="
input bool            UseStopAndReverse = true;           // Use Stop & Reverse
input bool            UseMACrossExit = true;              // Use MA Cross Exit
input bool            UseStopLoss = true;                 // Use Stop Loss
input bool            UseProfitTarget = true;             // Use Profit Target

//--- Global variables
int handleMA;
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
   
   //--- Create indicator handle
   handleMA = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   if(handleMA == INVALID_HANDLE)
   {
      Print("Error creating MA handle: ", GetLastError());
      return(INIT_FAILED);
   }
   
   Print("Mean Reversion EA initialized successfully");
   Print("MA Period: ", MA_Period);
   Print("Range Percent: ", RangePercent, "%");
   Print("Stop Loss: ", StopLossPips, " pips");
   Print("Profit Target: ", ProfitTargetPips, " pips");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handle
   if(handleMA != INVALID_HANDLE) IndicatorRelease(handleMA);
   
   Print("Mean Reversion EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for new bar (only trade on bar close)
   int bars = iBars(_Symbol, PERIOD_CURRENT);
   if(bars == barsTotal)
      return; // No new bar, exit
   barsTotal = bars;
   
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
   //--- Get current bar data (use closed bar [1] for non-repaint)
   double close[], high[], low[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, close) <= 0) return;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, 1, high) <= 0) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, 1, low) <= 0) return;
   
   //--- Get MA value
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(handleMA, 0, 1, 2, ma) <= 0) return;
   
   //--- Get current prices
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Loop through all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i))
         continue;
      
      if(position.Symbol() != _Symbol)
         continue;
      
      if(position.Magic() != MagicNumber)
         continue;
      
      //--- Check BUY position exits
      if(position.PositionType() == POSITION_TYPE_BUY)
      {
         // Exit 1: MA Cross Exit (close crosses above MA)
         if(UseMACrossExit)
         {
            if(close[0] > ma[0] && ma[1] <= ma[0]) // Cross above
            {
               trade.PositionClose(position.Ticket());
               Print("BUY position closed at MA cross above. Profit: ", position.Profit());
               continue;
            }
         }
      }
      
      //--- Check SELL position exits
      if(position.PositionType() == POSITION_TYPE_SELL)
      {
         // Exit 1: MA Cross Exit (close crosses below MA)
         if(UseMACrossExit)
         {
            if(close[0] < ma[0] && ma[1] >= ma[0]) // Cross below
            {
               trade.PositionClose(position.Ticket());
               Print("SELL position closed at MA cross below. Profit: ", position.Profit());
               continue;
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
   bool hasLong = false;
   bool hasShort = false;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i))
         continue;
      
      if(position.Symbol() != _Symbol)
         continue;
      
      if(position.Magic() != MagicNumber)
         continue;
      
      if(position.PositionType() == POSITION_TYPE_BUY)
         hasLong = true;
      
      if(position.PositionType() == POSITION_TYPE_SELL)
         hasShort = true;
   }
   
   //--- Get current bar data (use closed bar [1] for non-repaint)
   double close[], high[], low[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   
   if(CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, close) <= 0) return;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, 1, high) <= 0) return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 1, 1, low) <= 0) return;
   
   //--- Get MA value
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(handleMA, 0, 1, 1, ma) <= 0) return;
   
   //--- Calculate bar range
   double barRange = high[0] - low[0];
   if(barRange == 0) return; // Avoid division by zero
   
   //--- Calculate range thresholds
   double lower20Percent = low[0] + (barRange * RangePercent / 100.0);
   double upper20Percent = high[0] - (barRange * RangePercent / 100.0);
   
   //--- Get current prices for order placement
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Check LONG entry signal
   // Rule: Close < lower 20% of range AND Close < 50 SMA
   bool longSignal = (close[0] < lower20Percent) && (close[0] < ma[0]);
   
   if(longSignal)
   {
      //--- Stop and Reverse: Close short if exists
      if(UseStopAndReverse && hasShort)
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            if(!position.SelectByIndex(i))
               continue;
            
            if(position.Symbol() != _Symbol)
               continue;
            
            if(position.Magic() != MagicNumber)
               continue;
            
            if(position.PositionType() == POSITION_TYPE_SELL)
            {
               trade.PositionClose(position.Ticket());
               Print("SELL position closed (Stop & Reverse). Profit: ", position.Profit());
            }
         }
      }
      
      //--- Open LONG if no existing long position
      if(!hasLong)
      {
         OpenBuy(ask);
      }
   }
   
   //--- Check SHORT entry signal
   // Rule: Close > upper 20% of range AND Close > 50 SMA
   bool shortSignal = (close[0] > upper20Percent) && (close[0] > ma[0]);
   
   if(shortSignal)
   {
      //--- Stop and Reverse: Close long if exists
      if(UseStopAndReverse && hasLong)
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            if(!position.SelectByIndex(i))
               continue;
            
            if(position.Symbol() != _Symbol)
               continue;
            
            if(position.Magic() != MagicNumber)
               continue;
            
            if(position.PositionType() == POSITION_TYPE_BUY)
            {
               trade.PositionClose(position.Ticket());
               Print("BUY position closed (Stop & Reverse). Profit: ", position.Profit());
            }
         }
      }
      
      //--- Open SHORT if no existing short position
      if(!hasShort)
      {
         OpenSell(bid);
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
   
   //--- Calculate SL in pips
   if(UseStopLoss && StopLossPips > 0)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      
      // For 5-digit brokers, 1 pip = 10 points
      double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
      sl = price - (StopLossPips * pipValue);
      sl = NormalizeDouble(sl, digits);
   }
   
   //--- Calculate TP in pips
   if(UseProfitTarget && ProfitTargetPips > 0)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      
      // For 5-digit brokers, 1 pip = 10 points
      double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
      tp = price + (ProfitTargetPips * pipValue);
      tp = NormalizeDouble(tp, digits);
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
   
   //--- Calculate SL in pips
   if(UseStopLoss && StopLossPips > 0)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      
      // For 5-digit brokers, 1 pip = 10 points
      double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
      sl = price + (StopLossPips * pipValue);
      sl = NormalizeDouble(sl, digits);
   }
   
   //--- Calculate TP in pips
   if(UseProfitTarget && ProfitTargetPips > 0)
   {
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      
      // For 5-digit brokers, 1 pip = 10 points
      double pipValue = (digits == 5 || digits == 3) ? point * 10 : point;
      tp = price - (ProfitTargetPips * pipValue);
      tp = NormalizeDouble(tp, digits);
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
