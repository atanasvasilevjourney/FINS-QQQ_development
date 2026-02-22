//+------------------------------------------------------------------+
//|                                              ORB_15Min_EA.mq5    |
//|           15-Minute Opening Range Breakout Expert Advisor        |
//|  Range = first 15-min candle; entries via limit at ORB line      |
//|  on 5-min close outside range; SL = range mid, TP = 2x height   |
//|                                                                  |
//|  Backtesting: Attach to M5 or M1 chart; Strategy Tester with    |
//|  "Every tick" or "1 minute OHLC"; session times in server time.  |
//+------------------------------------------------------------------+
#property copyright "ORB 15-Min Strategy"
#property version   "1.01"
#property description "Identifies the first 15-min range candle of the session,"
#property description "monitors 5-min candles for breakout, places limit orders"
#property description "at the ORB line. SL = range middle, TP = 2 x range height."
#property description "Includes prop firm challenge rules: daily/max loss limits, profit targets."

#include <Trade\Trade.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input parameters
input group "=== Session (Server Time) ==="
input int      SessionStartHour   = 10;   // Session start hour (e.g. 10 = 10:00)
input int      SessionStartMinute = 0;    // Session start minute (e.g. 0 = :00)
input int      SessionEndHour    = 18;   // Session end hour (cancel orders / stop trading)
input int      SessionEndMinute   = 0;    // Session end minute

input group "=== Trading ==="
input double   LotSize            = 0.1;  // Lot size (fixed)
input int      MagicNumber        = 15015; // Magic number
input int      SlippagePoints     = 10;   // Slippage in points
input double   MaxSpreadPoints    = 50;   // Max spread (points) to allow new orders (0 = disable)

input group "=== Risk (Optional) ==="
input bool     UseRiskPercent     = false; // Use risk % for lot size
input double   RiskPercent        = 1.0;   // Risk per trade (% of balance, if UseRiskPercent)

input group "=== Behavior ==="
input bool     OneTradePerDay     = true;  // Only one trade per day (cancel opposite pending when one fills)
input bool     ShowRangeOnChart   = true;  // Draw range rectangle and mid line

input group "=== Prop Firm Challenge Rules ==="
input bool     EnableChallengeRules = false; // Enable prop firm challenge rules
input double   ChallengeAccountSize = 25000.0; // Challenge account size ($)
input double   Phase1ProfitTarget = 8.0; // Phase 1 profit target (%)
input double   Phase2ProfitTarget = 5.0; // Phase 2 profit target (%)
input double   DailyLossLimit = 5.0; // Daily loss limit (%)
input double   MaxLossLimit = 10.0; // Maximum loss limit (%)
input int      MinTradingDays = 5; // Minimum trading days
input bool     Phase1Complete = false; // Phase 1 completed (manual toggle)

//--- Global state
datetime g_SessionStart;       // Start of session (today)
datetime g_RangeCandleEnd;     // End of first 15-min candle (session start + 15 min)
datetime g_SessionEnd;        // End of session
double   g_RangeHigh;
double   g_RangeLow;
double   g_RangeMid;
double   g_RangeHeight;
bool     g_RangeValid;        // True when we have a valid range for today
datetime g_LastRangeDate;     // Date of current range (to reset on new day)
bool     g_BuyLimitPlaced;    // Already placed buy limit this session
bool     g_SellLimitPlaced;   // Already placed sell limit this session
ulong    g_BuyLimitTicket;
ulong    g_SellLimitTicket;
datetime g_LastBarTimeM5;     // Last processed M5 bar time (avoid duplicate signals)

//--- Challenge tracking variables
double   g_InitialBalance;    // Starting balance for challenge
double   g_DailyStartBalance; // Balance at start of current day
datetime g_DailyResetTime;    // Last daily reset time
int      g_TradingDaysCount;  // Number of trading days
bool     g_DailyLimitBreached; // Daily loss limit breached today
bool     g_MaxLimitBreached;  // Maximum loss limit breached
bool     g_Phase1Complete;    // Phase 1 profit target reached
double   g_HighestBalance;     // Highest balance reached (for max drawdown calc)

CTrade  g_Trade;
COrderInfo g_OrderInfo;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_Trade.SetExpertMagicNumber(MagicNumber);
   g_Trade.SetDeviationInPoints(SlippagePoints);
   // Limit orders: use RETURN (fill what's possible) for broad compatibility
   g_Trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_RangeHigh = 0;
   g_RangeLow = 0;
   g_RangeMid = 0;
   g_RangeHeight = 0;
   g_RangeValid = false;
   g_LastRangeDate = 0;
   g_BuyLimitPlaced = false;
   g_SellLimitPlaced = false;
   g_BuyLimitTicket = 0;
   g_SellLimitTicket = 0;
   g_LastBarTimeM5 = 0;

   // Initialize challenge tracking
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
      Print("Challenge Rules Enabled - Account: $", ChallengeAccountSize, 
            " | Phase 1 Target: ", Phase1ProfitTarget, "% | Daily Loss Limit: ", DailyLossLimit, "%");
   }

   if (!ValidateInputs())
   {
      Print("ORB 15Min EA: Invalid inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }

   RecalculateSessionTimes();
   SyncStateWithExistingOrders();

   Print("ORB 15Min EA initialized. Session: ", TimeToString(g_SessionStart, TIME_MINUTES),
        " - ", TimeToString(g_SessionEnd, TIME_MINUTES));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (ShowRangeOnChart)
      DeleteRangeObjects();
   Print("ORB 15Min EA deinitialized.");
}

//+------------------------------------------------------------------+
//| Recalculate session start/end for current day (server time)      |
//+------------------------------------------------------------------+
void RecalculateSessionTimes()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = SessionStartHour;
   dt.min  = SessionStartMinute;
   dt.sec  = 0;
   g_SessionStart = StructToTime(dt);
   g_RangeCandleEnd = g_SessionStart + 15 * 60;  // First 15-min candle ends here

   dt.hour = SessionEndHour;
   dt.min  = SessionEndMinute;
   dt.sec  = 0;
   g_SessionEnd = StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Step 1 & 2: Detect first 15-min candle of session and get        |
//| high, low, middle price. Uses M15 timeframe.                     |
//+------------------------------------------------------------------+
bool UpdateRangeFrom15MinCandle()
{
   RecalculateSessionTimes();

   // Only use range after the 15-min candle has closed
   if (TimeCurrent() < g_RangeCandleEnd)
      return false;

   MqlRates m15[];
   int need = 2;
   int copied = CopyRates(_Symbol, PERIOD_M15, g_SessionStart, need, m15);
   if (copied < 1)
   {
      return false;
   }

   // We want the bar that opens at g_SessionStart (first 15-min of session)
   int barIndex = -1;
   for (int i = 0; i < copied; i++)
   {
      if (m15[i].time == g_SessionStart)
      {
         barIndex = i;
         break;
      }
   }
   if (barIndex < 0)
      return false;

   g_RangeHigh   = m15[barIndex].high;
   g_RangeLow    = m15[barIndex].low;
   g_RangeMid    = (g_RangeHigh + g_RangeLow) / 2.0;
   g_RangeHeight = g_RangeHigh - g_RangeLow;
   g_RangeValid  = (g_RangeHeight > 0);
   g_LastRangeDate = g_SessionStart;

   if (g_RangeValid && ShowRangeOnChart)
      DrawRangeOnChart();

   return g_RangeValid;
}

//+------------------------------------------------------------------+
//| Step 3: Check if last closed 5-min candle closed outside range   |
//| Returns: 1 = close above high, -1 = close below low, 0 = no      |
//+------------------------------------------------------------------+
int Get5MinBreakoutDirection()
{
   MqlRates m5[];
   // Request last 2 completed M5 bars (index 1 = last closed)
   int copied = CopyRates(_Symbol, PERIOD_M5, 0, 2, m5);
   if (copied < 2)
      return 0;

   double closePrice = m5[1].close;
   datetime barTime  = m5[1].time;

   // Avoid processing same bar twice
   if (barTime == g_LastBarTimeM5)
      return 0;

   if (closePrice > g_RangeHigh)
      return 1;
   if (closePrice < g_RangeLow)
      return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Step 4 & 5: Place limit order at ORB line with SL and TP         |
//| Buy:  limit at range high, SL = mid, TP = high + 2*height         |
//| Sell: limit at range low,  SL = mid, TP = low - 2*height         |
//+------------------------------------------------------------------+
bool PlaceBuyLimitAtORB()
{
   if (g_BuyLimitPlaced)
      return true;

   // Check challenge rules before placing order
   if (EnableChallengeRules && !CanPlaceNewOrder())
      return false;

   double price = NormalizePrice(g_RangeHigh);
   double sl    = NormalizePrice(g_RangeMid);
   double tp    = NormalizePrice(g_RangeHigh + 2.0 * g_RangeHeight);
   double lots  = GetLotSize();

   if (lots <= 0)
      return false;
   if (!CheckSpread())
      return false;

   if (g_Trade.BuyLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ORB15 Buy"))
   {
      g_BuyLimitTicket = g_Trade.ResultOrder();
      g_BuyLimitPlaced = true;
      Print("ORB15: Buy Limit placed at ", price, " SL=", sl, " TP=", tp);
      return true;
   }
   Print("ORB15: Buy Limit failed: ", g_Trade.ResultRetcode());
   return false;
}

bool PlaceSellLimitAtORB()
{
   if (g_SellLimitPlaced)
      return true;

   // Check challenge rules before placing order
   if (EnableChallengeRules && !CanPlaceNewOrder())
      return false;

   double price = NormalizePrice(g_RangeLow);
   double sl    = NormalizePrice(g_RangeMid);
   double tp    = NormalizePrice(g_RangeLow - 2.0 * g_RangeHeight);
   double lots  = GetLotSize();

   if (lots <= 0)
      return false;
   if (!CheckSpread())
      return false;

   if (g_Trade.SellLimit(lots, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "ORB15 Sell"))
   {
      g_SellLimitTicket = g_Trade.ResultOrder();
      g_SellLimitPlaced = true;
      Print("ORB15: Sell Limit placed at ", price, " SL=", sl, " TP=", tp);
      return true;
   }
   Print("ORB15: Sell Limit failed: ", g_Trade.ResultRetcode());
   return false;
}

//+------------------------------------------------------------------+
//| Step 6: Manage open positions and pending orders                  |
//+------------------------------------------------------------------+
void ManageOrdersAndPositions()
{
   // Cancel pending orders at session end
   if (TimeCurrent() >= g_SessionEnd)
   {
      DeleteAllPendingOrders();
      return;
   }

   // If one trade per day and we have a position, cancel opposite pending
   if (OneTradePerDay && HasOpenPosition())
   {
      DeleteAllPendingOrders();
      return;
   }

   // Refresh ticket state (orders might have been filled or deleted externally)
   RefreshPendingFlags();
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
   g_BuyLimitTicket  = 0;
   g_SellLimitTicket = 0;
   g_BuyLimitPlaced  = false;
   g_SellLimitPlaced = false;
}

//+------------------------------------------------------------------+
//| Main tick logic: range detection, breakout detection, place       |
//| limit orders, manage orders.                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   RecalculateSessionTimes();

   // Check challenge rules if enabled
   if (EnableChallengeRules)
   {
      CheckChallengeLimits();
      if (g_DailyLimitBreached || g_MaxLimitBreached)
      {
         // Stop trading if limits breached
         DeleteAllPendingOrders();
         return;
      }
   }

   // New day: reset range and order flags
   if (IsNewDay())
   {
      g_RangeValid = false;
      g_LastRangeDate = 0;
      g_BuyLimitPlaced = false;
      g_SellLimitPlaced = false;
      g_BuyLimitTicket = 0;
      g_SellLimitTicket = 0;
      g_LastBarTimeM5 = 0;
      DeleteRangeObjects();
      
      // Reset daily challenge tracking
      if (EnableChallengeRules)
      {
         ResetDailyChallengeTracking();
      }
   }

   // Before range candle ends: do nothing (or could pre-calculate range from forming bar)
   if (TimeCurrent() < g_RangeCandleEnd)
      return;

   // After session end: only manage (cancel pendings)
   if (TimeCurrent() >= g_SessionEnd)
   {
      ManageOrdersAndPositions();
      return;
   }

   // Ensure we have valid range (first 15-min candle of session)
   if (!g_RangeValid)
   {
      if (!UpdateRangeFrom15MinCandle())
         return;
   }

   // Monitor 5-min candles for breakout
   int breakout = Get5MinBreakoutDirection();
   if (breakout == 1)
   {
      g_LastBarTimeM5 = GetLastClosedM5BarTime();
      PlaceBuyLimitAtORB();
   }
   else if (breakout == -1)
   {
      g_LastBarTimeM5 = GetLastClosedM5BarTime();
      PlaceSellLimitAtORB();
   }

   ManageOrdersAndPositions();
}

datetime GetLastClosedM5BarTime()
{
   MqlRates m5[];
   if (CopyRates(_Symbol, PERIOD_M5, 0, 2, m5) < 2)
      return 0;
   return m5[1].time;
}

//+------------------------------------------------------------------+
//| Helpers: normalize price, lot size, spread, validation           |
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
      // Risk per trade = distance from entry to SL in price * contract size
      double riskDistance = MathAbs(g_RangeHigh - g_RangeMid);  // use buy case; sell similar
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
   if (spread > (long)MaxSpreadPoints)
      return false;
   return true;
}

bool ValidateInputs()
{
   if (SessionStartHour < 0 || SessionStartHour > 23 || SessionStartMinute < 0 || SessionStartMinute > 59)
      return false;
   if (LotSize <= 0 && !UseRiskPercent)
      return false;
   if (UseRiskPercent && (RiskPercent <= 0 || RiskPercent > 100))
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
      if (MinTradingDays < 0)
         return false;
   }
   return true;
}

bool IsNewDay()
{
   static datetime lastDay = 0;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day));
   if (lastDay != today)
   {
      lastDay = today;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Sync state with existing orders (e.g. after restart)            |
//+------------------------------------------------------------------+
void SyncStateWithExistingOrders()
{
   RefreshPendingFlags();
}

//+------------------------------------------------------------------+
//| Chart objects: draw range rectangle and middle line              |
//+------------------------------------------------------------------+
void DrawRangeOnChart()
{
   DeleteRangeObjects();
   string prefix = "ORB15_";
   string dateStr = TimeToString(g_SessionStart, TIME_DATE);

   ObjectCreate(0, prefix + "Rect", OBJ_RECTANGLE, 0, g_SessionStart, g_RangeHigh, g_RangeCandleEnd, g_RangeLow);
   ObjectSetInteger(0, prefix + "Rect", OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, prefix + "Rect", OBJPROP_FILL, true);
   ObjectSetInteger(0, prefix + "Rect", OBJPROP_BACK, true);
   ObjectSetInteger(0, prefix + "Rect", OBJPROP_SELECTABLE, false);

   ObjectCreate(0, prefix + "Mid", OBJ_TREND, 0, g_SessionStart, g_RangeMid, g_SessionEnd, g_RangeMid);
   ObjectSetInteger(0, prefix + "Mid", OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, prefix + "Mid", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, prefix + "Mid", OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, prefix + "Mid", OBJPROP_BACK, true);
   ObjectSetInteger(0, prefix + "Mid", OBJPROP_SELECTABLE, false);
}

void DeleteRangeObjects()
{
   ObjectDelete(0, "ORB15_Rect");
   ObjectDelete(0, "ORB15_Mid");
}

//+------------------------------------------------------------------+
//| Challenge Rules: Check daily and maximum loss limits            |
//+------------------------------------------------------------------+
void CheckChallengeLimits()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Update highest balance for drawdown calculation
   if (currentBalance > g_HighestBalance)
      g_HighestBalance = currentBalance;
   
   // Check daily loss limit (5%)
   double dailyLoss = g_DailyStartBalance - currentEquity;
   double dailyLossPercent = (dailyLoss / g_DailyStartBalance) * 100.0;
   
   if (dailyLossPercent >= DailyLossLimit)
   {
      if (!g_DailyLimitBreached)
      {
         g_DailyLimitBreached = true;
         Print("CHALLENGE ALERT: Daily Loss Limit Breached! Daily Loss: ", 
               DoubleToString(dailyLossPercent, 2), "% (Limit: ", DailyLossLimit, "%)");
         Print("Trading halted for today. Balance: $", DoubleToString(currentBalance, 2));
      }
   }
   
   // Check maximum loss limit (10% from initial balance)
   double totalLoss = g_InitialBalance - currentEquity;
   double maxLossPercent = (totalLoss / g_InitialBalance) * 100.0;
   
   if (maxLossPercent >= MaxLossLimit)
   {
      if (!g_MaxLimitBreached)
      {
         g_MaxLimitBreached = true;
         Print("CHALLENGE FAILED: Maximum Loss Limit Breached! Total Loss: ", 
               DoubleToString(maxLossPercent, 2), "% (Limit: ", MaxLossLimit, "%)");
         Print("Challenge failed. Initial Balance: $", DoubleToString(g_InitialBalance, 2),
               " | Current Equity: $", DoubleToString(currentEquity, 2));
      }
   }
   
   // Check profit targets
   double profit = currentEquity - g_InitialBalance;
   double profitPercent = (profit / g_InitialBalance) * 100.0;
   
   if (!g_Phase1Complete && profitPercent >= Phase1ProfitTarget)
   {
      g_Phase1Complete = true;
      Print("CHALLENGE MILESTONE: Phase 1 Profit Target Reached! Profit: ", 
            DoubleToString(profitPercent, 2), "% (Target: ", Phase1ProfitTarget, "%)");
   }
   
   if (g_Phase1Complete && profitPercent >= (Phase1ProfitTarget + Phase2ProfitTarget))
   {
      Print("CHALLENGE COMPLETE: Both Phase Targets Reached! Total Profit: ", 
            DoubleToString(profitPercent, 2), "%");
   }
}

//+------------------------------------------------------------------+
//| Challenge Rules: Reset daily tracking on new day                |
//+------------------------------------------------------------------+
void ResetDailyChallengeTracking()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Only count as trading day if we had positions or orders
   if (HasOpenPosition() || OrdersTotal() > 0)
   {
      g_TradingDaysCount++;
      Print("Trading Day ", g_TradingDaysCount, " started. Balance: $", DoubleToString(currentBalance, 2));
   }
   
   g_DailyStartBalance = currentBalance;
   g_DailyLimitBreached = false;
   g_DailyResetTime = TimeCurrent();
   
   // Display challenge status
   if (EnableChallengeRules)
   {
      double profit = currentBalance - g_InitialBalance;
      double profitPercent = (profit / g_InitialBalance) * 100.0;
      Print("Daily Reset | Balance: $", DoubleToString(currentBalance, 2),
            " | Profit: ", DoubleToString(profitPercent, 2), "% | Trading Days: ", g_TradingDaysCount);
   }
}

//+------------------------------------------------------------------+
//| Challenge Rules: Check if new orders can be placed              |
//+------------------------------------------------------------------+
bool CanPlaceNewOrder()
{
   if (!EnableChallengeRules)
      return true;
   
   // Don't place orders if limits breached
   if (g_DailyLimitBreached || g_MaxLimitBreached)
   {
      return false;
   }
   
   // Check if daily loss limit would be breached with current equity
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = g_DailyStartBalance - currentEquity;
   double dailyLossPercent = (dailyLoss / g_DailyStartBalance) * 100.0;
   
   if (dailyLossPercent >= DailyLossLimit)
   {
      return false;
   }
   
   // Check maximum loss limit
   double totalLoss = g_InitialBalance - currentEquity;
   double maxLossPercent = (totalLoss / g_InitialBalance) * 100.0;
   
   if (maxLossPercent >= MaxLossLimit)
   {
      return false;
   }
   
   return true;
}
