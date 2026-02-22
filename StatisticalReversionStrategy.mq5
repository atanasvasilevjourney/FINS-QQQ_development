//+------------------------------------------------------------------+
//|                                 StatisticalReversionStrategy.mq5 |
//|                           Copyright 2025, Allan Munene Mutiiria. |
//|                    Part 39: Statistical Mean Reversion + Dashboard |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Allan Munene Mutiiria."
#property link      "https://t.me/Forex_Algo_Trader"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Math\Stat\Math.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Statistical Parameters ==="
input int InpPeriod = 50;                   // Period for statistical calculations
input double InpConfidenceLevel = 0.95;     // Confidence level for intervals (0.90-0.99)
input double InpJBThreshold = 2.0;          // Jarque-Bera threshold (lowered for more trades)
input double InpKurtosisThreshold = 5.0;    // Max excess kurtosis (relaxed)
input ENUM_TIMEFRAMES InpHigherTF = 0;      // Higher timeframe for confirmation (0 to disable)

input group "=== Trading Parameters ==="
input double InpRiskPercent = 1.0;          // Risk per trade (% of equity, 0 for fixed lots)
input double InpFixedLots = 0.01;           // Fixed lot size if InpRiskPercent = 0
input int InpBaseStopLossPips = 50;         // Base Stop Loss in pips
input int InpBaseTakeProfitPips = 100;       // Base Take Profit in pips
input int InpMagicNumber = 123456;          // Magic number for trades
input int InpMaxTradeHours = 48;             // Max trade duration in hours (0 to disable)

input group "=== Risk Management ==="
input bool InpUseTrailingStop = true;        // Enable trailing stop
input int InpTrailingStopPips = 30;          // Trailing stop distance in pips
input int InpTrailingStepPips = 10;          // Trailing step in pips
input bool InpUsePartialClose = true;        // Enable partial profit-taking
input double InpPartialClosePercent = 0.5;   // Percent of position to close at 50% TP

input group "=== Dashboard Parameters ==="
input bool InpShowDashboard = true;          // Show dashboard
input int InpDashboardX = 30;                 // Dashboard X position
input int InpDashboardY = 30;                 // Dashboard Y position
input int InpFontSize = 10;                  // Font size for dashboard text

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;
datetime g_lastBarTime = 0;
double g_pointMultiplier = 1.0;
CChartObjectRectLabel* g_dashboardBg = NULL;
CChartObjectRectLabel* g_headerBg = NULL;
CChartObjectLabel* g_titleLabel = NULL;
CChartObjectLabel* g_staticLabels[];
CChartObjectLabel* g_valueLabels[];
string g_staticNames[] = {
   "Symbol:", "Timeframe:", "Price:", "Skewness:", "Jarque-Bera:", "Kurtosis:",
   "Mean:", "Lower CI:", "Upper CI:", "Position:", "Lot Size:", "Profit:", "Duration:", "Signal:",
   "Equity:", "Balance:", "Free Margin:"
};
int g_staticCount = 17;

//+------------------------------------------------------------------+
//| Normal Inverse CDF Approximation                                 |
//+------------------------------------------------------------------+
double NormalInverse(double p) {
   double t = MathSqrt(-2.0 * MathLog(p < 0.5 ? p : 1.0 - p));
   double sign = (p < 0.5) ? -1.0 : 1.0;
   return sign * (t - (2.515517 + 0.802853 * t + 0.010328 * t * t) /
                  (1.0 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t * t * t));
}

//+------------------------------------------------------------------+
//| Check for Open Position of Type                                  |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE pos_type) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if (PositionGetInteger(POSITION_TYPE) == pos_type) return true;
   }
   return false;
}

bool HasPosition() {
   return (HasPosition(POSITION_TYPE_BUY) || HasPosition(POSITION_TYPE_SELL));
}

//+------------------------------------------------------------------+
//| Get Position Status                                              |
//+------------------------------------------------------------------+
string GetPositionStatus() {
   if (HasPosition(POSITION_TYPE_BUY)) return "Buy";
   if (HasPosition(POSITION_TYPE_SELL)) return "Sell";
   return "None";
}

//+------------------------------------------------------------------+
//| Get Current Lot Size                                             |
//+------------------------------------------------------------------+
double GetCurrentLotSize() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      return PositionGetDouble(POSITION_VOLUME);
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Get Current Profit                                               |
//+------------------------------------------------------------------+
double GetCurrentProfit() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      return PositionGetDouble(POSITION_PROFIT);
   }
   return 0.0;
}

//+------------------------------------------------------------------+
//| Get Position Duration                                            |
//+------------------------------------------------------------------+
string GetPositionDuration() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      int hours = (int)((TimeCurrent() - open_time) / 3600);
      return IntegerToString(hours) + "h";
   }
   return "0h";
}

//+------------------------------------------------------------------+
//| Get Signal Status                                                |
//+------------------------------------------------------------------+
string GetSignalStatus(bool buy_signal, bool sell_signal) {
   if (buy_signal) return "Buy";
   if (sell_signal) return "Sell";
   return "None";
}

//+------------------------------------------------------------------+
//| Create Dashboard                                                 |
//+------------------------------------------------------------------+
bool CreateDashboard() {
   if (!InpShowDashboard) return true;

   if (g_dashboardBg == NULL) {
      g_dashboardBg = new CChartObjectRectLabel();
      int h = g_staticCount * (InpFontSize + 6) + 30;
      if (!g_dashboardBg.Create(0, "StatReversion_DashboardBg", 0, InpDashboardX, InpDashboardY + 30, 300, h)) {
         Print("Error creating dashboard background: ", GetLastError());
         return false;
      }
      g_dashboardBg.Color(clrDodgerBlue);
      g_dashboardBg.BackColor(clrNavy);
      g_dashboardBg.BorderType(BORDER_FLAT);
      g_dashboardBg.Corner(CORNER_LEFT_UPPER);
   }

   if (g_headerBg == NULL) {
      g_headerBg = new CChartObjectRectLabel();
      if (!g_headerBg.Create(0, "StatReversion_HeaderBg", 0, InpDashboardX, InpDashboardY, 300, InpFontSize + 20)) {
         Print("Error creating header background: ", GetLastError());
         return false;
      }
      g_headerBg.Color(clrDodgerBlue);
      g_headerBg.BackColor(clrDarkBlue);
      g_headerBg.BorderType(BORDER_FLAT);
      g_headerBg.Corner(CORNER_LEFT_UPPER);
   }

   if (g_titleLabel == NULL) {
      g_titleLabel = new CChartObjectLabel();
      if (!g_titleLabel.Create(0, "StatReversion_Title", 0, InpDashboardX + 75, InpDashboardY + 5)) {
         Print("Error creating title label: ", GetLastError());
         return false;
      }
      g_titleLabel.Font("Arial Bold");
      g_titleLabel.FontSize(InpFontSize + 2);
      g_titleLabel.Description("Statistical Reversion");
      g_titleLabel.Color(clrWhite);
   }

   ArrayResize(g_staticLabels, g_staticCount);
   int y_offset = InpDashboardY + 30 + 10;
   for (int i = 0; i < g_staticCount; i++) {
      g_staticLabels[i] = new CChartObjectLabel();
      string label_name = "StatReversion_Static_" + IntegerToString(i);
      if (!g_staticLabels[i].Create(0, label_name, 0, InpDashboardX + 10, y_offset)) {
         DeleteDashboard();
         return false;
      }
      g_staticLabels[i].Font("Arial");
      g_staticLabels[i].FontSize(InpFontSize);
      g_staticLabels[i].Description(g_staticNames[i]);
      g_staticLabels[i].Color(clrLightGray);
      y_offset += InpFontSize + 6;
   }

   ArrayResize(g_valueLabels, g_staticCount);
   y_offset = InpDashboardY + 30 + 10;
   for (int i = 0; i < g_staticCount; i++) {
      g_valueLabels[i] = new CChartObjectLabel();
      string label_name = "StatReversion_Value_" + IntegerToString(i);
      if (!g_valueLabels[i].Create(0, label_name, 0, InpDashboardX + 150, y_offset)) {
         DeleteDashboard();
         return false;
      }
      g_valueLabels[i].Font("Arial");
      g_valueLabels[i].FontSize(InpFontSize);
      g_valueLabels[i].Description("");
      g_valueLabels[i].Color(clrCyan);
      y_offset += InpFontSize + 6;
   }

   ChartRedraw();
   return true;
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard(double mean, double lower_ci, double upper_ci, double skewness, double jb_stat, double kurtosis,
                     double skew_buy, double skew_sell, string position, double lot_size, double profit, string duration, string signal) {
   if (!InpShowDashboard || ArraySize(g_valueLabels) != g_staticCount) return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double price = iClose(_Symbol, _Period, 0);

   string values[] = {
      _Symbol, EnumToString(_Period), DoubleToString(price, _Digits),
      DoubleToString(skewness, 4), DoubleToString(jb_stat, 2), DoubleToString(kurtosis, 2),
      DoubleToString(mean, _Digits), DoubleToString(lower_ci, _Digits), DoubleToString(upper_ci, _Digits),
      position, DoubleToString(lot_size, 2), DoubleToString(profit, 2), duration, signal,
      DoubleToString(equity, 2), DoubleToString(balance, 2), DoubleToString(free_margin, 2)
   };

   color value_colors[] = {
      clrWhite, clrWhite, clrCyan, clrCyan, clrCyan, clrCyan,
      clrCyan, clrCyan, clrCyan, clrWhite, clrWhite,
      (profit > 0 ? clrLimeGreen : profit < 0 ? clrRed : clrGray), clrWhite,
      (signal == "Buy" ? clrLimeGreen : signal == "Sell" ? clrRed : clrGray),
      (equity > balance ? clrLimeGreen : equity < balance ? clrRed : clrGray), clrWhite, clrWhite
   };

   for (int i = 0; i < g_staticCount && i < ArraySize(values) && i < ArraySize(value_colors); i++) {
      if (g_valueLabels[i] != NULL) {
         g_valueLabels[i].Description(values[i]);
         g_valueLabels[i].Color(value_colors[i]);
      }
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Delete Dashboard                                                 |
//+------------------------------------------------------------------+
void DeleteDashboard() {
   if (g_dashboardBg != NULL) { g_dashboardBg.Delete(); delete g_dashboardBg; g_dashboardBg = NULL; }
   if (g_headerBg != NULL) { g_headerBg.Delete(); delete g_headerBg; g_headerBg = NULL; }
   if (g_titleLabel != NULL) { g_titleLabel.Delete(); delete g_titleLabel; g_titleLabel = NULL; }
   for (int i = 0; i < ArraySize(g_staticLabels); i++) {
      if (g_staticLabels[i] != NULL) { g_staticLabels[i].Delete(); delete g_staticLabels[i]; g_staticLabels[i] = NULL; }
   }
   for (int i = 0; i < ArraySize(g_valueLabels); i++) {
      if (g_valueLabels[i] != NULL) { g_valueLabels[i].Delete(); delete g_valueLabels[i]; g_valueLabels[i] = NULL; }
   }
   ArrayFree(g_staticLabels);
   ArrayFree(g_valueLabels);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Close All Positions of Type                                      |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE pos_type) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      if (PositionGetInteger(POSITION_TYPE) != pos_type) continue;
      trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop                                             |
//+------------------------------------------------------------------+
void ManageTrailingStop() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      double current_sl = PositionGetDouble(POSITION_SL);
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double current_price = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double trail_distance = InpTrailingStopPips * _Point * g_pointMultiplier;
      double trail_step = InpTrailingStepPips * _Point * g_pointMultiplier;
      double tp = PositionGetDouble(POSITION_TP);

      if (pos_type == POSITION_TYPE_BUY) {
         double new_sl = current_price - trail_distance;
         if (new_sl > current_sl + trail_step || current_sl == 0)
            trade.PositionModify(ticket, new_sl, tp);
      } else if (pos_type == POSITION_TYPE_SELL) {
         double new_sl = current_price + trail_distance;
         if (new_sl < current_sl - trail_step || current_sl == 0)
            trade.PositionModify(ticket, new_sl, tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Partial Close                                             |
//+------------------------------------------------------------------+
void ManagePartialClose() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp = PositionGetDouble(POSITION_TP);
      double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double volume = PositionGetDouble(POSITION_VOLUME);

      double half_tp_distance = MathAbs(tp - open_price) * 0.5;
      bool should_close = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && current_price >= open_price + half_tp_distance) ||
                          (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && current_price <= open_price - half_tp_distance);

      if (should_close) {
         double close_volume = NormalizeDouble(volume * InpPartialClosePercent, 2);
         double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if (close_volume >= minVol)
            trade.PositionClosePartial(ticket, close_volume);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Time-Based Exit                                           |
//+------------------------------------------------------------------+
void ManageTimeBasedExit() {
   if (InpMaxTradeHours == 0) return;
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      if ((TimeCurrent() - open_time) / 3600 >= InpMaxTradeHours)
         trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   if (_Digits == 5 || _Digits == 3)
      g_pointMultiplier = 10.0;
   else
      g_pointMultiplier = 1.0;

   if (InpShowDashboard && !CreateDashboard())
      Print("Failed to initialize dashboard, continuing without it");

   Print("Statistical Reversion Strategy Initialized. Period: ", InpPeriod, ", Confidence: ", InpConfidenceLevel * 100, "% on ", _Symbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   DeleteDashboard();
   Print("Statistical Reversion Strategy Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   if (InpUseTrailingStop) ManageTrailingStop();
   if (InpUsePartialClose) ManagePartialClose();
   ManageTimeBasedExit();

   if (iTime(_Symbol, _Period, 0) == g_lastBarTime) {
      UpdateDashboard(0, 0, 0, 0, 0, 0, 0, 0, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), GetSignalStatus(false, false));
      return;
   }
   g_lastBarTime = iTime(_Symbol, _Period, 0);

   if (!SymbolInfoDouble(_Symbol, SYMBOL_BID) || !SymbolInfoDouble(_Symbol, SYMBOL_ASK)) {
      UpdateDashboard(0, 0, 0, 0, 0, 0, 0, 0, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None");
      return;
   }

   double prices[];
   ArraySetAsSeries(prices, true);
   int copied = CopyClose(_Symbol, _Period, 1, InpPeriod, prices);
   if (copied != InpPeriod) {
      UpdateDashboard(0, 0, 0, 0, 0, 0, 0, 0, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None");
      return;
   }

   double mean, variance, skewness, kurtosis;
   if (!MathMoments(prices, mean, variance, skewness, kurtosis, 0, InpPeriod)) {
      UpdateDashboard(0, 0, 0, 0, 0, 0, 0, 0, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None");
      return;
   }

   double n = (double)InpPeriod;
   double jb_stat = n * (skewness * skewness / 6.0 + (kurtosis * kurtosis) / 24.0);

   double skew_buy_threshold = -0.3 - 0.05 * kurtosis;
   double skew_sell_threshold = 0.3 + 0.05 * kurtosis;

   if (kurtosis > InpKurtosisThreshold) {
      UpdateDashboard(mean, 0, 0, skewness, jb_stat, kurtosis, skew_buy_threshold, skew_sell_threshold, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None");
      return;
   }

   double std_dev = MathSqrt(variance);
   double confidenceLevel = MathMax(0.90, MathMin(0.99, InpConfidenceLevel));
   double z_score = NormalInverse(0.5 + confidenceLevel / 2.0);
   double ci_mult = z_score / MathSqrt(n);
   double upper_ci = mean + ci_mult * std_dev;
   double lower_ci = mean - ci_mult * std_dev;

   double current_price = iClose(_Symbol, _Period, 0);

   bool htf_valid = true;
   if (InpHigherTF != 0) {
      double htf_prices[];
      ArraySetAsSeries(htf_prices, true);
      int htf_copied = CopyClose(_Symbol, InpHigherTF, 1, InpPeriod, htf_prices);
      if (htf_copied != InpPeriod) {
         UpdateDashboard(mean, lower_ci, upper_ci, skewness, jb_stat, kurtosis, skew_buy_threshold, skew_sell_threshold, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None");
         return;
      }
      double htf_mean, htf_variance, htf_skewness, htf_kurtosis;
      if (!MathMoments(htf_prices, htf_mean, htf_variance, htf_skewness, htf_kurtosis, 0, InpPeriod)) {
         UpdateDashboard(mean, lower_ci, upper_ci, skewness, jb_stat, kurtosis, skew_buy_threshold, skew_sell_threshold, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None");
         return;
      }
      htf_valid = (current_price <= htf_mean && skewness <= 0) || (current_price >= htf_mean && skewness >= 0);
   }

   bool buy_signal = htf_valid && (current_price < lower_ci) && (skewness < skew_buy_threshold) && (jb_stat > InpJBThreshold);
   bool sell_signal = htf_valid && (current_price > upper_ci) && (skewness > skew_sell_threshold) && (jb_stat > InpJBThreshold);

   if (!buy_signal && !sell_signal) {
      buy_signal = htf_valid && (current_price < mean - 0.3 * std_dev);
      sell_signal = htf_valid && (current_price > mean + 0.3 * std_dev);
   }

   if (HasPosition(POSITION_TYPE_BUY) && sell_signal)
      CloseAllPositions(POSITION_TYPE_BUY);
   if (HasPosition(POSITION_TYPE_SELL) && buy_signal)
      CloseAllPositions(POSITION_TYPE_SELL);

   double lot_size = InpFixedLots;
   double riskPercent = MathMax(0, MathMin(10, InpRiskPercent));
   if (riskPercent > 0) {
      double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double sl_price_dist = InpBaseStopLossPips * _Point * g_pointMultiplier;
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if (tick_size > 0 && tick_value > 0) {
         double loss_per_lot = sl_price_dist * (tick_value / tick_size);
         if (loss_per_lot > 0)
            lot_size = (account_equity * riskPercent / 100.0) / loss_per_lot;
      }
      double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if (step > 0) lot_size = MathRound(lot_size / step) * step;
      lot_size = MathMax(minL, MathMin(maxL, lot_size));
   }

   if (!HasPosition() && buy_signal) {
      double sl = current_price - InpBaseStopLossPips * _Point * g_pointMultiplier;
      double tp = current_price + InpBaseTakeProfitPips * _Point * g_pointMultiplier;
      if (trade.Buy(lot_size, _Symbol, 0, sl, tp, "StatReversion Buy"))
         Print("Buy opened. Mean: ", mean, ", Price: ", current_price);
      else
         Print("Buy failed: ", GetLastError());
   } else if (!HasPosition() && sell_signal) {
      double sl = current_price + InpBaseStopLossPips * _Point * g_pointMultiplier;
      double tp = current_price - InpBaseTakeProfitPips * _Point * g_pointMultiplier;
      if (trade.Sell(lot_size, _Symbol, 0, sl, tp, "StatReversion Sell"))
         Print("Sell opened. Mean: ", mean, ", Price: ", current_price);
      else
         Print("Sell failed: ", GetLastError());
   }

   UpdateDashboard(mean, lower_ci, upper_ci, skewness, jb_stat, kurtosis, skew_buy_threshold, skew_sell_threshold,
                   GetPositionStatus(), lot_size, GetCurrentProfit(), GetPositionDuration(), GetSignalStatus(buy_signal, sell_signal));
}
