//+------------------------------------------------------------------+
//|                                    RangeBreakoutEA_Enhanced.mq5 |
//|                                    Copyright 2024, BM Trading |
//|                                             https://bmtrading.de |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, BM Trading"
#property link      "https://bmtrading.de"
#property version   "2.00"
#property description "Range Breakout Expert Advisor - Enhanced version with pending orders and improved safety"

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
input int      PositionCloseHour = 18;       // Position close hour
input int      PositionCloseMinute = 0;      // Position close minute
input double   RiskAmount = 50.0;            // Risk amount per trade
input int      MagicNumber = 12345;          // Magic number for this EA
input bool     ShowRangeVisualization = true; // Show range rectangle on chart

input group "=== Order Settings ==="
input bool     UsePendingOrders = true;      // Use pending orders (Buy Stop/Sell Stop)
input bool     OnlyOneTradePerDay = false;   // Only one trade per day (OCO)
input bool     UseTakeProfit = true;         // Use take profit
input double   TakeProfitFactor = 1.0;       // Take profit factor (multiplier of range size)

input group "=== Advanced Settings ==="
input double   MinRangeSize = 0.0001;        // Minimum range size to trade

//--- Global variables
datetime g_RangeTimeStart;
datetime g_RangeTimeEnd;
datetime g_TradingTimeEnd;
datetime g_PositionCloseTime;
double   g_RangeHigh;
double   g_RangeLow;
bool     g_RangeDetermined;
bool     g_PendingOrdersPlaced;
bool     g_TradeExecuted;
datetime g_LastTradeDate;
datetime g_EAStartTime;  // Track when EA was started
ulong    g_BuyStopTicket;
ulong    g_SellStopTicket;

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
    g_RangeDetermined = false;
    g_PendingOrdersPlaced = false;
    g_TradeExecuted = false;
    g_LastTradeDate = 0;
    g_EAStartTime = TimeCurrent();
    g_BuyStopTicket = 0;
    g_SellStopTicket = 0;
    
    // Check for existing positions and orders
    CheckExistingPositions();
    CheckExistingOrders();
    
    // Validate input parameters
    if(!ValidateInputs())
    {
        Print("Error: Invalid input parameters");
        return INIT_PARAMETERS_INCORRECT;
    }
    
    Print("Range Breakout EA Enhanced initialized successfully");
    Print("EA started at: ", TimeToString(g_EAStartTime));
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clean up any objects created (optional - comment out to keep ranges visible)
    if(ShowRangeVisualization)
    {
        string objName = "Range_" + TimeToString(g_RangeTimeStart, TIME_DATE);
        ObjectDelete(0, objName);
    }
    Print("Range Breakout EA Enhanced deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Calculate times for current day
    CalculateTimes();
    
    // Check for new day and reset daily variables
    if(CheckNewDay())
    {
        return; // Reset completed, wait for next tick
    }
    
    // If before range start, wait
    if(TimeCurrent() < g_RangeTimeStart)
    {
        return;
    }
    
    // Calculate range during range period
    if(IsInRangePeriod())
    {
        CalculateRange();
        return; // Wait for range to complete
    }
    
    // After range period - determine range if not done yet
    if(!g_RangeDetermined && TimeCurrent() >= g_RangeTimeEnd)
    {
        CalculateRange();
        if(g_RangeDetermined)
        {
            PlacePendingOrders();
        }
        return;
    }
    
    // Check for position close time
    if(IsPositionCloseTime())
    {
        CloseAllPositions();
        DeletePendingOrders();
        return;
    }
    
    // Check if trading period has ended
    if(TimeCurrent() >= g_TradingTimeEnd)
    {
        return; // No more trading
    }
    
    // Monitor pending orders and check for breakouts
    if(g_RangeDetermined && IsInTradingPeriod())
    {
        MonitorPendingOrders();
        
        // If pending orders failed and price broke out, open market position
        if(!g_PendingOrdersPlaced && !g_TradeExecuted)
        {
            CheckBreakoutMarketOrder();
        }
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
    
    // Set position close time
    dt.hour = PositionCloseHour;
    dt.min = PositionCloseMinute;
    dt.sec = 0;
    g_PositionCloseTime = StructToTime(dt);
}

//+------------------------------------------------------------------+
//| Calculate range high and low                                    |
//+------------------------------------------------------------------+
void CalculateRange()
{
    double highs[];
    double lows[];
    
    // Copy high and low prices for the range period
    int copied = CopyHigh(_Symbol, PERIOD_M1, g_RangeTimeStart, (int)(g_RangeTimeEnd - g_RangeTimeStart) / 60 + 1, highs);
    int copiedLow = CopyLow(_Symbol, PERIOD_M1, g_RangeTimeStart, (int)(g_RangeTimeEnd - g_RangeTimeStart) / 60 + 1, lows);
    
    if(copied <= 0 || copiedLow <= 0)
    {
        return;
    }
    
    // Find highest and lowest values
    int highIndex = ArrayMaximum(highs, 0, copied);
    int lowIndex = ArrayMinimum(lows, 0, copiedLow);
    
    if(highIndex >= 0 && lowIndex >= 0)
    {
        g_RangeHigh = highs[highIndex];
        g_RangeLow = lows[lowIndex];
        
        // Check minimum range size
        if((g_RangeHigh - g_RangeLow) >= MinRangeSize)
        {
            g_RangeDetermined = true;
            
            // Create/update range visualization
            if(ShowRangeVisualization)
            {
                CreateRangeVisualization();
            }
            
            Print("Range determined: High = ", g_RangeHigh, ", Low = ", g_RangeLow);
        }
        else
        {
            Print("Range too small: ", (g_RangeHigh - g_RangeLow), " < ", MinRangeSize);
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
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
    }
    else
    {
        // Update existing rectangle
        ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, g_RangeHigh);
        ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, g_RangeLow);
    }
}

//+------------------------------------------------------------------+
//| Place pending orders at range high and low                      |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
    if(!g_RangeDetermined || g_PendingOrdersPlaced)
        return;
    
    // Check if EA started after range completion - if so, don't place orders if price already broke out
    if(g_EAStartTime > g_RangeTimeEnd)
    {
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        if(currentPrice > g_RangeHigh || currentPrice < g_RangeLow)
        {
            Print("EA started after range completion and price already broke out. No orders placed.");
            g_PendingOrdersPlaced = true; // Prevent further attempts
            return;
        }
    }
    
    if(!UsePendingOrders)
    {
        g_PendingOrdersPlaced = true;
        return;
    }
    
    double lotSize = CalculateLotSize();
    if(lotSize <= 0)
    {
        Print("Cannot calculate lot size. Orders not placed.");
        return;
    }
    
    double sl, tp;
    
    // Calculate stop loss and take profit for buy stop
    sl = g_RangeLow;
    if(UseTakeProfit)
    {
        double rangeSize = g_RangeHigh - g_RangeLow;
        tp = g_RangeHigh + (rangeSize * TakeProfitFactor);
    }
    else
    {
        tp = 0;
    }
    
    // Place Buy Stop order
    if(g_Trade.BuyStop(lotSize, g_RangeHigh, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Range Breakout Buy Stop"))
    {
        g_BuyStopTicket = g_Trade.ResultOrder();
        Print("Buy Stop order placed at ", g_RangeHigh, ", SL = ", sl, ", TP = ", tp);
    }
    else
    {
        Print("Failed to place Buy Stop order: ", g_Trade.ResultRetcode());
    }
    
    // Calculate stop loss and take profit for sell stop
    sl = g_RangeHigh;
    if(UseTakeProfit)
    {
        double rangeSize = g_RangeHigh - g_RangeLow;
        tp = g_RangeLow - (rangeSize * TakeProfitFactor);
    }
    else
    {
        tp = 0;
    }
    
    // Place Sell Stop order
    if(g_Trade.SellStop(lotSize, g_RangeLow, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "Range Breakout Sell Stop"))
    {
        g_SellStopTicket = g_Trade.ResultOrder();
        Print("Sell Stop order placed at ", g_RangeLow, ", SL = ", sl, ", TP = ", tp);
    }
    else
    {
        Print("Failed to place Sell Stop order: ", g_Trade.ResultRetcode());
    }
    
    g_PendingOrdersPlaced = true;
}

//+------------------------------------------------------------------+
//| Monitor pending orders and handle execution                     |
//+------------------------------------------------------------------+
void MonitorPendingOrders()
{
    // Check if buy stop was executed
    if(g_BuyStopTicket > 0)
    {
        if(!OrderSelect(g_BuyStopTicket))
        {
            // Order doesn't exist - check if it was executed (became a position)
            if(HasPosition(POSITION_TYPE_BUY))
            {
                g_TradeExecuted = true;
                g_BuyStopTicket = 0;
                
                // If only one trade per day, delete opposite order
                if(OnlyOneTradePerDay && g_SellStopTicket > 0)
                {
                    if(OrderSelect(g_SellStopTicket))
                    {
                        g_Trade.OrderDelete(g_SellStopTicket);
                        Print("Opposite Sell Stop order deleted (OCO)");
                    }
                    g_SellStopTicket = 0;
                }
            }
        }
    }
    
    // Check if sell stop was executed
    if(g_SellStopTicket > 0)
    {
        if(!OrderSelect(g_SellStopTicket))
        {
            // Order doesn't exist - check if it was executed (became a position)
            if(HasPosition(POSITION_TYPE_SELL))
            {
                g_TradeExecuted = true;
                g_SellStopTicket = 0;
                
                // If only one trade per day, delete opposite order
                if(OnlyOneTradePerDay && g_BuyStopTicket > 0)
                {
                    if(OrderSelect(g_BuyStopTicket))
                    {
                        g_Trade.OrderDelete(g_BuyStopTicket);
                        Print("Opposite Buy Stop order deleted (OCO)");
                    }
                    g_BuyStopTicket = 0;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for breakout and open market position if pending failed  |
//+------------------------------------------------------------------+
void CheckBreakoutMarketOrder()
{
    if(!g_RangeDetermined || g_TradeExecuted)
        return;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double lotSize = CalculateLotSize();
    
    if(lotSize <= 0)
        return;
    
    double sl, tp;
    
    // Check for long breakout
    if(currentPrice > g_RangeHigh)
    {
        sl = g_RangeLow;
        if(UseTakeProfit)
        {
            double rangeSize = g_RangeHigh - g_RangeLow;
            tp = g_RangeHigh + (rangeSize * TakeProfitFactor);
        }
        else
        {
            tp = 0;
        }
        
        if(g_Trade.Buy(lotSize, _Symbol, 0, sl, tp, "Range Breakout Long"))
        {
            g_TradeExecuted = true;
            Print("Market Long position opened: Lot = ", lotSize, ", SL = ", sl, ", TP = ", tp);
            
            // Delete opposite pending order if OCO
            if(OnlyOneTradePerDay && g_SellStopTicket > 0)
            {
                if(OrderSelect(g_SellStopTicket))
                {
                    g_Trade.OrderDelete(g_SellStopTicket);
                }
                g_SellStopTicket = 0;
            }
        }
    }
    // Check for short breakout
    else if(currentPrice < g_RangeLow)
    {
        sl = g_RangeHigh;
        if(UseTakeProfit)
        {
            double rangeSize = g_RangeHigh - g_RangeLow;
            tp = g_RangeLow - (rangeSize * TakeProfitFactor);
        }
        else
        {
            tp = 0;
        }
        
        if(g_Trade.Sell(lotSize, _Symbol, 0, sl, tp, "Range Breakout Short"))
        {
            g_TradeExecuted = true;
            Print("Market Short position opened: Lot = ", lotSize, ", SL = ", sl, ", TP = ", tp);
            
            // Delete opposite pending order if OCO
            if(OnlyOneTradePerDay && g_BuyStopTicket > 0)
            {
                if(OrderSelect(g_BuyStopTicket))
                {
                    g_Trade.OrderDelete(g_BuyStopTicket);
                }
                g_BuyStopTicket = 0;
            }
        }
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
    
    // Calculate risk per lot (stop loss distance)
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
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                if(g_Trade.PositionClose(ticket))
                {
                    Print("Position closed at end of day: ", ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Delete all pending orders                                       |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
    // Delete buy stop
    if(g_BuyStopTicket > 0)
    {
        if(OrderSelect(g_BuyStopTicket))
        {
            g_Trade.OrderDelete(g_BuyStopTicket);
            Print("Buy Stop order deleted at end of day");
        }
        g_BuyStopTicket = 0;
    }
    
    // Delete sell stop
    if(g_SellStopTicket > 0)
    {
        if(OrderSelect(g_SellStopTicket))
        {
            g_Trade.OrderDelete(g_SellStopTicket);
            Print("Sell Stop order deleted at end of day");
        }
        g_SellStopTicket = 0;
    }
    
    // Also delete any other pending orders with our magic number
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket > 0)
        {
            if(OrderSelect(ticket))
            {
                if(OrderGetInteger(ORDER_MAGIC) == MagicNumber)
                {
                    g_Trade.OrderDelete(ticket);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for existing positions on EA start                       |
//+------------------------------------------------------------------+
void CheckExistingPositions()
{
    int posCount = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                posCount++;
                g_TradeExecuted = true; // Mark as executed to prevent new trades
            }
        }
    }
    
    if(posCount > 0)
    {
        Print("Found ", posCount, " existing position(s) on EA start");
    }
}

//+------------------------------------------------------------------+
//| Check for existing orders on EA start                          |
//+------------------------------------------------------------------+
void CheckExistingOrders()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(ticket > 0)
        {
            if(OrderSelect(ticket))
            {
                if(OrderGetInteger(ORDER_MAGIC) == MagicNumber)
                {
                    ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                    if(orderType == ORDER_TYPE_BUY_STOP)
                    {
                        g_BuyStopTicket = ticket;
                        g_PendingOrdersPlaced = true;
                    }
                    else if(orderType == ORDER_TYPE_SELL_STOP)
                    {
                        g_SellStopTicket = ticket;
                        g_PendingOrdersPlaced = true;
                    }
                }
            }
        }
    }
    
    if(g_PendingOrdersPlaced)
    {
        Print("Found existing pending orders on EA start");
    }
}

//+------------------------------------------------------------------+
//| Check if position exists                                        |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE positionType)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0)
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                if(PositionGetInteger(POSITION_TYPE) == positionType)
                {
                    return true;
                }
            }
        }
    }
    return false;
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
//| Check if current time is position close time                    |
//+------------------------------------------------------------------+
bool IsPositionCloseTime()
{
    static datetime lastCloseCheck = 0;
    datetime currentTime = TimeCurrent();
    
    // Check once per minute to avoid multiple executions
    if(currentTime >= g_PositionCloseTime && lastCloseCheck != currentTime)
    {
        MqlDateTime dt;
        TimeToStruct(currentTime, dt);
        if(dt.min == PositionCloseMinute)
        {
            lastCloseCheck = currentTime;
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check for new day and reset daily variables                    |
//+------------------------------------------------------------------+
bool CheckNewDay()
{
    MqlDateTime currentDt, lastTradeDt;
    TimeToStruct(TimeCurrent(), currentDt);
    TimeToStruct(g_LastTradeDate, lastTradeDt);
    
    // Reset if new day
    if(currentDt.day != lastTradeDt.day || currentDt.mon != lastTradeDt.mon || currentDt.year != lastTradeDt.year)
    {
        Print("New trading day detected. Resetting variables.");
        
        // Reset variables
        g_RangeDetermined = false;
        g_PendingOrdersPlaced = false;
        g_TradeExecuted = false;
        g_RangeHigh = 0.0;
        g_RangeLow = 0.0;
        g_BuyStopTicket = 0;
        g_SellStopTicket = 0;
        g_EAStartTime = TimeCurrent(); // Reset EA start time for new day
        
        // Delete old pending orders (they should be deleted at end of day, but just in case)
        DeletePendingOrders();
        
        return true;
    }
    return false;
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
    
    if(PositionCloseHour < 0 || PositionCloseHour > 23 || PositionCloseMinute < 0 || PositionCloseMinute > 59)
    {
        Print("Error: Invalid position close time");
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
    
    // Check take profit factor
    if(UseTakeProfit && TakeProfitFactor <= 0)
    {
        Print("Error: Take profit factor must be positive");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
