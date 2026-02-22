//+------------------------------------------------------------------+
//|                                        MeanReversion_Structured.mq5 |
//|  Mean Reversion EA: MA + RSI + ATR confluences, no repaint,      |
//|  risk management, performance table, entry visualization.       |
//|                                                                  |
//|  CONFLUENCES (all required for entry):                            |
//|  1. Mean deviation: price >= MinMAGap% away from MA1 (signal).   |
//|  2. Trend filter: price above MA2 for buy, below MA2 for sell.   |
//|  3. Volatility: ATR1 (fast) < ATR2 (slow).                       |
//|  4. RSI direction: rising (buy) / falling (sell) on closed bar.|
//|  NO REPAINT: signals evaluated only on new bar using closed bar. |
//|  VISUAL: entry arrow drawn at signal bar; removed when trade    |
//|  is closed (SL/TP/MA/manual).                                    |
//+------------------------------------------------------------------+
#property copyright "Mean Reversion EA - Structured Build"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input groups: Indicators
input group "=== MA1 (Signal / Mean) ==="
input ENUM_TIMEFRAMES MA1_Timeframe  = PERIOD_M15;  // MA1 Timeframe
input int             MA1_Period    = 360;         // MA1 Period (e.g. 360)
input ENUM_MA_METHOD  MA1_Method    = MODE_SMA;    // MA1 Method
input ENUM_APPLIED_PRICE MA1_Price  = PRICE_CLOSE; // MA1 Applied Price

input group "=== MA2 (Trend Filter, Higher TF) ==="
input ENUM_TIMEFRAMES MA2_Timeframe = PERIOD_D1;   // MA2 Timeframe
input int             MA2_Period   = 20;           // MA2 Period

input group "=== RSI (Momentum Filter) ==="
input ENUM_TIMEFRAMES RSI_Timeframe = PERIOD_M15;   // RSI Timeframe
input int             RSI_Period   = 20;           // RSI Period
input ENUM_APPLIED_PRICE RSI_Price  = PRICE_CLOSE;  // RSI Applied Price

input group "=== ATR (Volatility Filter) ==="
input ENUM_TIMEFRAMES ATR_Timeframe = PERIOD_M15;   // ATR Timeframe
input int             ATR1_Period  = 10;            // ATR1 Period (Fast)
input int             ATR2_Period  = 20;            // ATR2 Period (Slow)

//--- Input groups: Entry confluences
input group "=== Entry: Mean Deviation ==="
input double MinMAGapPercent = 0.6;   // Min distance from MA1 (%)

input group "=== Risk Management ==="
input double Lots        = 0.1;       // Lot size (fixed)
input bool   UseRiskPct  = false;     // Use risk % for lot size
input double RiskPct     = 1.0;       // Risk per trade (% of balance)
input double TPPercent   = 1.5;      // Take profit (%)
input double SLPercent   = 1.0;       // Stop loss (%)
input bool   UseATR_SLTP = false;     // Use ATR for SL/TP
input double ATR_SL_Mul  = 1.5;       // ATR multiplier for SL
input double ATR_TP_Mul  = 2.0;       // ATR multiplier for TP
input double MaxSpreadPoints = 50;    // Max spread (points, 0=off)
input int   CooldownBars = 0;        // Bars cooldown after trade (0=off)
input int   MaxPositionsPerDirection = 1; // Max buy/sell positions (1 = one per side)

input group "=== Exit ==="
input bool CloseAtMA = true;          // Close at MA touch when in profit

input group "=== Filters ==="
input bool UseTimeFilter = false;     // Trading hours filter
input int  StartHour     = 0;        // Start hour (broker)
input int  EndHour       = 24;       // End hour (broker)

input group "=== Display & Identification ==="
input int  MagicNumber   = 202502;    // Magic number
input bool ShowPanel     = true;     // Show performance panel
input bool ShowEntryMarkers = true;  // Draw entry arrows (removed when trade closes)

//--- Indicator handles
int g_handleMA1, g_handleMA2, g_handleRSI, g_handleATR1, g_handleATR2;

//--- New-bar / no-repaint
int g_barsTotal = 0;

//--- Cooldown
datetime g_lastTradeOpenTime = 0;

//--- Performance stats (session: since EA attach or since last reset)
int    g_totalTrades = 0;
int    g_wins        = 0;
int    g_losses      = 0;
double g_grossProfit = 0;
double g_grossLoss   = 0;

//--- Trade objects
CTrade         g_trade;
CPositionInfo g_posInfo;

//--- Object name prefix for entry markers (removed when position closes)
#define ENTRY_PREFIX "MR_Entry_"
#define PANEL_PREFIX "MR_Panel_"

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_handleMA1 = iMA(_Symbol, MA1_Timeframe, MA1_Period, 0, MA1_Method, MA1_Price);
   if (g_handleMA1 == INVALID_HANDLE) { Print("MA1 handle failed"); return INIT_FAILED; }

   g_handleMA2 = iMA(_Symbol, MA2_Timeframe, MA2_Period, 0, MODE_SMA, PRICE_CLOSE);
   if (g_handleMA2 == INVALID_HANDLE) { Print("MA2 handle failed"); return INIT_FAILED; }

   g_handleRSI = iRSI(_Symbol, RSI_Timeframe, RSI_Period, RSI_Price);
   if (g_handleRSI == INVALID_HANDLE) { Print("RSI handle failed"); return INIT_FAILED; }

   g_handleATR1 = iATR(_Symbol, ATR_Timeframe, ATR1_Period);
   if (g_handleATR1 == INVALID_HANDLE) { Print("ATR1 handle failed"); return INIT_FAILED; }

   g_handleATR2 = iATR(_Symbol, ATR_Timeframe, ATR2_Period);
   if (g_handleATR2 == INVALID_HANDLE) { Print("ATR2 handle failed"); return INIT_FAILED; }

   g_barsTotal = iBars(_Symbol, MA1_Timeframe);
   g_lastTradeOpenTime = 0;
   g_totalTrades = 0;
   g_wins = 0;
   g_losses = 0;
   g_grossProfit = 0;
   g_grossLoss = 0;

   Print("MeanReversion_Structured: No-repaint (bar-close signals). Entry markers removed when trade closes.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (g_handleMA1 != INVALID_HANDLE) IndicatorRelease(g_handleMA1);
   if (g_handleMA2 != INVALID_HANDLE) IndicatorRelease(g_handleMA2);
   if (g_handleRSI != INVALID_HANDLE) IndicatorRelease(g_handleRSI);
   if (g_handleATR1 != INVALID_HANDLE) IndicatorRelease(g_handleATR1);
   if (g_handleATR2 != INVALID_HANDLE) IndicatorRelease(g_handleATR2);
   DeleteAllEntryMarkers();
   DeletePerformancePanel();
   Print("MeanReversion_Structured deinitialized.");
}

//+------------------------------------------------------------------+
//| Only run signal logic on new bar (no repaint)                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   int bars = iBars(_Symbol, MA1_Timeframe);
   if (bars == g_barsTotal) return false;
   g_barsTotal = bars;
   return true;
}

//+------------------------------------------------------------------+
//| Count positions by direction (this symbol, this magic)           |
//+------------------------------------------------------------------+
void CountPositions(int &buyCount, int &sellCount)
{
   buyCount = 0;
   sellCount = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_posInfo.SelectByIndex(i)) continue;
      if (g_posInfo.Symbol() != _Symbol || g_posInfo.Magic() != MagicNumber) continue;
      if (g_posInfo.PositionType() == POSITION_TYPE_BUY)  buyCount++;
      if (g_posInfo.PositionType() == POSITION_TYPE_SELL) sellCount++;
   }
}

//+------------------------------------------------------------------+
//| Get indicator values from CLOSED bar (shift 1) - no repaint       |
//+------------------------------------------------------------------+
bool GetIndicatorValues(double &ma1, double &ma2, double &rsi0, double &rsi1, double &atr1, double &atr2, double &closeBar)
{
   const int shift = 1;  // last closed bar only
   double bufMA1[2], bufMA2[1], bufRSI[2], bufATR1[1], bufATR2[1];
   ArraySetAsSeries(bufMA1, true);
   ArraySetAsSeries(bufMA2, true);
   ArraySetAsSeries(bufRSI, true);
   ArraySetAsSeries(bufATR1, true);
   ArraySetAsSeries(bufATR2, true);

   if (CopyBuffer(g_handleMA1, 0, shift, 2, bufMA1) < 2) return false;
   if (CopyBuffer(g_handleMA2, 0, shift, 1, bufMA2) < 1) return false;
   if (CopyBuffer(g_handleRSI, 0, shift, 2, bufRSI) < 2) return false;
   if (CopyBuffer(g_handleATR1, 0, shift, 1, bufATR1) < 1) return false;
   if (CopyBuffer(g_handleATR2, 0, shift, 1, bufATR2) < 1) return false;

   ma1      = bufMA1[0];
   ma2      = bufMA2[0];
   rsi0     = bufRSI[0];  // current closed bar
   rsi1     = bufRSI[1];  // previous closed bar (for direction)
   atr1     = bufATR1[0];
   atr2     = bufATR2[0];
   closeBar = iClose(_Symbol, MA1_Timeframe, shift);
   return true;
}

//+------------------------------------------------------------------+
//| MA1 value for exit / current bar (for position management only)  |
//+------------------------------------------------------------------+
bool GetMA1Current(double &ma1Now)
{
   double buf[1];
   ArraySetAsSeries(buf, true);
   if (CopyBuffer(g_handleMA1, 0, 1, 1, buf) < 1) return false;
   ma1Now = buf[0];
   return true;
}

//+------------------------------------------------------------------+
//| Spread filter                                                     |
//+------------------------------------------------------------------+
bool SpreadOK()
{
   if (MaxSpreadPoints <= 0) return true;
   return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= (long)MaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Time filter                                                       |
//+------------------------------------------------------------------+
bool TimeFilterOK()
{
   if (!UseTimeFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if (EndHour > StartHour)
      return (dt.hour >= StartHour && dt.hour < EndHour);
   return (dt.hour >= StartHour || dt.hour < EndHour);
}

//+------------------------------------------------------------------+
//| Cooldown filter                                                   |
//+------------------------------------------------------------------+
bool CooldownOK()
{
   if (CooldownBars <= 0) return true;
   if (g_lastTradeOpenTime <= 0) return true;
   datetime barTime = iTime(_Symbol, MA1_Timeframe, 1);
   int barsSince = Bars(_Symbol, MA1_Timeframe, g_lastTradeOpenTime, barTime);
   return (barsSince >= CooldownBars);
}

//+------------------------------------------------------------------+
//| Manage positions: close at MA when in profit; cleanup markers   |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double ma1Now;
   if (!GetMA1Current(ma1Now)) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_posInfo.SelectByIndex(i)) continue;
      if (g_posInfo.Symbol() != _Symbol || g_posInfo.Magic() != MagicNumber) continue;

      ulong ticket = g_posInfo.Ticket();

      if (g_posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         if (CloseAtMA && g_posInfo.Profit() > 0 && bid > ma1Now)
         {
            if (g_trade.PositionClose(ticket))
               RemoveEntryMarker(ticket);
         }
      }
      else if (g_posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         if (CloseAtMA && g_posInfo.Profit() > 0 && ask < ma1Now)
         {
            if (g_trade.PositionClose(ticket))
               RemoveEntryMarker(ticket);
         }
      }
   }

   // Remove markers for positions that no longer exist (SL/TP hit or manual close)
   CleanupOrphanMarkers();
}

//+------------------------------------------------------------------+
//| Draw entry marker at signal bar (no repaint: bar already closed) |
//+------------------------------------------------------------------+
void DrawEntryMarker(ulong ticket, bool isBuy, datetime barTime, double price)
{
   if (!ShowEntryMarkers) return;
   string name = ENTRY_PREFIX + IntegerToString(ticket);
   if (ObjectFind(0, name) >= 0) ObjectDelete(0, name);

   int type = isBuy ? OBJ_ARROW_BUY : OBJ_ARROW_SELL;
   if (ObjectCreate(0, name, type, 0, barTime, price))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? clrLime : clrRed);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

//+------------------------------------------------------------------+
//| Remove entry marker when trade is closed                         |
//+------------------------------------------------------------------+
void RemoveEntryMarker(ulong ticket)
{
   string name = ENTRY_PREFIX + IntegerToString(ticket);
   ObjectDelete(0, name);
}

//+------------------------------------------------------------------+
//| Delete all entry markers                                         |
//+------------------------------------------------------------------+
void DeleteAllEntryMarkers()
{
   int total = ObjectsTotal(0, 0, OBJ_ARROW);
   for (int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_ARROW);
      if (StringFind(name, ENTRY_PREFIX) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Remove markers for positions that no longer exist (SL/TP/manual)  |
//+------------------------------------------------------------------+
void CleanupOrphanMarkers()
{
   string toDelete[];
   int total = ObjectsTotal(0, 0, -1);
   for (int i = 0; i < total; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      if (StringFind(name, ENTRY_PREFIX) != 0) continue;
      string suffix = StringSubstr(name, StringLen(ENTRY_PREFIX));
      ulong ticket = (ulong)StringToInteger(suffix);
      if (ticket > 0 && !PositionSelectByTicket((ulong)ticket))
      {
         int n = ArraySize(toDelete);
         ArrayResize(toDelete, n + 1);
         toDelete[n] = name;
      }
   }
   for (int j = 0; j < ArraySize(toDelete); j++)
      ObjectDelete(0, toDelete[j]);
}

//+------------------------------------------------------------------+
//| Record closed trade for performance stats                         |
//+------------------------------------------------------------------+
void RecordClosedTrade(double profit)
{
   g_totalTrades++;
   if (profit > 0) { g_wins++; g_grossProfit += profit; }
   else            { g_losses++; g_grossLoss += MathAbs(profit); }
}

//+------------------------------------------------------------------+
//| Performance panel on chart                                       |
//+------------------------------------------------------------------+
void UpdatePerformancePanel()
{
   if (!ShowPanel) return;
   DeletePerformancePanel();

   double pf = (g_grossLoss > 0) ? (g_grossProfit / g_grossLoss) : (g_grossProfit > 0 ? 999.99 : 0);
   double winRate = (g_totalTrades > 0) ? (100.0 * g_wins / g_totalTrades) : 0;
   double net = g_grossProfit - g_grossLoss;

   string lines[];
   ArrayResize(lines, 8);
   lines[0] = "=== Mean Reversion ===";
   lines[1] = "Trades: " + IntegerToString(g_totalTrades);
   lines[2] = "Wins: " + IntegerToString(g_wins) + " | Losses: " + IntegerToString(g_losses);
   lines[3] = "Win Rate: " + DoubleToString(winRate, 1) + "%";
   lines[4] = "Profit Factor: " + DoubleToString(pf, 2);
   lines[5] = "Gross Profit: " + DoubleToString(g_grossProfit, 2);
   lines[6] = "Gross Loss: " + DoubleToString(g_grossLoss, 2);
   lines[7] = "Net: " + DoubleToString(net, 2);

   int y = 20;
   for (int i = 0; i < ArraySize(lines); i++)
   {
      string name = PANEL_PREFIX + IntegerToString(i);
      if (ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
      {
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
         ObjectSetString(0, name, OBJPROP_TEXT, lines[i]);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
      y += 16;
   }
}

void DeletePerformancePanel()
{
   for (int i = 0; i < 20; i++)
      ObjectDelete(0, PANEL_PREFIX + IntegerToString(i));
}

//+------------------------------------------------------------------+
//| Calculate lot size (fixed or risk %)                             |
//+------------------------------------------------------------------+
double CalcLots(double entryPrice, double slPrice)
{
   if (!UseRiskPct || RiskPct <= 0) return Lots;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (RiskPct / 100.0);
   double dist = MathAbs(entryPrice - slPrice);
   if (dist <= 0) return Lots;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if (tickSz <= 0 || tickVal <= 0) return Lots;
   double riskPerLot = (dist / tickSz) * tickVal;
   if (riskPerLot <= 0) return Lots;
   double lot = riskAmount / riskPerLot;
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot / step) * step;
   lot = MathMax(minL, MathMin(maxL, lot));
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Get position ticket of the most recently opened position (our EA) |
//+------------------------------------------------------------------+
ulong GetLastOpenedPositionTicket(bool isBuy)
{
   ulong foundTicket = 0;
   datetime latestTime = 0;
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if (!g_posInfo.SelectByIndex(i)) continue;
      if (g_posInfo.Symbol() != _Symbol || g_posInfo.Magic() != MagicNumber) continue;
      if (isBuy && g_posInfo.PositionType() != POSITION_TYPE_BUY) continue;
      if (!isBuy && g_posInfo.PositionType() != POSITION_TYPE_SELL) continue;
      datetime ot = (datetime)g_posInfo.Time();
      if (ot > latestTime) { latestTime = ot; foundTicket = g_posInfo.Ticket(); }
   }
   return foundTicket;
}

//+------------------------------------------------------------------+
//| Open BUY                                                          |
//+------------------------------------------------------------------+
void OpenBuy(double ask, double atrVal)
{
   double sl = 0, tp = 0;
   if (UseATR_SLTP && atrVal > 0)
   {
      sl = ask - atrVal * ATR_SL_Mul;
      tp = ask + atrVal * ATR_TP_Mul;
   }
   else
   {
      if (SLPercent > 0) sl = ask - ask * (SLPercent / 100.0);
      if (TPPercent > 0) tp = ask + ask * (TPPercent / 100.0);
   }
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   double lot = CalcLots(ask, sl);

   if (g_trade.Buy(lot, _Symbol, ask, sl, tp, "MR_Buy"))
   {
      ulong ticket = GetLastOpenedPositionTicket(true);
      g_lastTradeOpenTime = TimeCurrent();
      datetime barTime = iTime(_Symbol, MA1_Timeframe, 1);
      double lowBar = iLow(_Symbol, MA1_Timeframe, 1);
      DrawEntryMarker(ticket, true, barTime, lowBar);
   }
   else
      Print("Buy failed: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Open SELL                                                         |
//+------------------------------------------------------------------+
void OpenSell(double bid, double atrVal)
{
   double sl = 0, tp = 0;
   if (UseATR_SLTP && atrVal > 0)
   {
      sl = bid + atrVal * ATR_SL_Mul;
      tp = bid - atrVal * ATR_TP_Mul;
   }
   else
   {
      if (SLPercent > 0) sl = bid + bid * (SLPercent / 100.0);
      if (TPPercent > 0) tp = bid - bid * (TPPercent / 100.0);
   }
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
   double lot = CalcLots(bid, sl);

   if (g_trade.Sell(lot, _Symbol, bid, sl, tp, "MR_Sell"))
   {
      ulong ticket = GetLastOpenedPositionTicket(false);
      g_lastTradeOpenTime = TimeCurrent();
      datetime barTime = iTime(_Symbol, MA1_Timeframe, 1);
      double highBar = iHigh(_Symbol, MA1_Timeframe, 1);
      DrawEntryMarker(ticket, false, barTime, highBar);
   }
   else
      Print("Sell failed: ", GetLastError());
}

//+------------------------------------------------------------------+
//| Check entry signals (only on new bar, closed bar data = no repaint)|
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
   if (!IsNewBar()) return;
   if (!SpreadOK() || !TimeFilterOK() || !CooldownOK()) return;

   double ma1, ma2, rsi0, rsi1, atr1, atr2, closeBar;
   if (!GetIndicatorValues(ma1, ma2, rsi0, rsi1, atr1, atr2, closeBar)) return;

   // Confluence 1: Volatility filter — fast ATR below slow ATR
   if (atr1 >= atr2) return;

   // Confluence 2: Price distance from mean (min gap %)
   double buyThreshold  = ma1 - ma1 * (MinMAGapPercent / 100.0);
   double sellThreshold  = ma1 + ma1 * (MinMAGapPercent / 100.0);

   int buyCount, sellCount;
   CountPositions(buyCount, sellCount);

   // BUY: price below MA1 by at least MinMAGap% + above MA2 (trend) + RSI rising
   if (buyCount < MaxPositionsPerDirection &&
       closeBar < buyThreshold &&
       closeBar > ma2 &&
       rsi0 > rsi1)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      OpenBuy(ask, atr1);
      return;
   }

   // SELL: price above MA1 by at least MinMAGap% + below MA2 (trend) + RSI falling
   if (sellCount < MaxPositionsPerDirection &&
       closeBar > sellThreshold &&
       closeBar < ma2 &&
       rsi0 < rsi1)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      OpenSell(bid, atr1);
   }
}

//+------------------------------------------------------------------+
//| OnTick: manage positions and cleanup markers every tick;          |
//|         signals only on new bar.                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();
   CheckEntrySignals();
   if (ShowPanel) UpdatePerformancePanel();
}

//+------------------------------------------------------------------+
//| TradeTransaction — detect closed positions to update stats       |
//| and remove entry marker (alternative to CleanupOrphanMarkers)    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if (trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong ticket = trans.position_id;
   if (ticket == 0) return;

   if (!HistoryDealSelect(trans.deal)) return;
   if (HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if (HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if (entry == DEAL_ENTRY_OUT)
   {
      double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                      HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                      HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
      RecordClosedTrade(profit);
      RemoveEntryMarker(ticket);
   }
}
//+------------------------------------------------------------------+
