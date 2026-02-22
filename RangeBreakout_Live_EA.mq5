//+------------------------------------------------------------------+
//|                                        RangeBreakout_Live_EA.mq5  |
//|  Range Breakout EA – video-exact logic, no repaint, perf table   |
//|  Range = time window (e.g. 3:05–6:05); after range: Buy Stop at   |
//|  high, Sell Stop at low; SL = 1% from open; close at 18:55.      |
//|                                                                  |
//|  STRATEGY (no interpretation):                                    |
//|  - Range: high/low of M1 bars between RangeStart and RangeEnd.   |
//|  - No repaint: range fixed only after RangeEnd using closed bars.|
//|  - After RangeEnd: place Buy Stop at range high, Sell Stop at low|
//|  - SL = 1% from order price (open); TP = none.                  |
//|  - One trade per day: when one order fills, cancel the other.   |
//|  - Close all positions and delete pendings at PositionClose time.|
//|  - Risk: RiskPercent of balance; lot from 1% SL distance.        |
//|  - Optional: MinRangePct filter; MaxSpread filter.               |
//|  - Visuals: range + entry levels; reset when trade closes.      |
//+------------------------------------------------------------------+
#property copyright "Range Breakout Live"
#property version   "1.00"
#property description "Range Breakout: range in time window, pending orders at high/low,"
#property description "SL 1% from open, no TP, close all at end time. One trade per day (OCO)."
#property description "No repaint: range uses only closed M1 bars. Visuals reset after trade close."

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input groups
input group "=== Range (Server Time) ==="
input int      RangeStartHour   = 3;    // Range start hour
input int      RangeStartMinute = 5;    // Range start minute
input int      RangeEndHour     = 6;    // Range end hour
input int      RangeEndMinute   = 5;    // Range end minute

input group "=== Session End ==="
input int      PositionCloseHour   = 18;  // Close positions / delete orders hour
input int      PositionCloseMinute = 55;  // Close positions / delete orders minute

input group "=== Risk Management ==="
input double   RiskPercent     = 1.0;   // Risk per trade (% of balance)
input double   FixedLotSize   = 0.0;    // Fixed lot (0 = use RiskPercent)
input double   MaxSpreadPoints = 0.0;   // Max spread to allow orders (0 = disable)

input group "=== Filters & Confluence ==="
input bool     UseRangeFilter  = false; // Use minimum range size filter
input double   MinRangePct     = 0.1;   // Min range size (% of price, if filter on)

input group "=== Orders & Behavior ==="
input int      MagicNumber     = 23456; // Magic number
input int      SlippagePoints  = 10;    // Slippage (points)
input bool     OneTradePerDay  = true;  // One trade per day (cancel opposite when one fills)

input group "=== Visualization ==="
input bool     ShowRangeVisual = true;  // Draw range and entry levels
input color    RangeColor      = clrYellow;  // Range rectangle color
input color    BuyLevelColor   = clrLime;    // Buy stop level color
input color    SellLevelColor  = clrOrangeRed; // Sell stop level color

input group "=== Trailing Stop ==="
input bool     UseTrailingStop = true;   // Use trailing stop loss
input double   TrailStartPct   = 0.3;    // Trail start when profit >= this % from open
input double   TrailStepPct    = 0.15;   // Trail step (% of price) to move SL

input group "=== Prop Firm (Challenge) ==="
input bool     EnablePropRules = false;  // Enable prop firm challenge rules
input double   ChallengeAccountSize = 100000.0; // Challenge account size ($) for % calc
input double   Phase1ProfitTarget   = 10.0;    // Phase 1 profit target (%)
input double   Phase2ProfitTarget   = 5.0;     // Phase 2 profit target (%)
input double   DailyLossLimitPct    = 5.0;     // Daily loss limit (% of daily start)
input double   MaxDrawdownPct       = 10.0;    // Max drawdown (% from initial/high)
input int      MinTradingDays       = 5;       // Min trading days (informational)
input bool     HighRiskMode         = true;    // High risk for fast pass (use PropRiskPercent)
input double   PropRiskPercent      = 2.5;     // Risk % per trade when HighRiskMode

input group "=== Performance Table ==="
input bool     ShowPerfTable   = true;  // Show performance panel on chart
input int      PerfPanelX     = 10;    // Panel X (pixels)
input int      PerfPanelY     = 30;    // Panel Y (pixels)

//--- Global state (no repaint: range fixed only after range end from closed bars)
datetime g_RangeTimeStart, g_RangeTimeEnd, g_PositionCloseTime;
double   g_RangeHigh, g_RangeLow;
bool     g_RangeValid;
datetime g_LastRangeDate;       // date of current range (for new-day reset)
bool     g_OrdersPlaced;
bool     g_TradeExecuted;       // one side filled
ulong    g_BuyStopTicket, g_SellStopTicket;
datetime g_LastClosedTradeTime; // last time we closed a trade (for visual reset)
datetime g_LastSessionCloseDate; // last date we ran CloseSession (avoid repeat)
string   g_ObjectPrefix = "RB_";

//--- Prop firm tracking
double   g_InitialBalance;
double   g_DailyStartBalance;
double   g_HighestBalance;
bool     g_DailyLimitBreached;
bool     g_MaxLimitBreached;
bool     g_Phase1Complete;
int      g_TradingDaysCount;
datetime g_LastDayForDailyReset;

CTrade         g_Trade;
COrderInfo     g_OrderInfo;
CPositionInfo  g_PosInfo;

//--- Performance stats (from history, this EA only)
double   g_TotalTrades, g_Wins, g_GrossProfit, g_GrossLoss, g_DailyPL;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_Trade.SetExpertMagicNumber(MagicNumber);
   g_Trade.SetDeviationInPoints(SlippagePoints);
   g_Trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_RangeHigh = 0;
   g_RangeLow  = 0;
   g_RangeValid = false;
   g_LastRangeDate = 0;
   g_OrdersPlaced = false;
   g_TradeExecuted = false;
   g_BuyStopTicket = 0;
   g_SellStopTicket = 0;
   g_LastClosedTradeTime = 0;
   g_LastSessionCloseDate = 0;
   g_DailyLimitBreached = false;
   g_MaxLimitBreached = false;
   g_Phase1Complete = false;
   g_TradingDaysCount = 0;
   g_LastDayForDailyReset = 0;

   if(EnablePropRules)
   {
      g_InitialBalance = ChallengeAccountSize;
      g_DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_HighestBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("RB Prop: Enabled | Account $", ChallengeAccountSize, " | P1: ", Phase1ProfitTarget,
            "% | P2: ", Phase2ProfitTarget, "% | DailyLoss: ", DailyLossLimitPct, "% | MaxDD: ", MaxDrawdownPct, "%");
      if(HighRiskMode)
         Print("RB Prop: HighRiskMode ON | Risk ", PropRiskPercent, "% per trade");
   }

   if(!ValidateInputs())
   {
      Print("RangeBreakout Live EA: Invalid inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }

   RecalculateTimes();
   SyncStateWithExistingOrders();

   if(ShowPerfTable)
      CreatePerfPanel();

   Print("RangeBreakout Live EA initialized. Range ", RangeStartHour, ":", RangeStartMinute,
         " - ", RangeEndHour, ":", RangeEndMinute, " | Close ", PositionCloseHour, ":", PositionCloseMinute);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAllVisuals();
   if(ShowPerfTable)
      ObjectDelete(0, g_ObjectPrefix + "PerfPanel");
   Print("RangeBreakout Live EA deinitialized.");
}

//+------------------------------------------------------------------+
//| Recalculate session times for today (server time)                 |
//+------------------------------------------------------------------+
void RecalculateTimes()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   dt.hour = RangeStartHour;
   dt.min  = RangeStartMinute;
   dt.sec  = 0;
   g_RangeTimeStart = StructToTime(dt);

   dt.hour = RangeEndHour;
   dt.min  = RangeEndMinute;
   dt.sec  = 0;
   g_RangeTimeEnd = StructToTime(dt);

   dt.hour = PositionCloseHour;
   dt.min  = PositionCloseMinute;
   dt.sec  = 0;
   g_PositionCloseTime = StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Determine range from closed M1 bars only (no repaint)              |
//| Call only when TimeCurrent() >= g_RangeTimeEnd.                    |
//+------------------------------------------------------------------+
bool UpdateRangeFromClosedBars()
{
   RecalculateTimes();
   if(TimeCurrent() < g_RangeTimeEnd)
      return false;

   int minutesInRange = (int)((g_RangeTimeEnd - g_RangeTimeStart) / 60);
   if(minutesInRange <= 0)
      return false;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_M1, g_RangeTimeStart, minutesInRange, rates);
   if(copied <= 0)
      return false;

   g_RangeHigh = rates[0].high;
   g_RangeLow  = rates[0].low;
   for(int i = 1; i < copied; i++)
   {
      if(rates[i].high > g_RangeHigh) g_RangeHigh = rates[i].high;
      if(rates[i].low  < g_RangeLow)  g_RangeLow  = rates[i].low;
   }
   double rangeSize = g_RangeHigh - g_RangeLow;

   if(rangeSize <= 0)
      return false;

   if(UseRangeFilter)
   {
      double mid = (g_RangeHigh + g_RangeLow) * 0.5;
      if(mid <= 0) return false;
      double minSize = mid * (MinRangePct / 100.0);
      if(rangeSize < minSize)
      {
         Print("Range filtered: size ", rangeSize, " < min ", minSize);
         return false;
      }
   }

   g_RangeValid = true;
   g_LastRangeDate = g_RangeTimeStart;

   if(ShowRangeVisual)
      DrawRangeAndEntryLevels();

   return true;
}

//+------------------------------------------------------------------+
//| Draw range rectangle and entry levels (no repaint; fixed levels)  |
//+------------------------------------------------------------------+
void DrawRangeAndEntryLevels()
{
   string dateStr = TimeToString(g_LastRangeDate, TIME_DATE);
   string rectName = g_ObjectPrefix + "Rect_" + dateStr;
   string buyName  = g_ObjectPrefix + "Buy_"  + dateStr;
   string sellName = g_ObjectPrefix + "Sell_" + dateStr;

   if(ObjectFind(0, rectName) < 0)
   {
      ObjectCreate(0, rectName, OBJ_RECTANGLE, 0, g_RangeTimeStart, g_RangeHigh, g_RangeTimeEnd, g_RangeLow);
      ObjectSetInteger(0, rectName, OBJPROP_COLOR, RangeColor);
      ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
      ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
      ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rectName, OBJPROP_WIDTH, 1);
   }
   else
   {
      ObjectSetDouble(0, rectName, OBJPROP_PRICE, 0, g_RangeHigh);
      ObjectSetDouble(0, rectName, OBJPROP_PRICE, 1, g_RangeLow);
   }

   datetime extendEnd = g_PositionCloseTime + 3600;
   if(ObjectFind(0, buyName) < 0)
   {
      ObjectCreate(0, buyName, OBJ_TREND, 0, g_RangeTimeEnd, g_RangeHigh, extendEnd, g_RangeHigh);
      ObjectSetInteger(0, buyName, OBJPROP_COLOR, BuyLevelColor);
      ObjectSetInteger(0, buyName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, buyName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, buyName, OBJPROP_BACK, false);
      ObjectSetInteger(0, buyName, OBJPROP_SELECTABLE, false);
   }
   if(ObjectFind(0, sellName) < 0)
   {
      ObjectCreate(0, sellName, OBJ_TREND, 0, g_RangeTimeEnd, g_RangeLow, extendEnd, g_RangeLow);
      ObjectSetInteger(0, sellName, OBJPROP_COLOR, SellLevelColor);
      ObjectSetInteger(0, sellName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, sellName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, sellName, OBJPROP_BACK, false);
      ObjectSetInteger(0, sellName, OBJPROP_SELECTABLE, false);
   }
}

//+------------------------------------------------------------------+
//| Delete all RB_ objects (call on new day or after trade close)     |
//+------------------------------------------------------------------+
void DeleteAllVisuals()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_ObjectPrefix) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Reset visuals for current day (after trade closed)                |
//+------------------------------------------------------------------+
void ResetVisualsAfterClose()
{
   if(!ShowRangeVisual) return;
   DeleteAllVisuals();
   g_LastClosedTradeTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Place Buy Stop at range high, Sell Stop at range low              |
//| SL = 1% from entry (open) price; TP = 0.                          |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   if(!g_RangeValid || g_OrdersPlaced)
      return;
   if(EnablePropRules && !CanPlaceNewOrder())
      return;

   double lots = CalculateLotSize();
   if(lots <= 0)
   {
      Print("Lot size invalid. Orders not placed.");
      return;
   }

   if(MaxSpreadPoints > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > (long)MaxSpreadPoints)
      {
         Print("Spread too high: ", spread);
         return;
      }
   }

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // Buy Stop: entry = g_RangeHigh, SL = 1% below entry
   double buySL = NormalizeDouble(g_RangeHigh * (1.0 - 0.01), digits);
   if(tickSize > 0)
      buySL = NormalizeDouble(MathFloor(buySL / tickSize) * tickSize, digits);

   if(g_Trade.BuyStop(lots, g_RangeHigh, _Symbol, buySL, 0, ORDER_TIME_GTC, 0, "RB Buy"))
   {
      g_BuyStopTicket = g_Trade.ResultOrder();
      Print("RB: Buy Stop placed at ", g_RangeHigh, " SL=", buySL);
   }
   else
      Print("RB: Buy Stop failed ", g_Trade.ResultRetcode());

   // Sell Stop: entry = g_RangeLow, SL = 1% above entry
   double sellSL = NormalizeDouble(g_RangeLow * (1.0 + 0.01), digits);
   if(tickSize > 0)
      sellSL = NormalizeDouble(MathCeil(sellSL / tickSize) * tickSize, digits);

   if(g_Trade.SellStop(lots, g_RangeLow, _Symbol, sellSL, 0, ORDER_TIME_GTC, 0, "RB Sell"))
   {
      g_SellStopTicket = g_Trade.ResultOrder();
      Print("RB: Sell Stop placed at ", g_RangeLow, " SL=", sellSL);
   }
   else
      Print("RB: Sell Stop failed ", g_Trade.ResultRetcode());

   g_OrdersPlaced = true;
   if(EnablePropRules)
      g_TradingDaysCount++;
}

//+------------------------------------------------------------------+
//| Lot size: by risk % (SL distance = 1% of entry price)             |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(FixedLotSize > 0)
   {
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double lots   = MathMax(minLot, MathMin(maxLot, FixedLotSize));
      return NormalizeDouble(MathFloor(lots / step) * step, 2);
   }

   double riskPct = RiskPercent;
   if(EnablePropRules && HighRiskMode)
      riskPct = MathMax(0.01, MathMin(100.0, PropRiskPercent));

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (riskPct / 100.0);
   if(riskAmount <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double entryMid = (g_RangeHigh + g_RangeLow) * 0.5;
   double slDistancePct = 0.01 * entryMid;
   if(slDistancePct <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double riskPerLot = (slDistancePct / tickSize) * tickValue;
   if(riskPerLot <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lots = riskAmount / riskPerLot;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = NormalizeDouble(MathFloor(lots / step) * step, 2);
   return lots;
}

//+------------------------------------------------------------------+
//| Monitor pending orders: if one filled, cancel the other (OCO)     |
//+------------------------------------------------------------------+
void MonitorPendingOrders()
{
   if(OneTradePerDay && HasAnyPosition())
   {
      if(g_BuyStopTicket > 0) { g_Trade.OrderDelete(g_BuyStopTicket); g_BuyStopTicket = 0; }
      if(g_SellStopTicket > 0) { g_Trade.OrderDelete(g_SellStopTicket); g_SellStopTicket = 0; }
      g_TradeExecuted = true;
      return;
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_STOP)
         g_BuyStopTicket = ticket;
      else if(ot == ORDER_TYPE_SELL_STOP)
         g_SellStopTicket = ticket;
   }

   if(HasPositionByType(POSITION_TYPE_BUY))
   {
      g_TradeExecuted = true;
      if(g_SellStopTicket > 0) { g_Trade.OrderDelete(g_SellStopTicket); g_SellStopTicket = 0; }
      g_BuyStopTicket = 0;
   }
   else if(HasPositionByType(POSITION_TYPE_SELL))
   {
      g_TradeExecuted = true;
      if(g_BuyStopTicket > 0) { g_Trade.OrderDelete(g_BuyStopTicket); g_BuyStopTicket = 0; }
      g_SellStopTicket = 0;
   }
}

bool HasAnyPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

bool HasPositionByType(ENUM_POSITION_TYPE pt)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pt)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Trailing stop: move SL in favor when profit >= TrailStartPct      |
//+------------------------------------------------------------------+
void TrailPositions()
{
   if(!UseTrailingStop || TrailStartPct <= 0 || TrailStepPct <= 0)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double current   = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);

      double startDist = openPrice * (TrailStartPct / 100.0);
      double stepDist = openPrice * (TrailStepPct / 100.0);
      if(startDist <= 0 || stepDist <= 0) continue;

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         if(current - openPrice < startDist) continue;
         double newSL = NormalizeDouble(current - stepDist, digits);
         if(newSL <= openPrice) continue;
         if(newSL <= sl + point) continue;
         g_Trade.PositionModify(ticket, newSL, tp);
      }
      else
      {
         if(openPrice - current < startDist) continue;
         double newSL = NormalizeDouble(current + stepDist, digits);
         if(newSL >= openPrice) continue;
         if(sl > 0 && newSL >= sl - point) continue;
         g_Trade.PositionModify(ticket, newSL, tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Prop firm: check daily loss and max drawdown; breach = stop      |
//+------------------------------------------------------------------+
void CheckPropRules()
{
   if(!EnablePropRules) return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance > g_HighestBalance)
      g_HighestBalance = balance;

   double dailyLoss = g_DailyStartBalance - equity;
   double dailyLossPct = (g_DailyStartBalance > 0) ? (dailyLoss / g_DailyStartBalance * 100.0) : 0;
   if(dailyLossPct >= DailyLossLimitPct)
   {
      if(!g_DailyLimitBreached)
      {
         g_DailyLimitBreached = true;
         Print("RB PROP: Daily loss limit breached! Daily loss ", DoubleToString(dailyLossPct, 2), "% (max ", DailyLossLimitPct, "%)");
      }
   }

   double drawdownFromInitial = (g_InitialBalance > 0) ? ((g_InitialBalance - equity) / g_InitialBalance * 100.0) : 0;
   double drawdownFromHigh = (g_HighestBalance > 0) ? ((g_HighestBalance - equity) / g_HighestBalance * 100.0) : 0;
   double maxDD = MathMax(drawdownFromInitial, drawdownFromHigh);
   if(maxDD >= MaxDrawdownPct)
   {
      if(!g_MaxLimitBreached)
      {
         g_MaxLimitBreached = true;
         Print("RB PROP: Max drawdown breached! DD ", DoubleToString(maxDD, 2), "% (max ", MaxDrawdownPct, "%)");
      }
   }

   if(g_DailyLimitBreached || g_MaxLimitBreached)
   {
      CloseSession();
      return;
   }

   double profitPct = (g_InitialBalance > 0) ? ((equity - g_InitialBalance) / g_InitialBalance * 100.0) : 0;
   if(!g_Phase1Complete && profitPct >= Phase1ProfitTarget)
   {
      g_Phase1Complete = true;
      Print("RB PROP: Phase 1 target reached! Profit ", DoubleToString(profitPct, 2), "%");
   }
   if(g_Phase1Complete && profitPct >= Phase1ProfitTarget + Phase2ProfitTarget)
      Print("RB PROP: Phase 2 target reached! Total profit ", DoubleToString(profitPct, 2), "%");
}

//+------------------------------------------------------------------+
//| Prop firm: can we place new orders?                               |
//+------------------------------------------------------------------+
bool CanPlaceNewOrder()
{
   if(!EnablePropRules) return true;
   if(g_DailyLimitBreached || g_MaxLimitBreached) return false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossPct = (g_DailyStartBalance > 0) ? ((g_DailyStartBalance - equity) / g_DailyStartBalance * 100.0) : 0;
   if(dailyLossPct >= DailyLossLimitPct) return false;
   double ddFromHigh = (g_HighestBalance > 0) ? ((g_HighestBalance - equity) / g_HighestBalance * 100.0) : 0;
   if(ddFromHigh >= MaxDrawdownPct) return false;
   return true;
}

//+------------------------------------------------------------------+
//| New day: reset daily prop tracking (daily loss reset)            |
//+------------------------------------------------------------------+
void ResetDailyPropTracking()
{
   if(!EnablePropRules) return;
   g_DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_DailyLimitBreached = false;
}

//+------------------------------------------------------------------+
//| Close all positions and delete pending orders at session end     |
//+------------------------------------------------------------------+
void CloseSession()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
         g_Trade.PositionClose(ticket);
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      g_Trade.OrderDelete(ticket);
   }
   g_BuyStopTicket = 0;
   g_SellStopTicket = 0;
   ResetVisualsAfterClose();
}

//+------------------------------------------------------------------+
//| New day reset                                                     |
//+------------------------------------------------------------------+
bool IsNewDay()
{
   static datetime s_lastDay = 0;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(s_lastDay != today)
   {
      s_lastDay = today;
      return true;
   }
   return false;
}

void ResetDayState()
{
   ResetDailyPropTracking();
   g_RangeValid = false;
   g_LastRangeDate = 0;
   g_OrdersPlaced = false;
   g_TradeExecuted = false;
   g_RangeHigh = 0;
   g_RangeLow = 0;
   g_BuyStopTicket = 0;
   g_SellStopTicket = 0;
   DeleteAllVisuals();
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: reset visuals when position closed            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;
   ResetVisualsAfterClose();
}

//+------------------------------------------------------------------+
//| Main tick                                                         |
//+------------------------------------------------------------------+
void OnTick()
{
   RecalculateTimes();

   if(EnablePropRules)
   {
      CheckPropRules();
      if(g_DailyLimitBreached || g_MaxLimitBreached)
      {
         if(ShowPerfTable) { UpdatePerfStats(); ChartRedraw(0); }
         return;
      }
   }

   if(HasAnyPosition())
      TrailPositions();

   if(IsNewDay())
   {
      ResetDayState();
   }

   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dtNow.year, dtNow.mon, dtNow.day));

   if(TimeCurrent() >= g_PositionCloseTime)
   {
      if(g_LastSessionCloseDate != today)
      {
         CloseSession();
         g_LastSessionCloseDate = today;
      }
      if(ShowPerfTable) { UpdatePerfStats(); ChartRedraw(0); }
      return;
   }

   if(TimeCurrent() < g_RangeTimeEnd)
   {
      if(ShowPerfTable) { UpdatePerfStats(); ChartRedraw(0); }
      return;
   }

   if(!g_RangeValid)
   {
      if(!UpdateRangeFromClosedBars())
         return;
      PlacePendingOrders();
      return;
   }

   MonitorPendingOrders();

   if(ShowPerfTable)
   {
      UpdatePerfStats();
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Sync state with existing orders/positions (e.g. after restart)    |
//+------------------------------------------------------------------+
void SyncStateWithExistingOrders()
{
   g_OrdersPlaced = false;
   g_BuyStopTicket = 0;
   g_SellStopTicket = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != MagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      g_OrdersPlaced = true;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_STOP) g_BuyStopTicket = ticket;
      else if(ot == ORDER_TYPE_SELL_STOP) g_SellStopTicket = ticket;
   }
   if(HasAnyPosition())
      g_TradeExecuted = true;
}

//+------------------------------------------------------------------+
//| Performance panel                                                 |
//+------------------------------------------------------------------+
void CreatePerfPanel()
{
   string name = g_ObjectPrefix + "PerfPanel";
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PerfPanelX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PerfPanelY);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }
}

void UpdatePerfStats()
{
   g_TotalTrades = 0;
   g_Wins = 0;
   g_GrossProfit = 0;
   g_GrossLoss = 0;
   g_DailyPL = 0;

   datetime dayStart;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   dayStart = StructToTime(dt);

   HistorySelect(0, TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber ||
         HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                      HistoryDealGetDouble(ticket, DEAL_SWAP) +
                      HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(dealTime >= dayStart)
         g_DailyPL += profit;
      g_TotalTrades++;
      if(profit > 0) { g_Wins += 1; g_GrossProfit += profit; }
      else           g_GrossLoss += profit;
   }

   double winrate = (g_TotalTrades > 0) ? (g_Wins / g_TotalTrades * 100.0) : 0.0;
   double pf = (g_GrossLoss < 0) ? (g_GrossProfit / (-g_GrossLoss)) : (g_GrossProfit > 0 ? 999.99 : 0.0);
   double totalPL = g_GrossProfit + g_GrossLoss;

   string text = StringFormat("RB Live | Trades: %.0f | Win%%: %.1f | PF: %.2f | Total P/L: %.2f | Daily: %.2f",
                              g_TotalTrades, winrate, pf, totalPL, g_DailyPL);
   if(EnablePropRules)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyLossPct = (g_DailyStartBalance > 0) ? ((g_DailyStartBalance - equity) / g_DailyStartBalance * 100.0) : 0;
      double ddPct = (g_HighestBalance > 0) ? ((g_HighestBalance - equity) / g_HighestBalance * 100.0) : 0;
      double profitPct = (g_InitialBalance > 0) ? ((equity - g_InitialBalance) / g_InitialBalance * 100.0) : 0;
      string breach = (g_DailyLimitBreached || g_MaxLimitBreached) ? " [BREACH]" : "";
      text += StringFormat("\nProp | P/L%%: %.2f | DailyDD%%: %.2f | MaxDD%%: %.2f | P1: %s | Days: %d%s",
                           profitPct, dailyLossPct, ddPct, (g_Phase1Complete ? "OK" : "-"), g_TradingDaysCount, breach);
   }
   ObjectSetString(0, g_ObjectPrefix + "PerfPanel", OBJPROP_TEXT, text);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Validation                                                        |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if(RangeStartHour < 0 || RangeStartHour > 23 || RangeEndHour < 0 || RangeEndHour > 23)
      return false;
   if(RangeStartMinute < 0 || RangeStartMinute > 59 || RangeEndMinute < 0 || RangeEndMinute > 59)
      return false;
   if(PositionCloseHour < 0 || PositionCloseHour > 23 || PositionCloseMinute < 0 || PositionCloseMinute > 59)
      return false;
   if(RangeStartHour > RangeEndHour || (RangeStartHour == RangeEndHour && RangeStartMinute >= RangeEndMinute))
      return false;
   if(FixedLotSize <= 0 && (RiskPercent <= 0 || RiskPercent > 100))
      return false;
   if(UseRangeFilter && MinRangePct <= 0)
      return false;
   if(EnablePropRules)
   {
      if(ChallengeAccountSize <= 0 || Phase1ProfitTarget <= 0 || Phase2ProfitTarget <= 0)
         return false;
      if(DailyLossLimitPct <= 0 || DailyLossLimitPct > 100 || MaxDrawdownPct <= 0 || MaxDrawdownPct > 100)
         return false;
      if(HighRiskMode && (PropRiskPercent <= 0 || PropRiskPercent > 100))
         return false;
   }
   if(UseTrailingStop && (TrailStartPct <= 0 || TrailStepPct <= 0))
      return false;
   return true;
}
//+------------------------------------------------------------------+
