//+------------------------------------------------------------------+
//|                                        EMA50_Bounce_OHLC.mq5     |
//|        EMA 50 Bounce - OHLC Interaction Based Architecture       |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "EMA 50 Bounce EA using Candle Interaction Logic"

#include <Trade/Trade.mqh>
CTrade trade;

//-------------------------------------------------------------------
// INPUT PARAMETERS
//-------------------------------------------------------------------
input int      InpMAPeriod        = 50;
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE;

input double   InpLotSize         = 0.10;
input bool     UseRiskPercent     = false;
input double   RiskPercent        = 1.0;

input int      StopLossPoints     = 300;
input int      TakeProfitPoints   = 600;

input bool     UseTolerance       = false;
input int      TolerancePoints    = 50;

input bool     RequireSecondLeg   = false;
input bool     UsePinBarFilter    = false;
input bool     UseDoubleStructure = false;

//-------------------------------------------------------------------
// GLOBALS
//-------------------------------------------------------------------
int    maHandle;
double maBuffer[];

bool   previousBounceDetected = false;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   maHandle = iMA(_Symbol,_Period,InpMAPeriod,0,MODE_EMA,InpPrice);

   if(maHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   ArraySetAsSeries(maBuffer,true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(maHandle != INVALID_HANDLE)
      IndicatorRelease(maHandle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar())
      return;

   if(CopyBuffer(maHandle,0,0,3,maBuffer) <= 0)
      return;

   if(PositionSelect(_Symbol))
      return;

   CheckForSetup();
}

//+------------------------------------------------------------------+
// CORE LOGIC
//+------------------------------------------------------------------+
void CheckForSetup()
{
   double ema = maBuffer[1];

   double open1  = iOpen(_Symbol,_Period,1);
   double close1 = iClose(_Symbol,_Period,1);
   double high1  = iHigh(_Symbol,_Period,1);
   double low1   = iLow(_Symbol,_Period,1);

   double open2  = iOpen(_Symbol,_Period,2);
   double close2 = iClose(_Symbol,_Period,2);

   bool bullishTrend = close2 > ema;
   bool bearishTrend = close2 < ema;

   //=============================================================
   // EMA INTERACTION (NO PURE DISTANCE LOGIC)
   //=============================================================

   bool bullishInteraction =
      (low1 < ema && close1 > ema);   // pierce + close above

   bool bearishInteraction =
      (high1 > ema && close1 < ema);  // pierce + close below

   // Optional tolerance soft filter
   if(UseTolerance)
   {
      if(!((MathAbs(low1 - ema) <= TolerancePoints*_Point) ||
           (MathAbs(high1 - ema) <= TolerancePoints*_Point)))
         return;
   }

   // Optional Second Leg Requirement
   if(RequireSecondLeg)
   {
      double low2  = iLow(_Symbol,_Period,2);
      double high2 = iHigh(_Symbol,_Period,2);

      bool secondTouch =
         (MathAbs(low2 - ema) <= (TolerancePoints*_Point)) ||
         (MathAbs(high2 - ema) <= (TolerancePoints*_Point));

      if(!secondTouch)
         return;
   }

   // Optional Pin Bar Filter
   if(UsePinBarFilter)
   {
      if(bullishTrend && bullishInteraction && !IsBullishPinBar(1))
         return;

      if(bearishTrend && bearishInteraction && !IsBearishPinBar(1))
         return;
   }

   // Optional Double Structure Filter
   if(UseDoubleStructure)
   {
      if(bullishTrend && bullishInteraction && !IsDoubleBottom())
         return;

      if(bearishTrend && bearishInteraction && !IsDoubleTop())
         return;
   }

   //=============================================================
   // FINAL DECISION
   //=============================================================

   if(bullishTrend && bullishInteraction)
      ExecuteTrade(ORDER_TYPE_BUY);

   if(bearishTrend && bearishInteraction)
      ExecuteTrade(ORDER_TYPE_SELL);
}

//+------------------------------------------------------------------+
// PIN BAR DETECTION
//+------------------------------------------------------------------+
bool IsBullishPinBar(int shift)
{
   double open  = iOpen(_Symbol,_Period,shift);
   double close = iClose(_Symbol,_Period,shift);
   double high  = iHigh(_Symbol,_Period,shift);
   double low   = iLow(_Symbol,_Period,shift);

   double body  = MathAbs(close-open);
   double lowerWick = MathMin(open,close) - low;

   return (lowerWick > body*2 && close > open);
}

//+------------------------------------------------------------------+
bool IsBearishPinBar(int shift)
{
   double open  = iOpen(_Symbol,_Period,shift);
   double close = iClose(_Symbol,_Period,shift);
   double high  = iHigh(_Symbol,_Period,shift);
   double low   = iLow(_Symbol,_Period,shift);

   double body  = MathAbs(close-open);
   double upperWick = high - MathMax(open,close);

   return (upperWick > body*2 && close < open);
}

//+------------------------------------------------------------------+
// DOUBLE STRUCTURE (SIMPLE SWING MODEL)
//+------------------------------------------------------------------+
bool IsDoubleBottom()
{
   double low1 = iLow(_Symbol,_Period,1);
   double low3 = iLow(_Symbol,_Period,3);

   return (MathAbs(low1 - low3) <= 20*_Point);
}

//+------------------------------------------------------------------+
bool IsDoubleTop()
{
   double high1 = iHigh(_Symbol,_Period,1);
   double high3 = iHigh(_Symbol,_Period,3);

   return (MathAbs(high1 - high3) <= 20*_Point);
}

//+------------------------------------------------------------------+
// TRADE EXECUTION
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type)
{
   double price = (type==ORDER_TYPE_BUY)?
      SymbolInfoDouble(_Symbol,SYMBOL_ASK):
      SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double lot = InpLotSize;

   if(UseRiskPercent)
      lot = CalculateLotByRisk();

   double sl,tp;

   if(type==ORDER_TYPE_BUY)
   {
      sl = price - StopLossPoints*_Point;
      tp = price + TakeProfitPoints*_Point;
      trade.Buy(lot,_Symbol,price,sl,tp,"EMA50 OHLC Buy");
   }
   else
   {
      sl = price + StopLossPoints*_Point;
      tp = price - TakeProfitPoints*_Point;
      trade.Sell(lot,_Symbol,price,sl,tp,"EMA50 OHLC Sell");
   }
}

//+------------------------------------------------------------------+
double CalculateLotByRisk()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent/100.0;

   double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);

   double lossPerLot = (StopLossPoints*_Point/tickSize)*tickValue;

   if(lossPerLot<=0)
      return(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN));

   double lot = riskMoney/lossPerLot;

   double step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double min  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   lot = MathFloor(lot/step)*step;

   if(lot<min)
      lot=min;

   return lot;
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBar=0;
   datetime current=iTime(_Symbol,_Period,0);

   if(current!=lastBar)
   {
      lastBar=current;
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
