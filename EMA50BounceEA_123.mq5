//+------------------------------------------------------------------+
//|                                        EMA50_Bounce_OHLC.mq5     |
//|        EMA 50 Bounce - OHLC Interaction Based Architecture       |
//|        Prop firm: trailing stop, performance table, news filter  |
//+------------------------------------------------------------------+
#property strict
#property version   "3.00"
#property description "EMA 50 Bounce EA - Forex/Prop: trailing stop, performance table, news filter"

#include <Trade/Trade.mqh>
CTrade trade;

//-------------------------------------------------------------------
// INPUT PARAMETERS
//-------------------------------------------------------------------
input group "=== EMA & Strategy ==="
input int      InpMAPeriod        = 50;
input ENUM_APPLIED_PRICE InpPrice = PRICE_CLOSE;

input group "=== Risk & Lots ==="
input double   InpLotSize         = 0.10;
input bool     UseRiskPercent     = false;
input double   RiskPercent        = 1.0;
input int      StopLossPoints     = 300;
input int      TakeProfitPoints   = 600;

input group "=== Optional Filters ==="
input bool     UseTolerance       = false;
input int      TolerancePoints    = 50;
input bool     RequireSecondLeg   = false;
input bool     UsePinBarFilter    = false;
input bool     UseDoubleStructure = false;

input group "=== Prop Firm / Execution ==="
input int      InpMagicNumber     = 50050;   // Magic number (EA identifier)
input bool     UseTrailingStop    = true;    // Use trailing stop
input int      BreakevenPoints    = 150;     // Move SL to breakeven after profit (points)
input int      TrailingStartPoints= 200;     // Start trailing after profit (points)
input int      TrailingDistancePoints= 150;  // Trailing distance from price (points)
input int      TrailingStepPoints = 50;      // Min move before updating trail (points)

input group "=== News Filter (Server Time) ==="
input bool     UseNewsFilter     = false;   // Block trading during news window
input int      NewsBlackoutStartHour = 12;   // Blackout start hour (0-23)
input int      NewsBlackoutEndHour   = 15;   // Blackout end hour (0-23)

input group "=== Performance Table ==="
input bool     ShowPerformanceTable = true; // Show performance stats on chart

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
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

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
   if(ShowPerformanceTable)
      Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- Trailing stop: run every tick when we have positions
   if(UseTrailingStop && HasOurPosition())
      ManageTrailingStop();

   //--- Performance table: update on chart
   if(ShowPerformanceTable)
      UpdatePerformanceTable();

   //--- New entries only on new bar
   if(!IsNewBar())
      return;

   if(CopyBuffer(maHandle,0,0,3,maBuffer) <= 0)
      return;

   if(HasOurPosition())
      return;

   if(UseNewsFilter && IsNewsBlackout())
      return;

   CheckForSetup();
}

//+------------------------------------------------------------------+
//| True if there is an open position on this symbol with our magic   |
//+------------------------------------------------------------------+
bool HasOurPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Trailing stop: breakeven first, then trail by points              |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double point = _Point;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      long  posType    = PositionGetInteger(POSITION_TYPE);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price = (posType == POSITION_TYPE_BUY) ? bid : ask;

      double profitPoints = 0;
      if(posType == POSITION_TYPE_BUY)
         profitPoints = (price - openPrice) / point;
      else
         profitPoints = (openPrice - price) / point;

      double newSL = currentSL;
      bool doModify = false;

      if(posType == POSITION_TYPE_BUY)
      {
         // Breakeven: move SL to entry once in profit by BreakevenPoints
         if(profitPoints >= BreakevenPoints && currentSL < openPrice && (currentSL == 0 || openPrice > currentSL))
         {
            newSL = NormalizeDouble(openPrice, _Digits);
            doModify = true;
         }
         // Trailing: after TrailingStartPoints profit, trail by TrailingDistancePoints
         if(profitPoints >= TrailingStartPoints)
         {
            double trailSL = NormalizeDouble(price - TrailingDistancePoints * point, _Digits);
            if(trailSL > openPrice && (trailSL > currentSL + TrailingStepPoints * point || currentSL == 0))
            {
               newSL = trailSL;
               doModify = true;
            }
         }
      }
      else  // SELL
      {
         if(profitPoints >= BreakevenPoints && (currentSL == 0 || currentSL > openPrice))
         {
            newSL = NormalizeDouble(openPrice, _Digits);
            doModify = true;
         }
         if(profitPoints >= TrailingStartPoints)
         {
            double trailSL = NormalizeDouble(price + TrailingDistancePoints * point, _Digits);
            if(trailSL < openPrice && (currentSL == 0 || trailSL < currentSL - TrailingStepPoints * point))
            {
               newSL = trailSL;
               doModify = true;
            }
         }
      }

      if(doModify && newSL != currentSL)
         trade.PositionModify(ticket, newSL, tp);
   }
}

//+------------------------------------------------------------------+
//| News filter: no trading during blackout window (server hours)     |
//+------------------------------------------------------------------+
bool IsNewsBlackout()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   int startH = MathMax(0, MathMin(23, NewsBlackoutStartHour));
   int endH   = MathMax(0, MathMin(23, NewsBlackoutEndHour));
   if(startH <= endH)
      return (h >= startH && h < endH);
   return (h >= startH || h < endH);
}

//+------------------------------------------------------------------+
//| Performance stats from history (this symbol + magic), show table  |
//+------------------------------------------------------------------+
void UpdatePerformanceTable()
{
   datetime from = 0;
   if(!HistorySelect(from, TimeCurrent()))
      return;

   int total = 0, wins = 0, losses = 0;
   double totalPL = 0, dailyPL = 0, peakBalance = 0, maxDD = 0;
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

      total++;
      totalPL += profit;
      if(dealTime >= dayStart) dailyPL += profit;
      if(profit > 0) wins++; else losses++;

      // Simple max DD from deal stream (peak-to-trough)
      if(totalPL > peakBalance) peakBalance = totalPL;
      double dd = peakBalance - totalPL;
      if(dd > maxDD) maxDD = dd;
   }

   double winRate = (total > 0) ? (100.0 * wins / total) : 0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double openPL  = equity - balance;

   string s = "=== EMA50 Bounce EA | Performance ===\n";
   s += StringFormat("Trades: %d  |  W: %d  L: %d  |  Win%%: %.1f\n", total, wins, losses, winRate);
   s += StringFormat("Total P/L: %.2f  |  Daily P/L: %.2f  |  Open P/L: %.2f\n", totalPL, dailyPL, openPL);
   s += StringFormat("Max DD (session): %.2f  |  Equity: %.2f\n", maxDD, equity);
   s += StringFormat("News filter: %s  |  Trail: %s\n", UseNewsFilter ? "ON" : "OFF", UseTrailingStop ? "ON" : "OFF");
   Comment(s);
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
