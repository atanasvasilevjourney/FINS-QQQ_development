//+------------------------------------------------------------------+
//|                                              KeltnerChannel_EA.mq5 |
//|         Keltner Channel mean reversion / breakout EA (MT5)        |
//|  Strategies: (1) Immediate on close outside channel              |
//|              (2) Re-entry when price closes back inside channel  |
//|  No repaint: signals on closed bar only; visuals reset on close. |
//|                                                                  |
//|  PARAMETERS: Timeframe, Keltner (EMA/ATR/ATR mult), TP/SL points,|
//|  lot or risk %, magic, spread limit, max positions.             |
//|  CONFLUENCES: Upper/middle/lower channel + close (bar 1 vs bar 2).|
//|  FILTERS: Optional trend filter (middle line slope).             |
//|  RISK: Fixed lot or risk % per trade; SL used for lot calculation.|
//|  VISUAL: Entry arrow at bar time/price; removed when trade closes.|
//|  PERFORMANCE TABLE: Trades / W / L / Win% / P/L (updated on close).|
//+------------------------------------------------------------------+
#property copyright "Keltner Channel EA"
#property version   "1.10"
#property description "Uses MT5 FreeIndicators Keltner Channel."
#property description "Two modes: immediate breakout or re-entry inside."
#property description "Optional trend filter (middle line slope)."
#property description "Profitability is not guaranteed; backtest on your symbol/timeframe."
#property description "Prop Firm Guard: daily/max loss, phase targets, optional trailing DD."

#include <Trade\Trade.mqh>

//--- Keltner Channel indicator path (from MQL5/Indicators/)
#define KC_PATH "FreeIndicators\\Keltner Channel.ex5"

//--- Strategy mode
enum ENUM_KC_STRATEGY
{
   KC_IMMEDIATE = 0,  // Immediate: trade when close outside channel
   KC_REENTRY  = 1   // Re-entry: trade when close back inside channel
};

//--- Input groups
input group "=== Symbol & Timeframe ==="
input ENUM_TIMEFRAMES InpTimeframe    = PERIOD_H1;  // Timeframe

input group "=== Keltner Channel (FreeIndicators) ==="
input int      InpKcEmaPeriod    = 20;   // Keltner EMA period
input int      InpKcAtrPeriod    = 10;   // Keltner ATR period
input double   InpKcAtrMultiplier = 2.0; // Keltner ATR multiplier

input group "=== Strategy ==="
input ENUM_KC_STRATEGY InpStrategy = KC_REENTRY;   // Strategy mode
input bool     InpUseTrendFilter  = false;         // Use middle line as trend filter

input group "=== Risk & Money ==="
input double   InpLotSize        = 0.1;  // Lot size (fixed)
input bool     InpUseRiskPct     = false;          // Use risk % for lot size
input double   InpRiskPct        = 1.0;  // Risk per trade (% of balance)
input int      InpSlPoints       = 200;  // Stop loss (points)
input int      InpTpPoints       = 500;  // Take profit (points)

input group "=== Trade Execution ==="
input int      InpMagic          = 20020;  // Magic number
input int      InpSlippagePoints  = 10;    // Slippage (points)
input int      InpMaxSpreadPoints = 0;    // Max spread to open (0 = disable)
input int      InpMaxPositions    = 1;     // Max open positions (1 = one at a time)

input group "=== Visualization ==="
input bool     InpShowEntryMarks = true;  // Draw entry markers (reset when trade closes)
input bool     InpShowPerfTable  = true;  // Show performance table

input group "=== Prop Firm Guard (Smart Layer) ==="
input bool     InpPropFirmGuard   = false;  // Enable prop firm challenge rules
input double   InpChallengeSize   = 25000.0; // Challenge account size ($); 0 = use balance at start
input double   InpPhase1TargetPct  = 8.0;    // Phase 1 profit target (%)
input double   InpPhase2TargetPct  = 5.0;   // Phase 2 profit target (%)
input double   InpDailyLossLimitPct = 5.0;   // Daily loss limit (%)
input double   InpMaxLossLimitPct  = 10.0;  // Max loss from initial (%)
input double   InpMaxDDFromHighPct = 0.0;   // Max drawdown from equity high (%); 0 = off
input int      InpMinTradingDays   = 0;     // Min trading days (0 = not enforced)
input bool     InpPhase1Complete   = false;  // Phase 1 passed (manual; for Phase 2)
input double   InpMaxDailyRiskPct  = 0.0;   // Max daily loss % before block (0=off); e.g. 1.5 = stop at 1.5% day loss
input int      InpMaxTradesPerDay  = 0;     // Max trades per day (0=no limit); e.g. 3 for Stability

//--- Globals
int      g_handleKc    = INVALID_HANDLE;
datetime g_lastBarTime = 0;
CTrade   g_trade;
string   g_objPrefix   = "KC_";

//--- Performance stats (for table; updated only on closed trade – no repaint)
int      g_totalTrades = 0;
int      g_wins        = 0;
int      g_losses      = 0;
double   g_totalProfit = 0.0;

//--- Prop Firm Guard state
double   g_initialBalance   = 0.0;
double   g_dailyStartBalance = 0.0;
double   g_highestEquity    = 0.0;
datetime g_lastDayTime      = 0;
int      g_tradingDaysCount = 0;
bool     g_dailyLimitBreached = false;
bool     g_maxLimitBreached   = false;
bool     g_phase1Complete     = false;
int      g_tradesOpenedToday  = 0;   // Reset each day; used when InpMaxTradesPerDay > 0

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_handleKc = iCustom(_Symbol, InpTimeframe, KC_PATH,
                       InpKcEmaPeriod, InpKcAtrPeriod, InpKcAtrMultiplier, false);
   if (g_handleKc == INVALID_HANDLE)
   {
      Print("KeltnerChannel_EA: Failed to create Keltner handle. Check path: ", KC_PATH);
      return INIT_FAILED;
   }

   if (InpPropFirmGuard)
   {
      g_initialBalance   = (InpChallengeSize > 0) ? InpChallengeSize : AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_highestEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
      g_phase1Complete    = InpPhase1Complete;
      g_dailyLimitBreached = false;
      g_maxLimitBreached   = false;
      g_lastDayTime        = 0;
      g_tradingDaysCount   = 0;
      g_tradesOpenedToday  = CountTradesOpenedToday();
      Print("Prop Firm Guard ON | Initial: $", DoubleToString(g_initialBalance, 2),
            " | Daily loss limit: ", InpDailyLossLimitPct, "% | Max loss: ", InpMaxLossLimitPct, "%");
   }

   LoadPerformanceFromHistory();
   if (InpShowPerfTable)
      UpdatePerformanceTable();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (g_handleKc != INVALID_HANDLE)
      IndicatorRelease(g_handleKc);
   DeleteAllKeltnerObjects();
   Comment("");
}

//+------------------------------------------------------------------+
//| Load performance stats from closed positions (this magic)         |
//+------------------------------------------------------------------+
void LoadPerformanceFromHistory()
{
   g_totalTrades = 0;
   g_wins        = 0;
   g_losses      = 0;
   g_totalProfit = 0.0;

   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   for (int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;
      if (HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if (HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      g_totalTrades++;
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      g_totalProfit += profit;
      if (profit >= 0)
         g_wins++;
      else
         g_losses++;
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction – on position close: reset visual, update table|
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if (trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if (trans.deal == 0) return;

   if (!HistoryDealSelect(trans.deal)) return;
   if (HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   if (HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   ulong posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   DeleteEntryVisualsForPosition(posId);

   g_totalTrades++;
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   g_totalProfit += profit;
   if (profit >= 0) g_wins++; else g_losses++;

   if (InpShowPerfTable)
      UpdatePerformanceTable();
}

//+------------------------------------------------------------------+
//| Delete all entry markers (prefix KC_ENT_); keep perf table       |
//+------------------------------------------------------------------+
void DeleteAllKeltnerObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for (int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if (StringFind(name, g_objPrefix + "ENT_") == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Delete entry visuals for a closed position (reset after close)    |
//+------------------------------------------------------------------+
void DeleteEntryVisualsForPosition(ulong positionId)
{
   ObjectDelete(0, g_objPrefix + "ENT_" + IntegerToString(positionId));
}

//+------------------------------------------------------------------+
//| Draw entry marker at bar time and price (kept until trade closes)|
//+------------------------------------------------------------------+
void DrawEntryMark(ulong positionId, datetime barTime, double price, bool isBuy)
{
   if (!InpShowEntryMarks) return;
   string name = g_objPrefix + "ENT_" + IntegerToString(positionId);
   ObjectDelete(0, name);

   if (ObjectCreate(0, name, OBJ_ARROW, 0, barTime, price))
   {
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? clrLime : clrOrangeRed);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
}

//+------------------------------------------------------------------+
//| Update performance table on chart                                |
//+------------------------------------------------------------------+
void UpdatePerformanceTable()
{
   if (!InpShowPerfTable) return;

   string tblName = g_objPrefix + "PerfTable";
   ObjectDelete(0, tblName);
   if (ObjectCreate(0, tblName, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, tblName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, tblName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, tblName, OBJPROP_YDISTANCE, 25);
      ObjectSetInteger(0, tblName, OBJPROP_SELECTABLE, false);

      double winPct = (g_totalTrades > 0) ? (100.0 * g_wins / g_totalTrades) : 0.0;
      string txt = "Keltner Channel EA | Trades: " + IntegerToString(g_totalTrades)
                 + " | W: " + IntegerToString(g_wins)
                 + " | L: " + IntegerToString(g_losses)
                 + " | Win%: " + DoubleToString(winPct, 1)
                 + " | P/L: " + DoubleToString(g_totalProfit, 2);
      ObjectSetString(0, tblName, OBJPROP_TEXT, txt);
      ObjectSetString(0, tblName, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, tblName, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, tblName, OBJPROP_COLOR, clrWhite);
   }
}

//+------------------------------------------------------------------+
//| True when a new bar has formed (once per bar; no repaint)         |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime barTime = iTime(_Symbol, InpTimeframe, 0);
   if (barTime == g_lastBarTime) return false;
   g_lastBarTime = barTime;
   return true;
}

//+------------------------------------------------------------------+
//| True when calendar day changed (for daily reset)                  |
//+------------------------------------------------------------------+
bool IsNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if (g_lastDayTime == today) return false;
   g_lastDayTime = today;
   return true;
}

//+------------------------------------------------------------------+
//| Prop Firm: check limits and update state (call each tick)         |
//+------------------------------------------------------------------+
void PropFirmCheckLimits()
{
   if (!InpPropFirmGuard) return;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if (eq > g_highestEquity) g_highestEquity = eq;

   // Daily loss: from start of day balance
   double dailyLoss = g_dailyStartBalance - eq;
   double dailyLossPct = (g_dailyStartBalance > 0) ? (100.0 * dailyLoss / g_dailyStartBalance) : 0;
   if (dailyLossPct >= InpDailyLossLimitPct)
   {
      if (!g_dailyLimitBreached)
      {
         g_dailyLimitBreached = true;
         Print("PROP GUARD: Daily loss limit reached. Daily loss: ", DoubleToString(dailyLossPct, 2), "% (max ", InpDailyLossLimitPct, "%). No new trades today.");
      }
   }

   // Max loss from initial
   double totalLoss = g_initialBalance - eq;
   double maxLossPct = (g_initialBalance > 0) ? (100.0 * totalLoss / g_initialBalance) : 0;
   if (maxLossPct >= InpMaxLossLimitPct)
   {
      if (!g_maxLimitBreached)
      {
         g_maxLimitBreached = true;
         Print("PROP GUARD: Max loss limit reached. Loss: ", DoubleToString(maxLossPct, 2), "% (max ", InpMaxLossLimitPct, "%). Challenge failed.");
      }
   }

   // Trailing drawdown from equity high
   if (InpMaxDDFromHighPct > 0 && g_highestEquity > 0)
   {
      double ddFromHigh = 100.0 * (g_highestEquity - eq) / g_highestEquity;
      if (ddFromHigh >= InpMaxDDFromHighPct)
      {
         if (!g_maxLimitBreached)
         {
            g_maxLimitBreached = true;
            Print("PROP GUARD: Max DD from high reached. DD: ", DoubleToString(ddFromHigh, 2), "% (max ", InpMaxDDFromHighPct, "%).");
         }
      }
   }

   // Phase targets (informational)
   double profitPct = (g_initialBalance > 0) ? (100.0 * (eq - g_initialBalance) / g_initialBalance) : 0;
   if (!g_phase1Complete && profitPct >= InpPhase1TargetPct)
   {
      g_phase1Complete = true;
      Print("PROP GUARD: Phase 1 target reached. Profit: ", DoubleToString(profitPct, 2), "%.");
   }
   if (g_phase1Complete && profitPct >= InpPhase1TargetPct + InpPhase2TargetPct)
      Print("PROP GUARD: Phase 2 target reached. Total profit: ", DoubleToString(profitPct, 2), "%.");
}

//+------------------------------------------------------------------+
//| Prop Firm: reset daily tracking on new day                        |
//+------------------------------------------------------------------+
void PropFirmResetDaily()
{
   if (!InpPropFirmGuard) return;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if (CountOpenPositions() > 0 || OrdersTotal() > 0)
      g_tradingDaysCount++;
   g_dailyStartBalance = bal;
   g_dailyLimitBreached = false;
   g_tradesOpenedToday  = 0;
   if (InpMinTradingDays > 0)
      Print("PROP GUARD: Day ", g_tradingDaysCount, " | Balance: $", DoubleToString(bal, 2));
}

//+------------------------------------------------------------------+
//| Count positions opened today (by this EA) for max-trades-per-day   |
//+------------------------------------------------------------------+
int CountTradesOpenedToday()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime dayStart = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   datetime dayEnd   = dayStart + 86400;
   HistorySelect(dayStart, dayEnd);
   int n = 0;
   for (int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;
      if (HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if (HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Prop Firm: allow new order only if no limit breached              |
//+------------------------------------------------------------------+
bool PropFirmCanOpen()
{
   if (!InpPropFirmGuard) return true;
   if (g_dailyLimitBreached || g_maxLimitBreached) return false;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLossPct = (g_dailyStartBalance > 0) ? (100.0 * (g_dailyStartBalance - eq) / g_dailyStartBalance) : 0;
   if (dailyLossPct >= InpDailyLossLimitPct) return false;

   double maxLossPct = (g_initialBalance > 0) ? (100.0 * (g_initialBalance - eq) / g_initialBalance) : 0;
   if (maxLossPct >= InpMaxLossLimitPct) return false;

   if (InpMaxDDFromHighPct > 0 && g_highestEquity > 0)
   {
      double ddPct = 100.0 * (g_highestEquity - eq) / g_highestEquity;
      if (ddPct >= InpMaxDDFromHighPct) return false;
   }

   // Max daily risk % (e.g. 1.5): stop new trades when day loss >= this (keeps DD under 5%)
   if (InpMaxDailyRiskPct > 0 && g_dailyStartBalance > 0)
   {
      double dayLossPct = 100.0 * (g_dailyStartBalance - eq) / g_dailyStartBalance;
      if (dayLossPct >= InpMaxDailyRiskPct) return false;
   }

   // Max trades per day (e.g. 3 for Stability consistency)
   if (InpMaxTradesPerDay > 0 && g_tradesOpenedToday >= InpMaxTradesPerDay)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Get lot size (fixed or by risk % using SL distance)               |
//+------------------------------------------------------------------+
double GetLotSize(double entryPrice, double slPrice)
{
   if (!InpUseRiskPct)
      return NormalizeLot(InpLotSize);

   double riskPct = MathMax(0.01, MathMin(100, InpRiskPct)) / 100.0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * riskPct;

   double dist = MathAbs(entryPrice - slPrice);
   if (dist <= 0) return NormalizeLot(InpLotSize);

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSz <= 0 || tickVal <= 0) return NormalizeLot(InpLotSize);

   double riskPerLot = (dist / tickSz) * tickVal;
   if (riskPerLot <= 0) return NormalizeLot(InpLotSize);

   double lots = riskAmount / riskPerLot;
   return NormalizeLot(lots);
}

double NormalizeLot(double lots)
{
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   return MathMax(minL, MathMin(maxL, NormalizeDouble(lots, 2)));
}

//+------------------------------------------------------------------+
//| Check spread limit                                                |
//+------------------------------------------------------------------+
bool IsSpreadOk()
{
   if (InpMaxSpreadPoints <= 0) return true;
   return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= (long)InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Count open positions for this magic                               |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int n = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
      if (PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         n++;
   return n;
}

//+------------------------------------------------------------------+
//| Read Keltner buffers (closed bars only: indices 1 and 2)          |
//| Buffer 0 = upper, 1 = middle, 2 = lower                          |
//+------------------------------------------------------------------+
bool GetKeltnerValues(double &kUp[], double &kMid[], double &kLo[])
{
   ArraySetAsSeries(kUp, true);
   ArraySetAsSeries(kMid, true);
   ArraySetAsSeries(kLo, true);
   if (CopyBuffer(g_handleKc, 0, 1, 3, kUp) < 3) return false;
   if (CopyBuffer(g_handleKc, 1, 1, 3, kMid) < 3) return false;
   if (CopyBuffer(g_handleKc, 2, 1, 3, kLo) < 3) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Signal: Buy (mean reversion from lower channel)                   |
//+------------------------------------------------------------------+
bool SignalBuy(double close1, double close2, double kUp1, double kUp2, double kLo1, double kLo2, double kMid1, double kMid2)
{
   if (InpStrategy == KC_IMMEDIATE)
   {
      // Close just went below lower channel
      if (close1 >= kLo1) return false;
      if (close2 < kLo2) return false;  // was already below
      if (InpUseTrendFilter && kMid1 <= kMid2) return false;
      return true;
   }
   // KC_REENTRY: was below lower, now back inside (above lower)
   if (close1 <= kLo1) return false;
   if (close2 >= kLo2) return false;
   if (InpUseTrendFilter && kMid1 <= kMid2) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Signal: Sell (mean reversion from upper channel)                  |
//+------------------------------------------------------------------+
bool SignalSell(double close1, double close2, double kUp1, double kUp2, double kLo1, double kLo2, double kMid1, double kMid2)
{
   if (InpStrategy == KC_IMMEDIATE)
   {
      // Close just went above upper channel
      if (close1 <= kUp1) return false;
      if (close2 > kUp2) return false;
      if (InpUseTrendFilter && kMid1 >= kMid2) return false;
      return true;
   }
   // KC_REENTRY: was above upper, now back inside (below upper)
   if (close1 >= kUp1) return false;
   if (close2 <= kUp2) return false;
   if (InpUseTrendFilter && kMid1 >= kMid2) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Open buy position and draw entry mark                             |
//+------------------------------------------------------------------+
void OpenBuy(datetime barTime)
{
   if (!PropFirmCanOpen()) return;
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl    = (InpSlPoints > 0) ? NormalizeDouble(ask - InpSlPoints * point, digits) : 0;
   double tp    = (InpTpPoints > 0) ? NormalizeDouble(ask + InpTpPoints * point, digits) : 0;
   double lots  = GetLotSize(ask, sl);

   if (g_trade.Buy(lots, _Symbol, ask, sl, tp, ""))
   {
      g_tradesOpenedToday++;
      ulong posId = GetLastOpenedPositionId();
      if (posId > 0)
         DrawEntryMark(posId, barTime, ask, true);
   }
}

//+------------------------------------------------------------------+
//| Open sell position and draw entry mark                            |
//+------------------------------------------------------------------+
void OpenSell(datetime barTime)
{
   if (!PropFirmCanOpen()) return;
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl    = (InpSlPoints > 0) ? NormalizeDouble(bid + InpSlPoints * point, digits) : 0;
   double tp    = (InpTpPoints > 0) ? NormalizeDouble(bid - InpTpPoints * point, digits) : 0;
   double lots  = GetLotSize(bid, sl);

   if (g_trade.Sell(lots, _Symbol, bid, sl, tp, ""))
   {
      g_tradesOpenedToday++;
      ulong posId = GetLastOpenedPositionId();
      if (posId > 0)
         DrawEntryMark(posId, barTime, bid, false);
   }
}

//+------------------------------------------------------------------+
//| Return position identifier of our magic's position (after open) |
//+------------------------------------------------------------------+
ulong GetLastOpenedPositionId()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
      if (PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return PositionGetInteger(POSITION_IDENTIFIER);
   return 0;
}

//+------------------------------------------------------------------+
//| OnTick – process only on new bar (closed bar data = no repaint)   |
//+------------------------------------------------------------------+
void OnTick()
{
   if (g_handleKc == INVALID_HANDLE) return;

   if (InpPropFirmGuard)
   {
      PropFirmCheckLimits();
      if (IsNewDay())
         PropFirmResetDaily();
      if (g_dailyLimitBreached || g_maxLimitBreached)
         return;   // no new signals until next day (daily) or never (max)
   }

   if (!IsNewBar()) return;   // once per bar

   double kUp[], kMid[], kLo[];
   if (!GetKeltnerValues(kUp, kMid, kLo)) return;

   // Closed bar: index 0 = bar 1 (last closed), index 1 = bar 2 (previous)
   double close1 = iClose(_Symbol, InpTimeframe, 1);
   double close2 = iClose(_Symbol, InpTimeframe, 2);
   double kUp1 = kUp[0], kUp2 = kUp[1];
   double kLo1 = kLo[0], kLo2 = kLo[1];
   double kMid1 = kMid[0], kMid2 = kMid[1];

   if (!IsSpreadOk()) return;
   if (CountOpenPositions() >= InpMaxPositions) return;
   if (!PropFirmCanOpen()) return;

   datetime barTime = iTime(_Symbol, InpTimeframe, 1);

   if (SignalBuy(close1, close2, kUp1, kUp2, kLo1, kLo2, kMid1, kMid2))
   {
      OpenBuy(barTime);
      return;
   }
   if (SignalSell(close1, close2, kUp1, kUp2, kLo1, kLo2, kMid1, kMid2))
      OpenSell(barTime);
}
