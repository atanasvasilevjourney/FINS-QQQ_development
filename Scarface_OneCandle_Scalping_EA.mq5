//+------------------------------------------------------------------+
//|                              Scarface_OneCandle_Scalping_EA.mq5  |
//|     Scarface Trades "Simple One Candle Scalping" - US Open       |
//|     First 15-min candle after US open = range; retracement       |
//|     entries (Buy Limit at high, Sell Limit at low); SL=other side |
//|     TP = factor * range; optional trailing stop; prop firm rules |
//+------------------------------------------------------------------+
#property copyright "Scarface One Candle Scalping (BM Trading style)"
#property version   "1.00"
#property description "US open first candle range breakout with retracement entries."
#property description "Limit orders at range high/low; SL opposite side; TP factor."
#property description "Prop firm rules, chart visuals, trailing stop optional."

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- Session (server time; e.g. 16:30 for US open in GMT+2)
input group "=== Session (Server Time) ==="
input int      USOpenHour         = 16;   // US open hour
input int      USOpenMinute       = 30;   // US open minute
input int      OrderExpireHours   = 3;    // Cancel pending orders after (hours)

//--- Signal & timeframe
input group "=== Signal ==="
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M15; // Signal timeframe (first bar = trigger)
input double   LotSize            = 0.1;  // Lot size (fixed)
input double   TPFactor           = 2.0;  // TP = entry ± (TPFactor * range height)
input bool     TradeBuy           = true;  // Allow buy (limit at range high)
input bool     TradeSell          = true;  // Allow sell (limit at range low)
input int      MagicNumber        = 16016; // Magic number
input int      SlippagePoints     = 10;   // Slippage (points)
input double   MaxSpreadPoints    = 50;   // Max spread to allow new orders (0=off)

//--- Risk (optional)
input group "=== Risk ==="
input bool     UseRiskPercent     = false; // Use risk % for lot size
input double   RiskPercent        = 1.0;   // Risk per trade (% of balance)

//--- Trailing stop
input group "=== Trailing Stop ==="
input bool     UseTrailingStop    = true;  // Use trailing stop
input double   TrailingStartR     = 0.5;   // Start trailing after profit (in R; 0.5 = half range)
input double   TrailingStepR     = 0.25;   // Trail step (in R; move SL every 0.25R profit)

//--- Visuals
input group "=== Visuals ==="
input bool     ShowRangeOnChart   = true;  // Draw range, entry levels, labels

//--- Prop firm challenge
input group "=== Prop Firm Challenge ==="
input bool     EnableChallengeRules = false; // Enable prop firm rules
input double   ChallengeAccountSize = 25000.0; // Challenge account size ($)
input double   Phase1ProfitTarget = 8.0;   // Phase 1 profit target (%)
input double   Phase2ProfitTarget = 5.0;   // Phase 2 profit target (%)
input double   DailyLossLimit     = 5.0;   // Daily loss limit (%)
input double   MaxLossLimit       = 10.0;  // Max drawdown / loss limit (%)
input int      MinTradingDays     = 5;     // Min trading days (info only)
input bool     Phase1Complete     = false; // Phase 1 done (manual toggle)

//--- Globals
datetime   g_USOpenToday;        // US open time today
double     g_TriggerHigh, g_TriggerLow, g_RangeHeight;
bool       g_RangeValid;
datetime   g_LastRangeDate;
bool       g_IsTradeDay;        // Already placed/filled one trade today
ulong      g_BuyLimitTicket, g_SellLimitTicket;
bool       g_BuyLimitPlaced, g_SellLimitPlaced;
datetime   g_LastBarTime;        // Last processed bar (avoid duplicate signals)
datetime   g_OrderExpireTime;

// Challenge
double     g_InitialBalance, g_DailyStartBalance, g_HighestBalance;
datetime   g_DailyResetTime;
int        g_TradingDaysCount;
bool       g_DailyLimitBreached, g_MaxLimitBreached, g_Phase1Complete;

CTrade        g_Trade;
COrderInfo    g_OrderInfo;
CPositionInfo g_PosInfo;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_Trade.SetExpertMagicNumber(MagicNumber);
   g_Trade.SetDeviationInPoints(SlippagePoints);
   g_Trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_TriggerHigh = 0; g_TriggerLow = 0; g_RangeHeight = 0;
   g_RangeValid = false; g_LastRangeDate = 0;
   g_IsTradeDay = false;
   g_BuyLimitTicket = 0; g_SellLimitTicket = 0;
   g_BuyLimitPlaced = false; g_SellLimitPlaced = false;
   g_LastBarTime = 0; g_OrderExpireTime = 0;

   if (EnableChallengeRules)
   {
      g_InitialBalance = ChallengeAccountSize;
      g_DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_DailyResetTime = 0;
      g_TradingDaysCount = 0;
      g_DailyLimitBreached = false;
      g_MaxLimitBreached = false;
      g_Phase1Complete = Phase1Complete;
      g_HighestBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      Print("Scarface OCS: Challenge rules ON | Account $", ChallengeAccountSize,
            " | Phase1 ", Phase1ProfitTarget, "% | Daily loss ", DailyLossLimit, "%");
   }

   if (!ValidateInputs())
   {
      Print("Scarface OCS: Invalid inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }

   SyncStateWithExistingOrders();
   Print("Scarface One Candle Scalping EA initialized. US Open: ", USOpenHour, ":", USOpenMinute);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (ShowRangeOnChart)
      DeleteVisualObjects();
   Print("Scarface One Candle Scalping EA deinitialized.");
}

//+------------------------------------------------------------------+
//| Recalculate US open and expiration for today (server time)        |
//+------------------------------------------------------------------+
void RecalculateSessionTimes()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = USOpenHour;
   dt.min  = USOpenMinute;
   dt.sec  = 0;
   g_USOpenToday = StructToTime(dt);
   g_OrderExpireTime = g_USOpenToday + (OrderExpireHours * 3600);
}

//+------------------------------------------------------------------+
//| Get index of bar that opens at US open (trigger bar)              |
//+------------------------------------------------------------------+
int GetTriggerBarIndex()
{
   return iBarShift(_Symbol, SignalTimeframe, g_USOpenToday, false);
}

//+------------------------------------------------------------------+
//| Update range from first candle after US open                      |
//+------------------------------------------------------------------+
bool UpdateRangeFromTriggerBar()
{
   RecalculateSessionTimes();

   // Must be after trigger bar has closed (US open + 1 bar)
   int periodSec = PeriodSeconds(SignalTimeframe);
   if (periodSec <= 0)
      periodSec = 15 * 60;
   if (TimeCurrent() < g_USOpenToday + periodSec)
      return false;

   int idx = GetTriggerBarIndex();
   if (idx < 0)
      return false;

   g_TriggerHigh = iHigh(_Symbol, SignalTimeframe, idx);
   g_TriggerLow  = iLow(_Symbol, SignalTimeframe, idx);
   g_RangeHeight = g_TriggerHigh - g_TriggerLow;
   g_RangeValid  = (g_RangeHeight > 0);
   g_LastRangeDate = g_USOpenToday;

   if (g_RangeValid && ShowRangeOnChart)
      DrawVisuals();

   return g_RangeValid;
}

//+------------------------------------------------------------------+
//| Check if last closed bar closed outside range (1=above, -1=below) |
//+------------------------------------------------------------------+
int GetBreakoutDirection()
{
   double close1 = iClose(_Symbol, SignalTimeframe, 1);
   datetime barTime = iTime(_Symbol, SignalTimeframe, 1);

   if (barTime == g_LastBarTime)
      return 0;

   if (close1 > g_TriggerHigh)
      return 1;
   if (close1 < g_TriggerLow)
      return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Place Buy Limit at trigger high with SL/TP and expiration         |
//+------------------------------------------------------------------+
bool PlaceBuyLimit()
{
   if (g_BuyLimitPlaced)
      return true;
   if (EnableChallengeRules && !CanPlaceNewOrder())
      return false;

   double price = NormalizePrice(g_TriggerHigh);
   double sl    = NormalizePrice(g_TriggerLow);
   double tp    = NormalizePrice(g_TriggerHigh + TPFactor * g_RangeHeight);
   double lots  = GetLotSize();

   if (lots <= 0 || !CheckSpread())
      return false;

   if (g_Trade.BuyLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, g_OrderExpireTime, "ScarfaceOCS Buy"))
   {
      g_BuyLimitTicket = g_Trade.ResultOrder();
      g_BuyLimitPlaced = true;
      g_IsTradeDay = true;
      Print("Scarface OCS: Buy Limit at ", price, " SL=", sl, " TP=", tp);
      if (ShowRangeOnChart)
         DrawVisuals();
      return true;
   }
   Print("Scarface OCS: Buy Limit failed ", g_Trade.ResultRetcode());
   return false;
}

//+------------------------------------------------------------------+
//| Place Sell Limit at trigger low                                   |
//+------------------------------------------------------------------+
bool PlaceSellLimit()
{
   if (g_SellLimitPlaced)
      return true;
   if (EnableChallengeRules && !CanPlaceNewOrder())
      return false;

   double price = NormalizePrice(g_TriggerLow);
   double sl    = NormalizePrice(g_TriggerHigh);
   double tp    = NormalizePrice(g_TriggerLow - TPFactor * g_RangeHeight);
   double lots  = GetLotSize();

   if (lots <= 0 || !CheckSpread())
      return false;

   if (g_Trade.SellLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, g_OrderExpireTime, "ScarfaceOCS Sell"))
   {
      g_SellLimitTicket = g_Trade.ResultOrder();
      g_SellLimitPlaced = true;
      g_IsTradeDay = true;
      Print("Scarface OCS: Sell Limit at ", price, " SL=", sl, " TP=", tp);
      if (ShowRangeOnChart)
         DrawVisuals();
      return true;
   }
   Print("Scarface OCS: Sell Limit failed ", g_Trade.ResultRetcode());
   return false;
}

//+------------------------------------------------------------------+
//| Manage pending orders and trailing stop                           |
//+------------------------------------------------------------------+
void ManageOrdersAndPositions()
{
   // Cancel pending at expiration
   if (TimeCurrent() >= g_OrderExpireTime)
   {
      DeleteAllPendingOrders();
      return;
   }
   // One trade per day: if we have a position, cancel pendings
   if (HasOpenPosition())
   {
      DeleteAllPendingOrders();
      if (UseTrailingStop)
         ProcessTrailingStop();
      return;
   }
   RefreshPendingFlags();
   if (UseTrailingStop)
      ProcessTrailingStop();
}

void ProcessTrailingStop()
{
   double oneR = g_RangeHeight;
   if (oneR <= 0)
   {
      // After EA restart: estimate 1R from open position (open to initial SL distance)
      for (int j = PositionsTotal() - 1; j >= 0; j--)
      {
         if (!g_PosInfo.SelectByIndex(j))
            continue;
         if (g_PosInfo.Symbol() != _Symbol || g_PosInfo.Magic() != MagicNumber)
            continue;
         double op = g_PosInfo.PriceOpen();
         double sl = g_PosInfo.StopLoss();
         if (sl > 0)
            oneR = MathAbs(op - sl);
         break;
      }
   }
   if (oneR <= 0)
      return;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_PosInfo.SelectByIndex(i))
         continue;
      if (g_PosInfo.Symbol() != _Symbol || g_PosInfo.Magic() != MagicNumber)
         continue;

      ulong ticket = g_PosInfo.Ticket();
      double openPrice = g_PosInfo.PriceOpen();
      double currentSL = g_PosInfo.StopLoss();
      double currentTP = g_PosInfo.TakeProfit();

      if (g_PosInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profitR = (bid - openPrice) / oneR;
         if (profitR < TrailingStartR)
            continue;

         double newSL = openPrice + (profitR - TrailingStepR) * oneR;
         newSL = NormalizePrice(newSL);
         if (newSL <= openPrice)
            continue;
         if (currentSL > 0 && newSL <= currentSL)
            continue;
         if (newSL >= bid - _Point)
            continue;
         if (currentTP > 0 && newSL >= currentTP)
            continue;

         if (g_Trade.PositionModify(ticket, newSL, currentTP))
            continue;
      }
      else // SELL
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitR = (openPrice - ask) / oneR;
         if (profitR < TrailingStartR)
            continue;

         double newSL = openPrice - (profitR - TrailingStepR) * oneR;
         newSL = NormalizePrice(newSL);
         if (newSL >= openPrice)
            continue;
         if (currentSL > 0 && newSL >= currentSL)
            continue;
         if (newSL <= ask + _Point)
            continue;
         if (currentTP > 0 && newSL <= currentTP)
            continue;

         g_Trade.PositionModify(ticket, newSL, currentTP);
      }
   }
}

void RefreshPendingFlags()
{
   g_BuyLimitTicket  = FindPendingOrder(ORDER_TYPE_BUY_LIMIT);
   g_SellLimitTicket = FindPendingOrder(ORDER_TYPE_SELL_LIMIT);
   g_BuyLimitPlaced  = (g_BuyLimitTicket > 0);
   g_SellLimitPlaced = (g_SellLimitTicket > 0);
}

ulong FindPendingOrder(ENUM_ORDER_TYPE type)
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!g_OrderInfo.SelectByIndex(i))
         continue;
      if (g_OrderInfo.Symbol() != _Symbol || g_OrderInfo.Magic() != MagicNumber)
         continue;
      if (g_OrderInfo.OrderType() == type)
         return g_OrderInfo.Ticket();
   }
   return 0;
}

bool HasOpenPosition()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!PositionSelectByTicket(PositionGetTicket(i)))
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

void DeleteAllPendingOrders()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!g_OrderInfo.SelectByIndex(i))
         continue;
      if (g_OrderInfo.Symbol() != _Symbol || g_OrderInfo.Magic() != MagicNumber)
         continue;
      g_Trade.OrderDelete(g_OrderInfo.Ticket());
   }
   g_BuyLimitTicket = 0; g_SellLimitTicket = 0;
   g_BuyLimitPlaced = false; g_SellLimitPlaced = false;
}

//+------------------------------------------------------------------+
//| New bar in signal timeframe? (static last total bars)             |
//+------------------------------------------------------------------+
bool IsNewSignalBar()
{
   int barsNow = iBars(_Symbol, SignalTimeframe);
   static int lastBars = 0;
   if (barsNow != lastBars)
   {
      lastBars = barsNow;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Main tick                                                         |
//+------------------------------------------------------------------+
void OnTick()
{
   RecalculateSessionTimes();

   if (EnableChallengeRules)
   {
      CheckChallengeLimits();
      if (g_DailyLimitBreached || g_MaxLimitBreached)
      {
         DeleteAllPendingOrders();
         return;
      }
   }

   // New day: reset range and trade-per-day
   if (IsNewDay())
   {
      g_RangeValid = false;
      g_LastRangeDate = 0;
      g_IsTradeDay = false;
      g_BuyLimitPlaced = false;
      g_SellLimitPlaced = false;
      g_BuyLimitTicket = 0;
      g_SellLimitTicket = 0;
      g_LastBarTime = 0;
      DeleteVisualObjects();
      if (EnableChallengeRules)
         ResetDailyChallengeTracking();
   }

   // Before trigger bar closes: nothing
   int periodSec = PeriodSeconds(SignalTimeframe);
   if (periodSec <= 0)
      periodSec = 15 * 60;
   if (TimeCurrent() < g_USOpenToday + periodSec)
   {
      ManageOrdersAndPositions();
      return;
   }

   // After expiration: only manage
   if (TimeCurrent() >= g_OrderExpireTime)
   {
      ManageOrdersAndPositions();
      return;
   }

   if (!g_RangeValid)
   {
      if (!UpdateRangeFromTriggerBar())
      {
         ManageOrdersAndPositions();
         return;
      }
   }

   // Check for breakout only on new bar to avoid duplicate signals
   if (IsNewSignalBar())
   {
      int dir = GetBreakoutDirection();
      if (dir == 1)
      {
         g_LastBarTime = iTime(_Symbol, SignalTimeframe, 1);
         if (!g_IsTradeDay && TimeCurrent() < g_OrderExpireTime && TradeBuy)
            PlaceBuyLimit();
      }
      else if (dir == -1)
      {
         g_LastBarTime = iTime(_Symbol, SignalTimeframe, 1);
         if (!g_IsTradeDay && TimeCurrent() < g_OrderExpireTime && TradeSell)
            PlaceSellLimit();
      }
   }

   ManageOrdersAndPositions();
}

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   return NormalizeDouble(price, _Digits);
}

double GetLotSize()
{
   if (UseRiskPercent)
   {
      double riskPct = MathMax(0.01, MathMin(100, RiskPercent)) / 100.0;
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount = balance * riskPct;
      double riskDistance = g_RangeHeight;
      if (riskDistance <= 0)
         return LotSize;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if (tickSize <= 0 || tickValue <= 0)
         return LotSize;
      double riskPerLot = (riskDistance / tickSize) * tickValue;
      if (riskPerLot <= 0)
         return LotSize;
      double lots = riskAmount / riskPerLot;
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      lots = MathFloor(lots / step) * step;
      lots = MathMax(minLot, MathMin(maxLot, lots));
      return NormalizeDouble(lots, 2);
   }
   return NormalizeDouble(MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), LotSize), 2);
}

bool CheckSpread()
{
   if (MaxSpreadPoints <= 0)
      return true;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= (long)MaxSpreadPoints);
}

bool ValidateInputs()
{
   if (USOpenHour < 0 || USOpenHour > 23 || USOpenMinute < 0 || USOpenMinute > 59)
      return false;
   if (LotSize <= 0 && !UseRiskPercent)
      return false;
   if (UseRiskPercent && (RiskPercent <= 0 || RiskPercent > 100))
      return false;
   if (!TradeBuy && !TradeSell)
      return false;
   if (EnableChallengeRules)
   {
      if (ChallengeAccountSize <= 0)
         return false;
      if (DailyLossLimit <= 0 || DailyLossLimit > 100)
         return false;
      if (MaxLossLimit <= 0 || MaxLossLimit > 100)
         return false;
      if (Phase1ProfitTarget <= 0 || Phase1ProfitTarget > 100)
         return false;
      if (Phase2ProfitTarget <= 0 || Phase2ProfitTarget > 100)
         return false;
   }
   return true;
}

bool IsNewDay()
{
   static int lastDayOfYear = 0;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if (lastDayOfYear != dt.day_of_year)
   {
      lastDayOfYear = dt.day_of_year;
      return true;
   }
   return false;
}

void SyncStateWithExistingOrders()
{
   RefreshPendingFlags();
   if (HasOpenPosition())
      g_IsTradeDay = true;
}

//+------------------------------------------------------------------+
//| Challenge rules                                                   |
//+------------------------------------------------------------------+
void CheckChallengeLimits()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if (balance > g_HighestBalance)
      g_HighestBalance = balance;

   double dailyLoss = g_DailyStartBalance - equity;
   double dailyLossPct = (g_DailyStartBalance > 0) ? (dailyLoss / g_DailyStartBalance) * 100.0 : 0;
   if (dailyLossPct >= DailyLossLimit)
   {
      if (!g_DailyLimitBreached)
      {
         g_DailyLimitBreached = true;
         Print("CHALLENGE: Daily loss limit reached ", DoubleToString(dailyLossPct, 2), "%");
      }
   }

   double totalLoss = g_InitialBalance - equity;
   double maxLossPct = (g_InitialBalance > 0) ? (totalLoss / g_InitialBalance) * 100.0 : 0;
   if (maxLossPct >= MaxLossLimit)
   {
      if (!g_MaxLimitBreached)
      {
         g_MaxLimitBreached = true;
         Print("CHALLENGE: Max loss limit reached ", DoubleToString(maxLossPct, 2), "%");
      }
   }

   double profit = equity - g_InitialBalance;
   double profitPct = (g_InitialBalance > 0) ? (profit / g_InitialBalance) * 100.0 : 0;
   if (!g_Phase1Complete && profitPct >= Phase1ProfitTarget)
   {
      g_Phase1Complete = true;
      Print("CHALLENGE: Phase 1 target reached ", DoubleToString(profitPct, 2), "%");
   }
}

void ResetDailyChallengeTracking()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if (HasOpenPosition() || OrdersTotal() > 0)
      g_TradingDaysCount++;
   g_DailyStartBalance = balance;
   g_DailyLimitBreached = false;
   g_DailyResetTime = TimeCurrent();
}

bool CanPlaceNewOrder()
{
   if (!EnableChallengeRules)
      return true;
   if (g_DailyLimitBreached || g_MaxLimitBreached)
      return false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossPct = (g_DailyStartBalance > 0)
      ? ((g_DailyStartBalance - equity) / g_DailyStartBalance) * 100.0 : 0;
   if (dailyLossPct >= DailyLossLimit)
      return false;
   double maxLossPct = (g_InitialBalance > 0)
      ? ((g_InitialBalance - equity) / g_InitialBalance) * 100.0 : 0;
   if (maxLossPct >= MaxLossLimit)
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Chart visuals: range, entry lines, labels                         |
//+------------------------------------------------------------------+
#define PREFIX "ScarfaceOCS_"

void DrawVisuals()
{
   if (!g_RangeValid || !ShowRangeOnChart)
      return;
   DeleteVisualObjects();

   datetime tEnd = g_USOpenToday + PeriodSeconds(SignalTimeframe);
   if (tEnd <= g_USOpenToday)
      tEnd = g_USOpenToday + 15 * 60;

   // Range rectangle (semi-transparent)
   ObjectCreate(0, PREFIX "Rect", OBJ_RECTANGLE, 0, g_USOpenToday, g_TriggerHigh, tEnd, g_TriggerLow);
   ObjectSetInteger(0, PREFIX "Rect", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, PREFIX "Rect", OBJPROP_FILL, true);
   ObjectSetInteger(0, PREFIX "Rect", OBJPROP_BACK, true);
   ObjectSetInteger(0, PREFIX "Rect", OBJPROP_SELECTABLE, false);

   // Entry levels: high (buy) and low (sell)
   ObjectCreate(0, PREFIX "EntryHigh", OBJ_HLINE, 0, 0, g_TriggerHigh);
   ObjectSetInteger(0, PREFIX "EntryHigh", OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, PREFIX "EntryHigh", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, PREFIX "EntryHigh", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, PREFIX "EntryHigh", OBJPROP_BACK, false);
   ObjectSetInteger(0, PREFIX "EntryHigh", OBJPROP_SELECTABLE, false);
   ObjectSetString(0, PREFIX "EntryHigh", OBJPROP_NAME, " BUY ENTRY ");

   ObjectCreate(0, PREFIX "EntryLow", OBJ_HLINE, 0, 0, g_TriggerLow);
   ObjectSetInteger(0, PREFIX "EntryLow", OBJPROP_COLOR, clrOrangeRed);
   ObjectSetInteger(0, PREFIX "EntryLow", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, PREFIX "EntryLow", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, PREFIX "EntryLow", OBJPROP_BACK, false);
   ObjectSetInteger(0, PREFIX "EntryLow", OBJPROP_SELECTABLE, false);
   ObjectSetString(0, PREFIX "EntryLow", OBJPROP_NAME, " SELL ENTRY ");

   // Labels
   ObjectCreate(0, PREFIX "LblHigh", OBJ_TEXT, 0, g_USOpenToday, g_TriggerHigh);
   ObjectSetString(0, PREFIX "LblHigh", OBJPROP_TEXT, " Buy Limit | SL below range ");
   ObjectSetInteger(0, PREFIX "LblHigh", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, PREFIX "LblHigh", OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, PREFIX "LblHigh", OBJPROP_BACK, false);

   ObjectCreate(0, PREFIX "LblLow", OBJ_TEXT, 0, g_USOpenToday, g_TriggerLow);
   ObjectSetString(0, PREFIX "LblLow", OBJPROP_TEXT, " Sell Limit | SL above range ");
   ObjectSetInteger(0, PREFIX "LblLow", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, PREFIX "LblLow", OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, PREFIX "LblLow", OBJPROP_BACK, false);

   ChartRedraw(0);
}

void DeleteVisualObjects()
{
   ObjectDelete(0, PREFIX "Rect");
   ObjectDelete(0, PREFIX "EntryHigh");
   ObjectDelete(0, PREFIX "EntryLow");
   ObjectDelete(0, PREFIX "LblHigh");
   ObjectDelete(0, PREFIX "LblLow");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
