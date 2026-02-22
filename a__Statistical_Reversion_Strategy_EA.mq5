//+------------------------------------------------------------------+
//|                                 StatisticalReversionStrategy.mq5 |
//|                           Copyright 2025, Allan Munene Mutiiria. |
//|                                   https://t.me/Forex_Algo_Trader |
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
input int InpBaseTakeProfitPips = 100;      // Base Take Profit in pips
input int InpMagicNumber = 123456;          // Magic number for trades
input int InpMaxTradeHours = 48;            // Max trade duration in hours (0 to disable)

input group "=== Risk Management ==="
input bool InpUseTrailingStop = true;       // Enable trailing stop
input int InpTrailingStopPips = 30;         // Trailing stop distance in pips
input int InpTrailingStepPips = 10;         // Trailing step in pips
input bool InpUsePartialClose = true;       // Enable partial profit-taking
input double InpPartialClosePercent = 0.5;  // Percent of position to close at 50% TP

input group "=== Dashboard Parameters ==="
input bool InpShowDashboard = true;         // Show dashboard
input int InpDashboardX = 30;               // Dashboard X position
input int InpDashboardY = 30;               // Dashboard Y position
input int InpFontSize = 10;                 // Font size for dashboard text

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade trade;                                      //--- Trade object
datetime g_lastBarTime = 0;                        //--- Last processed bar time
double g_pointMultiplier = 1.0;                    //--- Point multiplier for broker digits
CChartObjectRectLabel* g_dashboardBg = NULL;       //--- Dashboard background object
CChartObjectRectLabel* g_headerBg = NULL;          //--- Header background object
CChartObjectLabel* g_titleLabel = NULL;            //--- Title label object
CChartObjectLabel* g_staticLabels[];               //--- Static labels array
CChartObjectLabel* g_valueLabels[];                //--- Value labels array
string g_staticNames[] = {
   "Symbol:", "Timeframe:", "Price:", "Skewness:", "Jarque-Bera:", "Kurtosis:",
   "Mean:", "Lower CI:", "Upper CI:", "Position:", "Lot Size:", "Profit:", "Duration:", "Signal:",
   "Equity:", "Balance:", "Free Margin:"
};                                                 //--- Static label names
int g_staticCount = ArraySize(g_staticNames);      //--- Number of static labels


//+------------------------------------------------------------------+
//| Create Dashboard                                                 |
//+------------------------------------------------------------------+
bool CreateDashboard() {
   if (!InpShowDashboard) return true;             //--- Return if dashboard disabled

   Print("Creating dashboard...");                 //--- Log dashboard creation

// Create main background rectangle
   if (g_dashboardBg == NULL) {                    //--- Check if background exists
      g_dashboardBg = new CChartObjectRectLabel(); //--- Create background object
      if (!g_dashboardBg.Create(0, "StatReversion_DashboardBg", 0, InpDashboardX, InpDashboardY + 30, 300, g_staticCount * (InpFontSize + 6) + 30)) { //--- Create dashboard background
         Print("Error creating dashboard background: ", GetLastError()); //--- Log error
         return false;                             //--- Return failure
      }
      g_dashboardBg.Color(clrDodgerBlue);          //--- Set border color
      g_dashboardBg.BackColor(clrNavy);            //--- Set background color
      g_dashboardBg.BorderType(BORDER_FLAT);       //--- Set border type
      g_dashboardBg.Corner(CORNER_LEFT_UPPER);     //--- Set corner alignment
   }

// Create header background
   if (g_headerBg == NULL) {                       //--- Check if header background exists
      g_headerBg = new CChartObjectRectLabel();   //--- Create header background object
      if (!g_headerBg.Create(0, "StatReversion_HeaderBg", 0, InpDashboardX, InpDashboardY, 300, InpFontSize + 20)) { //--- Create header background
         Print("Error creating header background: ", GetLastError()); //--- Log error
         return false;                             //--- Return failure
      }
      g_headerBg.Color(clrDodgerBlue);             //--- Set border color
      g_headerBg.BackColor(clrDarkBlue);           //--- Set background color
      g_headerBg.BorderType(BORDER_FLAT);          //--- Set border type
      g_headerBg.Corner(CORNER_LEFT_UPPER);        //--- Set corner alignment
   }

// Create title label (centered)
   if (g_titleLabel == NULL) {                     //--- Check if title label exists
      g_titleLabel = new CChartObjectLabel();     //--- Create title label object
      if (!g_titleLabel.Create(0, "StatReversion_Title", 0, InpDashboardX + 75, InpDashboardY + 5)) { //--- Create title label
         Print("Error creating title label: ", GetLastError()); //--- Log error
         return false;                             //--- Return failure
      }
      if (!g_titleLabel.Font("Arial Bold") || !g_titleLabel.FontSize(InpFontSize + 2) || !g_titleLabel.Description("Statistical Reversion")) { //--- Set title properties
         Print("Error setting title properties: ", GetLastError()); //--- Log error
         return false;                             //--- Return failure
      }
      g_titleLabel.Color(clrWhite);                //--- Set title color
   }

// Initialize static labels (left-aligned)
   ArrayFree(g_staticLabels);                      //--- Free static labels array
   ArrayResize(g_staticLabels, g_staticCount);     //--- Resize static labels array
   int y_offset = InpDashboardY + 30 + 10;         //--- Set y offset for labels
   for (int i = 0; i < g_staticCount; i++) {      //--- Iterate through static labels
      g_staticLabels[i] = new CChartObjectLabel(); //--- Create static label object
      string label_name = "StatReversion_Static_" + IntegerToString(i); //--- Generate label name
      if (!g_staticLabels[i].Create(0, label_name, 0, InpDashboardX + 10, y_offset)) { //--- Create static label
         Print("Error creating static label: ", label_name, ", Error: ", GetLastError()); //--- Log error
         DeleteDashboard();                       //--- Delete dashboard
         return false;                            //--- Return failure
      }
      if (!g_staticLabels[i].Font("Arial") || !g_staticLabels[i].FontSize(InpFontSize) || !g_staticLabels[i].Description(g_staticNames[i])) { //--- Set static label properties
         Print("Error setting static label properties: ", label_name, ", Error: ", GetLastError()); //--- Log error
         DeleteDashboard();                       //--- Delete dashboard
         return false;                            //--- Return failure
      }
      g_staticLabels[i].Color(clrLightGray);       //--- Set static label color
      y_offset += InpFontSize + 6;                 //--- Update y offset
   }

// Initialize value labels (right-aligned, starting at center)
   ArrayFree(g_valueLabels);                       //--- Free value labels array
   ArrayResize(g_valueLabels, g_staticCount);      //--- Resize value labels array
   y_offset = InpDashboardY + 30 + 10;             //--- Reset y offset for values
   for (int i = 0; i < g_staticCount; i++) {      //--- Iterate through value labels
      g_valueLabels[i] = new CChartObjectLabel();  //--- Create value label object
      string label_name = "StatReversion_Value_" + IntegerToString(i); //--- Generate label name
      if (!g_valueLabels[i].Create(0, label_name, 0, InpDashboardX + 150, y_offset)) { //--- Create value label
         Print("Error creating value label: ", label_name, ", Error: ", GetLastError()); //--- Log error
         DeleteDashboard();                       //--- Delete dashboard
         return false;                            //--- Return failure
      }
      if (!g_valueLabels[i].Font("Arial") || !g_valueLabels[i].FontSize(InpFontSize) || !g_valueLabels[i].Description("")) { //--- Set value label properties
         Print("Error setting value label properties: ", label_name, ", Error: ", GetLastError()); //--- Log error
         DeleteDashboard();                       //--- Delete dashboard
         return false;                            //--- Return failure
      }
      g_valueLabels[i].Color(clrCyan);             //--- Set value label color
      y_offset += InpFontSize + 6;                 //--- Update y offset
   }

   ChartRedraw();                                  //--- Redraw chart
   Print("Dashboard created successfully");        //--- Log success
   return true;                                    //--- Return true on success
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                 |
//+------------------------------------------------------------------+
void UpdateDashboard(double mean, double lower_ci, double upper_ci, double skewness, double jb_stat, double kurtosis,
                     double skew_buy, double skew_sell, string position, double lot_size, double profit, string duration, string signal) {
   if (!InpShowDashboard || ArraySize(g_valueLabels) != g_staticCount) { //--- Check if dashboard enabled and labels valid
      Print("Dashboard update skipped: Not initialized or invalid array size"); //--- Log skip
      return;                                      //--- Exit function
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE); //--- Get account balance
   double equity = AccountInfoDouble(ACCOUNT_EQUITY); //--- Get account equity
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE); //--- Get free margin
   double price = iClose(_Symbol, _Period, 0);     //--- Get current close price

   string values[] = {
      _Symbol, EnumToString(_Period), DoubleToString(price, _Digits),
      DoubleToString(skewness, 4), DoubleToString(jb_stat, 2), DoubleToString(kurtosis, 2),
      DoubleToString(mean, _Digits), DoubleToString(lower_ci, _Digits), DoubleToString(upper_ci, _Digits),
      position, DoubleToString(lot_size, 2), DoubleToString(profit, 2), duration, signal,
      DoubleToString(equity, 2), DoubleToString(balance, 2), DoubleToString(free_margin, 2)
   };                                              //--- Set value strings

   color value_colors[] = {
      clrWhite, clrWhite, (price > 0 ? clrCyan : clrGray), (skewness != 0 ? clrCyan : clrGray), (jb_stat != 0 ? clrCyan : clrGray), (kurtosis != 0 ? clrCyan : clrGray),
      (mean != 0 ? clrCyan : clrGray), (lower_ci != 0 ? clrCyan : clrGray), (upper_ci != 0 ? clrCyan : clrGray),
      clrWhite, clrWhite, (profit > 0 ? clrLimeGreen : profit < 0 ? clrRed : clrGray), clrWhite,
      (signal == "Buy" ? clrLimeGreen : signal == "Sell" ? clrRed : clrGray),
      (equity > balance ? clrLimeGreen : equity < balance ? clrRed : clrGray), clrWhite, clrWhite
   };                                              //--- Set value colors

   for (int i = 0; i < g_staticCount; i++) {      //--- Iterate through values
      if (g_valueLabels[i] != NULL) {             //--- Check if label exists
         g_valueLabels[i].Description(values[i]); //--- Set value description
         g_valueLabels[i].Color(value_colors[i]); //--- Set value color
      } else {                                    //--- Handle null label
         Print("Warning: Value label ", i, " is NULL"); //--- Log warning
      }
   }
   ChartRedraw();                                  //--- Redraw chart
   Print("Dashboard updated: Signal=", signal, ", Position=", position, ", Profit=", profit); //--- Log update
}

//+------------------------------------------------------------------+
//| Delete Dashboard                                                 |
//+------------------------------------------------------------------+
void DeleteDashboard() {
   if (g_dashboardBg != NULL) {                    //--- Check if background exists
      g_dashboardBg.Delete();                      //--- Delete background
      delete g_dashboardBg;                        //--- Free background memory
      g_dashboardBg = NULL;                        //--- Set background to null
      Print("Dashboard background deleted");       //--- Log deletion
   }
   if (g_headerBg != NULL) {                       //--- Check if header background exists
      g_headerBg.Delete();                         //--- Delete header background
      delete g_headerBg;                           //--- Free header background memory
      g_headerBg = NULL;                           //--- Set header background to null
      Print("Header background deleted");          //--- Log deletion
   }
   if (g_titleLabel != NULL) {                     //--- Check if title label exists
      g_titleLabel.Delete();                       //--- Delete title label
      delete g_titleLabel;                         //--- Free title label memory
      g_titleLabel = NULL;                         //--- Set title label to null
      Print("Title label deleted");                //--- Log deletion
   }
   for (int i = 0; i < ArraySize(g_staticLabels); i++) { //--- Iterate through static labels
      if (g_staticLabels[i] != NULL) {             //--- Check if label exists
         g_staticLabels[i].Delete();               //--- Delete static label
         delete g_staticLabels[i];                 //--- Free static label memory
         g_staticLabels[i] = NULL;                 //--- Set static label to null
      }
   }
   for (int i = 0; i < ArraySize(g_valueLabels); i++) { //--- Iterate through value labels
      if (g_valueLabels[i] != NULL) {              //--- Check if label exists
         g_valueLabels[i].Delete();                //--- Delete value label
         delete g_valueLabels[i];                  //--- Free value label memory
         g_valueLabels[i] = NULL;                  //--- Set value label to null
      }
   }
   ArrayFree(g_staticLabels);                      //--- Free static labels array
   ArrayFree(g_valueLabels);                       //--- Free value labels array
   ChartRedraw();                                  //--- Redraw chart
   Print("Dashboard labels cleared");              //--- Log clearance
}

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(InpMagicNumber);     //--- Set magic number
   trade.SetDeviationInPoints(10);                 //--- Set deviation in points
   trade.SetTypeFilling(ORDER_FILLING_FOK);        //--- Set filling type

// Adjust point multiplier for broker digits
   if (_Digits == 5 || _Digits == 3)               //--- Check broker digits
      g_pointMultiplier = 10.0;                    //--- Set multiplier for 5/3 digits
   else                                            //--- Default digits
      g_pointMultiplier = 1.0;                     //--- Set multiplier for others

// Validate inputs (use local variables)
   double confidenceLevel = InpConfidenceLevel;    //--- Copy confidence level
   if (InpConfidenceLevel < 0.90 || InpConfidenceLevel > 0.99) { //--- Check confidence level range
      Print("Warning: InpConfidenceLevel out of range (0.90-0.99). Using 0.95."); //--- Log warning
      confidenceLevel = 0.95;                      //--- Set default confidence level
   }
   double riskPercent = InpRiskPercent;            //--- Copy risk percent
   if (InpRiskPercent < 0 || InpRiskPercent > 10) { //--- Check risk percent range
      Print("Warning: InpRiskPercent out of range (0-10). Using 1.0."); //--- Log warning
      riskPercent = 1.0;                           //--- Set default risk percent
   }

// Initialize dashboard (non-critical)
   if (InpShowDashboard && !CreateDashboard()) {   //--- Check if dashboard creation failed
      Print("Failed to initialize dashboard, continuing without it"); //--- Log failure
   }

   Print("Statistical Reversion Strategy Initialized. Period: ", InpPeriod, ", Confidence: ", confidenceLevel * 100, "% on ", _Symbol, "/", Period()); //--- Log initialization
   return(INIT_SUCCEEDED);                         //--- Return success
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   DeleteDashboard();                              //--- Delete dashboard
   Print("Statistical Reversion Strategy Deinitialized. Reason: ", reason); //--- Log deinitialization
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick() {
// Check for new bar to avoid over-calculation
   if (iTime(_Symbol, _Period, 0) == g_lastBarTime) { //--- Check if new bar
      if (InpUseTrailingStop)                      //--- Check trailing stop enabled
         ManageTrailingStop();                     //--- Manage trailing stop
      if (InpUsePartialClose)                      //--- Check partial close enabled
         ManagePartialClose();                     //--- Manage partial close
      ManageTimeBasedExit();                       //--- Manage time-based exit
      UpdateDashboard(0, 0, 0, 0, 0, 0, 0, 0, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), GetSignalStatus(false, false)); //--- Update dashboard with no signal
      return;                                      //--- Exit function
   }
   g_lastBarTime = iTime(_Symbol, _Period, 0);     //--- Update last bar time

// Check market availability
   if (!SymbolInfoDouble(_Symbol, SYMBOL_BID) || !SymbolInfoDouble(_Symbol, SYMBOL_ASK)) { //--- Check market data
      Print("Error: Market data unavailable for ", _Symbol); //--- Log error
      UpdateDashboard(0, 0, 0, 0, 0, 0, 0, 0, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None"); //--- Update dashboard with no signal
      return;                                      //--- Exit function
   }

// Copy historical close prices
   double prices[];                                //--- Declare prices array
   ArraySetAsSeries(prices, true);                 //--- Set as series
   int copied = CopyClose(_Symbol, _Period, 1, InpPeriod, prices); //--- Copy close prices
   if (copied != InpPeriod) {                      //--- Check copy success
      Print("Error copying prices: ", copied, ", Error: ", GetLastError()); //--- Log error
      UpdateDashboard(0, 0, 0, 0, 0, 0, 0, 0, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None"); //--- Update dashboard with no signal
      return;                                      //--- Exit function
   }

// Calculate statistical moments
   double mean, variance, skewness, kurtosis;      //--- Declare statistical variables
   if (!MathMoments(prices, mean, variance, skewness, kurtosis, 0, InpPeriod)) { //--- Calculate moments
      Print("Error calculating moments: ", GetLastError()); //--- Log error
      UpdateDashboard(0, 0, 0, 0, 0, 0, 0, 0, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None"); //--- Update dashboard with no signal
      return;                                      //--- Exit function
   }

// Jarque-Bera test
   double n = (double)InpPeriod;                   //--- Set sample size
   double jb_stat = n * (skewness * skewness / 6.0 + (kurtosis * kurtosis) / 24.0); //--- Calculate JB statistic

// Log statistical values
   Print("Stats: Skewness=", DoubleToString(skewness, 4), ", JB=", DoubleToString(jb_stat, 2), ", Kurtosis=", DoubleToString(kurtosis, 2)); //--- Log stats

// Adaptive skewness thresholds
   double skew_buy_threshold = -0.3 - 0.05 * kurtosis; //--- Calculate buy skew threshold
   double skew_sell_threshold = 0.3 + 0.05 * kurtosis; //--- Calculate sell skew threshold

// Kurtosis filter
   if (kurtosis > InpKurtosisThreshold) {          //--- Check kurtosis threshold
      Print("Trade skipped: High kurtosis (", kurtosis, ") > ", InpKurtosisThreshold); //--- Log skip
      UpdateDashboard(mean, 0, 0, skewness, jb_stat, kurtosis, skew_buy_threshold, skew_sell_threshold, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None"); //--- Update dashboard with no signal
      return;                                      //--- Exit function
   }

   double std_dev = MathSqrt(variance);            //--- Calculate standard deviation

// Adaptive confidence interval
   double confidenceLevel = InpConfidenceLevel;    //--- Copy confidence level
   if (confidenceLevel < 0.90 || confidenceLevel > 0.99) //--- Validate confidence level
      confidenceLevel = 0.95;                      //--- Set default confidence level
   double z_score = NormalInverse(0.5 + confidenceLevel / 2.0); //--- Calculate z-score
   double ci_mult = z_score / MathSqrt(n);        //--- Calculate CI multiplier
   double upper_ci = mean + ci_mult * std_dev;    //--- Calculate upper CI
   double lower_ci = mean - ci_mult * std_dev;    //--- Calculate lower CI

// Current close price
   double current_price = iClose(_Symbol, _Period, 0); //--- Get current close price

// Higher timeframe confirmation (if enabled)
   bool htf_valid = true;                          //--- Initialize HTF validity
   if (InpHigherTF != 0) {                         //--- Check if HTF enabled
      double htf_prices[];                         //--- Declare HTF prices array
      ArraySetAsSeries(htf_prices, true);          //--- Set as series
      int htf_copied = CopyClose(_Symbol, InpHigherTF, 1, InpPeriod, htf_prices); //--- Copy HTF close prices
      if (htf_copied != InpPeriod) {               //--- Check HTF copy success
         Print("Error copying HTF prices: ", htf_copied, ", Error: ", GetLastError()); //--- Log error
         UpdateDashboard(mean, lower_ci, upper_ci, skewness, jb_stat, kurtosis, skew_buy_threshold, skew_sell_threshold, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None"); //--- Update dashboard with no signal
         return;                                   //--- Exit function
      }
      double htf_mean, htf_variance, htf_skewness, htf_kurtosis; //--- Declare HTF stats
      if (!MathMoments(htf_prices, htf_mean, htf_variance, htf_skewness, htf_kurtosis, 0, InpPeriod)) { //--- Calculate HTF moments
         Print("Error calculating HTF moments: ", GetLastError()); //--- Log error
         UpdateDashboard(mean, lower_ci, upper_ci, skewness, jb_stat, kurtosis, skew_buy_threshold, skew_sell_threshold, GetPositionStatus(), GetCurrentLotSize(), GetCurrentProfit(), GetPositionDuration(), "None"); //--- Update dashboard with no signal
         return;                                   //--- Exit function
      }
      htf_valid = (current_price <= htf_mean && skewness <= 0) || (current_price >= htf_mean && skewness >= 0); //--- Check HTF validity
      Print("HTF Check: Price=", DoubleToString(current_price, _Digits), ", HTF Mean=", DoubleToString(htf_mean, _Digits), ", Valid=", htf_valid); //--- Log HTF check
   }

// Generate signals
   bool buy_signal = htf_valid && (current_price < lower_ci) && (skewness < skew_buy_threshold) && (jb_stat > InpJBThreshold); //--- Check buy signal conditions
   bool sell_signal = htf_valid && (current_price > upper_ci) && (skewness > skew_sell_threshold) && (jb_stat > InpJBThreshold); //--- Check sell signal conditions

// Fallback signal
   if (!buy_signal && !sell_signal) {              //--- Check no primary signal
      buy_signal = htf_valid && (current_price < mean - 0.3 * std_dev); //--- Check fallback buy
      sell_signal = htf_valid && (current_price > mean + 0.3 * std_dev); //--- Check fallback sell
      Print("Fallback Signal: Buy=", buy_signal, ", Sell=", sell_signal); //--- Log fallback signals
   }

// Log signal status
   Print("Signal Check: Buy=", buy_signal, ", Sell=", sell_signal, ", Price=", DoubleToString(current_price, _Digits),
         ", LowerCI=", DoubleToString(lower_ci, _Digits), ", UpperCI=", DoubleToString(upper_ci, _Digits),
         ", Skew=", DoubleToString(skewness, 4), ", BuyThresh=", DoubleToString(skew_buy_threshold, 4),
         ", SellThresh=", DoubleToString(skew_sell_threshold, 4), ", JB=", DoubleToString(jb_stat, 2)); //--- Log signal details

// Position management: Close opposite positions
   if (HasPosition(POSITION_TYPE_BUY) && sell_signal) //--- Check buy position with sell signal
      CloseAllPositions(POSITION_TYPE_BUY);        //--- Close all buys
   if (HasPosition(POSITION_TYPE_SELL) && buy_signal) //--- Check sell position with buy signal
      CloseAllPositions(POSITION_TYPE_SELL);       //--- Close all sells

// Calculate lot size
   double lot_size = InpFixedLots;                 //--- Set default lot size
   double riskPercent = InpRiskPercent;            //--- Copy risk percent
   if (riskPercent > 0) {                          //--- Check if risk percent enabled
      double account_equity = AccountInfoDouble(ACCOUNT_EQUITY); //--- Get account equity
      double sl_points = InpBaseStopLossPips * g_pointMultiplier; //--- Calculate SL points
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE); //--- Get tick value
      if (tick_value == 0) {                       //--- Check invalid tick value
         Print("Error: Invalid tick value for ", _Symbol); //--- Log error
         return;                                   //--- Exit function
      }
      lot_size = NormalizeDouble((account_equity * riskPercent / 100.0) / (sl_points * tick_value), 2); //--- Calculate risk-based lot size
      lot_size = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(lot_size, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX))); //--- Clamp lot size
      Print("Lot Size: Equity=", account_equity, ", SL Points=", sl_points, ", Tick Value=", tick_value, ", Lot=", lot_size); //--- Log lot size calculation
   }

// Open new positions
   if (!HasPosition() && buy_signal) {             //--- Check no position and buy signal
      double sl = current_price - InpBaseStopLossPips * _Point * g_pointMultiplier; //--- Calculate SL
      double tp = current_price + InpBaseTakeProfitPips * _Point * g_pointMultiplier; //--- Calculate TP
      if (trade.Buy(lot_size, _Symbol, 0, sl, tp, "StatReversion Buy: Skew=" + DoubleToString(skewness, 4) + ", JB=" + DoubleToString(jb_stat, 2))) { //--- Open buy order
         Print("Buy order opened. Mean: ", DoubleToString(mean, 5), ", Current: ", DoubleToString(current_price, 5)); //--- Log buy open
      } else {                                     //--- Handle buy open failure
         Print("Buy order failed: ", GetLastError()); //--- Log error
      }
   } else if (!HasPosition() && sell_signal) {     //--- Check no position and sell signal
      double sl = current_price + InpBaseStopLossPips * _Point * g_pointMultiplier; //--- Calculate SL
      double tp = current_price - InpBaseTakeProfitPips * _Point * g_pointMultiplier; //--- Calculate TP
      if (trade.Sell(lot_size, _Symbol, 0, sl, tp, "StatReversion Sell: Skew=" + DoubleToString(skewness, 4) + ", JB=" + DoubleToString(jb_stat, 2))) { //--- Open sell order
         Print("Sell order opened. Mean: ", DoubleToString(mean, 5), ", Current: ", DoubleToString(current_price, 5)); //--- Log sell open
      } else {                                     //--- Handle sell open failure
         Print("Sell order failed: ", GetLastError()); //--- Log error
      }
   }

// Update dashboard
   UpdateDashboard(mean, lower_ci, upper_ci, skewness, jb_stat, kurtosis, skew_buy_threshold, skew_sell_threshold,
                   GetPositionStatus(), lot_size, GetCurrentProfit(), GetPositionDuration(), GetSignalStatus(buy_signal, sell_signal)); //--- Update dashboard with signals

// Manage trailing stop and partial close
   if (InpUseTrailingStop)                        //--- Check trailing stop enabled
      ManageTrailingStop();                       //--- Manage trailing stop
   if (InpUsePartialClose)                        //--- Check partial close enabled
      ManagePartialClose();                       //--- Manage partial close
   ManageTimeBasedExit();                         //--- Manage time-based exit
}

//+------------------------------------------------------------------+
//| Normal Inverse CDF Approximation                                 |
//+------------------------------------------------------------------+
double NormalInverse(double p) {
   double t = MathSqrt(-2.0 * MathLog(p < 0.5 ? p : 1.0 - p)); //--- Calculate t value
   double sign = (p < 0.5) ? -1.0 : 1.0;           //--- Determine sign
   return sign * (t - (2.515517 + 0.802853 * t + 0.010328 * t * t) /
                  (1.0 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t * t * t)); //--- Return approximated inverse CDF
}

//+------------------------------------------------------------------+
//| Get Position Status                                              |
//+------------------------------------------------------------------+
string GetPositionStatus() {
   if (HasPosition(POSITION_TYPE_BUY)) return "Buy"; //--- Return "Buy" if buy position open
   if (HasPosition(POSITION_TYPE_SELL)) return "Sell"; //--- Return "Sell" if sell position open
   return "None";                                 //--- Return "None" if no position
}

//+------------------------------------------------------------------+
//| Get Current Lot Size                                             |
//+------------------------------------------------------------------+
double GetCurrentLotSize() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) { //--- Iterate through positions
      if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) //--- Check symbol and magic
         return PositionGetDouble(POSITION_VOLUME); //--- Return position volume
   }
   return 0.0;                                    //--- Return 0 if no position
}

//+------------------------------------------------------------------+
//| Get Current Profit                                               |
//+------------------------------------------------------------------+
double GetCurrentProfit() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) { //--- Iterate through positions
      if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) //--- Check symbol and magic
         return PositionGetDouble(POSITION_PROFIT); //--- Return position profit
   }
   return 0.0;                                    //--- Return 0 if no position
}

//+------------------------------------------------------------------+
//| Get Position Duration                                            |
//+------------------------------------------------------------------+
string GetPositionDuration() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) { //--- Iterate through positions
      if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) { //--- Check symbol and magic
         datetime open_time = (datetime)PositionGetInteger(POSITION_TIME); //--- Get open time
         datetime current_time = TimeCurrent(); //--- Get current time
         int hours = (int)((current_time - open_time) / 3600); //--- Calculate hours
         return IntegerToString(hours) + "h"; //--- Return duration string
      }
   }
   return "0h";                                   //--- Return "0h" if no position
}

//+------------------------------------------------------------------+
//| Get Signal Status                                                |
//+------------------------------------------------------------------+
string GetSignalStatus(bool buy_signal, bool sell_signal) {
   if (buy_signal) return "Buy";                  //--- Return "Buy" if buy signal
   if (sell_signal) return "Sell";                //--- Return "Sell" if sell signal
   return "None";                                 //--- Return "None" if no signal
}

//+------------------------------------------------------------------+
//| Check for Open Position of Type                                  |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE pos_type) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) { //--- Iterate through positions
      if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetInteger(POSITION_TYPE) == pos_type) //--- Check details
         return true;                                //--- Return true if match
   }
   return false;                                  //--- Return false if no match
}

//+------------------------------------------------------------------+
//| Check for Any Open Position                                      |
//+------------------------------------------------------------------+
bool HasPosition() {
   return (HasPosition(POSITION_TYPE_BUY) || HasPosition(POSITION_TYPE_SELL)); //--- Check for buy or sell position
}

//+------------------------------------------------------------------+
//| Close All Positions of Type                                      |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE pos_type) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) { //--- Iterate through positions
      if (PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetInteger(POSITION_TYPE) == pos_type) { //--- Check details
         ulong ticket = PositionGetInteger(POSITION_TICKET); //--- Get ticket
         double profit = PositionGetDouble(POSITION_PROFIT); //--- Get profit
         trade.PositionClose(ticket);                //--- Close position
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop                                             |
//+------------------------------------------------------------------+
void ManageTrailingStop() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) { //--- Iterate through positions
      if (PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) //--- Check symbol and magic
         continue;                                   //--- Skip if not match

      ulong ticket = PositionGetInteger(POSITION_TICKET); //--- Get ticket
      double current_sl = PositionGetDouble(POSITION_SL); //--- Get current SL
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE); //--- Get position type
      double current_price = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK); //--- Get current price

      double trail_distance = InpTrailingStopPips * _Point * g_pointMultiplier; //--- Calculate trail distance
      double trail_step = InpTrailingStepPips * _Point * g_pointMultiplier; //--- Calculate trail step

      if (pos_type == POSITION_TYPE_BUY) {            //--- Check buy position
         double new_sl = current_price - trail_distance; //--- Calculate new SL
         if (new_sl > current_sl + trail_step || current_sl == 0) { //--- Check if update needed
            trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP)); //--- Modify position
         }
      } else if (pos_type == POSITION_TYPE_SELL) {    //--- Check sell position
         double new_sl = current_price + trail_distance; //--- Calculate new SL
         if (new_sl < current_sl - trail_step || current_sl == 0) { //--- Check if update needed
            trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP)); //--- Modify position
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Partial Close                                             |
//+------------------------------------------------------------------+
void ManagePartialClose() {
   for (int i = PositionsTotal() - 1; i >= 0; i--) { //--- Iterate through positions
      if (PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) //--- Check symbol and magic
         continue;                                   //--- Skip if not match

      ulong ticket = PositionGetInteger(POSITION_TICKET); //--- Get ticket
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN); //--- Get open price
      double tp = PositionGetDouble(POSITION_TP); //--- Get TP
      double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK); //--- Get current price
      double volume = PositionGetDouble(POSITION_VOLUME); //--- Get position volume

      double half_tp_distance = MathAbs(tp - open_price) * 0.5; //--- Calculate half TP distance
      bool should_close = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && current_price >= open_price + half_tp_distance) ||
                          (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && current_price <= open_price - half_tp_distance); //--- Check if at half TP

      if (should_close) {                             //--- Check if partial close needed
         double close_volume = NormalizeDouble(volume * InpPartialClosePercent, 2); //--- Calculate close volume
         if (close_volume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) { //--- Check minimum volume
            trade.PositionClosePartial(ticket, close_volume); //--- Close partial position
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Time-Based Exit                                           |
//+------------------------------------------------------------------+
void ManageTimeBasedExit() {
   if (InpMaxTradeHours == 0) return;              //--- Exit if no max duration

   for (int i = PositionsTotal() - 1; i >= 0; i--) { //--- Iterate through positions
      if (PositionGetSymbol(i) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) //--- Check symbol and magic
         continue;                                   //--- Skip if not match

      ulong ticket = PositionGetInteger(POSITION_TICKET); //--- Get ticket
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME); //--- Get open time
      datetime current_time = TimeCurrent();       //--- Get current time
      if ((current_time - open_time) / 3600 >= InpMaxTradeHours) { //--- Check if duration exceeded
         double profit = PositionGetDouble(POSITION_PROFIT); //--- Get profit
         trade.PositionClose(ticket);                 //--- Close position
      }
   }
}
//+------------------------------------------------------------------+
