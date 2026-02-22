//+------------------------------------------------------------------+
//|                                              MartingaleGrid_EA.mq5 |
//|  Martingale Grid EA: grid entries on pullback from high/low,     |
//|  close grid at TP from break-even. No repaint, prop firm ready,  |
//|  trailing stop, clear visualization, reset on closed entry.      |
//+------------------------------------------------------------------+
#property copyright "Martingale Grid EA"
#property version   "1.00"
#property description "Grid: open buy after X points down from high, sell after X up from low."
#property description "Add positions every X points with lot multiplier. Close grid at TP from BE."
#property description "No repaint | Prop firm risk | Trailing stop | Reset on close."

#include <Trade\Trade.mqh>

//--- Grid & lots
input group "=== Grid & Lots ==="
input int      InpGridPoints     = 1000;   // Grid distance (points)
input double   InpStartLots      = 0.01;   // Starting lot size
input double   InpLotsMultiplier = 3.0;    // Lot multiplier per level (e.g. 3 = 0.01, 0.03, 0.09...)
input int      InpTPPoints       = 200;    // Take profit from break-even (points)

//--- Trade execution
input group "=== Trade Execution ==="
input int      InpMagic          = 77100;  // Magic number
input int      InpSlippagePoints  = 10;     // Slippage (points)
input double   InpMaxSpreadPoints = 0;      // Max spread to open (0 = disable)

//--- Risk (Prop firm style)
input group "=== Risk Management (Prop Firm) ==="
input bool     InpUseRiskLimits  = true;   // Use risk limits
input int      InpMaxPositions   = 20;     // Max total positions (buy+sell)
input double   InpMaxLotSize     = 1.0;    // Max lot per order
input double   InpDailyLossPct   = 5.0;    // Daily loss limit (% of daily start balance)
input double   InpMaxDrawdownPct = 10.0;   // Max drawdown % (from highest equity)
input double   InpChallengeSize  = 100000; // Challenge account size ($) for % limits

//--- Trailing stop
input group "=== Trailing Stop ==="
input bool     InpUseTrailing    = false;  // Use trailing stop
input int      InpTrailStartPoints = 100;  // Start trailing after profit (points from BE)
input int      InpTrailStepPoints  = 50;   // Trail step (points)

//--- Visualization
input group "=== Visualization ==="
input bool     InpShowComment    = true;   // Show info panel on chart
input bool     InpShowLevels     = false;  // Draw BE / grid levels on chart

//--- Global: price tracking (reset when grid closed)
double   g_HighestPrice;
double   g_LowestPrice;

//--- Trade
CTrade  g_Trade;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_Trade.SetExpertMagicNumber(InpMagic);
   g_Trade.SetDeviationInPoints(InpSlippagePoints);
   g_Trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_HighestPrice = 0;
   g_LowestPrice  = DBL_MAX;

   if (!ValidateInputs())
   {
      Print("MartingaleGrid: Invalid inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if (InpUseRiskLimits)
      InitPropFirmState();

   Print("MartingaleGrid EA initialized. Grid=", InpGridPoints, " pts, TP=", InpTPPoints, " pts.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (InpShowLevels)
      DeleteLevelObjects();
   Comment("");
   Print("MartingaleGrid EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Validate inputs                                                    |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if (InpGridPoints <= 0 || InpTPPoints <= 0)
      return false;
   if (InpStartLots <= 0 || InpLotsMultiplier < 1.0)
      return false;
   if (InpUseRiskLimits)
   {
      if (InpMaxPositions <= 0 || InpMaxLotSize <= 0)
         return false;
      if (InpDailyLossPct <= 0 || InpMaxDrawdownPct <= 0 || InpChallengeSize <= 0)
         return false;
   }
   if (InpUseTrailing && (InpTrailStartPoints < 0 || InpTrailStepPoints <= 0))
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Normalize lot to symbol step                                       |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if (step <= 0)
      step = 0.01;
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   if (InpUseRiskLimits && InpMaxLotSize > 0)
      lots = MathMin(lots, InpMaxLotSize);
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Normalize price                                                    |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   return NormalizeDouble(price, _Digits);
}

//+------------------------------------------------------------------+
//| Check spread (no repaint: current spread only)                    |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   if (InpMaxSpreadPoints <= 0)
      return true;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= (long)InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| Count positions by magic and symbol (our EA only)                 |
//+------------------------------------------------------------------+
int CountPositions(int &outBuyCount, int &outSellCount,
                   double &outSumBuyPriceLots, double &outTotalBuyLots,
                   double &outSumSellPriceLots, double &outTotalSellLots,
                   double &outLastBuyPrice, double &outLastBuyLots,
                   double &outLastSellPrice, double &outLastSellLots)
{
   outBuyCount = 0;
   outSellCount = 0;
   outSumBuyPriceLots = 0;
   outTotalBuyLots = 0;
   outSumSellPriceLots = 0;
   outTotalSellLots = 0;
   outLastBuyPrice = 0;
   outLastBuyLots = 0;
   outLastSellPrice = 0;
   outLastSellLots = 0;

   double lowestBuy  = DBL_MAX;
   double highestSell = 0;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double posLots  = PositionGetDouble(POSITION_VOLUME);
      long   posType  = PositionGetInteger(POSITION_TYPE);

      if (posType == POSITION_TYPE_BUY)
      {
         outBuyCount++;
         outSumBuyPriceLots += posPrice * posLots;
         outTotalBuyLots   += posLots;
         if (posPrice < lowestBuy)
         {
            lowestBuy = posPrice;
            outLastBuyPrice = posPrice;
            outLastBuyLots  = posLots;
         }
      }
      else if (posType == POSITION_TYPE_SELL)
      {
         outSellCount++;
         outSumSellPriceLots += posPrice * posLots;
         outTotalSellLots   += posLots;
         if (posPrice > highestSell)
         {
            highestSell = posPrice;
            outLastSellPrice = posPrice;
            outLastSellLots  = posLots;
         }
      }
   }
   return outBuyCount + outSellCount;
}

//+------------------------------------------------------------------+
//| Prop firm: daily loss & max drawdown check                        |
//+------------------------------------------------------------------+
static double   s_DailyStartBalance = 0;
static double   s_HighestEquity     = 0;
static datetime s_LastDay           = 0;

void InitPropFirmState()
{
   s_DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   s_HighestEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
   s_LastDay           = 0;
}

bool CanOpenNewOrder()
{
   if (!InpUseRiskLimits)
      return true;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if (today != s_LastDay)
   {
      s_LastDay = today;
      s_DailyStartBalance = balance;
      if (s_HighestEquity <= 0)
         s_HighestEquity = equity;
   }
   if (equity > s_HighestEquity)
      s_HighestEquity = equity;

   double refSize = (InpChallengeSize > 0) ? InpChallengeSize : balance;
   double dailyLossPct = (s_DailyStartBalance > 0)
      ? (s_DailyStartBalance - equity) / s_DailyStartBalance * 100.0
      : 0;
   double drawdownPct = (s_HighestEquity > 0)
      ? (s_HighestEquity - equity) / s_HighestEquity * 100.0
      : 0;

   if (dailyLossPct >= InpDailyLossPct)
   {
      static datetime lastWarn = 0;
      if (TimeCurrent() - lastWarn > 3600)
      {
         Print("MartingaleGrid: Daily loss limit reached ", DoubleToString(dailyLossPct, 2), "%");
         lastWarn = TimeCurrent();
      }
      return false;
   }
   if (drawdownPct >= InpMaxDrawdownPct)
   {
      static datetime lastWarn2 = 0;
      if (TimeCurrent() - lastWarn2 > 3600)
      {
         Print("MartingaleGrid: Max drawdown reached ", DoubleToString(drawdownPct, 2), "%");
         lastWarn2 = TimeCurrent();
      }
      return false;
   }

   int buyC, sellC;
   double d1, d2, d3, d4, lastBuyP, lastBuyL, lastSellP, lastSellL;
   int total = CountPositions(buyC, sellC, d1, d2, d3, d4, lastBuyP, lastBuyL, lastSellP, lastSellL);
   if (total >= InpMaxPositions)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Close all positions of one type (buy or sell)                     |
//+------------------------------------------------------------------+
void ClosePositions(bool closeBuy, bool closeSell)
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      if (posType == POSITION_TYPE_BUY  && closeBuy)
         g_Trade.PositionClose(ticket);
      if (posType == POSITION_TYPE_SELL && closeSell)
         g_Trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Reset high/low after closing a grid (no repaint: use current)     |
//+------------------------------------------------------------------+
void ResetAfterClose(bool resetBuy, bool resetSell)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if (resetBuy)
   {
      g_HighestPrice = bid;
      g_LowestPrice  = (g_LowestPrice < DBL_MAX) ? g_LowestPrice : bid;
   }
   if (resetSell)
   {
      g_LowestPrice  = bid;
      g_HighestPrice = (g_HighestPrice > 0) ? g_HighestPrice : bid;
   }
   if (resetBuy && resetSell)
   {
      g_HighestPrice = bid;
      g_LowestPrice  = bid;
   }
}

//+------------------------------------------------------------------+
//| Trailing stop: move SL for buy/sell positions                     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   if (!InpUseTrailing || InpTrailStepPoints <= 0)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      long   posType  = PositionGetInteger(POSITION_TYPE);

      double trailStartDist = InpTrailStartPoints * point;
      double trailStep      = InpTrailStepPoints * point;

      if (posType == POSITION_TYPE_BUY)
      {
         double profitDist = bid - openPrice;
         if (profitDist < trailStartDist)
            continue;
         double newSL = bid - trailStep;
         newSL = NormalizePrice(newSL);
         if (newSL <= openPrice)
            continue;
         if (sl <= 0 || newSL > sl)
            g_Trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
      }
      else if (posType == POSITION_TYPE_SELL)
      {
         double profitDist = openPrice - ask;
         if (profitDist < trailStartDist)
            continue;
         double newSL = ask + trailStep;
         newSL = NormalizePrice(newSL);
         if (newSL >= openPrice)
            continue;
         if (sl <= 0 || newSL < sl)
            g_Trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
      }
   }
}

//+------------------------------------------------------------------+
//| Draw BE / grid levels (optional)                                  |
//+------------------------------------------------------------------+
#define OBJ_PREFIX "MG_"

void DrawLevels(double avgBuy, double avgSell, double tpBuy, double tpSell)
{
   if (!InpShowLevels)
      return;
   datetime t0 = TimeCurrent();
   datetime t1 = t0 + 24 * 3600;

   if (avgBuy > 0)
   {
      ObjectCreate(0, OBJ_PREFIX "BE_Buy", OBJ_TREND, 0, t0, avgBuy, t1, avgBuy);
      ObjectSetInteger(0, OBJ_PREFIX "BE_Buy", OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, OBJ_PREFIX "BE_Buy", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, OBJ_PREFIX "BE_Buy", OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, OBJ_PREFIX "BE_Buy", OBJPROP_BACK, true);
   }
   else
      ObjectDelete(0, OBJ_PREFIX "BE_Buy");
   if (tpBuy > 0)
   {
      ObjectCreate(0, OBJ_PREFIX "TP_Buy", OBJ_TREND, 0, t0, tpBuy, t1, tpBuy);
      ObjectSetInteger(0, OBJ_PREFIX "TP_Buy", OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(0, OBJ_PREFIX "TP_Buy", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, OBJ_PREFIX "TP_Buy", OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, OBJ_PREFIX "TP_Buy", OBJPROP_BACK, true);
   }
   else
      ObjectDelete(0, OBJ_PREFIX "TP_Buy");
   if (avgSell > 0 && avgSell < DBL_MAX)
   {
      ObjectCreate(0, OBJ_PREFIX "BE_Sell", OBJ_TREND, 0, t0, avgSell, t1, avgSell);
      ObjectSetInteger(0, OBJ_PREFIX "BE_Sell", OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, OBJ_PREFIX "BE_Sell", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, OBJ_PREFIX "BE_Sell", OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, OBJ_PREFIX "BE_Sell", OBJPROP_BACK, true);
   }
   else
      ObjectDelete(0, OBJ_PREFIX "BE_Sell");
   if (tpSell > 0)
   {
      ObjectCreate(0, OBJ_PREFIX "TP_Sell", OBJ_TREND, 0, t0, tpSell, t1, tpSell);
      ObjectSetInteger(0, OBJ_PREFIX "TP_Sell", OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, OBJ_PREFIX "TP_Sell", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, OBJ_PREFIX "TP_Sell", OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, OBJ_PREFIX "TP_Sell", OBJPROP_BACK, true);
   }
   else
      ObjectDelete(0, OBJ_PREFIX "TP_Sell");
}

void DeleteLevelObjects()
{
   ObjectDelete(0, OBJ_PREFIX "BE_Buy");
   ObjectDelete(0, OBJ_PREFIX "TP_Buy");
   ObjectDelete(0, OBJ_PREFIX "BE_Sell");
   ObjectDelete(0, OBJ_PREFIX "TP_Sell");
}

//+------------------------------------------------------------------+
//| Main tick: no repaint (only current Bid and positions)            |
//+------------------------------------------------------------------+
void OnTick()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Update high/low (current price only, no future data)
   if (bid > g_HighestPrice)
      g_HighestPrice = bid;
   if (g_LowestPrice == DBL_MAX || bid < g_LowestPrice)
      g_LowestPrice = bid;

   int buyCount = 0, sellCount = 0;
   double sumBuyPL = 0, totalBuyLots = 0, sumSellPL = 0, totalSellLots = 0;
   double lastBuyPrice = 0, lastBuyLots = 0, lastSellPrice = 0, lastSellLots = 0;
   CountPositions(buyCount, sellCount,
                  sumBuyPL, totalBuyLots, sumSellPL, totalSellLots,
                  lastBuyPrice, lastBuyLots, lastSellPrice, lastSellLots);

   double avgBuyPrice  = (totalBuyLots  > 0) ? sumBuyPL  / totalBuyLots  : 0;
   double avgSellPrice  = (totalSellLots > 0) ? sumSellPL / totalSellLots : 0;
   double tpPriceBuy    = (avgBuyPrice  > 0) ? NormalizePrice(avgBuyPrice  + InpTPPoints * point) : 0;
   double tpPriceSell   = (avgSellPrice > 0) ? NormalizePrice(avgSellPrice - InpTPPoints * point) : 0;

   // Trailing stop
   ManageTrailingStop();

   // Close at TP (break-even + TP points) — then reset
   if (buyCount > 0 && avgBuyPrice > 0 && bid >= tpPriceBuy)
   {
      ClosePositions(true, false);
      ResetAfterClose(true, false);
   }
   if (sellCount > 0 && avgSellPrice > 0 && bid <= tpPriceSell)
   {
      ClosePositions(false, true);
      ResetAfterClose(false, true);
   }

   // Re-count after possible close
   CountPositions(buyCount, sellCount,
                  sumBuyPL, totalBuyLots, sumSellPL, totalSellLots,
                  lastBuyPrice, lastBuyLots, lastSellPrice, lastSellLots);
   avgBuyPrice  = (totalBuyLots  > 0) ? sumBuyPL  / totalBuyLots  : 0;
   avgSellPrice = (totalSellLots > 0) ? sumSellPL / totalSellLots : 0;
   tpPriceBuy   = (avgBuyPrice  > 0) ? NormalizePrice(avgBuyPrice  + InpTPPoints * point) : 0;
   tpPriceSell  = (avgSellPrice > 0) ? NormalizePrice(avgSellPrice - InpTPPoints * point) : 0;

   if (!CanOpenNewOrder() || !CheckSpread())
   {
      if (InpShowComment)
         UpdateComment(buyCount, sellCount, avgBuyPrice, avgSellPrice, tpPriceBuy, tpPriceSell,
                       totalBuyLots, totalSellLots, lastBuyPrice, lastSellPrice);
      if (InpShowLevels)
         DrawLevels(avgBuyPrice, avgSellPrice, tpPriceBuy, tpPriceSell);
      return;
   }

   double gridDist = InpGridPoints * point;

   // First buy: price dropped grid points from high (one entry only when buyCount==0)
   if (buyCount <= 0)
   {
      if (bid <= g_HighestPrice - gridDist)
      {
         double lots = NormalizeLots(InpStartLots);
         if (lots > 0 && g_Trade.Buy(lots, _Symbol, 0, 0, 0, "MG_Buy"))
            g_HighestPrice = bid;  // prevent duplicate first entry on same tick
      }
   }
   else
   {
      if (bid <= lastBuyPrice - gridDist)
      {
         double newLots = NormalizeLots(lastBuyLots * InpLotsMultiplier);
         if (newLots > 0 && newLots != lastBuyLots && g_Trade.Buy(newLots, _Symbol, 0, 0, 0, "MG_Buy"))
            g_HighestPrice = bid;  // prevent duplicate add on same tick
      }
   }

   // First sell: price rose grid points from low
   if (sellCount <= 0)
   {
      if (g_LowestPrice < DBL_MAX && bid >= g_LowestPrice + gridDist)
      {
         double lots = NormalizeLots(InpStartLots);
         if (lots > 0 && g_Trade.Sell(lots, _Symbol, 0, 0, 0, "MG_Sell"))
            g_LowestPrice = bid;
      }
   }
   else
   {
      if (bid >= lastSellPrice + gridDist)
      {
         double newLots = NormalizeLots(lastSellLots * InpLotsMultiplier);
         if (newLots > 0 && newLots != lastSellLots && g_Trade.Sell(newLots, _Symbol, 0, 0, 0, "MG_Sell"))
            g_LowestPrice = bid;
      }
   }

   if (InpShowComment)
      UpdateComment(buyCount, sellCount, avgBuyPrice, avgSellPrice, tpPriceBuy, tpPriceSell,
                    totalBuyLots, totalSellLots, lastBuyPrice, lastSellPrice);
   if (InpShowLevels)
      DrawLevels(avgBuyPrice, avgSellPrice, tpPriceBuy, tpPriceSell);
}

//+------------------------------------------------------------------+
//| Chart comment (clear visualization)                               |
//+------------------------------------------------------------------+
void UpdateComment(int buyCount, int sellCount,
                   double avgBuy, double avgSell, double tpBuy, double tpSell,
                   double totalBuyLots, double totalSellLots,
                   double lastBuyPrice, double lastSellPrice)
{
   string c = "=== Martingale Grid EA ===\n";
   c += StringFormat("Grid: %d pts | TP: %d pts | Lot x%.1f\n", InpGridPoints, InpTPPoints, InpLotsMultiplier);
   c += StringFormat("Buy positions: %d | Sell positions: %d\n", buyCount, sellCount);
   if (avgBuy > 0)
      c += StringFormat("Avg Buy: %s | TP Buy: %s | Lots: %.2f\n",
                        DoubleToString(avgBuy, _Digits), DoubleToString(tpBuy, _Digits), totalBuyLots);
   if (avgSell > 0)
      c += StringFormat("Avg Sell: %s | TP Sell: %s | Lots: %.2f\n",
                        DoubleToString(avgSell, _Digits), DoubleToString(tpSell, _Digits), totalSellLots);
   c += StringFormat("High: %s | Low: %s\n", DoubleToString(g_HighestPrice, _Digits), DoubleToString(g_LowestPrice, _Digits));
   c += StringFormat("Bid: %s\n", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits));
   Comment(c);
}

//+------------------------------------------------------------------+
