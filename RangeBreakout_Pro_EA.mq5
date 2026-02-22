//+------------------------------------------------------------------+
//|                                            RangeBreakout_Pro_EA.mq5 |
//|  Range Breakout EA – Pro: no repaint, trailing (limit moves),   |
//|  performance table, entry visuals (reset after close), prop firm |
//|  and magic randomizer.                                           |
//|  Range = high/low of M1 bars between RangeStart–RangeEnd (fixed  |
//|  after RangeEnd). SL = range boundary; optional TP; trail SL     |
//|  limited by max moves; close all at TradingEnd.                  |
//+------------------------------------------------------------------+
#property copyright "Range Breakout Pro"
#property version   "1.00"
#property description "Range between two times; breakout entries; SL at range;"
#property description "trailing stop with max move limit; prop firm ready; no repaint."

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Range (server time)
input group "=== Range (Server Time) ==="
input int      RangeStartHour   = 3;    // Range start hour
input int      RangeStartMinute = 0;    // Range start minute
input int      RangeEndHour     = 6;    // Range end hour
input int      RangeEndMinute   = 0;    // Range end minute

//--- Session end
input group "=== Session End ==="
input int      TradingEndHour   = 18;   // Close positions / delete orders hour
input int      TradingEndMinute = 0;    // Close positions / delete orders minute

//--- Risk
input group "=== Risk Management ==="
input double   RiskMoney        = 50.0;  // Risk per trade (money; 0 = use RiskPercent)
input double   RiskPercent      = 1.0;   // Risk per trade (% of balance; if RiskMoney=0)
input double   FixedLotSize     = 0.0;   // Fixed lot (0 = use risk-based)

//--- Filters & Confluence
input group "=== Filters & Confluence ==="
input double   MinRangeSize     = 0.0;   // Min range size (price; 0=disable)
input double   MinRangePct      = 0.0;   // Min range size (% of mid price; 0=disable)
input double   MaxSpreadPoints  = 0.0;   // Max spread to allow orders (0=disable)

//--- Orders & Behavior
input group "=== Orders & Behavior ==="
input int      MagicNumber      = 23456; // Magic number (base)
input int      SlippagePoints   = 10;    // Slippage (points)
input bool     OneTradePerDay   = true;  // One trade per day (cancel opposite when one fills)
input bool     UsePendingOrders = true;  // Use Buy/Sell Stop at range (false = market on breakout)
input bool     UseTakeProfit    = false; // Use take profit
input double   TakeProfitFactor = 1.0;   // TP = entry ± (range size * factor)

//--- Trailing Stop (limited by max moves)
input group "=== Trailing Stop ==="
input bool     UseTrailingStop  = true;  // Use trailing stop loss
input double   TrailStartPct    = 0.3;   // Start trail when profit >= this % from open
input double   TrailStepPct     = 0.15;  // Step (% of price) to move SL
input int      TrailMaxMoves    = 10;    // Max number of SL moves (0 = unlimited)

//--- Prop Firm
input group "=== Prop Firm (Challenge) ==="
input bool     EnablePropRules  = false; // Enable prop firm challenge rules
input double   ChallengeAccountSize = 100000.0; // Challenge account size ($)
input double   Phase1ProfitTarget   = 10.0; // Phase 1 profit target (%)
input double   Phase2ProfitTarget   = 5.0;  // Phase 2 profit target (%)
input double   DailyLossLimitPct    = 5.0;  // Daily loss limit (% of daily start)
input double   MaxDrawdownPct       = 10.0; // Max drawdown (% from initial/high)
input int      MinTradingDays      = 5;    // Min trading days (informational)
input bool     PropMagicRandomizer = false; // Randomize magic (base + 0..PropMagicOffset)
input int      PropMagicOffset     = 99;   // Magic offset for randomizer (0..999)

//--- Performance Table
input group "=== Performance Table ==="
input bool     ShowPerfTable   = true;  // Show performance panel
input int      PerfPanelX      = 10;    // Panel X (pixels)
input int      PerfPanelY      = 30;    // Panel Y (pixels)

//--- Visualization
input group "=== Visualization ==="
input bool     ShowRangeVisual = true;  // Draw range and entry levels
input color    RangeColor     = clrDodgerBlue;  // Range rectangle
input color    BuyLevelColor  = clrLime;        // Buy level / entry
input color    SellLevelColor = clrOrangeRed;    // Sell level / entry

//--- Effective magic (base or base + random)
int            g_Magic;

//--- Time and range state
datetime       g_RangeTimeStart, g_RangeTimeEnd, g_TradingTimeEnd;
double         g_RangeHigh, g_RangeLow;
bool           g_RangeValid;
datetime       g_LastRangeDate;
bool           g_OrdersPlaced;
bool           g_TradeExecuted;
ulong          g_BuyStopTicket, g_SellStopTicket;
datetime       g_LastSessionCloseDate;
string         g_ObjectPrefix = "RBP_";

//--- Trailing: how many times we moved SL for current position(s)
ulong          g_TrailTicket;
int            g_TrailMoveCount;

//--- Prop firm
double         g_InitialBalance, g_DailyStartBalance, g_HighestBalance;
bool          g_DailyLimitBreached, g_MaxLimitBreached, g_Phase1Complete;
int           g_TradingDaysCount;
datetime      g_LastDayForDailyReset;

//--- Performance (from history)
double        g_TotalTrades, g_Wins, g_GrossProfit, g_GrossLoss, g_DailyPL;

CTrade        g_Trade;
COrderInfo    g_OrderInfo;
CPositionInfo g_PosInfo;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_Magic = MagicNumber;
   if(EnablePropRules && PropMagicRandomizer && PropMagicOffset > 0)
      g_Magic = MagicNumber + (MathRand() % (PropMagicOffset + 1));

   g_Trade.SetExpertMagicNumber(g_Magic);
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
   g_LastSessionCloseDate = 0;
   g_TrailTicket = 0;
   g_TrailMoveCount = 0;
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
      Print("RBP Prop: Enabled | Magic ", g_Magic, " | Account $", ChallengeAccountSize,
            " | P1: ", Phase1ProfitTarget, "% | DailyLoss: ", DailyLossLimitPct, "% | MaxDD: ", MaxDrawdownPct, "%");
   }

   if(!ValidateInputs())
   {
      Print("RangeBreakout Pro EA: Invalid inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }

   RecalculateTimes();
   SyncStateWithExistingOrders();

   if(ShowPerfTable)
      CreatePerfPanel();

   Print("RangeBreakout Pro EA initialized. Magic ", g_Magic, " | Range ", RangeStartHour, ":", RangeStartMinute,
         " - ", RangeEndHour, ":", RangeEndMinute, " | Close ", TradingEndHour, ":", TradingEndMinute);
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
   Print("RangeBreakout Pro EA deinitialized.");
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

   dt.hour = TradingEndHour;
   dt.min  = TradingEndMinute;
   dt.sec  = 0;
   g_TradingTimeEnd = StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Range from closed M1 bars only (no repaint). Call when time >= RangeEnd. |
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

   if(MinRangeSize > 0 && rangeSize < MinRangeSize)
   {
      Print("RBP: Range filtered (size ", rangeSize, " < ", MinRangeSize, ")");
      return false;
   }
   if(MinRangePct > 0)
   {
      double mid = (g_RangeHigh + g_RangeLow) * 0.5;
      if(mid <= 0) return false;
      double minSize = mid * (MinRangePct / 100.0);
      if(rangeSize < minSize)
      {
         Print("RBP: Range filtered (size ", rangeSize, " < ", minSize, " min pct)");
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
//| Draw range rectangle and entry levels (no repaint)                |
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

   datetime extendEnd = g_TradingTimeEnd + 3600;
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
//| Delete all RBP_ objects (new day or after trade close)            |
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
//| Reset visuals after trade closed (keep chart clean)                |
//+------------------------------------------------------------------+
void ResetVisualsAfterClose()
{
   if(!ShowRangeVisual) return;
   DeleteAllVisuals();
}

//+------------------------------------------------------------------+
//| Place Buy Stop at range high, Sell Stop at range low; SL = range boundary |
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
      Print("RBP: Lot size invalid. Orders not placed.");
      return;
   }

   if(MaxSpreadPoints > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > (long)MaxSpreadPoints)
      {
         Print("RBP: Spread too high: ", spread);
         return;
      }
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double rangeSize = g_RangeHigh - g_RangeLow;

   // Buy Stop: entry = g_RangeHigh, SL = g_RangeLow
   double buyTP = 0;
   if(UseTakeProfit && TakeProfitFactor > 0)
      buyTP = NormalizeDouble(g_RangeHigh + rangeSize * TakeProfitFactor, digits);

   if(g_Trade.BuyStop(lots, g_RangeHigh, _Symbol, g_RangeLow, buyTP, ORDER_TIME_GTC, 0, "RBP Buy"))
   {
      g_BuyStopTicket = g_Trade.ResultOrder();
      Print("RBP: Buy Stop at ", g_RangeHigh, " SL=", g_RangeLow, " TP=", buyTP);
   }
   else
      Print("RBP: Buy Stop failed ", g_Trade.ResultRetcode());

   // Sell Stop: entry = g_RangeLow, SL = g_RangeHigh
   double sellTP = 0;
   if(UseTakeProfit && TakeProfitFactor > 0)
      sellTP = NormalizeDouble(g_RangeLow - rangeSize * TakeProfitFactor, digits);

   if(g_Trade.SellStop(lots, g_RangeLow, _Symbol, g_RangeHigh, sellTP, ORDER_TIME_GTC, 0, "RBP Sell"))
   {
      g_SellStopTicket = g_Trade.ResultOrder();
      Print("RBP: Sell Stop at ", g_RangeLow, " SL=", g_RangeHigh, " TP=", sellTP);
   }
   else
      Print("RBP: Sell Stop failed ", g_Trade.ResultRetcode());

   g_OrdersPlaced = true;
   if(EnablePropRules)
      g_TradingDaysCount++;
}

//+------------------------------------------------------------------+
//| Market order on breakout (when not using pending orders)           |
//+------------------------------------------------------------------+
void CheckBreakoutMarketOrder()
{
   if(!g_RangeValid || g_TradeExecuted || UsePendingOrders)
      return;
   if(EnablePropRules && !CanPlaceNewOrder())
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double lots = CalculateLotSize();
   if(lots <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double rangeSize = g_RangeHigh - g_RangeLow;

   if(bid > g_RangeHigh)
   {
      double tp = 0;
      if(UseTakeProfit && TakeProfitFactor > 0)
         tp = NormalizeDouble(g_RangeHigh + rangeSize * TakeProfitFactor, digits);
      if(g_Trade.Buy(lots, _Symbol, 0, g_RangeLow, tp, "RBP Long"))
      {
         g_TradeExecuted = true;
         Print("RBP: Market Long at ", bid, " SL=", g_RangeLow);
      }
   }
   else if(bid < g_RangeLow)
   {
      double tp = 0;
      if(UseTakeProfit && TakeProfitFactor > 0)
         tp = NormalizeDouble(g_RangeLow - rangeSize * TakeProfitFactor, digits);
      if(g_Trade.Sell(lots, _Symbol, 0, g_RangeHigh, tp, "RBP Short"))
      {
         g_TradeExecuted = true;
         Print("RBP: Market Short at ", bid, " SL=", g_RangeHigh);
      }
   }
}

//+------------------------------------------------------------------+
//| Lot size: risk money or risk %; SL distance = range size          |
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

   double riskAmount;
   if(RiskMoney > 0)
      riskAmount = RiskMoney;
   else
      riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (MathMax(0.01, MathMin(100.0, RiskPercent)) / 100.0);

   if(riskAmount <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double rangeSize = g_RangeHigh - g_RangeLow;
   if(rangeSize <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double riskPerLot = (rangeSize / tickSize) * tickValue;
   if(riskPerLot <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lots = riskAmount / riskPerLot;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(MathFloor(lots / step) * step, 2);
}

//+------------------------------------------------------------------+
//| Monitor pending orders; OCO when one fills                        |
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
      if(OrderGetInteger(ORDER_MAGIC) != g_Magic || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_STOP)  g_BuyStopTicket = ticket;
      else if(ot == ORDER_TYPE_SELL_STOP) g_SellStopTicket = ticket;
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
      if(PositionGetInteger(POSITION_MAGIC) == g_Magic && PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
   }
   return false;
}

bool HasPositionByType(ENUM_POSITION_TYPE pt)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_Magic || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == pt)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Trailing stop: move SL in favor; limit by TrailMaxMoves            |
//+------------------------------------------------------------------+
void TrailPositions()
{
   if(!UseTrailingStop || TrailStartPct <= 0 || TrailStepPct <= 0)
      return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_Magic || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(TrailMaxMoves > 0 && g_TrailTicket != ticket)
      {
         g_TrailTicket = ticket;
         g_TrailMoveCount = 0;
      }
      if(TrailMaxMoves > 0 && g_TrailMoveCount >= TrailMaxMoves)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double current  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl       = PositionGetDouble(POSITION_SL);
      double tp       = PositionGetDouble(POSITION_TP);

      double startDist = openPrice * (TrailStartPct / 100.0);
      double stepDist  = openPrice * (TrailStepPct / 100.0);
      if(startDist <= 0 || stepDist <= 0) continue;

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         if(current - openPrice < startDist) continue;
         double newSL = NormalizeDouble(current - stepDist, digits);
         if(newSL <= openPrice) continue;
         if(newSL <= sl + point) continue;
         if(g_Trade.PositionModify(ticket, newSL, tp))
            g_TrailMoveCount++;
      }
      else
      {
         if(openPrice - current < startDist) continue;
         double newSL = NormalizeDouble(current + stepDist, digits);
         if(newSL >= openPrice) continue;
         if(sl > 0 && newSL >= sl - point) continue;
         if(g_Trade.PositionModify(ticket, newSL, tp))
            g_TrailMoveCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| When position closed, reset trail counter for next position       |
//+------------------------------------------------------------------+
void OnPositionClosed(ulong ticket)
{
   if(g_TrailTicket == ticket)
   {
      g_TrailTicket = 0;
      g_TrailMoveCount = 0;
   }
}

//+------------------------------------------------------------------+
//| Prop firm: check daily loss and max drawdown                      |
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
         Print("RBP PROP: Daily loss limit breached! ", DoubleToString(dailyLossPct, 2), "% (max ", DailyLossLimitPct, "%)");
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
         Print("RBP PROP: Max drawdown breached! DD ", DoubleToString(maxDD, 2), "% (max ", MaxDrawdownPct, "%)");
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
      Print("RBP PROP: Phase 1 target reached! Profit ", DoubleToString(profitPct, 2), "%");
   }
   if(g_Phase1Complete && profitPct >= Phase1ProfitTarget + Phase2ProfitTarget)
      Print("RBP PROP: Phase 2 target reached! Total ", DoubleToString(profitPct, 2), "%");
}

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
      if(PositionGetInteger(POSITION_MAGIC) == g_Magic && PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         OnPositionClosed(ticket);
         g_Trade.PositionClose(ticket);
      }
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket <= 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != g_Magic || OrderGetString(ORDER_SYMBOL) != _Symbol)
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
   g_TrailTicket = 0;
   g_TrailMoveCount = 0;
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
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != g_Magic)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
      return;
   OnPositionClosed(trans.position);
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
      ResetDayState();

   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dtNow.year, dtNow.mon, dtNow.day));

   if(TimeCurrent() >= g_TradingTimeEnd)
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
      if(UsePendingOrders)
         PlacePendingOrders();
      else
         CheckBreakoutMarketOrder();
      return;
   }

   if(UsePendingOrders)
      MonitorPendingOrders();
   else
      CheckBreakoutMarketOrder();

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
      if(OrderGetInteger(ORDER_MAGIC) != g_Magic || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      g_OrdersPlaced = true;
      ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ot == ORDER_TYPE_BUY_STOP)  g_BuyStopTicket = ticket;
      else if(ot == ORDER_TYPE_SELL_STOP) g_SellStopTicket = ticket;
   }
   if(HasAnyPosition())
      g_TradeExecuted = true;
}

//+------------------------------------------------------------------+
//| Performance panel (from history, this EA only – no repaint)        |
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

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);

   HistorySelect(0, TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != g_Magic ||
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

   string text = StringFormat("RBP | Magic: %d | Trades: %.0f | Win%%: %.1f | PF: %.2f | P/L: %.2f | Daily: %.2f",
                              g_Magic, g_TotalTrades, winrate, pf, totalPL, g_DailyPL);
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
   if(TradingEndHour < 0 || TradingEndHour > 23 || TradingEndMinute < 0 || TradingEndMinute > 59)
      return false;
   if(RangeStartHour > RangeEndHour || (RangeStartHour == RangeEndHour && RangeStartMinute >= RangeEndMinute))
      return false;
   if(FixedLotSize <= 0 && RiskMoney <= 0 && (RiskPercent <= 0 || RiskPercent > 100))
      return false;
   if(UseTrailingStop && (TrailStartPct <= 0 || TrailStepPct <= 0))
      return false;
   if(EnablePropRules)
   {
      if(ChallengeAccountSize <= 0 || Phase1ProfitTarget <= 0 || Phase2ProfitTarget <= 0)
         return false;
      if(DailyLossLimitPct <= 0 || DailyLossLimitPct > 100 || MaxDrawdownPct <= 0 || MaxDrawdownPct > 100)
         return false;
      if(PropMagicRandomizer && (PropMagicOffset < 0 || PropMagicOffset > 999))
         return false;
   }
   return true;
}
//+------------------------------------------------------------------+
