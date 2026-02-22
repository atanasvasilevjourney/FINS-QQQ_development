//+------------------------------------------------------------------+
//|                                                    SigmaScore.mq5 |
//| Sigma Score: Z-score of log returns (statistical anomaly detector) |
//| TECHAURORA - FZCO / Dominic Michael Frehner                       |
//+------------------------------------------------------------------+
#property copyright "TECHAURORA - FZCO"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_width1  2
#property indicator_label1  "Sigma Score"

input int    InpLookback = 20;
input double InpUpperThreshold = 2.0;
input double InpLowerThreshold = -2.0;

double SigmaBuffer[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit() {
    SetIndexBuffer(0, SigmaBuffer, INDICATOR_DATA);
    ArraySetAsSeries(SigmaBuffer, true);

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
                const int &spread[]) {
    if(rates_total < InpLookback + 1)
        return(0);

    ArraySetAsSeries(close, true);
    ArraySetAsSeries(time, true);

    int start;
    if(prev_calculated == 0) {
        start = rates_total - InpLookback - 1;
        ArrayInitialize(SigmaBuffer, EMPTY_VALUE);
    } else {
        start = rates_total - prev_calculated;
        if(start < 0) start = 0;
    }

    for(int i = start; i >= 0; i--) {
        if(i + InpLookback >= rates_total) {
            SigmaBuffer[i] = EMPTY_VALUE;
            continue;
        }

        double sum_returns = 0;
        double sum_squared = 0;
        int valid_count = 0;

        for(int j = 0; j < InpLookback; j++) {
            int idx1 = i + j;
            int idx2 = i + j + 1;

            if(idx2 < rates_total && close[idx1] > 0 && close[idx2] > 0) {
                double log_return = MathLog(close[idx1] / close[idx2]);
                sum_returns += log_return;
                sum_squared += log_return * log_return;
                valid_count++;
            }
        }

        if(i + 1 < rates_total && close[i] > 0 && close[i + 1] > 0) {
            double current_return = MathLog(close[i] / close[i + 1]);

            if(valid_count >= InpLookback) {
                double mean = sum_returns / valid_count;
                double variance = (sum_squared / valid_count) - (mean * mean);
                if(variance < 0) variance = 0;

                double stdev = MathSqrt(variance);

                if(stdev > 0.0000001)
                    SigmaBuffer[i] = (current_return - mean) / stdev;
                else
                    SigmaBuffer[i] = 0;
            } else {
                SigmaBuffer[i] = EMPTY_VALUE;
            }
        } else {
            SigmaBuffer[i] = EMPTY_VALUE;
        }
    }

    return(rates_total);
}
