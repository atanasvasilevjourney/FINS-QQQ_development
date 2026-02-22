//+------------------------------------------------------------------+
//|                                                  Sigma_Score.mq5 |
//|                                        Aurora Technologies, 2025 |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Aurora Technologies"
#property link      "https://aurora-tech.io"
#property version   "1.01"

#property indicator_separate_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_width1  2
#property indicator_label1  "Sigma Score"

// Input parameters
input int InpLookback = 20;                          // Lookback period
input double InpUpperThreshold = 2.0;                // Upper Threshold
input double InpLowerThreshold = -2.0;               // Lower Threshold

// Indicator buffers
double SigmaBuffer[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // Indicator buffers mapping
    SetIndexBuffer(0, SigmaBuffer, INDICATOR_DATA);
    ArraySetAsSeries(SigmaBuffer, true);
    
    // Set horizontal levels
    IndicatorSetInteger(INDICATOR_LEVELS, 3);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, 0.0);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, InpUpperThreshold);
    IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, InpLowerThreshold);
    
    IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrGray);
    IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrRed);
    IndicatorSetInteger(INDICATOR_LEVELCOLOR, 2, clrGreen);
    
    IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
    IndicatorSetInteger(INDICATOR_LEVELSTYLE, 1, STYLE_DASH);
    IndicatorSetInteger(INDICATOR_LEVELSTYLE, 2, STYLE_DASH);
    
    // Set indicator labels
    PlotIndexSetString(0, PLOT_LABEL, "Sigma Score");
    IndicatorSetString(INDICATOR_SHORTNAME, "Sigma Score (" + IntegerToString(InpLookback) + ")");
    IndicatorSetInteger(INDICATOR_DIGITS, 2);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    // Check for minimum required bars
    if(rates_total < InpLookback + 1) 
    {
        return(0);
    }
    
    // Set arrays as timeseries
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(time, true);
    
    // Calculate start position
    int start;
    if(prev_calculated == 0)
    {
        start = rates_total - InpLookback - 1;
        // Initialize buffer with EMPTY_VALUE
        ArrayInitialize(SigmaBuffer, EMPTY_VALUE);
    }
    else
    {
        start = rates_total - prev_calculated;
    }
    
    // Calculate Sigma Score for each bar
    for(int i = start; i >= 0; i--)
    {
        // Skip if not enough history
        if(i + InpLookback >= rates_total)
        {
            SigmaBuffer[i] = EMPTY_VALUE;
            continue;
        }
        
        // Calculate log returns for lookback period
        double sum_returns = 0;
        double sum_squared = 0;
        int valid_count = 0;
        
        for(int j = 0; j < InpLookback; j++)
        {
            int idx1 = i + j;
            int idx2 = i + j + 1;
            
            if(idx2 < rates_total && close[idx1] > 0 && close[idx2] > 0)
            {
                double log_return = MathLog(close[idx1] / close[idx2]);
                sum_returns += log_return;
                sum_squared += log_return * log_return;
                valid_count++;
            }
        }
        
        // Calculate current bar's log return
        if(i + 1 < rates_total && close[i] > 0 && close[i + 1] > 0)
        {
            double current_return = MathLog(close[i] / close[i + 1]);
            
            if(valid_count >= InpLookback)
            {
                // Calculate mean and standard deviation
                double mean = sum_returns / valid_count;
                double variance = (sum_squared / valid_count) - (mean * mean);
                
                // Ensure variance is non-negative
                if(variance < 0) variance = 0;
                
                double stdev = MathSqrt(variance);
                
                // Calculate z-score (Sigma Score)
                if(stdev > 0.0000001) // Avoid division by zero
                {
                    SigmaBuffer[i] = (current_return - mean) / stdev;
                }
                else
                {
                    SigmaBuffer[i] = 0;
                }
            }
            else
            {
                SigmaBuffer[i] = EMPTY_VALUE;
            }
        }
        else
        {
            SigmaBuffer[i] = EMPTY_VALUE;
        }
    }
    
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Cleanup if needed
}
//+------------------------------------------------------------------+