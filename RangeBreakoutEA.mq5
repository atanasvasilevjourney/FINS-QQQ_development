//+------------------------------------------------------------------+
//|                                            RangeBreakoutEA.mq5 |
//|                                    Copyright 2024, BM Trading |
//|                                             https://bmtrading.de |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, BM Trading"
#property link      "https://bmtrading.de"
#property version   "1.00"
#property description "Range Breakout Expert Advisor - Identifies breakout zones in the morning and trades breakouts"

//--- Include necessary libraries
#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Range Settings ==="
input int      RangeStartHour = 3;           // Range start hour
input int      RangeStartMinute = 0;         // Range start minute
input int      RangeEndHour = 6;             // Range end hour
input int      RangeEndMinute = 0;           // Range end minute

input group "=== Trading Settings ==="
input int      TradingEndHour = 18;          // Trading end hour
input int      TradingEndMinute = 0;         // Trading end minute
input double   RiskAmount = 50.0;            // Risk amount per trade
input int      MagicNumber = 12345;          // Magic number for this EA
input bool     ShowRangeVisualization = true; // Show range rectangle on chart

input group "=== Advanced Settings ==="
input int      MaxTradesPerDay = 1;          // Maximum trades per day
input bool     AllowMultipleBreakouts = false; // Allow multiple breakouts per day
input double   MinRangeSize = 0.0001;        // Minimum range size to trade

//--- Global variables
datetime g_RangeTimeStart;
datetime g_RangeTimeEnd;
datetime g_TradingTimeEnd;
double   g_RangeHigh;
double   g_RangeLow;
bool     g_TradeOpened;
int      g_DailyTradeCount;
datetime g_LastTradeDate;

//--- Trade object
CTrade g_Trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set magic number for trade object
    g_Trade.SetExpertMagicNumber(MagicNumber);
    
    // Initialize global variables
    g_RangeHigh = 0.0;
    g_RangeLow = 0.0;
    g_TradeOpened = false;
    g_DailyTradeCount = 0;
    g_LastTradeDate = 0;
    
    // Validate input parameters
    if(!ValidateInputs())
    {
        Print("Error: Invalid input parameters");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    Print("Range Breakout EA initialized successfully");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up any objects created
    ObjectDelete(0, "Range_" + TimeToString(g_RangeTimeStart, TIME_DATE));
    Print("Range Breakout EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Calculate times for current day
    CalculateTimes();
    
    // Calculate range if we're in range period
    if(IsInRangePeriod())
    {
        CalculateRange();
    }
    
    // Check for new day and reset daily variables
    CheckNewDay();
    
    // Check for breakouts and open positions
    if(IsInTradingPeriod() && !g_TradeOpened)
    {
        CheckBreakouts();
    }
    
    // Close positions at trading end time
    if(IsTradingEndTime())
    {
        CloseAllPositions();
    }
}

//+------------------------------------------------------------------+
//| Calculate times for current day                                 |
//+------------------------------------------------------------------+
void CalculateTimes()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Set range start time
    dt.hour = RangeStartHour;
    dt.min = RangeStartMinute;
    dt.sec = 0;
    g_RangeTimeStart = StructToTime(dt);
    
    // Set range end time
    dt.hour = RangeEndHour;
    dt.min = RangeEndMinute;
    dt.sec = 0;
    g_RangeTimeEnd = StructToTime(dt);
    
    // Set trading end time
    dt.hour = TradingEndHour;
    dt.min = TradingEndMinute;
    dt.sec = 0;
    g_TradingTimeEnd = StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Calculate range high and low                                    |
//+------------------------------------------------------------------+
void CalculateRange()
{
    double highs[];
    double lows[];
    
    // Copy high and low prices for the range period
    if(CopyHigh(_Symbol, PERIOD_M1, g_RangeTimeStart, g_RangeTimeEnd, highs) <= 0 ||
       CopyLow(_Symbol, PERIOD_M1, g_RangeTimeStart, g_RangeTimeEnd, lows) <= 0)
    {
        return;
    }
    
    // Find highest and lowest values
    int highIndex = ArrayMaximum(highs);
    int lowIndex = ArrayMinimum(lows);
    
    if(highIndex >= 0 && lowIndex >= 0)
    {
        g_RangeHigh = highs[highIndex];
        g_RangeLow = lows[lowIndex];
        
        // Create/update range visualization
        if(ShowRangeVisualization)
        {
            CreateRangeVisualization();
        }
    }
}

//+------------------------------------------------------------------+
//| Create range visualization rectangle                            |
//+------------------------------------------------------------------+
void CreateRangeVisualization()
{
    string objName = "Range_" + TimeToString(g_RangeTimeStart, TIME_DATE);
    
    if(ObjectFind(0, objName) < 0)
    {
        // Create new rectangle
        ObjectCreate(0, objName, OBJ_RECTANGLE, 0, g_RangeTimeStart, g_RangeHigh, g_RangeTimeEnd, g_RangeLow);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrYellow);
        ObjectSetInteger(0, objName, OBJPROP_FILL, true);
        ObjectSetInteger(0, objName, OBJPROP_BACK, true);
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
    }
    else
    {
        // Update existing rectangle
        ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, g_RangeHigh);
        ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, g_RangeLow);
    }
}

//+------------------------------------------------------------------+
//| Check for breakouts and open positions                          |
//+------------------------------------------------------------------+
void CheckBreakouts()
{
    if(g_RangeHigh <= 0 || g_RangeLow <= 0)
        return;
    
    // Check if range size meets minimum requirement
    if((g_RangeHigh - g_RangeLow) < MinRangeSize)
        return;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check for long breakout (above range high)
    if(currentPrice > g_RangeHigh)
    {
        OpenLongPosition();
    }
    // Check for short breakout (below range low)
    else if(currentPrice < g_RangeLow)
    {
        OpenShortPosition();
    }
}

//+------------------------------------------------------------------+
//| Open long position                                              |
//+------------------------------------------------------------------+
void OpenLongPosition()
{
    if(g_DailyTradeCount >= MaxTradesPerDay)
        return;
    
    double lotSize = CalculateLotSize();
    double sl = g_RangeLow;
    
    if(g_Trade.Buy(lotSize, _Symbol, 0, sl, 0, "Range Breakout Long"))
    {
        g_TradeOpened = true;
        g_DailyTradeCount++;
        g_LastTradeDate = TimeCurrent();
        Print("Long position opened: Lot size = ", lotSize, ", SL = ", sl);
    }
    else
    {
        Print("Failed to open long position: ", g_Trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Open short position                                             |
//+------------------------------------------------------------------+
void OpenShortPosition()
{
    if(g_DailyTradeCount >= MaxTradesPerDay)
        return;
    
    double lotSize = CalculateLotSize();
    double sl = g_RangeHigh;
    
    if(g_Trade.Sell(lotSize, _Symbol, 0, sl, 0, "Range Breakout Short"))
    {
        g_TradeOpened = true;
        g_DailyTradeCount++;
        g_LastTradeDate = TimeCurrent();
        Print("Short position opened: Lot size = ", lotSize, ", SL = ", sl);
    }
    else
    {
        Print("Failed to open short position: ", g_Trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk amount                         |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    if(g_RangeHigh <= 0 || g_RangeLow <= 0)
        return 0.01; // Default minimum lot size
    
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double rangeSize = g_RangeHigh - g_RangeLow;
    
    if(tickSize <= 0 || tickValue <= 0)
        return 0.01;
    
    // Calculate risk per lot
    double riskPerLot = (rangeSize / tickSize) * tickValue;
    
    if(riskPerLot <= 0)
        return 0.01;
    
    // Calculate lot size based on risk amount
    double lotSize = RiskAmount / riskPerLot;
    
    // Normalize lot size
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Close all positions opened by this EA                          |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                if(g_Trade.PositionClose(PositionGetTicket(i)))
                {
                    Print("Position closed: ", PositionGetTicket(i));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if current time is in range period                        |
//+------------------------------------------------------------------+
bool IsInRangePeriod()
{
    datetime currentTime = TimeCurrent();
    return (currentTime >= g_RangeTimeStart && currentTime <= g_RangeTimeEnd);
}

//+------------------------------------------------------------------+
//| Check if current time is in trading period                      |
//+------------------------------------------------------------------+
bool IsInTradingPeriod()
{
    datetime currentTime = TimeCurrent();
    return (currentTime >= g_RangeTimeEnd && currentTime < g_TradingTimeEnd);
}

//+------------------------------------------------------------------+
//| Check if current time is trading end time                       |
//+------------------------------------------------------------------+
bool IsTradingEndTime()
{
    datetime currentTime = TimeCurrent();
    return (currentTime >= g_TradingTimeEnd);
}

//+------------------------------------------------------------------+
//| Check for new day and reset daily variables                    |
//+------------------------------------------------------------------+
void CheckNewDay()
{
    MqlDateTime currentDt, lastTradeDt;
    TimeToStruct(TimeCurrent(), currentDt);
    TimeToStruct(g_LastTradeDate, lastTradeDt);
    
    // Reset if new day
    if(currentDt.day != lastTradeDt.day || currentDt.mon != lastTradeDt.mon || currentDt.year != lastTradeDt.year)
    {
        g_TradeOpened = false;
        g_DailyTradeCount = 0;
        g_RangeHigh = 0.0;
        g_RangeLow = 0.0;
    }
}

//+------------------------------------------------------------------+
//| Validate input parameters                                       |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
    // Check time parameters
    if(RangeStartHour < 0 || RangeStartHour > 23 || RangeEndHour < 0 || RangeEndHour > 23)
    {
        Print("Error: Invalid hour values (0-23)");
        return false;
    }
    
    if(RangeStartMinute < 0 || RangeStartMinute > 59 || RangeEndMinute < 0 || RangeEndMinute > 59)
    {
        Print("Error: Invalid minute values (0-59)");
        return false;
    }
    
    if(TradingEndHour < 0 || TradingEndHour > 23 || TradingEndMinute < 0 || TradingEndMinute > 59)
    {
        Print("Error: Invalid trading end time");
        return false;
    }
    
    // Check if range start is before range end
    if(RangeStartHour > RangeEndHour || (RangeStartHour == RangeEndHour && RangeStartMinute >= RangeEndMinute))
    {
        Print("Error: Range start time must be before range end time");
        return false;
    }
    
    // Check risk amount
    if(RiskAmount <= 0)
    {
        Print("Error: Risk amount must be positive");
        return false;
    }
    
    // Check magic number
    if(MagicNumber <= 0)
    {
        Print("Error: Magic number must be positive");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
