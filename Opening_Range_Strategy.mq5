//+------------------------------------------------------------------+
//|                                    Opening_Range_Strategy.mq5    |
//|                                                                  |
//|                           Opening Range Breakout Strategy       |
//+------------------------------------------------------------------+
#property copyright "Opening Range Strategy"
#property version   "1.02"
#property description "Opening Range Breakout - Prop firm rules, trailing stop, drawdown filters."

// Include necessary files
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Create trade object
CTrade trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Opening Range Settings ==="
input int    OR_StartHour = 16;        // Opening Range Start Hour (Broker Time)
input int    OR_StartMinute = 30;     // Opening Range Start Minute
input int    OR_EndHour = 16;          // Opening Range End Hour (Broker Time)
input int    OR_EndMinute = 35;       // Opening Range End Minute

input group "=== Strategy Settings ==="
enum ENUM_BIAS_MODE
{
    BIAS_OR_DIRECTION,    // Based on OR Bullish/Bearish
    BIAS_FIRST_BREAKOUT   // Based on First Close Outside Range
};
input ENUM_BIAS_MODE BiasMode = BIAS_OR_DIRECTION;     // Bias Determination Method
input int    MagicNumber = 123456;     // Magic Number (filter own positions/orders)
input int    StopTradingHour = 22;         // Stop Trading Hour (Broker Time)
input int    StopTradingMinute = 0;        // Stop Trading Minute
input int    ConsecutiveCandles = 1;       // Consecutive Candles Required for Entry (min 1)

input group "=== Display Settings ==="
input color  HighLineColor = clrRed;           // High Line Color
input color  LowLineColor = clrGreen;          // Low Line Color
input int    LineWidth = 2;                   // Line Width
input bool   ShowFormationPoints = true;      // Show High/Low Formation Points

input group "=== Signal Line Settings ==="
input color  SignalHighColor = clrOrange;     // Signal High Line Color
input color  SignalLowColor = clrBlue;        // Signal Low Line Color
input int    SignalLineWidth = 2;             // Signal Line Width

input group "=== Position Sizing ==="
enum ENUM_POSITION_SIZING
{
    FIXED_CONTRACTS,     // Fixed Contracts
    FIXED_RISK_USD,      // Fixed Risk USD
    RISK_PERCENT_ACCOUNT // Risk % of Account
};
input ENUM_POSITION_SIZING PositionSizingMode = FIXED_RISK_USD; // Position Sizing Mode
input int    PositionSize = 1;                // Position Size (Contracts)
input double RiskAmountUSD = 1000.0;          // Risk Amount (USD)
input double RiskPercentAccount = 2.0;        // Risk % of Account Balance

input group "=== Risk Management ==="
input int    ATRLength = 14;                  // ATR Length
input double ATRMultiplier = 3.0;             // ATR Multiplier for SL
input double TPMultiplier = 3.0;              // TP Multiplier (SL Size * X)
input bool   ClosePositionsAtEOD = true;      // Auto Close Positions at End of Day
input int    EODCloseHour = 15;               // EOD Close Hour (e.g. 15 = 3 PM)
input int    EODCloseMinute = 55;             // EOD Close Minute (e.g. 55 = 3:55 PM)

input group "=== Visualization ==="
input bool   ShowLongShortTool = true;        // Show Long Short Tool
input color  RiskColor = C'255,0,0,70';       // Risk Area Color
input color  RewardColor = C'0,255,0,70';     // Reward Area Color
input color  EntryLineColor = clrWhite;       // Entry Line Color
input color  SessionBgColor = C'0,0,255,240'; // Session Background Color

input group "=== Prop Firm Challenge ==="
input bool   EnableChallengeRules = false;   // Enable prop firm rules
input double ChallengeAccountSize = 25000.0; // Challenge account size ($)
input double Phase1ProfitTarget = 8.0;       // Phase 1 profit target (%)
input double Phase2ProfitTarget = 5.0;       // Phase 2 profit target (%)
input double DailyLossLimit = 5.0;           // Daily loss limit (%)
input double MaxLossLimit = 10.0;            // Max drawdown / loss limit (%)
input int    MinTradingDays = 5;               // Min trading days (info)
input bool   Phase1Complete = false;         // Phase 1 done (manual toggle)

input group "=== Trailing Stop ==="
input bool   UseTrailingStop = true;         // Use trailing stop
input double TrailingStartATR = 1.0;          // Start trailing after profit (ATR mult)
input double TrailingStepATR = 0.5;          // Trail step (ATR mult; move SL every X ATR)

input group "=== Drawdown & Filters ==="
input double MaxEquityDrawdownPercent = 6.0; // Max equity drawdown % from peak (0=off)
input int    ConsecutiveLossesLimit = 2;     // Pause new trades after N losses in a row (0=off)
input int    MaxSpreadPoints = 40;           // Max spread to allow new trades (0=off)
input int    MaxTradesPerDay = 2;            // Max new trades per day (1-2 helps limit DD)

//+------------------------------------------------------------------+
//| Global Variables for Session & Range Tracking                   |
//+------------------------------------------------------------------+
// Session state variables
bool g_sessionActive = false;
bool g_waitingForSignal = false;
bool g_signalFound = false;

// Opening range variables
double g_sessionHigh = 0.0;
double g_sessionLow = 0.0;
double g_sessionOpen = 0.0;
double g_sessionClose = 0.0;
bool g_orBullish = false;

// Bar tracking for exact formation points
datetime g_sessionHighTime = 0;
datetime g_sessionLowTime = 0;
int g_sessionHighBar = 0;
int g_sessionLowBar = 0;

// Signal tracking variables
double g_currentSignalLevel = 0.0;
bool g_signalIsHigh = false;
datetime g_signalTime = 0;

// Strategy state variables
bool g_longSignalActive = false;
bool g_shortSignalActive = false;
double g_longEntryLevel = 0.0;
double g_shortEntryLevel = 0.0;

// New bias mode variables
bool g_biasFound = false;
bool g_longBias = false;  // true = long bias, false = short bias
datetime g_biasTime = 0;

// Consecutive candles tracking
int g_consecutiveLongCloses = 0;  // Count of consecutive closes above signal level
int g_consecutiveShortCloses = 0; // Count of consecutive closes below signal level

// Drawing object names (for management)
string g_orHighLineName = "";
string g_orLowLineName = "";
string g_signalLineName = "";

// Long Short Tool variables
struct TradeVisualization
{
    string entryLineName;
    string riskBoxName;
    string rewardBoxName;
    datetime entryTime;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    int entryDay;
};

TradeVisualization g_currentTrade;
string g_tradeVisualizations[];  // Array of active visualization object names
datetime g_tradeEntryTimes[];    // Array of entry times for cleanup
int g_tradeEntryDays[];         // Array of entry days for cleanup

// Daily reset tracking
datetime g_lastProcessedDate = 0;

// Prop firm & drawdown
double   g_InitialBalance = 0;
double   g_DailyStartBalance = 0;
double   g_HighestBalance = 0;
double   g_HighestEquity = 0;
bool     g_DailyLimitBreached = false;
bool     g_MaxLimitBreached = false;
bool     g_Phase1Complete = false;
int      g_TradesToday = 0;
int      g_ConsecutiveLosses = 0;
bool     g_HadPositionLastTick = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== Opening Range Strategy Starting ===");

    Print("Opening Range EA Configuration:");
    Print("  OR Session: ", StringFormat("%d:%02d", OR_StartHour, OR_StartMinute), " - ",
          StringFormat("%d:%02d", OR_EndHour, OR_EndMinute), " (Broker Time)");
    Print("  Stop Trading: ", StringFormat("%d:%02d", StopTradingHour, StopTradingMinute), " (Broker Time)");
    Print("  Bias Mode: ", (BiasMode == BIAS_OR_DIRECTION ? "OR Direction" : "First Breakout"));

    // Configure CTrade for market execution
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(30);
    trade.SetTypeFilling(ORDER_FILLING_RETURN);

    if(EnableChallengeRules)
    {
        g_InitialBalance = ChallengeAccountSize;
        g_DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_HighestBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_Phase1Complete = Phase1Complete;
        Print("OR: Challenge rules ON | Account $", ChallengeAccountSize,
              " | Phase1 ", Phase1ProfitTarget, "% | Daily loss ", DailyLossLimit, "%");
    }
    g_HighestEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    g_HadPositionLastTick = false;

    if(EnableChallengeRules && (ChallengeAccountSize <= 0 || DailyLossLimit <= 0 || MaxLossLimit <= 0))
    {
        Print("OR: Invalid challenge inputs (account size, daily/max loss must be > 0)");
        return(INIT_PARAMETERS_INCORRECT);
    }
    if(MaxTradesPerDay > 0 && (MaxTradesPerDay < 1 || MaxTradesPerDay > 10))
    {
        Print("OR: MaxTradesPerDay should be 1-10 (or 0 for no limit)");
        return(INIT_PARAMETERS_INCORRECT);
    }

    // Reset all variables
    ResetDailyVariables();

    Print("=== Opening Range Strategy Ready ===");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up all drawing objects
    CleanupDrawingObjects();
}

//+------------------------------------------------------------------+
//| Check if we have an open position (this EA, this symbol)         |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!posInfo.SelectByIndex(i))
            continue;
        if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber)
            continue;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Prop firm: check daily and max loss limits                      |
//+------------------------------------------------------------------+
void CheckChallengeLimits()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(balance > g_HighestBalance)
        g_HighestBalance = balance;

    double dailyLoss = g_DailyStartBalance - equity;
    double dailyLossPct = (g_DailyStartBalance > 0) ? (dailyLoss / g_DailyStartBalance) * 100.0 : 0;
    if(dailyLossPct >= DailyLossLimit)
    {
        if(!g_DailyLimitBreached)
        {
            g_DailyLimitBreached = true;
            Print("OR CHALLENGE: Daily loss limit reached ", DoubleToString(dailyLossPct, 2), "%");
        }
    }

    double totalLoss = g_InitialBalance - equity;
    double maxLossPct = (g_InitialBalance > 0) ? (totalLoss / g_InitialBalance) * 100.0 : 0;
    if(maxLossPct >= MaxLossLimit)
    {
        if(!g_MaxLimitBreached)
        {
            g_MaxLimitBreached = true;
            Print("OR CHALLENGE: Max loss limit reached ", DoubleToString(maxLossPct, 2), "%");
        }
    }

    double profitPct = (g_InitialBalance > 0) ? ((equity - g_InitialBalance) / g_InitialBalance) * 100.0 : 0;
    if(!g_Phase1Complete && profitPct >= Phase1ProfitTarget)
    {
        g_Phase1Complete = true;
        Print("OR CHALLENGE: Phase 1 target reached ", DoubleToString(profitPct, 2), "%");
    }
}

//+------------------------------------------------------------------+
//| Prop firm: reset daily tracking on new day                      |
//+------------------------------------------------------------------+
void ResetDailyChallengeTracking()
{
    g_DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_DailyLimitBreached = false;
    g_TradesToday = 0;
}

//+------------------------------------------------------------------+
//| Can we place a new order? (prop firm + drawdown + filters)      |
//+------------------------------------------------------------------+
bool CanPlaceNewOrder()
{
    if(EnableChallengeRules && (g_DailyLimitBreached || g_MaxLimitBreached))
        return false;

    if(MaxTradesPerDay > 0 && g_TradesToday >= MaxTradesPerDay)
        return false;

    if(ConsecutiveLossesLimit > 0 && g_ConsecutiveLosses >= ConsecutiveLossesLimit)
        return false;

    if(MaxEquityDrawdownPercent > 0 && g_HighestEquity > 0)
    {
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double ddPct = (g_HighestEquity - equity) / g_HighestEquity * 100.0;
        if(ddPct >= MaxEquityDrawdownPercent)
            return false;
    }

    if(MaxSpreadPoints > 0)
    {
        long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        if(spread > (long)MaxSpreadPoints)
            return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| After position closed: check last deal to update consecutive losses |
//+------------------------------------------------------------------+
void UpdateConsecutiveLossesFromHistory()
{
    if(ConsecutiveLossesLimit <= 0)
        return;
    datetime from = TimeCurrent() - 86400;
    if(!HistorySelect(from, TimeCurrent()))
        return;
    for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0)
            continue;
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
            continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
            continue;
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;
        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
        if(profit < 0)
            g_ConsecutiveLosses++;
        else
            g_ConsecutiveLosses = 0;
        return;
    }
}

//+------------------------------------------------------------------+
//| Trailing stop: move SL in profit direction by ATR steps          |
//+------------------------------------------------------------------+
void ProcessTrailingStop()
{
    if(!UseTrailingStop)
        return;
    double atr = GetATRValue();
    if(atr <= 0)
        return;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!posInfo.SelectByIndex(i))
            continue;
        if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber)
            continue;

        ulong ticket = posInfo.Ticket();
        double openPrice = posInfo.PriceOpen();
        double currentSL = posInfo.StopLoss();
        double currentTP = posInfo.TakeProfit();

        if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
            double profitDist = bid - openPrice;
            if(profitDist < TrailingStartATR * atr)
                continue;
            double newSL = bid - TrailingStepATR * atr;
            newSL = NormalizeDouble(newSL, _Digits);
            if(newSL <= openPrice)
                continue;
            if(currentSL > 0 && newSL <= currentSL)
                continue;
            if(newSL >= bid - _Point)
                continue;
            if(currentTP > 0 && newSL >= currentTP)
                continue;
            trade.PositionModify(ticket, newSL, currentTP);
        }
        else
        {
            double profitDist = openPrice - ask;
            if(profitDist < TrailingStartATR * atr)
                continue;
            double newSL = ask + TrailingStepATR * atr;
            newSL = NormalizeDouble(newSL, _Digits);
            if(newSL >= openPrice)
                continue;
            if(currentSL > 0 && newSL >= currentSL)
                continue;
            if(newSL <= ask + _Point)
                continue;
            if(currentTP > 0 && newSL <= currentTP)
                continue;
            trade.PositionModify(ticket, newSL, currentTP);
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Update equity peak for drawdown filter
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity > g_HighestEquity)
        g_HighestEquity = equity;

    if(EnableChallengeRules)
    {
        CheckChallengeLimits();
        if(g_DailyLimitBreached || g_MaxLimitBreached)
        {
            // No new trades; still manage trailing and EOD close
            MonitorPositions();
            UpdateTradeVisualization();
            g_HadPositionLastTick = HasOpenPosition();
            return;
        }
    }

    // Track consecutive losses when position just closed
    bool hasPos = HasOpenPosition();
    if(g_HadPositionLastTick && !hasPos)
        UpdateConsecutiveLossesFromHistory();
    g_HadPositionLastTick = hasPos;

    // Check for new day and reset if needed
    CheckDailyReset();

    // Check if we're in the opening range session
    bool inSession = IsInOpeningRangeSession();

    // Handle opening range logic
    ProcessOpeningRange(inSession);

    // Handle bias detection (if using first breakout mode)
    if(BiasMode == BIAS_FIRST_BREAKOUT)
        ProcessBiasDetection();

    // Handle signal detection
    ProcessSignalDetection();

    // Check for opening range line breaks
    CheckLineBreaks();

    // Process trading logic
    ProcessTradingLogic();

    // Monitor existing positions
    MonitorPositions();

    // Update Long Short Tool visualization
    UpdateTradeVisualization();

    // Update session background
    UpdateSessionBackground(inSession);
}

//+------------------------------------------------------------------+
//| Check if current time is within opening range session           |
//+------------------------------------------------------------------+
bool IsInOpeningRangeSession()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    // Calculate current time in minutes since midnight
    int currentMinutes = dt.hour * 60 + dt.min;

    // Calculate session start and end in minutes since midnight
    int startMinutes = OR_StartHour * 60 + OR_StartMinute;
    int endMinutes = OR_EndHour * 60 + OR_EndMinute;

    // Check if current time is within the session window
    return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
}



//+------------------------------------------------------------------+
//| Process Opening Range Logic                                      |
//+------------------------------------------------------------------+
void ProcessOpeningRange(bool inSession)
{
    double currentHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);
    double currentLow = iLow(_Symbol, PERIOD_CURRENT, 0);
    double currentOpen = iOpen(_Symbol, PERIOD_CURRENT, 0);
    double currentClose = iClose(_Symbol, PERIOD_CURRENT, 0);
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    // Start of session logic
    if(inSession && !g_sessionActive)
    {
        g_sessionHigh = currentHigh;
        g_sessionLow = currentLow;
        g_sessionOpen = currentOpen;
        g_sessionActive = true;
        g_waitingForSignal = false;
        g_signalFound = false;
        g_sessionHighTime = currentTime;
        g_sessionLowTime = currentTime;
        g_sessionHighBar = iBars(_Symbol, PERIOD_CURRENT) - 1;
        g_sessionLowBar = iBars(_Symbol, PERIOD_CURRENT) - 1;

        Print("Opening Range session started - High: ", g_sessionHigh, " Low: ", g_sessionLow);
    }

    // During session - track new highs and lows with exact bar indices
    if(inSession && g_sessionActive)
    {
        // Track new highs with exact timing and bar index
        if(currentHigh > g_sessionHigh)
        {
            g_sessionHigh = currentHigh;
            g_sessionHighTime = currentTime;
            g_sessionHighBar = iBars(_Symbol, PERIOD_CURRENT) - 1; // Current bar index

            // Show formation point if enabled
            if(ShowFormationPoints)
            {
                string markerName = "OR_High_Formation_" + TimeToString(currentTime, TIME_SECONDS);
                ObjectCreate(0, markerName, OBJ_ARROW_UP, 0, currentTime, currentHigh);
                ObjectSetInteger(0, markerName, OBJPROP_COLOR, HighLineColor);
                ObjectSetInteger(0, markerName, OBJPROP_WIDTH, 2);
            }
        }

        // Track new lows with exact timing and bar index
        if(currentLow < g_sessionLow)
        {
            g_sessionLow = currentLow;
            g_sessionLowTime = currentTime;
            g_sessionLowBar = iBars(_Symbol, PERIOD_CURRENT) - 1; // Current bar index

            // Show formation point if enabled
            if(ShowFormationPoints)
            {
                string markerName = "OR_Low_Formation_" + TimeToString(currentTime, TIME_SECONDS);
                ObjectCreate(0, markerName, OBJ_ARROW_DOWN, 0, currentTime, currentLow);
                ObjectSetInteger(0, markerName, OBJPROP_COLOR, LowLineColor);
                ObjectSetInteger(0, markerName, OBJPROP_WIDTH, 2);
            }
        }

        g_sessionClose = currentClose;
    }

    // End of session logic
    if(!inSession && g_sessionActive)
    {
        g_sessionActive = false;

        if(BiasMode == BIAS_OR_DIRECTION)
        {
            // Traditional method: Determine if opening range was bullish or bearish
            g_orBullish = (g_sessionClose > g_sessionOpen);
            g_waitingForSignal = true;

            Print("Opening Range ended - Bullish: ", g_orBullish, " High: ", g_sessionHigh, " Low: ", g_sessionLow);
        }
        else
        {
            // First breakout method: Wait for first close outside range to determine bias
            g_waitingForSignal = true;
            g_biasFound = false;

            Print("Opening Range ended - Waiting for first breakout. High: ", g_sessionHigh, " Low: ", g_sessionLow);
        }

        // Create opening range lines
        CreateOpeningRangeLines();
    }
}

//+------------------------------------------------------------------+
//| Process Signal Detection Logic                                   |
//+------------------------------------------------------------------+
void ProcessSignalDetection()
{
    if(!g_waitingForSignal || g_signalFound)
        return;

    // For first breakout mode, need to wait for bias first
    if(BiasMode == BIAS_FIRST_BREAKOUT && !g_biasFound)
        return;

    // Check the LAST COMPLETED candle (bar 1) instead of current developing candle (bar 0)
    double lastOpen = iOpen(_Symbol, PERIOD_CURRENT, 1);
    double lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);
    double lastHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double lastLow = iLow(_Symbol, PERIOD_CURRENT, 1);
    datetime lastTime = iTime(_Symbol, PERIOD_CURRENT, 1);

    bool isBullishCandle = (lastClose > lastOpen);
    bool isBearishCandle = (lastClose < lastOpen);

    // Debug output - only print once per new bar
    static datetime lastPrintTime = 0;
    if(g_waitingForSignal && lastTime != lastPrintTime)
    {
        if(BiasMode == BIAS_OR_DIRECTION)
        {
            Print("Checking completed candle for signal - OR Bullish: ", g_orBullish,
                  " Bar time: ", TimeToString(lastTime),
                  " Open: ", lastOpen, " Close: ", lastClose, " High: ", lastHigh, " Low: ", lastLow,
                  " Bullish: ", isBullishCandle, " Bearish: ", isBearishCandle);
        }
        else
        {
            Print("Checking completed candle for signal - Bias: ", (g_longBias ? "LONG" : "SHORT"),
                  " Bar time: ", TimeToString(lastTime),
                  " Open: ", lastOpen, " Close: ", lastClose, " High: ", lastHigh, " Low: ", lastLow,
                  " Bullish: ", isBullishCandle, " Bearish: ", isBearishCandle);
        }
        lastPrintTime = lastTime;
    }

    // Signal detection logic - use completed candle data
    bool shouldCreateSignal = false;

    if(BiasMode == BIAS_OR_DIRECTION)
    {
        // Original logic
        shouldCreateSignal = (g_orBullish && isBearishCandle) || (!g_orBullish && isBullishCandle);
    }
    else
    {
        // First breakout mode - opposite signal after bias determined
        shouldCreateSignal = (g_longBias && isBearishCandle) || (!g_longBias && isBullishCandle);
    }

    if(shouldCreateSignal)
    {
        bool createLongSignal = (BiasMode == BIAS_OR_DIRECTION) ? (!g_orBullish && isBullishCandle) : (!g_longBias && isBullishCandle);

        if(createLongSignal)
        {
            // Create signal for LONG trades (bearish OR + bullish candle, OR long bias + bullish candle)
            g_signalFound = true;
            g_waitingForSignal = false;
            g_currentSignalLevel = lastLow;   // Use completed candle's low
            g_signalIsHigh = false;
            g_signalTime = lastTime;          // Use completed candle's time
            g_longSignalActive = true;
            g_longEntryLevel = lastLow;       // Use completed candle's low

            // Create signal line
            CreateSignalLine(g_currentSignalLevel, false);

            Print("*** BULLISH SIGNAL FOUND ***");
            Print("  - Signal level (LOW of bullish candle): ", g_currentSignalLevel);
            Print("  - Signal time: ", TimeToString(g_signalTime));
            Print("  - Candle OHLC: O=", lastOpen, " H=", lastHigh, " L=", lastLow, " C=", lastClose);
            Print("  - Waiting for breakout BELOW: ", g_currentSignalLevel);
        }
        else
        {
            // Create signal for SHORT trades (bullish OR + bearish candle, OR short bias + bearish candle)
            g_signalFound = true;
            g_waitingForSignal = false;
            g_currentSignalLevel = lastHigh;  // Use completed candle's high
            g_signalIsHigh = true;
            g_signalTime = lastTime;          // Use completed candle's time
            g_shortSignalActive = true;
            g_shortEntryLevel = lastHigh;     // Use completed candle's high

            // Create signal line
            CreateSignalLine(g_currentSignalLevel, true);

            Print("*** BEARISH SIGNAL FOUND ***");
            Print("  - Signal level (HIGH of bearish candle): ", g_currentSignalLevel);
            Print("  - Signal time: ", TimeToString(g_signalTime));
            Print("  - Candle OHLC: O=", lastOpen, " H=", lastHigh, " L=", lastLow, " C=", lastClose);
        }
    }
}

//+------------------------------------------------------------------+
//| Create Opening Range Lines                                       |
//+------------------------------------------------------------------+
void CreateOpeningRangeLines()
{
    // Clean up existing lines
    if(g_orHighLineName != "")
        ObjectDelete(0, g_orHighLineName);
    if(g_orLowLineName != "")
        ObjectDelete(0, g_orLowLineName);

    // Generate unique names for new lines
    string timeStr = TimeToString(TimeCurrent(), TIME_SECONDS);
    g_orHighLineName = "OR_High_" + timeStr;
    g_orLowLineName = "OR_Low_" + timeStr;

    // Calculate end of day time (4:00 PM EST)
    datetime endOfDayTime = GetEndOfDayTime();

    // Create high line from exact formation time, extending right until broken or EOD
    ObjectCreate(0, g_orHighLineName, OBJ_TREND, 0, g_sessionHighTime, g_sessionHigh, endOfDayTime, g_sessionHigh);
    ObjectSetInteger(0, g_orHighLineName, OBJPROP_COLOR, HighLineColor);
    ObjectSetInteger(0, g_orHighLineName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, g_orHighLineName, OBJPROP_WIDTH, LineWidth);
    ObjectSetInteger(0, g_orHighLineName, OBJPROP_RAY_RIGHT, false); // Don't extend beyond EOD initially

    // Create low line from exact formation time, extending right until broken or EOD
    ObjectCreate(0, g_orLowLineName, OBJ_TREND, 0, g_sessionLowTime, g_sessionLow, endOfDayTime, g_sessionLow);
    ObjectSetInteger(0, g_orLowLineName, OBJPROP_COLOR, LowLineColor);
    ObjectSetInteger(0, g_orLowLineName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, g_orLowLineName, OBJPROP_WIDTH, LineWidth);
    ObjectSetInteger(0, g_orLowLineName, OBJPROP_RAY_RIGHT, false); // Don't extend beyond EOD initially

    Print("OR Lines created - High from: ", TimeToString(g_sessionHighTime), " Low from: ", TimeToString(g_sessionLowTime));
}

//+------------------------------------------------------------------+
//| Create Signal Line                                               |
//+------------------------------------------------------------------+
void CreateSignalLine(double level, bool isHigh)
{
    // Clean up existing signal line
    if(g_signalLineName != "")
        ObjectDelete(0, g_signalLineName);

    // Generate unique name for signal line
    string timeStr = TimeToString(TimeCurrent(), TIME_SECONDS);
    g_signalLineName = "Signal_" + timeStr;

    // Calculate end of day time
    datetime endOfDayTime = GetEndOfDayTime();

    // Create signal line from exact formation time, extending until broken or EOD
    color lineColor = isHigh ? SignalHighColor : SignalLowColor;

    ObjectCreate(0, g_signalLineName, OBJ_TREND, 0, g_signalTime, level, endOfDayTime, level);
    ObjectSetInteger(0, g_signalLineName, OBJPROP_COLOR, lineColor);
    ObjectSetInteger(0, g_signalLineName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, g_signalLineName, OBJPROP_WIDTH, SignalLineWidth);
    ObjectSetInteger(0, g_signalLineName, OBJPROP_RAY_RIGHT, false); // Don't extend beyond EOD

    Print("Signal line created at level: ", level, " from time: ", TimeToString(g_signalTime));
}

//+------------------------------------------------------------------+
//| Check for daily reset                                            |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
    datetime now = TimeCurrent();

    // Reset daily flags at start of new trading day (working EA pattern)
    if(!IsSameDay(now, g_lastProcessedDate))
    {
        // End any active lines at end of previous day before reset
        EndActiveLinesAtEOD();

        // Reset all variables
        ResetDailyVariables();
        if(EnableChallengeRules)
            ResetDailyChallengeTracking();
        g_lastProcessedDate = now;

        Print("=== NEW TRADING DAY ===");
        Print("Server Date: ", TimeToString(now, TIME_DATE));
        Print("Variables reset for new trading day");

        // Log today's timing information
        LogTodaysTiming();
    }
}

//+------------------------------------------------------------------+
//| Log today's timing (placeholder - can add timezone info)         |
//+------------------------------------------------------------------+
void LogTodaysTiming()
{
    // Optional: log session times for current day
}

//+------------------------------------------------------------------+
//| Reset all daily variables                                        |
//+------------------------------------------------------------------+
void ResetDailyVariables()
{
    // Session state variables
    g_sessionActive = false;
    g_waitingForSignal = false;
    g_signalFound = false;

    // Opening range variables
    g_sessionHigh = 0.0;
    g_sessionLow = 0.0;
    g_sessionOpen = 0.0;
    g_sessionClose = 0.0;
    g_orBullish = false;

    // Timing variables
    g_sessionHighTime = 0;
    g_sessionLowTime = 0;
    g_sessionHighBar = 0;
    g_sessionLowBar = 0;

    // Signal variables
    g_currentSignalLevel = 0.0;
    g_signalIsHigh = false;
    g_signalTime = 0;

    // Strategy state
    g_longSignalActive = false;
    g_shortSignalActive = false;
    g_longEntryLevel = 0.0;
    g_shortEntryLevel = 0.0;

    // Bias mode variables
    g_biasFound = false;
    g_longBias = false;
    g_biasTime = 0;

    // Consecutive candles counters
    g_consecutiveLongCloses = 0;
    g_consecutiveShortCloses = 0;

    g_TradesToday = 0;
    g_ConsecutiveLosses = 0;  // Reset so "pause after N losses" is per day

    // Clean up drawing objects from previous day
    CleanupDrawingObjects();

    // Clean up old trade visualizations
    CleanupOldVisualizations();
}

//+------------------------------------------------------------------+
//| Clean up all drawing objects                                     |
//+------------------------------------------------------------------+
void CleanupDrawingObjects()
{
    // Delete opening range lines
    if(g_orHighLineName != "")
    {
        ObjectDelete(0, g_orHighLineName);
        g_orHighLineName = "";
    }
    if(g_orLowLineName != "")
    {
        ObjectDelete(0, g_orLowLineName);
        g_orLowLineName = "";
    }

    // Delete signal line
    if(g_signalLineName != "")
    {
        ObjectDelete(0, g_signalLineName);
        g_signalLineName = "";
    }
}

//+------------------------------------------------------------------+
//| Process Trading Logic                                            |
//+------------------------------------------------------------------+
void ProcessTradingLogic()
{
    // Check if we've passed stop trading time
    if(IsPastStopTradingTime())
    {
        // Reset signal states to prevent new trades
        g_longSignalActive = false;
        g_shortSignalActive = false;
        g_consecutiveLongCloses = 0;
        g_consecutiveShortCloses = 0;
        return;
    }

    // Use completed candle (bar 1) for entry decisions, just like signal detection
    double lastOpen = iOpen(_Symbol, PERIOD_CURRENT, 1);
    double lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);
    double lastHigh = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double lastLow = iLow(_Symbol, PERIOD_CURRENT, 1);
    datetime lastTime = iTime(_Symbol, PERIOD_CURRENT, 1);

    double atrValue = GetATRValue();

    if(atrValue <= 0)
        return;

    // Update consecutive close counters
    UpdateConsecutiveCloses(lastClose);

    // Check for long entry (candle closes above signal high line)
    if(g_shortSignalActive && g_shortEntryLevel > 0 && g_consecutiveLongCloses >= ConsecutiveCandles)
    {
        // Get current market price for entry
        double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        // Calculate SL and TP distances from entry price for proper risk/reward ratio
        double slDistance = atrValue * ATRMultiplier;
        double tpDistance = slDistance * TPMultiplier;

        // Calculate stop loss and take profit for long position
        double longSL = entryPrice - slDistance;
        double longTP = entryPrice + tpDistance;

        // Calculate position size
        double calculatedQty = CalculatePositionSize(entryPrice, longSL);

        // Execute long trade (only if we don't already have our position and filters allow)
        if(!HasOpenPosition() && CanPlaceNewOrder() && ExecuteLongTrade(calculatedQty, longSL, longTP))
        {
            g_TradesToday++;
            // Reset signal state and counters
            g_shortSignalActive = false;
            g_shortEntryLevel = 0.0;
            g_consecutiveLongCloses = 0;
            g_consecutiveShortCloses = 0;

            // Create entry arrow
            CreateEntryArrow(true, entryPrice);

            // Create Long Short Tool visualization
            if(ShowLongShortTool)
            {
                CreateTradeVisualization(true, entryPrice, longSL, longTP);
            }

            Print("=== LONG POSITION OPENED ===");
            Print("Trigger: ", ConsecutiveCandles, " consecutive closes above signal level ", g_shortEntryLevel);
            Print("Candle close: ", lastClose, " at ", TimeToString(lastTime));
            Print("Entry Price: ", entryPrice);
            Print("Stop Loss: ", longSL, " (distance: ", MathAbs(entryPrice - longSL), ")");
            Print("Take Profit: ", longTP, " (distance: ", MathAbs(longTP - entryPrice), ")");
            Print("Risk:Reward Ratio: 1:", DoubleToString(MathAbs(longTP - entryPrice) / MathAbs(entryPrice - longSL), 2));
            Print("Size: ", calculatedQty);
        }
    }

    // Check for short entry (candle closes below signal low line)
    if(g_longSignalActive && g_longEntryLevel > 0 && g_consecutiveShortCloses >= ConsecutiveCandles)
    {
        // Get current market price for entry
        double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // Calculate SL and TP distances from entry price for proper risk/reward ratio
        double slDistance = atrValue * ATRMultiplier;
        double tpDistance = slDistance * TPMultiplier;

        // Calculate stop loss and take profit for short position
        double shortSL = entryPrice + slDistance;
        double shortTP = entryPrice - tpDistance;

        // Calculate position size
        double calculatedQty = CalculatePositionSize(entryPrice, shortSL);

        // Execute short trade (only if we don't already have our position and filters allow)
        if(!HasOpenPosition() && CanPlaceNewOrder() && ExecuteShortTrade(calculatedQty, shortSL, shortTP))
        {
            g_TradesToday++;
            // Reset signal state and counters
            g_longSignalActive = false;
            g_longEntryLevel = 0.0;
            g_consecutiveLongCloses = 0;
            g_consecutiveShortCloses = 0;

            // Create entry arrow
            CreateEntryArrow(false, entryPrice);

            // Create Long Short Tool visualization
            if(ShowLongShortTool)
            {
                CreateTradeVisualization(false, entryPrice, shortSL, shortTP);
            }

            Print("=== SHORT POSITION OPENED ===");
            Print("Trigger: ", ConsecutiveCandles, " consecutive closes below signal level ", g_longEntryLevel);
            Print("Candle close: ", lastClose, " at ", TimeToString(lastTime));
            Print("Entry Price: ", entryPrice);
            Print("Stop Loss: ", shortSL, " (distance: ", MathAbs(shortSL - entryPrice), ")");
            Print("Take Profit: ", shortTP, " (distance: ", MathAbs(entryPrice - shortTP), ")");
            Print("Risk:Reward Ratio: 1:", DoubleToString(MathAbs(entryPrice - shortTP) / MathAbs(shortSL - entryPrice), 2));
            Print("Size: ", calculatedQty);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Position Size based on risk mode                      |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entryPrice, double stopLoss)
{
    double calculatedQty = 0;
    double riskAmount = 0;

    if(PositionSizingMode == FIXED_RISK_USD)
    {
        riskAmount = RiskAmountUSD;
    }
    else if(PositionSizingMode == RISK_PERCENT_ACCOUNT)
    {
        // Calculate risk amount based on account balance percentage
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        riskAmount = (accountBalance * RiskPercentAccount) / 100.0;

        Print("Account Balance: ", DoubleToString(accountBalance, 2),
              " Risk %: ", RiskPercentAccount,
              " Risk Amount: ", DoubleToString(riskAmount, 2));
    }

    if(PositionSizingMode == FIXED_RISK_USD || PositionSizingMode == RISK_PERCENT_ACCOUNT)
    {
        // Calculate position size based on risk amount
        double riskDistance = MathAbs(entryPrice - stopLoss);

        // Get symbol specifications
        double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

        if(riskDistance > 0 && tickSize > 0 && tickValue > 0)
        {
            // Calculate risk per unit (lot)
            double ticksInRiskDistance = riskDistance / tickSize;
            double riskPerUnit = ticksInRiskDistance * tickValue;

            // Calculate position size
            if(riskPerUnit > 0)
            {
                calculatedQty = riskAmount / riskPerUnit;
            }

            Print("Risk Distance: ", DoubleToString(riskDistance, _Digits),
                  " Ticks: ", DoubleToString(ticksInRiskDistance, 2),
                  " Risk per Unit: ", DoubleToString(riskPerUnit, 2),
                  " Target Position Size: ", DoubleToString(calculatedQty, 2));
        }
    }
    else
    {
        // Fixed contracts mode
        calculatedQty = PositionSize;
    }

    // Ensure minimum size and normalize according to symbol constraints
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    // Ensure minimum lot size
    calculatedQty = MathMax(minLot, calculatedQty);

    // Ensure maximum lot size
    calculatedQty = MathMin(maxLot, calculatedQty);

    // Round to lot step
    if(lotStep > 0)
    {
        calculatedQty = MathRound(calculatedQty / lotStep) * lotStep;
    }

    // Final check to ensure we have at least minimum lot
    if(calculatedQty < minLot)
        calculatedQty = minLot;

    Print("Final Position Size: ", calculatedQty,
          " (Min: ", minLot, " Max: ", maxLot, " Step: ", lotStep, ")");

    return calculatedQty;
}

//+------------------------------------------------------------------+
//| Execute Long Trade                                               |
//+------------------------------------------------------------------+
bool ExecuteLongTrade(double volume, double stopLoss, double takeProfit)
{
    // Normalize prices
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    takeProfit = NormalizeDouble(takeProfit, _Digits);

    // Execute market buy order
    if(trade.Buy(volume, _Symbol, 0.0, stopLoss, takeProfit, "OR Long Entry"))
    {
        Print("Long trade executed successfully");
        return true;
    }
    else
    {
        Print("Failed to execute long trade. Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Execute Short Trade                                              |
//+------------------------------------------------------------------+
bool ExecuteShortTrade(double volume, double stopLoss, double takeProfit)
{
    // Normalize prices
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    takeProfit = NormalizeDouble(takeProfit, _Digits);

    // Execute market sell order
    if(trade.Sell(volume, _Symbol, 0.0, stopLoss, takeProfit, "OR Short Entry"))
    {
        Print("Short trade executed successfully");
        return true;
    }
    else
    {
        Print("Failed to execute short trade. Error: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Create Entry Arrow Visualization                                 |
//+------------------------------------------------------------------+
void CreateEntryArrow(bool isLong, double price)
{
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    string arrowName = "Entry_Arrow_" + TimeToString(currentTime, TIME_SECONDS);

    if(isLong)
    {
        // Create up arrow for long entry
        ObjectCreate(0, arrowName, OBJ_ARROW_UP, 0, currentTime, price);
        ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrGreen);
    }
    else
    {
        // Create down arrow for short entry
        ObjectCreate(0, arrowName, OBJ_ARROW_DOWN, 0, currentTime, price);
        ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrRed);
    }

    ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
    ObjectSetInteger(0, arrowName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Get ATR value                                                    |
//+------------------------------------------------------------------+
double GetATRValue()
{
    double atr[];
    ArraySetAsSeries(atr, true);

    if(CopyBuffer(iATR(_Symbol, PERIOD_CURRENT, ATRLength), 0, 0, 1, atr) <= 0)
    {
        Print("Error getting ATR value");
        return 0.0;
    }

    return atr[0];
}

//+------------------------------------------------------------------+
//| Monitor existing positions                                       |
//+------------------------------------------------------------------+
void MonitorPositions()
{
    if(!HasOpenPosition())
        return;

    // Check if it's near end of day and close position (if enabled)
    if(ClosePositionsAtEOD && IsNearEndOfDay())
    {
        CloseAllPositions("End of day close");
        return;
    }

    // Trailing stop
    ProcessTrailingStop();
}

//+------------------------------------------------------------------+
//| Check if it's near end of trading day                          |
//+------------------------------------------------------------------+
bool IsNearEndOfDay()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    // Use configurable EOD time (broker time)
    return (dt.hour == EODCloseHour && dt.min == EODCloseMinute);
}

//+------------------------------------------------------------------+
//| Close all positions (this EA only, by magic)                     |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!posInfo.SelectByIndex(i))
            continue;
        if(posInfo.Symbol() != _Symbol || posInfo.Magic() != MagicNumber)
            continue;
        if(trade.PositionClose(posInfo.Ticket()))
            Print("Position closed: ", reason);
        else
            Print("Failed to close position. Error: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Create Trade Visualization (Long Short Tool)                    |
//+------------------------------------------------------------------+
void CreateTradeVisualization(bool isLong, double entryPrice, double stopLoss, double takeProfit)
{
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    string timeStr = TimeToString(currentTime, TIME_SECONDS);

    // Initialize current trade visualization
    g_currentTrade.entryLineName = "Entry_Line_" + timeStr;
    g_currentTrade.riskBoxName = "Risk_Box_" + timeStr;
    g_currentTrade.rewardBoxName = "Reward_Box_" + timeStr;
    g_currentTrade.entryTime = currentTime;
    g_currentTrade.entryPrice = entryPrice;
    g_currentTrade.stopLoss = stopLoss;
    g_currentTrade.takeProfit = takeProfit;

    // Calculate current day for cleanup
    MqlDateTime dt;
    TimeToStruct(currentTime, dt);
    g_currentTrade.entryDay = dt.year * 10000 + dt.mon * 100 + dt.day; // YYYYMMDD format

    // Calculate initial end time (extend 50 bars initially)
    datetime extendTime = currentTime + (50 * PeriodSeconds(PERIOD_CURRENT));

    // Create entry line (white horizontal line at entry price)
    ObjectCreate(0, g_currentTrade.entryLineName, OBJ_TREND, 0, currentTime, entryPrice, extendTime, entryPrice);
    ObjectSetInteger(0, g_currentTrade.entryLineName, OBJPROP_COLOR, EntryLineColor);
    ObjectSetInteger(0, g_currentTrade.entryLineName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, g_currentTrade.entryLineName, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, g_currentTrade.entryLineName, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, g_currentTrade.entryLineName, OBJPROP_BACK, false);

    // Create risk box (entry to stop loss)
    double riskTop = MathMax(entryPrice, stopLoss);
    double riskBottom = MathMin(entryPrice, stopLoss);

    ObjectCreate(0, g_currentTrade.riskBoxName, OBJ_RECTANGLE, 0, currentTime, riskTop, extendTime, riskBottom);
    ObjectSetInteger(0, g_currentTrade.riskBoxName, OBJPROP_COLOR, RiskColor);
    ObjectSetInteger(0, g_currentTrade.riskBoxName, OBJPROP_FILL, true);
    ObjectSetInteger(0, g_currentTrade.riskBoxName, OBJPROP_BACK, true);
    ObjectSetInteger(0, g_currentTrade.riskBoxName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, g_currentTrade.riskBoxName, OBJPROP_SELECTABLE, false);

    // Create reward box (entry to take profit)
    double rewardTop = MathMax(entryPrice, takeProfit);
    double rewardBottom = MathMin(entryPrice, takeProfit);

    ObjectCreate(0, g_currentTrade.rewardBoxName, OBJ_RECTANGLE, 0, currentTime, rewardTop, extendTime, rewardBottom);
    ObjectSetInteger(0, g_currentTrade.rewardBoxName, OBJPROP_COLOR, RewardColor);
    ObjectSetInteger(0, g_currentTrade.rewardBoxName, OBJPROP_FILL, true);
    ObjectSetInteger(0, g_currentTrade.rewardBoxName, OBJPROP_BACK, true);
    ObjectSetInteger(0, g_currentTrade.rewardBoxName, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, g_currentTrade.rewardBoxName, OBJPROP_SELECTABLE, false);

    Print("Long Short Tool visualization created for ", (isLong ? "LONG" : "SHORT"), " at ", entryPrice);
}

//+------------------------------------------------------------------+
//| Update Trade Visualization while position is active             |
//+------------------------------------------------------------------+
void UpdateTradeVisualization()
{
    if(!ShowLongShortTool)
        return;

    // Check if we have an active trade visualization
    if(g_currentTrade.entryLineName == "")
        return;

    bool positionExists = HasOpenPosition();
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    if(positionExists)
    {
        // Position is still active - extend visualization
        datetime extendTime = currentTime + (10 * PeriodSeconds(PERIOD_CURRENT));

        // Extend entry line
        ObjectSetInteger(0, g_currentTrade.entryLineName, OBJPROP_TIME, 1, extendTime);
        ObjectSetDouble(0, g_currentTrade.entryLineName, OBJPROP_PRICE, 1, g_currentTrade.entryPrice);

        // Extend risk box
        double riskTop = MathMax(g_currentTrade.entryPrice, g_currentTrade.stopLoss);
        double riskBottom = MathMin(g_currentTrade.entryPrice, g_currentTrade.stopLoss);
        ObjectSetInteger(0, g_currentTrade.riskBoxName, OBJPROP_TIME, 1, extendTime);
        ObjectSetDouble(0, g_currentTrade.riskBoxName, OBJPROP_PRICE, 0, riskTop);
        ObjectSetDouble(0, g_currentTrade.riskBoxName, OBJPROP_PRICE, 1, riskBottom);

        // Extend reward box
        double rewardTop = MathMax(g_currentTrade.entryPrice, g_currentTrade.takeProfit);
        double rewardBottom = MathMin(g_currentTrade.entryPrice, g_currentTrade.takeProfit);
        ObjectSetInteger(0, g_currentTrade.rewardBoxName, OBJPROP_TIME, 1, extendTime);
        ObjectSetDouble(0, g_currentTrade.rewardBoxName, OBJPROP_PRICE, 0, rewardTop);
        ObjectSetDouble(0, g_currentTrade.rewardBoxName, OBJPROP_PRICE, 1, rewardBottom);
    }
    else
    {
        // Position closed - finalize visualization
        FinalizeTradeVisualization();
    }
}

//+------------------------------------------------------------------+
//| Finalize Trade Visualization when position closes               |
//+------------------------------------------------------------------+
void FinalizeTradeVisualization()
{
    if(g_currentTrade.entryLineName == "")
        return;

    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    // Ensure minimum 4 bars width
    datetime minEndTime = g_currentTrade.entryTime + (4 * PeriodSeconds(PERIOD_CURRENT));
    datetime finalEndTime = MathMax(currentTime, minEndTime);

    // Finalize entry line
    ObjectSetInteger(0, g_currentTrade.entryLineName, OBJPROP_TIME, 1, finalEndTime);
    ObjectSetDouble(0, g_currentTrade.entryLineName, OBJPROP_PRICE, 1, g_currentTrade.entryPrice);

    // Finalize risk box
    ObjectSetInteger(0, g_currentTrade.riskBoxName, OBJPROP_TIME, 1, finalEndTime);

    // Finalize reward box
    ObjectSetInteger(0, g_currentTrade.rewardBoxName, OBJPROP_TIME, 1, finalEndTime);

    // Add to arrays for cleanup management
    int n = ArraySize(g_tradeVisualizations);
    ArrayResize(g_tradeVisualizations, n + 3);
    ArrayResize(g_tradeEntryTimes, n + 3);
    ArrayResize(g_tradeEntryDays, n + 3);

    g_tradeVisualizations[n] = g_currentTrade.entryLineName;
    g_tradeVisualizations[n + 1] = g_currentTrade.riskBoxName;
    g_tradeVisualizations[n + 2] = g_currentTrade.rewardBoxName;

    g_tradeEntryTimes[n] = g_currentTrade.entryTime;
    g_tradeEntryTimes[n + 1] = g_currentTrade.entryTime;
    g_tradeEntryTimes[n + 2] = g_currentTrade.entryTime;

    g_tradeEntryDays[n] = g_currentTrade.entryDay;
    g_tradeEntryDays[n + 1] = g_currentTrade.entryDay;
    g_tradeEntryDays[n + 2] = g_currentTrade.entryDay;

    // Clear current trade struct
    g_currentTrade.entryLineName = "";
    g_currentTrade.riskBoxName = "";
    g_currentTrade.rewardBoxName = "";
    g_currentTrade.entryTime = 0;
    g_currentTrade.entryPrice = 0.0;
    g_currentTrade.stopLoss = 0.0;
    g_currentTrade.takeProfit = 0.0;
    g_currentTrade.entryDay = 0;

    // Clean up old visualizations (30+ days)
    CleanupOldVisualizations();

    Print("Long Short Tool visualization finalized");
}

//+------------------------------------------------------------------+
//| Clean up old trade visualizations (30+ days)                    |
//+------------------------------------------------------------------+
void CleanupOldVisualizations()
{
    if(ArraySize(g_tradeVisualizations) == 0)
        return;

    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime now = TimeCurrent();
    const int keepSeconds = 30 * 24 * 3600; // 30 days in seconds

    for(int i = ArraySize(g_tradeVisualizations) - 1; i >= 0; i--)
    {
        if(now - g_tradeEntryTimes[i] > keepSeconds)
        {
            ObjectDelete(0, g_tradeVisualizations[i]);
            // Remove by shifting (MQL5 ArrayRemove exists in build 3815+)
            int total = ArraySize(g_tradeVisualizations);
            for(int j = i; j < total - 1; j++)
            {
                g_tradeVisualizations[j] = g_tradeVisualizations[j + 1];
                g_tradeEntryTimes[j] = g_tradeEntryTimes[j + 1];
                g_tradeEntryDays[j] = g_tradeEntryDays[j + 1];
            }
            ArrayResize(g_tradeVisualizations, total - 1);
            ArrayResize(g_tradeEntryTimes, total - 1);
            ArrayResize(g_tradeEntryDays, total - 1);
        }
    }
}

//+------------------------------------------------------------------+
//| Get end of day time (broker time)                              |
//+------------------------------------------------------------------+
datetime GetEndOfDayTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    dt.hour = 16;
    dt.min = 0;
    dt.sec = 0;
    return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Helper function to check if markets are open                    |
//+------------------------------------------------------------------+
bool IsMarketOpen()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    // Check if it's a weekday (Monday=1 to Friday=5)
    if(dt.day_of_week < 1 || dt.day_of_week > 5)
        return false;

    // Calculate current time in minutes since midnight
    int currentMinutes = dt.hour * 60 + dt.min;

    // Market open: 9:30 AM (570 minutes)
    // Market close: 4:00 PM (960 minutes)
    return (currentMinutes >= 570 && currentMinutes < 960);
}

//+------------------------------------------------------------------+
//| Check for opening range line breaks                             |
//+------------------------------------------------------------------+
void CheckLineBreaks()
{
    double currentHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);
    double currentLow = iLow(_Symbol, PERIOD_CURRENT, 0);
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    // Check if OR high line is broken
    if(g_orHighLineName != "" && currentHigh > g_sessionHigh)
    {
        // End the line at the current bar where it was broken
        ObjectSetInteger(0, g_orHighLineName, OBJPROP_TIME, 1, currentTime);
        ObjectSetDouble(0, g_orHighLineName, OBJPROP_PRICE, 1, g_sessionHigh);
        g_orHighLineName = "";

        Print("OR High line broken at: ", currentHigh, " at time: ", TimeToString(currentTime));
    }

    // Check if OR low line is broken
    if(g_orLowLineName != "" && currentLow < g_sessionLow)
    {
        // End the line at the current bar where it was broken
        ObjectSetInteger(0, g_orLowLineName, OBJPROP_TIME, 1, currentTime);
        ObjectSetDouble(0, g_orLowLineName, OBJPROP_PRICE, 1, g_sessionLow);
        g_orLowLineName = "";

        Print("OR Low line broken at: ", currentLow, " at time: ", TimeToString(currentTime));
    }

    // Check if signal line is broken
    if(g_signalLineName != "" && g_currentSignalLevel > 0)
    {
        if(g_signalIsHigh && currentHigh > g_currentSignalLevel)
        {
            // End signal high line at break point
            ObjectSetInteger(0, g_signalLineName, OBJPROP_TIME, 1, currentTime);
            ObjectSetDouble(0, g_signalLineName, OBJPROP_PRICE, 1, g_currentSignalLevel);
            g_signalLineName = "";
            g_currentSignalLevel = 0.0;

            Print("Signal high line broken upward at: ", currentHigh, " at time: ", TimeToString(currentTime));
        }
        else if(!g_signalIsHigh && currentLow < g_currentSignalLevel)
        {
            // End signal low line at break point
            ObjectSetInteger(0, g_signalLineName, OBJPROP_TIME, 1, currentTime);
            ObjectSetDouble(0, g_signalLineName, OBJPROP_PRICE, 1, g_currentSignalLevel);
            g_signalLineName = "";
            g_currentSignalLevel = 0.0;

            Print("Signal low line broken downward at: ", currentLow, " at time: ", TimeToString(currentTime));
        }
    }
}

//+------------------------------------------------------------------+
//| Update session background visualization                         |
//+------------------------------------------------------------------+
void UpdateSessionBackground(bool inSession)
{
    static string bgRectName = "";
    static datetime sessionStartTime = 0;

    if(inSession && g_sessionActive)
    {
        // Create or update background rectangle during session
        if(bgRectName == "")
        {
            // First time creating the rectangle - store session start time
            sessionStartTime = GetSessionStartTime(); // Exact 09:30 EST time
            bgRectName = "Session_BG_" + TimeToString(sessionStartTime, TIME_SECONDS);

            // Calculate session end time (09:35 EST)
            datetime sessionEndTime = sessionStartTime + 300; // 5 minutes

            // Create rectangle using current OR high/low with some padding
            double topPrice = g_sessionHigh + (g_sessionHigh - g_sessionLow) * 0.1; // 10% padding above
            double bottomPrice = g_sessionLow - (g_sessionHigh - g_sessionLow) * 0.1; // 10% padding below

            ObjectCreate(0, bgRectName, OBJ_RECTANGLE, 0, sessionStartTime, topPrice, sessionEndTime, bottomPrice);
            ObjectSetInteger(0, bgRectName, OBJPROP_COLOR, SessionBgColor);
            ObjectSetInteger(0, bgRectName, OBJPROP_FILL, true);
            ObjectSetInteger(0, bgRectName, OBJPROP_BACK, true);
            ObjectSetInteger(0, bgRectName, OBJPROP_SELECTED, false);
            ObjectSetInteger(0, bgRectName, OBJPROP_SELECTABLE, false);
        }
        else
        {
            // Update the rectangle to expand with the growing OR range
            datetime sessionEndTime = sessionStartTime + 300;
            double topPrice = g_sessionHigh + (g_sessionHigh - g_sessionLow) * 0.1;
            double bottomPrice = g_sessionLow - (g_sessionHigh - g_sessionLow) * 0.1;

            // Update rectangle coordinates
            ObjectSetInteger(0, bgRectName, OBJPROP_TIME, 0, sessionStartTime);
            ObjectSetDouble(0, bgRectName, OBJPROP_PRICE, 0, topPrice);
            ObjectSetInteger(0, bgRectName, OBJPROP_TIME, 1, sessionEndTime);
            ObjectSetDouble(0, bgRectName, OBJPROP_PRICE, 1, bottomPrice);
        }
    }
    else if(!inSession && bgRectName != "" && !g_sessionActive)
    {
        // Session ended - finalize the rectangle with exact session bounds
        datetime sessionEndTime = sessionStartTime + 300; // Exact 5-minute session
        double topPrice = g_sessionHigh + (g_sessionHigh - g_sessionLow) * 0.1;
        double bottomPrice = g_sessionLow - (g_sessionHigh - g_sessionLow) * 0.1;

        // Final update to rectangle
        ObjectSetInteger(0, bgRectName, OBJPROP_TIME, 0, sessionStartTime);
        ObjectSetDouble(0, bgRectName, OBJPROP_PRICE, 0, topPrice);
        ObjectSetInteger(0, bgRectName, OBJPROP_TIME, 1, sessionEndTime);
        ObjectSetDouble(0, bgRectName, OBJPROP_PRICE, 1, bottomPrice);

        bgRectName = ""; // Reset for next session

        Print("Session BG finalized - Time: ", TimeToString(sessionStartTime), " to ", TimeToString(sessionEndTime),
              " Price: ", bottomPrice, " to ", topPrice);
    }
}

//+------------------------------------------------------------------+
//| End active lines at end of day                                  |
//+------------------------------------------------------------------+
void EndActiveLinesAtEOD()
{
    datetime eodTime = GetEndOfDayTime() - 3600; // End 1 hour before to be safe

    // End OR high line if still active
    if(g_orHighLineName != "")
    {
        ObjectSetInteger(0, g_orHighLineName, OBJPROP_TIME, 1, eodTime);
        ObjectSetDouble(0, g_orHighLineName, OBJPROP_PRICE, 1, g_sessionHigh);
        Print("OR High line ended at EOD");
    }

    // End OR low line if still active
    if(g_orLowLineName != "")
    {
        ObjectSetInteger(0, g_orLowLineName, OBJPROP_TIME, 1, eodTime);
        ObjectSetDouble(0, g_orLowLineName, OBJPROP_PRICE, 1, g_sessionLow);
        Print("OR Low line ended at EOD");
    }

    // End signal line if still active
    if(g_signalLineName != "")
    {
        ObjectSetInteger(0, g_signalLineName, OBJPROP_TIME, 1, eodTime);
        ObjectSetDouble(0, g_signalLineName, OBJPROP_PRICE, 1, g_currentSignalLevel);
        Print("Signal line ended at EOD");
    }
}

//+------------------------------------------------------------------+
//| Get exact session start time (broker time)                     |
//+------------------------------------------------------------------+
datetime GetSessionStartTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    dt.hour = OR_StartHour;
    dt.min = OR_StartMinute;
    dt.sec = 0;
    return StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Process Bias Detection (First Breakout Mode)                    |
//+------------------------------------------------------------------+
void ProcessBiasDetection()
{
    if(g_biasFound || !g_waitingForSignal)
        return;

    // Check the LAST COMPLETED candle for first breakout
    double lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);
    datetime lastTime = iTime(_Symbol, PERIOD_CURRENT, 1);

    // Debug output - only print once per new bar
    static datetime lastBiasPrintTime = 0;
    if(lastTime != lastBiasPrintTime)
    {
        Print("Checking for bias - Close: ", lastClose, " OR High: ", g_sessionHigh, " OR Low: ", g_sessionLow);
        lastBiasPrintTime = lastTime;
    }

    // Check if candle closed outside the opening range
    if(lastClose > g_sessionHigh)
    {
        // First close above range - LONG bias
        g_biasFound = true;
        g_longBias = true;
        g_biasTime = lastTime;

        Print("*** LONG BIAS ESTABLISHED *** - First close above OR at: ", lastClose, " Time: ", TimeToString(lastTime));
    }
    else if(lastClose < g_sessionLow)
    {
        // First close below range - SHORT bias
        g_biasFound = true;
        g_longBias = false;
        g_biasTime = lastTime;

        Print("*** SHORT BIAS ESTABLISHED *** - First close below OR at: ", lastClose, " Time: ", TimeToString(lastTime));
    }
}

//+------------------------------------------------------------------+
//| Check if past stop trading time                                  |
//+------------------------------------------------------------------+
bool IsPastStopTradingTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    // Calculate current time in minutes since midnight
    int currentMinutes = dt.hour * 60 + dt.min;

    // Calculate stop trading time in minutes since midnight
    int stopMinutes = StopTradingHour * 60 + StopTradingMinute;

    return (currentMinutes >= stopMinutes);
}

//+------------------------------------------------------------------+
//| Update consecutive closes counters                               |
//+------------------------------------------------------------------+
void UpdateConsecutiveCloses(double lastClose)
{
    static datetime lastUpdateTime = 0;
    datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 1);

    // Only update once per completed bar
    if(currentTime <= lastUpdateTime)
        return;
    lastUpdateTime = currentTime;

    // Update consecutive closes for long signals (closes above signal level)
    if(g_shortSignalActive && g_shortEntryLevel > 0)
    {
        if(lastClose > g_shortEntryLevel)
        {
            g_consecutiveLongCloses++;
            g_consecutiveShortCloses = 0; // Reset opposite counter

            Print("Consecutive long closes: ", g_consecutiveLongCloses, "/", ConsecutiveCandles,
                  " (Close: ", lastClose, " > Signal: ", g_shortEntryLevel, ")");
        }
        else
        {
            g_consecutiveLongCloses = 0; // Reset if close is not above level
        }
    }

    // Update consecutive closes for short signals (closes below signal level)
    if(g_longSignalActive && g_longEntryLevel > 0)
    {
        if(lastClose < g_longEntryLevel)
        {
            g_consecutiveShortCloses++;
            g_consecutiveLongCloses = 0; // Reset opposite counter

            Print("Consecutive short closes: ", g_consecutiveShortCloses, "/", ConsecutiveCandles,
                  " (Close: ", lastClose, " < Signal: ", g_longEntryLevel, ")");
        }
        else
        {
            g_consecutiveShortCloses = 0; // Reset if close is not below level
        }
    }
}



//+------------------------------------------------------------------+
//| Check if two datetimes are on same day                          |
//+------------------------------------------------------------------+
bool IsSameDay(datetime a, datetime b)
{
    MqlDateTime da, db;
    TimeToStruct(a, da);
    TimeToStruct(b, db);

    return (da.year == db.year && da.mon == db.mon && da.day == db.day);
}


//+------------------------------------------------------------------+
