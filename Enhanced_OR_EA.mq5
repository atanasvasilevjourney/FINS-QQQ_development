//+------------------------------------------------------------------+
//|                                              Enhanced_OR_EA.mq5   |
//|                        Enhanced Opening Range Strategy EA        |
//+------------------------------------------------------------------+
#property copyright "HorizonAI"
#property link      ""
#property version   "1.00"
#property strict
#property description "Enhanced Opening Range Strategy EA for MT5 - Translated from PineScript + extras"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Enums
enum ENUM_OR_DURATION { OR_5MIN=5, OR_15MIN=15, OR_30MIN=30, OR_45MIN=45, OR_60MIN=60 };
enum ENUM_POSITION_SIZING { PS_FIXED_CONTRACTS, PS_FIXED_USD_RISK };
enum ENUM_SL_TYPE { SL_RANGE_PCT, SL_ATR_MULT, SL_FIXED_PCT, SL_FIXED_POINTS, SL_OPPOSITE_RANGE };
enum ENUM_TP_TYPE { TP_RR, TP_RANGE_PCT, TP_ATR_MULT, TP_FIXED_PCT, TP_FIXED_POINTS };

//--- Inputs: Opening Range
input group "=== Opening Range Settings ==="
input int InpORStartHour = 9;                    // OR Start Hour (server time)
input int InpORStartMin = 30;                    // OR Start Minute
input ENUM_OR_DURATION InpORDuration = OR_15MIN; // OR Duration (minutes)
input int InpBreakoutCandles = 2;                // Consecutive Breakout Candles
input bool InpReverseLogic = false;              // Reverse Logic (Short on Bull Break, Long on Bear)

//--- Inputs: Position Sizing
input group "=== Position Sizing ==="
input ENUM_POSITION_SIZING InpPosSizing = PS_FIXED_CONTRACTS;
input double InpFixedContracts = 1.0;            // Fixed Contracts/Lots
input double InpFixedUSDRisk = 100.0;            // USD Risk per Trade
input double InpTickValue = 12.50;              // Tick Value (USD per point, e.g. ES=12.5)

//--- Inputs: Risk Management
input group "=== Risk Management ==="
input ENUM_SL_TYPE InpSLType = SL_RANGE_PCT;     // Stop Loss Type
input double InpSLValue = 50.0;                  // SL Value (%, mult, points)
input ENUM_TP_TYPE InpTPType = TP_RR;            // Take Profit Type
input double InpTPValue = 2.0;                   // TP Value (RR, %, mult, points)
input int InpATRLength = 14;                     // ATR Length
input bool InpEnableTrail = true;                // Enable Trailing Stop
input double InpTrailStart = 20.0;               // Trail Start (points)
input double InpTrailStep = 10.0;                // Trail Step (points)

//--- Inputs: Prop Firm, DST & Visual (single set)
input group "=== Prop Firm & Misc ==="
input ulong InpMagic = 123456;                   // Magic Number
input bool InpEnforceProp = true;                // Enforce Prop Firm Rules
input double InpMaxDailyLoss = 500.0;            // Max Daily Loss (USD)
input double InpMaxDrawdown = 1000.0;            // Max Drawdown (USD)
input int InpMaxTradesDay = 3;                   // Max Trades per Day
input bool InpAutoDST = true;                    // Auto DST Adjustment
input int InpDSTOffset = 1;                      // DST Offset (hours)
input color InpRiskColor = clrYellow;            // Risk Box Color
input color InpRewardColor = clrGreen;           // Reward Color
input color InpEntryColor = clrWhite;            // Entry Line Color

//--- Inputs: Second Chance
input group "=== Second Chance ==="
input bool InpEnableSecondChance = false;         // Enable Second Chance (opp. trade after SL)

//--- Globals
CTrade trade;
CPositionInfo pos;
COrderInfo order;

int atr_handle;
double or_high, or_low, or_size;
datetime or_start_time, session_start_time;
int breakout_up_count = 0, breakout_down_count = 0;
bool in_or_period = false, or_broken_up = false, or_broken_down = false;
bool first_trade_sl_hit = false;
int trades_today = 0;
double daily_pnl = 0, max_dd = 0, running_dd = 0;
double prev_high = 0, prev_low = 0;
string perf_table = "OR_PerfTable";
int bars_total_prev = 0;
int adjusted_or_start_hour;

//--- Performance stats
double total_trades = 0, wins = 0, total_profit = 0, gross_profit = 0, gross_loss = 0;
double winrate = 0, profit_factor = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber((int)InpMagic);
   atr_handle = iATR(_Symbol, PERIOD_CURRENT, InpATRLength);
   if(atr_handle == INVALID_HANDLE) return INIT_FAILED;

   adjusted_or_start_hour = InpORStartHour;

   CreatePerfTable();

   Print("Enhanced OR EA initialized");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "OR_");
   ObjectsDeleteAll(0, perf_table);
   IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: detect SL exit for Second Chance             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic)
            return;
         if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
            return;
         if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            return;
         long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
         if(reason == DEAL_REASON_SL)
         {
            first_trade_sl_hit = true;
            Print("OR EA: Position closed at SL - Second Chance eligible: ", InpEnableSecondChance);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;

   UpdateDST();
   CheckPropRules();
   UpdatePerfStats();
   UpdatePerfTable();

   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);

   // New session check (daily) - use adjusted hour for DST
   if(IsNewSession(dt.hour, dt.min))
   {
      ResetSessionVars();
      session_start_time = current_time;
   }

   // OR period - use adjusted hour
   if(IsORStart(dt.hour, dt.min))
   {
      in_or_period = true;
      or_start_time = current_time;
      or_high = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      or_low = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   }

   if(in_or_period && (current_time - or_start_time) / 60 >= (int)InpORDuration)
   {
      in_or_period = false;
      or_size = or_high - or_low;
      Print("OR complete: High=", or_high, " Low=", or_low);
      DrawORBox();
   }

   if(!in_or_period && or_high > 0)
   {
      UpdateORHighLow();

      double close = iClose(_Symbol, PERIOD_CURRENT, 1);
      if(close > or_high)
      {
         breakout_up_count++;
         breakout_down_count = 0;
         if(breakout_up_count >= InpBreakoutCandles && !or_broken_up && PositionsTotalByMagic() == 0)
            SignalBreakout(true);
      }
      else if(close < or_low)
      {
         breakout_down_count++;
         breakout_up_count = 0;
         if(breakout_down_count >= InpBreakoutCandles && !or_broken_down && PositionsTotalByMagic() == 0)
            SignalBreakout(false);
      }
      else
      {
         breakout_up_count = 0;
         breakout_down_count = 0;
      }
   }

   if(InpEnableTrail) TrailPositions();

   if(IsEOD(dt.hour)) CloseAllPositions("EOD");

   UpdatePerfTable();
}

//+------------------------------------------------------------------+
//| Check new bar                                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   int bars_total = iBars(_Symbol, PERIOD_CURRENT);
   if(bars_total != bars_total_prev)
   {
      bars_total_prev = bars_total;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| New session (daily open) - uses adjusted_or_start_hour            |
//+------------------------------------------------------------------+
bool IsNewSession(int hour, int min)
{
   static datetime last_session = 0;
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = adjusted_or_start_hour;
   dt.min  = InpORStartMin;
   dt.sec  = 0;
   datetime session_time = StructToTime(dt);

   if(now >= session_time && last_session != session_time)
   {
      last_session = session_time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| OR start time - uses adjusted_or_start_hour for DST              |
//+------------------------------------------------------------------+
bool IsORStart(int hour, int min)
{
   return (hour == adjusted_or_start_hour && min == InpORStartMin);
}

//+------------------------------------------------------------------+
//| Update OR high/low during period                                 |
//+------------------------------------------------------------------+
void UpdateORHighLow()
{
   double high = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double low = iLow(_Symbol, PERIOD_CURRENT, 1);
   or_high = MathMax(or_high, high);
   or_low = MathMin(or_low, low);
}

//+------------------------------------------------------------------+
//| Signal breakout                                                  |
//+------------------------------------------------------------------+
void SignalBreakout(bool is_bull)
{
   if(InpReverseLogic) is_bull = !is_bull;

   if(first_trade_sl_hit && InpEnableSecondChance)
      is_bull = !is_bull;

   double entry = is_bull ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = GetStopLoss(entry, is_bull);
   double tp = GetTakeProfit(entry, sl, is_bull);
   double lots = GetPositionSize(entry, sl);

   string comment = is_bull ? (first_trade_sl_hit ? "Second Buy" : "Buy") : (first_trade_sl_hit ? "Second Sell" : "Sell");
   if(first_trade_sl_hit && InpReverseLogic) comment = "Reverse " + comment;

   if(trade.PositionOpen(_Symbol, is_bull ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lots, entry, sl, tp, comment))
   {
      or_broken_up = is_bull;
      or_broken_down = !is_bull;
      first_trade_sl_hit = false;
      trades_today++;
      DrawEntryLine(entry);
   }
}

//+------------------------------------------------------------------+
//| Get position size                                                |
//+------------------------------------------------------------------+
double GetPositionSize(double entry, double sl)
{
   double lots = InpFixedContracts;
   if(InpPosSizing == PS_FIXED_USD_RISK)
   {
      double risk = MathAbs(entry - sl) / _Point;
      double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_val == 0) tick_val = InpTickValue;
      lots = InpFixedUSDRisk / (risk * tick_val);
   }
   double minlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxlot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(minlot, MathMin(maxlot, NormalizeDouble(lots / step, 0) * step));
   return lots;
}

//+------------------------------------------------------------------+
//| Get stop loss                                                    |
//+------------------------------------------------------------------+
double GetStopLoss(double entry, bool is_long)
{
   double sl;
   double atr[1];
   if(CopyBuffer(atr_handle, 0, 1, 1, atr) < 1) return entry;

   switch(InpSLType)
   {
      case SL_RANGE_PCT:
         sl = is_long ? entry - (or_size * InpSLValue / 100) : entry + (or_size * InpSLValue / 100);
         break;
      case SL_ATR_MULT:
         sl = is_long ? entry - (atr[0] * InpSLValue) : entry + (atr[0] * InpSLValue);
         break;
      case SL_FIXED_PCT:
         sl = is_long ? entry * (1 - InpSLValue / 100) : entry * (1 + InpSLValue / 100);
         break;
      case SL_FIXED_POINTS:
         sl = is_long ? entry - (InpSLValue * _Point) : entry + (InpSLValue * _Point);
         break;
      case SL_OPPOSITE_RANGE:
         sl = is_long ? or_low : or_high;
         break;
      default: sl = entry;
   }
   return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| Get take profit                                                  |
//+------------------------------------------------------------------+
double GetTakeProfit(double entry, double sl, bool is_long)
{
   double tp;
   double risk = MathAbs(entry - sl);
   double atr[1];
   if(CopyBuffer(atr_handle, 0, 1, 1, atr) < 1) atr[0] = risk;

   switch(InpTPType)
   {
      case TP_RR:
         tp = is_long ? entry + (risk * InpTPValue) : entry - (risk * InpTPValue);
         break;
      case TP_RANGE_PCT:
         tp = is_long ? entry + (or_size * InpTPValue / 100) : entry - (or_size * InpTPValue / 100);
         break;
      case TP_ATR_MULT:
         tp = is_long ? entry + (atr[0] * InpTPValue) : entry - (atr[0] * InpTPValue);
         break;
      case TP_FIXED_PCT:
         tp = is_long ? entry * (1 + InpTPValue / 100) : entry * (1 - InpTPValue / 100);
         break;
      case TP_FIXED_POINTS:
         tp = is_long ? entry + (InpTPValue * _Point) : entry - (InpTPValue * _Point);
         break;
      default: tp = entry;
   }
   return NormalizeDouble(tp, _Digits);
}

//+------------------------------------------------------------------+
//| Trailing stop                                                    |
//+------------------------------------------------------------------+
void TrailPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Magic() == (long)InpMagic && pos.Symbol() == _Symbol)
      {
         double open = pos.PriceOpen();
         double current = pos.PriceCurrent();
         double sl = pos.StopLoss();

         double trail_start_dist = InpTrailStart * _Point;
         double trail_step_dist = InpTrailStep * _Point;

         if(pos.PositionType() == POSITION_TYPE_BUY)
         {
            if(current - open >= trail_start_dist)
            {
               double new_sl = NormalizeDouble(current - trail_start_dist, _Digits);
               if(new_sl > sl + trail_step_dist)
                  trade.PositionModify(pos.Ticket(), new_sl, pos.TakeProfit());
            }
         }
         else
         {
            if(open - current >= trail_start_dist)
            {
               double new_sl = NormalizeDouble(current + trail_start_dist, _Digits);
               if(new_sl < sl - trail_step_dist || sl == 0)
                  trade.PositionModify(pos.Ticket(), new_sl, pos.TakeProfit());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check prop rules before trade                                    |
//+------------------------------------------------------------------+
void CheckPropRules()
{
   if(!InpEnforceProp) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   running_dd = balance - equity;
   if(running_dd > max_dd) max_dd = running_dd;

   HistorySelect(TimeCurrent() - 86400, TimeCurrent());
   daily_pnl = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0 && HistoryDealGetInteger(ticket, DEAL_MAGIC) == (long)InpMagic)
         daily_pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }

   if(daily_pnl <= -InpMaxDailyLoss || max_dd >= InpMaxDrawdown || trades_today >= InpMaxTradesDay)
   {
      CloseAllPositions("Prop Limit");
      ExpertRemove();
   }
}

//+------------------------------------------------------------------+
//| Update perf stats                                                |
//+------------------------------------------------------------------+
void UpdatePerfStats()
{
   HistorySelect(0, TimeCurrent());
   total_trades = 0; wins = 0; total_profit = 0; gross_profit = 0; gross_loss = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)InpMagic || HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      total_trades++;
      total_profit += profit;
      if(profit > 0)
      {
         wins++;
         gross_profit += profit;
      }
      else
         gross_loss += profit;
   }
   winrate = total_trades > 0 ? (wins / total_trades * 100.0) : 0.0;
   profit_factor = (gross_loss < 0.0) ? gross_profit / (-gross_loss) : (gross_profit > 0.0 ? 999.99 : 0.0);
}

//+------------------------------------------------------------------+
//| Create perf table                                                |
//+------------------------------------------------------------------+
void CreatePerfTable()
{
   ObjectCreate(0, perf_table, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, perf_table, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, perf_table, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, perf_table, OBJPROP_YDISTANCE, 30);
   ObjectSetInteger(0, perf_table, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, perf_table, OBJPROP_FONTSIZE, 9);
}

//+------------------------------------------------------------------+
//| Update perf table                                                |
//+------------------------------------------------------------------+
void UpdatePerfTable()
{
   string text = StringFormat("Trades: %.0f | Winrate: %.1f%% | PF: %.2f | Daily P&L: %.2f | DD: %.2f",
                             total_trades, winrate, profit_factor, daily_pnl, running_dd);
   ObjectSetString(0, perf_table, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Draw OR box                                                      |
//+------------------------------------------------------------------+
void DrawORBox()
{
   string name = "OR_Box_" + TimeToString(TimeCurrent(), TIME_DATE);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, or_start_time, or_high, TimeCurrent() + PeriodSeconds() * 20, or_low);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpRiskColor);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

//+------------------------------------------------------------------+
//| Draw entry line                                                  |
//+------------------------------------------------------------------+
void DrawEntryLine(double price)
{
   string name = "OR_Entry_" + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
   ObjectCreate(0, name, OBJ_TREND, 0, TimeCurrent(), price, TimeCurrent() + PeriodSeconds() * 10, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpEntryColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Magic() == (long)InpMagic)
         trade.PositionClose(pos.Ticket());
   }
   Print("Closed all: ", reason);
}

//+------------------------------------------------------------------+
//| Positions by magic                                               |
//+------------------------------------------------------------------+
int PositionsTotalByMagic()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(pos.SelectByIndex(i) && pos.Magic() == (long)InpMagic && pos.Symbol() == _Symbol)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Reset session vars                                               |
//+------------------------------------------------------------------+
void ResetSessionVars()
{
   or_high = 0; or_low = 0;
   breakout_up_count = 0; breakout_down_count = 0;
   or_broken_up = false; or_broken_down = false;
   in_or_period = false;
   trades_today = 0;
   daily_pnl = 0;
}

//+------------------------------------------------------------------+
//| DST adjustment                                                   |
//+------------------------------------------------------------------+
void UpdateDST()
{
   if(!InpAutoDST) { adjusted_or_start_hour = InpORStartHour; return; }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool is_dst = (dt.mon > 3 || (dt.mon == 3 && dt.day >= 10)) && (dt.mon < 11 || (dt.mon == 11 && dt.day < 3));
   if(is_dst)
      adjusted_or_start_hour = InpORStartHour + InpDSTOffset;
   else
      adjusted_or_start_hour = InpORStartHour - InpDSTOffset;
   if(adjusted_or_start_hour >= 24) adjusted_or_start_hour -= 24;
   if(adjusted_or_start_hour < 0) adjusted_or_start_hour += 24;
}

//+------------------------------------------------------------------+
//| EOD check (e.g., 16:00)                                          |
//+------------------------------------------------------------------+
bool IsEOD(int hour)
{
   return hour >= 16;
}
