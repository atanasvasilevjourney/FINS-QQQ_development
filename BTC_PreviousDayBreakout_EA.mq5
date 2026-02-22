//+------------------------------------------------------------------+
//|                                    BTC_PreviousDayBreakout_EA.mq5 |
//|            Bitcoin Previous Day High/Low Breakout Strategy        |
//|  Signal TF: daily (or user); buy above prev day high, sell below  |
//|  prev day low. SL/TP in %, trailing stop, close before next bar. |
//|  No repaint: entries on price cross; visuals only after fill.   |
//+------------------------------------------------------------------+
#property copyright "BTC Previous Day Breakout"
#property version   "1.00"
#property description "Breakout above previous day high = Buy; below previous day low = Sell."
#property description "SL/TP in % of price; optional trailing stop; close X min before next candle."
#property description "Entry visuals kept until position closes (reset on close)."
#property description "Optional Funded Account rules: daily/max loss, phase targets, trailing DD."

#include <Trade\Trade.mqh>

//--- Object prefix for chart objects (entry visuals, perf table)
#define OBJ_PREFIX "BTCPDB_"

//--- Input groups
input group "=== Symbol & Timeframe ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_D1;  // Signal timeframe (previous bar = this TF)

input group "=== Risk & Money ==="
input double   InpLotSize     = 0.01;  // Lot size (fixed; used if UseRiskMoney = false)
input bool     InpUseRiskMoney = true;  // Use risk money for lot size
input double   InpRiskMoney   = 100.0; // Risk per trade (account currency)

input group "=== Stop Loss & Take Profit ==="
input double   InpSLPercent   = 2.0;   // Stop loss (% of price)
input double   InpTPPercent   = 1.0;   // Take profit (% of price)

input group "=== Trailing Stop ==="
input bool     InpUseTrailingStop   = true;  // Use trailing stop
input double   InpTSLTriggerPercent = 0.5;   // TSL trigger (% above/below open)
input double   InpTSLPercent       = 0.25;   // TSL trail distance (% of price)

input group "=== Session ==="
input int      InpCloseMinutesBeforeNextCandle = 30; // Close positions this many min before next bar (0=disable)

input group "=== Trade Execution ==="
input int      InpMagic        = 30030;  // Magic number
input int      InpSlippagePts  = 10;     // Slippage (points)

input group "=== Filters & Confluence ==="
input double   InpMaxSpreadPts = 0;      // Max spread (points) to allow entry (0 = disable)
input double   InpMinRangePercent = 0;   // Min previous bar range % of price to trade (0 = disable)

input group "=== Visualization ==="
input bool     InpShowEntryVisuals = true;  // Draw entry level lines (reset when trade closes)
input bool     InpShowPerfTable   = true;  // Show performance table
input int      InpPerfPanelX     = 10;     // Performance panel X
input int      InpPerfPanelY     = 25;     // Performance panel Y

input group "=== Funded Account (Prop Firm) ==="
input bool     InpFundedAccount   = false; // Enable funded account rules
input double   InpAccountSize     = 100000.0; // Account size for % (0 = use balance at start)
input double   InpPhase1TargetPct = 10.0;  // Phase 1 profit target (%)
input double   InpPhase2TargetPct = 5.0;   // Phase 2 profit target (%)
input double   InpDailyLossLimitPct = 5.0; // Daily loss limit (%)
input double   InpMaxLossLimitPct   = 10.0; // Max loss from initial (%)
input double   InpMaxDDFromHighPct  = 0.0;  // Max drawdown from equity high (%); 0 = off
input int      InpMinTradingDays    = 0;    // Min trading days (0 = not enforced)
input bool     InpPhase1Complete    = false; // Phase 1 passed (manual; for Phase 2)

//--- Globals
CTrade         g_Trade;
datetime       g_LastOpenBarTime = 0;     // Bar time when we last opened (one-trade-per-bar)
datetime       g_LastBarTime = 0;         // Current bar time (signal TF) for internal use
const string   g_Prefix = OBJ_PREFIX;

//--- Performance stats (from history; no repaint)
int            g_TotalTrades = 0;
int            g_Wins        = 0;
double         g_TotalProfit = 0.0;
double         g_GrossProfit = 0.0;  // Sum of winning exits
double         g_GrossLoss   = 0.0;  // Sum of losing exits
double         g_DailyPL     = 0.0;

//--- Funded account state
double         g_InitialBalance    = 0.0;
double         g_DailyStartBalance = 0.0;
double         g_HighestEquity     = 0.0;
datetime       g_LastDayTime       = 0;
bool           g_DailyLimitBreached = false;
bool           g_MaxLimitBreached   = false;
bool           g_Phase1Complete     = false;
int            g_TradingDaysCount   = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_Trade.SetExpertMagicNumber(InpMagic);
   g_Trade.SetDeviationInPoints(InpSlippagePts);
   g_Trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_LastOpenBarTime = 0;
   g_LastBarTime = 0;

   if (!ValidateInputs())
   {
      Print("BTC Previous Day Breakout EA: Invalid inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (InpFundedAccount)
   {
      g_InitialBalance    = (InpAccountSize > 0) ? InpAccountSize : AccountInfoDouble(ACCOUNT_BALANCE);
      g_DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_HighestEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
      g_Phase1Complete    = InpPhase1Complete;
      g_DailyLimitBreached = false;
      g_MaxLimitBreached   = false;
      g_LastDayTime        = 0;
      g_TradingDaysCount   = 0;
      Print("Funded Account ON | Initial: ", DoubleToString(g_InitialBalance, 2),
            " | Daily loss limit: ", InpDailyLossLimitPct, "% | Max loss: ", InpMaxLossLimitPct, "%");
   }

   LoadPerformanceFromHistory();
   if (InpShowPerfTable)
      CreatePerfPanel();

   Print("BTC Previous Day Breakout EA initialized. TF: ", EnumToString(InpTimeframe),
         " | SL%: ", InpSLPercent, " | TP%: ", InpTPPercent,
         (InpUseTrailingStop ? " | TSL ON" : ""),
         (InpFundedAccount ? " | Funded ON" : ""));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAllEntryVisuals();
   ObjectDelete(0, g_Prefix + "PerfPanel");
   ChartRedraw(0);
   Print("BTC Previous Day Breakout EA deinitialized.");
}

//+------------------------------------------------------------------+
//| Validate input parameters                                         |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if (InpTimeframe <= 0) return false;
   if (!InpUseRiskMoney && (InpLotSize <= 0)) return false;
   if (InpUseRiskMoney && InpRiskMoney <= 0) return false;
   if (InpSLPercent < 0 || InpTPPercent < 0) return false;
   if (InpCloseMinutesBeforeNextCandle < 0 || InpCloseMinutesBeforeNextCandle > 1440) return false;
   if (InpUseTrailingStop && (InpTSLTriggerPercent <= 0 || InpTSLPercent <= 0)) return false;
   if (InpMinRangePercent < 0 || InpMinRangePercent > 100) return false;
   if (InpFundedAccount)
   {
      if (InpAccountSize < 0) return false;
      if (InpPhase1TargetPct <= 0 || InpPhase2TargetPct <= 0) return false;
      if (InpDailyLossLimitPct <= 0 || InpDailyLossLimitPct > 100) return false;
      if (InpMaxLossLimitPct <= 0 || InpMaxLossLimitPct > 100) return false;
      if (InpMaxDDFromHighPct < 0 || InpMaxDDFromHighPct > 100) return false;
      if (InpMinTradingDays < 0) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| True when calendar day changed (for funded account daily reset)   |
//+------------------------------------------------------------------+
bool IsNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if (g_LastDayTime == today) return false;
   g_LastDayTime = today;
   return true;
}

//+------------------------------------------------------------------+
//| Funded account: check daily/max loss and trailing DD              |
//+------------------------------------------------------------------+
void CheckFundedLimits()
{
   if (!InpFundedAccount) return;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if (eq > g_HighestEquity) g_HighestEquity = eq;

   // Daily loss limit
   double dailyLoss = g_DailyStartBalance - eq;
   double dailyLossPct = (g_DailyStartBalance > 0) ? (100.0 * dailyLoss / g_DailyStartBalance) : 0;
   if (dailyLossPct >= InpDailyLossLimitPct)
   {
      if (!g_DailyLimitBreached)
      {
         g_DailyLimitBreached = true;
         Print("FUNDED: Daily loss limit reached. Daily loss: ", DoubleToString(dailyLossPct, 2),
               "% (max ", InpDailyLossLimitPct, "%). No new trades today.");
      }
   }

   // Max loss from initial balance
   double totalLoss = g_InitialBalance - eq;
   double maxLossPct = (g_InitialBalance > 0) ? (100.0 * totalLoss / g_InitialBalance) : 0;
   if (maxLossPct >= InpMaxLossLimitPct)
   {
      if (!g_MaxLimitBreached)
      {
         g_MaxLimitBreached = true;
         Print("FUNDED: Max loss limit reached. Loss: ", DoubleToString(maxLossPct, 2),
               "% (max ", InpMaxLossLimitPct, "%). Challenge failed.");
      }
   }

   // Trailing drawdown from equity high
   if (InpMaxDDFromHighPct > 0 && g_HighestEquity > 0)
   {
      double ddFromHigh = g_HighestEquity - eq;
      double ddPct = 100.0 * ddFromHigh / g_HighestEquity;
      if (ddPct >= InpMaxDDFromHighPct)
      {
         if (!g_MaxLimitBreached)
         {
            g_MaxLimitBreached = true;
            Print("FUNDED: Max drawdown from high reached. DD: ", DoubleToString(ddPct, 2),
                  "% (max ", InpMaxDDFromHighPct, "%).");
         }
      }
   }

   // Phase targets (informational)
   double profit = eq - g_InitialBalance;
   double profitPct = (g_InitialBalance > 0) ? (100.0 * profit / g_InitialBalance) : 0;
   if (!g_Phase1Complete && profitPct >= InpPhase1TargetPct)
   {
      g_Phase1Complete = true;
      Print("FUNDED: Phase 1 target reached. Profit: ", DoubleToString(profitPct, 2), "%");
   }
   if (g_Phase1Complete && profitPct >= (InpPhase1TargetPct + InpPhase2TargetPct))
      Print("FUNDED: Phase 2 target reached. Total profit: ", DoubleToString(profitPct, 2), "%");
}

//+------------------------------------------------------------------+
//| Funded account: reset daily tracking on new day                  |
//+------------------------------------------------------------------+
void ResetDailyFundedTracking()
{
   if (!InpFundedAccount) return;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if (HasOpenPosition())
      g_TradingDaysCount++;
   g_DailyStartBalance = bal;
   g_DailyLimitBreached = false;
   if (InpMinTradingDays > 0)
      Print("FUNDED: Daily reset | Balance: ", DoubleToString(bal, 2),
            " | Trading days: ", g_TradingDaysCount);
}

//+------------------------------------------------------------------+
//| Funded account: can we open a new order?                         |
//+------------------------------------------------------------------+
bool CanPlaceNewOrder()
{
   if (!InpFundedAccount) return true;
   if (g_DailyLimitBreached || g_MaxLimitBreached) return false;
   if (InpMinTradingDays > 0 && g_TradingDaysCount < InpMinTradingDays) return true; // allow trading

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyLoss = g_DailyStartBalance - eq;
   double dailyLossPct = (g_DailyStartBalance > 0) ? (100.0 * dailyLoss / g_DailyStartBalance) : 0;
   if (dailyLossPct >= InpDailyLossLimitPct) return false;

   double totalLoss = g_InitialBalance - eq;
   double maxLossPct = (g_InitialBalance > 0) ? (100.0 * totalLoss / g_InitialBalance) : 0;
   if (maxLossPct >= InpMaxLossLimitPct) return false;

   if (InpMaxDDFromHighPct > 0 && g_HighestEquity > 0)
   {
      double ddPct = 100.0 * (g_HighestEquity - eq) / g_HighestEquity;
      if (ddPct >= InpMaxDDFromHighPct) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Load performance stats from history (this magic, this symbol)      |
//+------------------------------------------------------------------+
void LoadPerformanceFromHistory()
{
   g_TotalTrades = 0;
   g_Wins        = 0;
   g_TotalProfit = 0.0;
   g_GrossProfit = 0.0;
   g_GrossLoss   = 0.0;
   g_DailyPL     = 0.0;

   datetime dayStart;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   dayStart = StructToTime(dt);

   HistorySelect(0, TimeCurrent());
   for (int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;
      if (HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if (HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if (dealTime >= dayStart)
         g_DailyPL += profit;

      g_TotalTrades++;
      g_TotalProfit += profit;
      if (profit > 0) { g_Wins++; g_GrossProfit += profit; }
      else            g_GrossLoss += profit;
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction – on position close: reset entry visual       |
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
   if (HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   ulong posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   DeleteEntryVisualsForPosition(posId);

   g_TotalTrades++;
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                 + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   g_TotalProfit += profit;
   if (profit > 0) { g_Wins++; g_GrossProfit += profit; }
   else            g_GrossLoss += profit;

   datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   MqlDateTime dts;
   TimeToStruct(TimeCurrent(), dts);
   dts.hour = 0; dts.min = 0; dts.sec = 0;
   if (dealTime >= StructToTime(dts))
      g_DailyPL += profit;

   if (InpShowPerfTable)
      UpdatePerfPanel();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Get previous bar high/low on signal timeframe (shift 1 = last     |
//| closed bar). No repaint: uses closed bar only.                   |
//+------------------------------------------------------------------+
bool GetPreviousBarLevels(double &prevHigh, double &prevLow, double &rangePct)
{
   prevHigh = iHigh(_Symbol, InpTimeframe, 1);
   prevLow  = iLow(_Symbol, InpTimeframe, 1);
   if (prevHigh <= 0 || prevLow <= 0 || prevHigh <= prevLow)
      return false;

   double mid = (prevHigh + prevLow) / 2.0;
   rangePct = (mid > 0) ? (100.0 * (prevHigh - prevLow) / mid) : 0;
   return true;
}

//+------------------------------------------------------------------+
//| Check if we already opened a trade on current signal bar          |
//+------------------------------------------------------------------+
bool AlreadyTradedThisBar()
{
   datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
   return (g_LastOpenBarTime == currentBarTime && g_LastOpenBarTime != 0);
}

//+------------------------------------------------------------------+
//| Set bar time after opening a position (one trade per bar)         |
//+------------------------------------------------------------------+
void MarkBarAsTraded()
{
   g_LastOpenBarTime = iTime(_Symbol, InpTimeframe, 0);
}

//+------------------------------------------------------------------+
//| Calculate lot size: fixed or from risk money and SL distance      |
//+------------------------------------------------------------------+
double CalculateLots(double entryPrice, double slPrice)
{
   if (!InpUseRiskMoney)
      return NormalizeLots(InpLotSize);

   double slDistance = MathAbs(entryPrice - slPrice);
   if (slDistance <= 0) return NormalizeLots(InpLotSize);

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if (tickSize <= 0 || tickValue <= 0) return NormalizeLots(InpLotSize);

   double ticks = slDistance / tickSize;
   double riskPerLot = ticks * tickValue;
   if (riskPerLot <= 0) return NormalizeLots(InpLotSize);

   double lots = InpRiskMoney / riskPerLot;
   return NormalizeLots(lots);
}

double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Check spread filter                                               |
//+------------------------------------------------------------------+
bool IsSpreadOk()
{
   if (InpMaxSpreadPts <= 0) return true;
   long spread = (long)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= (long)InpMaxSpreadPts);
}

//+------------------------------------------------------------------+
//| Check min range filter (confluence)                               |
//+------------------------------------------------------------------+
bool IsRangeOk(double rangePct)
{
   if (InpMinRangePercent <= 0) return true;
   return (rangePct >= InpMinRangePercent);
}

//+------------------------------------------------------------------+
//| Open buy: SL/TP in %, lot from risk or fixed                      |
//+------------------------------------------------------------------+
bool OpenBuy(double prevHigh, datetime barTime)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double sl = 0, tp = 0;
   if (InpSLPercent > 0)
      sl = NormalizeDouble(ask - ask * InpSLPercent / 100.0, digits);
   if (InpTPPercent > 0)
      tp = NormalizeDouble(ask + ask * InpTPPercent / 100.0, digits);

   double lots = CalculateLots(ask, sl);
   if (lots <= 0) return false;

   if (!g_Trade.Buy(lots, _Symbol, ask, sl, tp, "BTCPDB Buy"))
   {
      Print("BTCPDB: Buy failed ", g_Trade.ResultRetcode());
      return false;
   }

   ulong posId = GetLastOpenedPositionId();
   if (posId > 0 && InpShowEntryVisuals)
      DrawEntryVisuals(posId, barTime, prevHigh, prevHigh, true);

   MarkBarAsTraded();
   return true;
}

//+------------------------------------------------------------------+
//| Open sell: SL/TP in %, lot from risk or fixed                     |
//+------------------------------------------------------------------+
bool OpenSell(double prevLow, datetime barTime)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double sl = 0, tp = 0;
   if (InpSLPercent > 0)
      sl = NormalizeDouble(bid + bid * InpSLPercent / 100.0, digits);
   if (InpTPPercent > 0)
      tp = NormalizeDouble(bid - bid * InpTPPercent / 100.0, digits);

   double lots = CalculateLots(bid, sl);
   if (lots <= 0) return false;

   if (!g_Trade.Sell(lots, _Symbol, bid, sl, tp, "BTCPDB Sell"))
   {
      Print("BTCPDB: Sell failed ", g_Trade.ResultRetcode());
      return false;
   }

   ulong posId = GetLastOpenedPositionId();
   if (posId > 0 && InpShowEntryVisuals)
      DrawEntryVisuals(posId, barTime, prevLow, prevLow, false);

   MarkBarAsTraded();
   return true;
}

ulong GetLastOpenedPositionId()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetTicket(i) <= 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return PositionGetInteger(POSITION_IDENTIFIER);
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Manage open positions: trailing stop, close before next candle    |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   datetime timeZero = iTime(_Symbol, InpTimeframe, 0);
   long periodSec = PeriodSeconds(InpTimeframe);
   datetime closeTime = timeZero + periodSec - (datetime)(InpCloseMinutesBeforeNextCandle * 60);

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
      double posSL   = PositionGetDouble(POSITION_SL);
      double posTP   = PositionGetDouble(POSITION_TP);
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

      // Close before next candle
      if (InpCloseMinutesBeforeNextCandle > 0 && TimeCurrent() >= closeTime)
      {
         g_Trade.PositionClose(ticket);
         continue;
      }

      // Trailing stop
      if (InpUseTrailingStop)
      {
         if (posType == POSITION_TYPE_BUY)
         {
            double triggerLevel = posOpen + posOpen * InpTSLTriggerPercent / 100.0;
            if (bid >= triggerLevel)
            {
               double newSL = NormalizeDouble(bid - bid * InpTSLPercent / 100.0, digits);
               if (newSL > posSL && newSL < bid)
               {
                  if (posTP <= 0) posTP = 0;
                  g_Trade.PositionModify(ticket, newSL, posTP);
               }
            }
         }
         else if (posType == POSITION_TYPE_SELL)
         {
            double triggerLevel = posOpen - posOpen * InpTSLTriggerPercent / 100.0;
            if (ask <= triggerLevel)
            {
               double newSL = NormalizeDouble(ask + ask * InpTSLPercent / 100.0, digits);
               if ((posSL <= 0 || newSL < posSL) && newSL > ask)
               {
                  if (posTP <= 0) posTP = 0;
                  g_Trade.PositionModify(ticket, newSL, posTP);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if we have any open position (this symbol, this magic)       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (PositionGetTicket(i) <= 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Main tick: breakout check (once per bar), manage positions        |
//+------------------------------------------------------------------+
void OnTick()
{
   // Reset bar-traded flag on new bar (new day on D1)
   datetime bar0Time = iTime(_Symbol, InpTimeframe, 0);
   if (bar0Time != g_LastBarTime)
      g_LastBarTime = bar0Time;

   // Funded account: daily reset and limit checks
   if (InpFundedAccount)
   {
      if (IsNewDay())
         ResetDailyFundedTracking();
      CheckFundedLimits();
      if (g_DailyLimitBreached || g_MaxLimitBreached)
      {
         ManagePositions();
         if (InpShowPerfTable) UpdatePerfPanel();
         ChartRedraw(0);
         return;
      }
   }

   ManagePositions();

   // Breakout logic: only if no position and conditions met
   if (HasOpenPosition())
   {
      if (InpShowPerfTable)
         UpdatePerfPanel();
      ChartRedraw(0);
      return;
   }

   if (InpFundedAccount && !CanPlaceNewOrder())
   {
      if (InpShowPerfTable) UpdatePerfPanel();
      ChartRedraw(0);
      return;
   }

   double prevHigh, prevLow, rangePct;
   if (!GetPreviousBarLevels(prevHigh, prevLow, rangePct))
      return;
   if (!IsRangeOk(rangePct))
      return;
   if (!IsSpreadOk())
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   datetime barTime = iTime(_Symbol, InpTimeframe, 1);  // Last closed bar time

   // Buy: price broke above previous day high (only one trade per bar)
   if (bid > prevHigh)
   {
      if (AlreadyTradedThisBar())
         return;
      OpenBuy(prevHigh, barTime);
      if (InpShowPerfTable) UpdatePerfPanel();
      ChartRedraw(0);
      return;
   }

   // Sell: price broke below previous day low
   if (bid < prevLow)
   {
      if (AlreadyTradedThisBar())
         return;
      OpenSell(prevLow, barTime);
      if (InpShowPerfTable) UpdatePerfPanel();
      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Draw entry visuals: horizontal line at breakout level (kept until |
//| position closes – no repaint; drawn only after fill).           |
//+------------------------------------------------------------------+
void DrawEntryVisuals(ulong positionId, datetime barTime, double level1, double level2, bool isBuy)
{
   string prefix = g_Prefix + "ENT_" + IntegerToString(positionId);
   DeleteEntryVisualsForPosition(positionId);

   datetime extendEnd = barTime + PeriodSeconds(InpTimeframe) * 5;

   // Breakout level line (prev day high/low)
   string lineName = prefix + "_L1";
   if (ObjectCreate(0, lineName, OBJ_TREND, 0, barTime, level1, extendEnd, level1))
   {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, isBuy ? clrDodgerBlue : clrOrangeRed);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, lineName, OBJPROP_BACK, false);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
   }

   if (MathAbs(level2 - level1) > 0)
   {
      string line2Name = prefix + "_L2";
      if (ObjectCreate(0, line2Name, OBJ_TREND, 0, barTime, level2, extendEnd, level2))
      {
         ObjectSetInteger(0, line2Name, OBJPROP_COLOR, isBuy ? clrLightBlue : clrTomato);
         ObjectSetInteger(0, line2Name, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, line2Name, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, line2Name, OBJPROP_BACK, false);
         ObjectSetInteger(0, line2Name, OBJPROP_SELECTABLE, false);
      }
   }

   // Entry arrow at bar time and breakout level (no repaint: drawn only after fill)
   string arrowName = prefix + "_ARR";
   if (ObjectCreate(0, arrowName, OBJ_ARROW, 0, barTime, level1))
   {
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, isBuy ? clrLime : clrOrangeRed);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, arrowName, OBJPROP_BACK, false);
      ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   }
}

//+------------------------------------------------------------------+
//| Delete entry visuals for a closed position (reset after close)     |
//+------------------------------------------------------------------+
void DeleteEntryVisualsForPosition(ulong positionId)
{
   string prefix = g_Prefix + "ENT_" + IntegerToString(positionId);
   ObjectDelete(0, prefix + "_L1");
   ObjectDelete(0, prefix + "_L2");
   ObjectDelete(0, prefix + "_ARR");
}

//+------------------------------------------------------------------+
//| Delete all entry visuals (prefix ENT_)                            |
//+------------------------------------------------------------------+
void DeleteAllEntryVisuals()
{
   int total = ObjectsTotal(0, 0, -1);
   for (int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if (StringFind(name, g_Prefix + "ENT_") == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Performance panel: create once                                    |
//+------------------------------------------------------------------+
void CreatePerfPanel()
{
   string name = g_Prefix + "PerfPanel";
   if (ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPerfPanelX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPerfPanelY);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   UpdatePerfPanel();
}

//+------------------------------------------------------------------+
//| Performance panel: update text (Trades, Win%, PF, P/L, Daily)      |
//+------------------------------------------------------------------+
void UpdatePerfPanel()
{
   if (!InpShowPerfTable) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);
   double dailyPL = 0.0;
   HistorySelect(dayStart, TimeCurrent());
   for (int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if (t == 0) continue;
      if (HistoryDealGetInteger(t, DEAL_MAGIC) != InpMagic) continue;
      if (HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol) continue;
      if (HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      dailyPL += HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_COMMISSION);
   }

   double winPct = (g_TotalTrades > 0) ? (100.0 * g_Wins / g_TotalTrades) : 0.0;
   double pf = (g_GrossLoss < 0) ? (g_GrossProfit / (-g_GrossLoss)) : (g_GrossProfit > 0 ? 999.99 : 0.0);

   string text = StringFormat("BTCPDB | Trades: %d | Win%%: %.1f | PF: %.2f | P/L: %.2f | Daily: %.2f",
                              g_TotalTrades, winPct, pf, g_TotalProfit, dailyPL);
   ObjectSetString(0, g_Prefix + "PerfPanel", OBJPROP_TEXT, text);
}
