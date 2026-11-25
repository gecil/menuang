//+------------------------------------------------------------------+
//|                                       Trendline_Trade_Master.mq5 |
//|     Trendline Trade Master v1.20 — Exact Diagonal Touch Engine   |
//|  Standar Tanpa Ray | Presisi Garis Miring | Multi-Order | XM     |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Trendline Trade Master"
#property version     "1.20"
#property description "EA Visual Garis Tren: Eksekusi Real-Time Tick saat Garis Tersentuh (BUY, SELL, TP, SL, Alarm)"
#property description "v1.20: Standar Tanpa Ray Left/Right + Interpolasi Bar-Index Presisi Garis Miring + Trailing SL Profit"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| [1] Enum & Parameter Input                                       |
//+------------------------------------------------------------------+
enum ENUM_AFTER_ENTRY_ACTION
{
   ENTRY_LINE_DELETE  = 0, // Hapus garis Entry otomatis setelah order terbuka
   ENTRY_LINE_DISABLE = 1  // Ubah garis jadi abu-abu (_DONE) agar tidak entry dobel
};

enum ENUM_TOUCH_PRICE_MODE
{
   TOUCH_BID_CHART = 0,    // Harga Chart (Bid) — persis seperti garis candle di layar
   TOUCH_EXEC_SIDE = 1     // Harga Eksekusi (Ask untuk BUY/SL_SELL, Bid untuk SELL/SL_BUY)
};

enum ENUM_LINE_ROLE
{
   ROLE_NONE    = 0,
   ROLE_BUY     = 1,
   ROLE_SELL    = 2,
   ROLE_TP_ALL  = 3,
   ROLE_TP_BUY  = 4,
   ROLE_TP_SELL = 5,
   ROLE_SL_ALL  = 6,
   ROLE_SL_BUY  = 7,
   ROLE_SL_SELL = 8,
   ROLE_CLOSE   = 9,
   ROLE_ALERT   = 10       // Garis trendline/horizontal biasa -> hanya bunyi/alert tanpa order
};

input group "=== 1. LOT & MULTI-ORDER ==="
input double                  InpDefaultLot            = 0.01;              // Lot Default (bisa diubah langsung dari Panel Chart)
input double                  InpLotStepBtn            = 0.01;              // Kelipatan tombol [-] / [+] Lot di Panel
input int                     InpMaxOpenPositions      = 10;                // Maks posisi terbuka bersamaan (0 = tanpa batas)
input bool                    InpManageManualPositions = true;              // Garis TP/SL juga menutup posisi manual di simbol ini?

input group "=== 2. ATURAN SENTUHAN GARIS TREN (REAL-TIME TICK) ==="
input ENUM_TOUCH_PRICE_MODE   InpTouchPriceMode        = TOUCH_BID_CHART;   // Acuan harga sentuhan garis
input double                  InpTouchTolerancePts     = 0.0;               // Toleransi jarak sentuh (poin, 0 = tepat menyentuh)
input int                     InpDragCooldownSec       = 1;                 // Jeda aman (detik) setelah garis dibuat/digeser (0 = instan)
input ENUM_AFTER_ENTRY_ACTION InpAfterEntryAction      = ENTRY_LINE_DELETE; // Aksi pada garis Entry setelah order berhasil
input bool                    InpDeleteTPSLAfterHit    = true;              // Hapus garis TP/SL otomatis setelah menutup posisi?
input bool                    InpTPOnlyIfProfit        = false;             // True = garis "TP" umum hanya tutup yg profit; False = selalu tutup
input bool                    InpSLOnlyIfLoss          = false;             // False = garis "SL" bisa jadi Trailing SL saat profit!

input group "=== 3. STANDAR BENTUK GARIS TREN (TANPA RAY) ==="
input bool                    InpDefaultRayRight       = false;             // Ray Right pada garis baru (Default: False / Tanpa Ray)
input bool                    InpDefaultRayLeft        = false;             // Ray Left pada garis baru (Default: False / Tanpa Ray)
input int                     InpDefaultLineBars       = 15;                // Panjang garis baru ke kiri & kanan bar berjalan (bar)

input group "=== 4. BUNYI & ALERT GARIS TRENDLINE BIASA ==="
input bool                    InpAlertPlainLines       = true;              // Bunyikan suara saat SEMUA garis tren biasa terlewati?
input bool                    InpPlainLineRepeat       = false;             // False = bunyi 1x per garis; True = bunyi ulang jika dilewati lagi
input int                     InpPlainRepeatCooldownSec= 30;                // Jeda anti-spam (detik) jika bunyi ulang aktif
input bool                    InpPlainLinePopup        = true;              // Tampilkan pop-up Alert saat garis biasa terlewati?
input string                  InpSoundEntry            = "alert.wav";       // File suara saat garis BUY/SELL tersentuh
input string                  InpSoundClose            = "ok.wav";          // File suara saat garis TP/SL menutup posisi
input string                  InpSoundPlain            = "alert2.wav";      // File suara saat garis trendline biasa terlewati

input group "=== 5. BACKUP BROKER SL/TP DALAM USD (OPSIONAL) ==="
input bool                    InpUseBrokerSLTP         = false;             // Pasang SL/TP broker otomatis saat garis Entry tersentuh?
input double                  InpBrokerSLMoneyBase     = 3.0;               // SL Broker ($) untuk InpDefaultLot (proporsional jika lot beda)
input double                  InpBrokerTPMoneyBase     = 6.0;               // TP Broker ($) untuk InpDefaultLot (RR 1:2)
input double                  InpCommissionPerLot      = 0.0;               // Komisi per 1.00 lot (XM Std/UltraLow=0, XM Zero=7.0)

input group "=== 6. FILTER BROKER (XM READY) ==="
input int                     InpMaxSpreadPts          = 80;                // Spread maks untuk Entry baru (poin, 0=Off; TP/SL tidak diblokir)
input int                     InpSlippagePts           = 80;                // Toleransi Slippage (poin)
input int                     InpFastRetries           = 3;                 // Retry cepat (80ms) saat Requote/Off-Quotes
input long                    InpMagicNumber           = 990100;            // Magic Number EA

input group "=== 7. TAMPILAN PANEL & WARNA GARIS ==="
input bool                    InpShowPanel             = true;              // Tampilkan Panel Tombol 1-Klik di Chart
input int                     InpPanelX                = 14;                // Posisi X Panel
input int                     InpPanelY                = 24;                // Posisi Y Panel
input color                   InpColorBuy              = clrDodgerBlue;     // Warna Garis BUY
input color                   InpColorSell             = clrOrangeRed;      // Warna Garis SELL
input color                   InpColorTP               = clrLimeGreen;      // Warna Garis TP
input color                   InpColorSL               = clrGold;           // Warna Garis SL
input int                     InpLineWidth             = 2;                 // Ketebalan Garis Tren (1-5)
input bool                    InpEnableAlerts          = true;              // Pop-up Alert saat order/TP/SL tereksekusi?
input bool                    InpEnablePush            = false;             // Push Notification ke HP?

//+------------------------------------------------------------------+
//| [2] Konstanta UI & Struktur Pelacakan Garis                      |
//+------------------------------------------------------------------+
#define UI_PFX         "TLTM_UI_"
#define BTN_MINIMIZE   (UI_PFX + "BTN_MIN")
#define BTN_LOT_MINUS  (UI_PFX + "BTN_LMINUS")
#define BTN_LOT_PLUS   (UI_PFX + "BTN_LPLUS")
#define BTN_ADD_BUY    (UI_PFX + "BTN_BUY")
#define BTN_ADD_SELL   (UI_PFX + "BTN_SELL")
#define BTN_ADD_TP     (UI_PFX + "BTN_TP")
#define BTN_ADD_SL     (UI_PFX + "BTN_SL")
#define BTN_ADD_TPBUY  (UI_PFX + "BTN_TPB")
#define BTN_ADD_TPSELL (UI_PFX + "BTN_TPS")
#define BTN_ADD_SLBUY  (UI_PFX + "BTN_SLB")
#define BTN_ADD_SLSELL (UI_PFX + "BTN_SLS")
#define BTN_CLEAR_LN   (UI_PFX + "BTN_CLEAR")
#define BTN_CLOSE_ALL  (UI_PFX + "BTN_CLOSE")

struct SLineTrack
{
   string         name;
   ENUM_LINE_ROLE role;
   int            prevSide;      // +1 harga di atas garis, -1 harga di bawah garis, 0 belum terekam
   ulong          armedAfterMs;  // GetTickCount64() batas selesai cooldown geser/repeat
   double         lastLinePx;
   bool           seenThisPass;
};

//+------------------------------------------------------------------+
//| [3] Variabel Global                                              |
//+------------------------------------------------------------------+
CTrade      g_trade;
double      g_point          = 0.01;
int         g_digits         = 2;
double      g_activeLot      = 0.01;
bool        g_panelMinimized = false;
int         g_lineCounter    = 1;
string      g_lastStatusMsg  = "Siap — klik tombol atau gambar garis manual";
ulong       g_lastAlgoWarnMs = 0;
SLineTrack  g_tracks[];

int         g_cntBuyLines    = 0;
int         g_cntSellLines   = 0;
int         g_cntTPLines     = 0;
int         g_cntSLLines     = 0;
int         g_cntAlertLines  = 0;

//+------------------------------------------------------------------+
//| [4] Helper Umum, Suara & Lot                                     |
//+------------------------------------------------------------------+
int GetLotDigits(double stepLot)
{
   int dig = 0;
   double s = stepLot;
   while(dig < 8 && MathAbs(s - MathRound(s)) > 1e-8) { s *= 10.0; dig++; }
   return dig;
}

double NormalizeLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 0.01;

   int dig = GetLotDigits(stepLot);
   lot = MathMax(lot, minLot);
   if(maxLot > 0.0) lot = MathMin(lot, maxLot);
   return NormalizeDouble(MathRound(lot / stepLot) * stepLot, dig);
}

ENUM_ORDER_TYPE_FILLING GetOptimalFilling(string symbol)
{
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

bool RetcodeOK(uint code)
{
   return (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_PLACED);
}

bool IsRetryableRetcode(uint code)
{
   return (code == TRADE_RETCODE_REQUOTE       ||
           code == TRADE_RETCODE_PRICE_CHANGED ||
           code == TRADE_RETCODE_PRICE_OFF     ||
           code == TRADE_RETCODE_TIMEOUT       ||
           code == TRADE_RETCODE_CONNECTION    ||
           code == TRADE_RETCODE_TOO_MANY_REQUESTS);
}

void PlayAudioCue(const string wavFile)
{
   if(wavFile == "" || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   PlaySound(wavFile);
}

void NotifyStatus(string msg, bool showAlert = false, string soundFile = "")
{
   g_lastStatusMsg = TimeToString(TimeCurrent(), TIME_SECONDS) + " | " + msg;
   Print("[Trendline Master] ", msg);

   if(soundFile != "")
      PlayAudioCue(soundFile);

   if(showAlert && InpEnableAlerts && !MQLInfoInteger(MQL_OPTIMIZATION))
      Alert("[Trendline Master] ", _Symbol, " | ", msg);
   if(showAlert && InpEnablePush && !MQLInfoInteger(MQL_OPTIMIZATION))
      SendNotification("[Trendline Master] " + _Symbol + " | " + msg);
}

void WarnAlgoTradingOff(const string context)
{
   ulong nowMs = GetTickCount64();
   if(nowMs - g_lastAlgoWarnMs < 8000) return;
   g_lastAlgoWarnMs = nowMs;
   NotifyStatus("GAGAL " + context + ": Algo Trading OFF! Aktifkan tombol Algo Trading MT5!", true, "timeout.wav");
}

bool IsManagedPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   if(InpManageManualPositions) return true;
   return (PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}

int CountManagedPositions(int dirFilter = 0)
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsManagedPosition(t)) continue;
      long pType = PositionGetInteger(POSITION_TYPE);
      if(dirFilter == 1  && pType != POSITION_TYPE_BUY)  continue;
      if(dirFilter == -1 && pType != POSITION_TYPE_SELL) continue;
      cnt++;
   }
   return cnt;
}

double GetManagedFloatingPL()
{
   double pl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsManagedPosition(t)) continue;
      pl += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return pl;
}

//+------------------------------------------------------------------+
//| [5] Konversi SL/TP Broker Opsional (Nilai USD Bersih)            |
//+------------------------------------------------------------------+
double GetMoneyPerPriceUnit1Lot()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) bid = 1000.0;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double testStep = MathMax(g_point * 100.0, tickSize * 10.0);
   if(testStep <= 0.0) testStep = 1.0;

   double prof = 0.0;
   if(OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, bid, bid + testStep, prof) && prof > 0.0)
      return prof / testStep;

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickVal > 0.0 && tickSize > 0.0)
      return tickVal / tickSize;

   return 100.0;
}

void CalcOptionalBrokerSLTP(ENUM_POSITION_TYPE type, double lot, double entryPrice, double &outSL, double &outTP)
{
   outSL = 0.0;
   outTP = 0.0;
   if(!InpUseBrokerSLTP) return;

   double baseLot = NormalizeLot(InpDefaultLot);
   if(baseLot <= 0.0) baseLot = 0.01;

   double moneyPerPriceBase = GetMoneyPerPriceUnit1Lot() * baseLot;
   if(moneyPerPriceBase <= 0.0) return;

   double commBase = MathMax(0.0, InpCommissionPerLot) * baseLot;
   double stopLvl  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double spread   = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist  = stopLvl + spread + 2.0 * g_point;

   if(InpBrokerSLMoneyBase > 0.0)
   {
      double slDist = MathMax(0.01, InpBrokerSLMoneyBase - commBase) / moneyPerPriceBase;
      if(slDist < minDist) slDist = minDist;
      outSL = NormalizeDouble((type == POSITION_TYPE_BUY) ? (entryPrice - slDist) : (entryPrice + slDist), g_digits);
   }

   if(InpBrokerTPMoneyBase > 0.0)
   {
      double tpDist = MathMax(0.01, InpBrokerTPMoneyBase + commBase) / moneyPerPriceBase;
      if(tpDist < minDist) tpDist = minDist;
      outTP = NormalizeDouble((type == POSITION_TYPE_BUY) ? (entryPrice + tpDist) : (entryPrice - tpDist), g_digits);
   }
}

//+------------------------------------------------------------------+
//| [6] Deteksi Peran, Lot & Interpolasi Presisi Garis Miring        |
//+------------------------------------------------------------------+
bool HasToken(const string upperText, const string token)
{
   int pos = StringFind(upperText, token);
   while(pos >= 0)
   {
      bool leftOK  = (pos == 0);
      if(!leftOK)
      {
         ushort chL = StringGetCharacter(upperText, pos - 1);
         leftOK = !(chL >= 'A' && chL <= 'Z');
      }
      int endPos = pos + StringLen(token);
      bool rightOK = (endPos >= StringLen(upperText));
      if(!rightOK)
      {
         ushort chR = StringGetCharacter(upperText, endPos);
         rightOK = !(chR >= 'A' && chR <= 'Z');
      }
      if(leftOK && rightOK)
         return true;
      pos = StringFind(upperText, token, pos + 1);
   }
   return false;
}

ENUM_LINE_ROLE DetectLineRole(const string objName)
{
   if(StringFind(objName, UI_PFX) == 0)
      return ROLE_NONE;

   long objType = ObjectGetInteger(0, objName, OBJPROP_TYPE);
   if(objType != OBJ_TREND && objType != OBJ_HLINE)
      return ROLE_NONE;

   string desc = ObjectGetString(0, objName, OBJPROP_TEXT);
   string comb = objName + " " + desc;
   StringToUpper(comb);

   if(HasToken(comb, "DONE") || HasToken(comb, "USED") || HasToken(comb, "OFF") || HasToken(comb, "ALERTED"))
      return ROLE_NONE;

   if(HasToken(comb, "CLOSE") || HasToken(comb, "EXIT"))
      return ROLE_CLOSE;

   if(HasToken(comb, "TPBUY"))  return ROLE_TP_BUY;
   if(HasToken(comb, "TPSELL")) return ROLE_TP_SELL;
   if(HasToken(comb, "SLBUY"))  return ROLE_SL_BUY;
   if(HasToken(comb, "SLSELL")) return ROLE_SL_SELL;

   bool isTP   = HasToken(comb, "TP") || HasToken(comb, "TAKEPROFIT");
   bool isSL   = HasToken(comb, "SL") || HasToken(comb, "STOPLOSS");
   bool isBuy  = HasToken(comb, "BUY")  || HasToken(comb, "LONG");
   bool isSell = HasToken(comb, "SELL") || HasToken(comb, "SHORT");

   if(isTP)
   {
      if(isBuy && !isSell) return ROLE_TP_BUY;
      if(isSell && !isBuy) return ROLE_TP_SELL;
      return ROLE_TP_ALL;
   }

   if(isSL)
   {
      if(isBuy && !isSell) return ROLE_SL_BUY;
      if(isSell && !isBuy) return ROLE_SL_SELL;
      return ROLE_SL_ALL;
   }

   if(isBuy && !isSell) return ROLE_BUY;
   if(isSell && !isBuy) return ROLE_SELL;

   if(HasToken(comb, "ALERT") || HasToken(comb, "BELL") || InpAlertPlainLines)
      return ROLE_ALERT;

   return ROLE_NONE;
}

double ParseLineLot(const string objName)
{
   string desc = ObjectGetString(0, objName, OBJPROP_TEXT);
   string src  = desc + " " + objName;
   int    len  = StringLen(src);

   for(int i = 0; i < len; i++)
   {
      ushort ch = StringGetCharacter(src, i);
      if(ch >= '0' && ch <= '9')
      {
         int start = i;
         bool hasDot = false;
         while(i < len)
         {
            ushort c2 = StringGetCharacter(src, i);
            if(c2 >= '0' && c2 <= '9') { i++; continue; }
            if(c2 == '.' && !hasDot)   { hasDot = true; i++; continue; }
            break;
         }
         if(hasDot)
         {
            string tok = StringSubstr(src, start, i - start);
            double val = StringToDouble(tok);
            if(val > 0.0)
               return NormalizeLot(val);
         }
      }
   }

   return NormalizeLot(g_activeLot);
}

// Konversi waktu titik anchor ke koordinat bar-index kontinu (0.0 = bar berjalan, <0 masa lalu, >0 masa depan)
// Persis mengikuti cara MT5 menggambar garis miring di layar (kebal jeda weekend/rollover & anchor masa depan!)
bool TimeToBarFloat(datetime t, datetime bar0Time, int periodSec, double &outBarIdx)
{
   if(t <= 0 || bar0Time <= 0 || periodSec <= 0)
      return false;

   if(t == bar0Time)
   {
      outBarIdx = 0.0;
      return true;
   }

   if(t > bar0Time)
   {
      outBarIdx = (double)(t - bar0Time) / (double)periodSec;
      return true;
   }

   int shift = iBarShift(_Symbol, PERIOD_CURRENT, t, false);
   if(shift < 0)
      return false;

   datetime barT = iTime(_Symbol, PERIOD_CURRENT, shift);
   double   frac = (double)(t - barT) / (double)periodSec;
   if(frac < 0.0) frac = 0.0;
   if(frac > 1.0) frac = 1.0;

   outBarIdx = -(double)shift + frac;
   return true;
}

// Hitung harga garis tren persis di posisi visual candle berjalan (bar 0)
// outRangeState: 0 = aktif di bar 0, -1 = segmen berakhir di masa lalu, +1 = segmen belum dimulai (masih di kanan)
double GetLineCurrentPrice(const string objName, int &outRangeState)
{
   outRangeState = 0;

   long objType = ObjectGetInteger(0, objName, OBJPROP_TYPE);
   if(objType == OBJ_HLINE)
      return ObjectGetDouble(0, objName, OBJPROP_PRICE);

   if(objType != OBJ_TREND)
      return 0.0;

   datetime t1 = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
   double   p1 = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 1);
   double   p2 = ObjectGetDouble(0, objName, OBJPROP_PRICE, 1);

   if(p1 <= 0.0 || p2 <= 0.0)
      return 0.0;

   bool rayRight = (bool)ObjectGetInteger(0, objName, OBJPROP_RAY_RIGHT);
   bool rayLeft  = (bool)ObjectGetInteger(0, objName, OBJPROP_RAY_LEFT);

   datetime bar0Time  = iTime(_Symbol, PERIOD_CURRENT, 0);
   int      periodSec = PeriodSeconds(PERIOD_CURRENT);

   double idx1 = 0.0, idx2 = 0.0;
   if(TimeToBarFloat(t1, bar0Time, periodSec, idx1) && TimeToBarFloat(t2, bar0Time, periodSec, idx2))
   {
      double leftIdx  = MathMin(idx1, idx2);
      double rightIdx = MathMax(idx1, idx2);

      // Cek apakah candle berjalan (bar 0) berada dalam rentang garis (penting untuk garis tanpa Ray!)
      if(!rayRight && rightIdx < -0.5)
      {
         outRangeState = -1; // Ujung kanan garis sudah lewat di belakang bar 0
         return 0.0;
      }
      if(!rayLeft && leftIdx > 0.5)
      {
         outRangeState = 1;  // Seluruh garis masih di sebelah kanan bar 0
         return 0.0;
      }

      double dIdx = idx2 - idx1;
      if(MathAbs(dIdx) < 1e-6)
      {
         // Kedua titik pada bar yang sama (garis vertikal) -> pakai rata-rata harga
         return (p1 + p2) * 0.5;
      }

      double frac = (0.0 - idx1) / dIdx;
      // Jika tanpa Ray dan bar 0 berada di margin ujung +-0.5 bar, jepit tepat ke harga ujung garis
      if(!rayLeft && !rayRight)
      {
         if(frac < 0.0) frac = 0.0;
         if(frac > 1.0) frac = 1.0;
      }

      return NormalizeDouble(p1 + (p2 - p1) * frac, g_digits);
   }

   // Fallback jika iBarShift belum siap
   double fallbackP = (bar0Time > 0) ? ObjectGetValueByTime(0, objName, bar0Time, 0) : 0.0;
   if(fallbackP <= 0.0)
      fallbackP = ObjectGetValueByTime(0, objName, TimeCurrent(), 0);
   return fallbackP;
}

double GetReferencePriceForRole(ENUM_LINE_ROLE role)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(InpTouchPriceMode == TOUCH_BID_CHART || role == ROLE_ALERT)
      return bid;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(role == ROLE_BUY || role == ROLE_SL_SELL || role == ROLE_TP_SELL)
      return ask;
   return bid;
}

//+------------------------------------------------------------------+
//| [7] Manajemen Array Tracking Garis (Anti-Misfire saat Geser)     |
//+------------------------------------------------------------------+
int FindTrackIndex(const string name)
{
   int n = ArraySize(g_tracks);
   for(int i = 0; i < n; i++)
      if(g_tracks[i].name == name) return i;
   return -1;
}

void ArmOrResetTrack(const string name, ENUM_LINE_ROLE role, int customCooldownSec = -1)
{
   int rangeState = 0;
   double lp = GetLineCurrentPrice(name, rangeState);
   double rp = GetReferencePriceForRole(role);
   int side  = 0;
   if(lp > 0.0 && rp > 0.0)
   {
      if(rp > lp)      side =  1;
      else if(rp < lp) side = -1;
   }

   int sec = (customCooldownSec >= 0) ? customCooldownSec : MathMax(0, InpDragCooldownSec);
   ulong armAt = GetTickCount64() + (ulong)sec * 1000;

   int idx = FindTrackIndex(name);
   if(idx < 0)
   {
      idx = ArraySize(g_tracks);
      ArrayResize(g_tracks, idx + 1);
      g_tracks[idx].name = name;
   }
   g_tracks[idx].role         = role;
   g_tracks[idx].prevSide     = side;
   g_tracks[idx].armedAfterMs = armAt;
   g_tracks[idx].lastLinePx   = lp;
   g_tracks[idx].seenThisPass = true;
}

void RemoveTrackByIndex(int idx)
{
   int n = ArraySize(g_tracks);
   if(idx < 0 || idx >= n) return;
   for(int i = idx; i < n - 1; i++)
      g_tracks[i] = g_tracks[i + 1];
   ArrayResize(g_tracks, n - 1);
}

void FinalizeTriggeredLine(const string objName, bool isEntryLine)
{
   bool shouldDelete = isEntryLine ? (InpAfterEntryAction == ENTRY_LINE_DELETE) : InpDeleteTPSLAfterHit;
   if(shouldDelete)
   {
      ObjectDelete(0, objName);
   }
   else
   {
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDimGray);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_SELECTED, false);
      string oldDesc = ObjectGetString(0, objName, OBJPROP_TEXT);
      ObjectSetString(0, objName, OBJPROP_TEXT, oldDesc + " [DONE]");
   }

   int idx = FindTrackIndex(objName);
   if(idx >= 0) RemoveTrackByIndex(idx);
   ChartRedraw(0);
}

void TriggerPlainLineAlert(const string objName, double linePx, double refPx)
{
   string dir = (refPx >= linePx) ? "NAIK menembus" : "TURUN menembus";
   string msg = StringFormat("GARIS TREN TERLEWATI: %s (%s @ %.*f)", objName, dir, g_digits, linePx);

   g_lastStatusMsg = TimeToString(TimeCurrent(), TIME_SECONDS) + " | " + msg;
   Print("[Trendline Master] ", msg);

   PlayAudioCue(InpSoundPlain);

   if(InpPlainLinePopup && !MQLInfoInteger(MQL_OPTIMIZATION))
      Alert("[Trendline Master] ", _Symbol, " | ", msg);
   if(InpEnablePush && !MQLInfoInteger(MQL_OPTIMIZATION))
      SendNotification("[Trendline Master] " + _Symbol + " | " + msg);

   if(!InpPlainLineRepeat)
   {
      string oldDesc = ObjectGetString(0, objName, OBJPROP_TEXT);
      string newDesc = (oldDesc == "") ? "[ALERTED]" : (oldDesc + " [ALERTED]");
      ObjectSetString(0, objName, OBJPROP_TEXT, newDesc);
      int idx = FindTrackIndex(objName);
      if(idx >= 0) RemoveTrackByIndex(idx);
      ChartRedraw(0);
   }
   else
   {
      ArmOrResetTrack(objName, ROLE_ALERT, MathMax(3, InpPlainRepeatCooldownSec));
   }
}

//+------------------------------------------------------------------+
//| [8] Eksekusi Order & Penutupan Posisi (XM Fast-Retry Ready)      |
//+------------------------------------------------------------------+
bool ExecuteTrendlineEntry(ENUM_POSITION_TYPE type, double lot, const string lineName, double linePrice)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      WarnAlgoTradingOff("ORDER " + lineName);
      return false;
   }

   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
   {
      NotifyStatus("GAGAL: Simbol ini tidak mendukung open posisi (cek simbol XM)!", true, "timeout.wav");
      return false;
   }

   if(InpMaxOpenPositions > 0 && CountManagedPositions(0) >= InpMaxOpenPositions)
   {
      NotifyStatus(StringFormat("Lewati %s: batas maks %d posisi tercapai", lineName, InpMaxOpenPositions), false);
      return false;
   }

   if(InpMaxSpreadPts > 0)
   {
      double spPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
      if(spPts > InpMaxSpreadPts)
      {
         NotifyStatus(StringFormat("Lewati %s: spread %.0f > batas %d pts", lineName, spPts, InpMaxSpreadPts), false);
         return false;
      }
   }

   lot = NormalizeLot(lot);
   int maxTry = MathMax(0, InpFastRetries);
   string dirTxt = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
   string cmt    = StringFormat("TL_%s %.2f", dirTxt, lot);

   for(int attempt = 0; attempt <= maxTry && !IsStopped(); attempt++)
   {
      if(attempt > 0 && !MQLInfoInteger(MQL_TESTER))
         Sleep(80);

      double px = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = 0.0, tp = 0.0;
      CalcOptionalBrokerSLTP(type, lot, px, sl, tp);

      g_trade.SetExpertMagicNumber(InpMagicNumber);
      g_trade.SetDeviationInPoints(InpSlippagePts);
      g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

      bool ok = (type == POSITION_TYPE_BUY)
                ? g_trade.Buy(lot, _Symbol, px, sl, tp, cmt)
                : g_trade.Sell(lot, _Symbol, px, sl, tp, cmt);

      uint rc = g_trade.ResultRetcode();
      if(ok && RetcodeOK(rc))
      {
         double fillPx = (g_trade.ResultPrice() > 0.0) ? g_trade.ResultPrice() : px;
         NotifyStatus(StringFormat("ORDER %s %.2f @ %.*f (sentuh %s @ %.*f)",
                                   dirTxt, lot, g_digits, fillPx, lineName, g_digits, linePrice),
                      true, InpSoundEntry);
         return true;
      }

      if(attempt < maxTry && IsRetryableRetcode(rc))
         continue;

      NotifyStatus(StringFormat("GAGAL %s %.2f (%s) kode %u: %s",
                                dirTxt, lot, lineName, rc, g_trade.ResultRetcodeDescription()),
                   true, "timeout.wav");
      return false;
   }

   return false;
}

int ClosePositionsByTrendline(ENUM_LINE_ROLE role, const string lineName, double linePrice)
{
   int matchingCnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsManagedPosition(ticket)) continue;
      long   pType  = PositionGetInteger(POSITION_TYPE);
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      bool match = false;
      switch(role)
      {
         case ROLE_CLOSE:   match = true; break;
         case ROLE_TP_BUY:  match = (pType == POSITION_TYPE_BUY);  break;
         case ROLE_TP_SELL: match = (pType == POSITION_TYPE_SELL); break;
         case ROLE_TP_ALL:  match = InpTPOnlyIfProfit ? (profit >= 0.0) : true; break;
         case ROLE_SL_BUY:  match = (pType == POSITION_TYPE_BUY);  break;
         case ROLE_SL_SELL: match = (pType == POSITION_TYPE_SELL); break;
         case ROLE_SL_ALL:  match = InpSLOnlyIfLoss   ? (profit <= 0.0) : true; break;
         default:           match = false; break;
      }
      if(match) matchingCnt++;
   }

   if(matchingCnt == 0)
      return 0;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      WarnAlgoTradingOff("CLOSE " + lineName);
      return -1;
   }

   int closedCnt = 0;
   double closedPL = 0.0;
   int maxTry = MathMax(0, InpFastRetries);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsManagedPosition(ticket)) continue;

      long   pType  = PositionGetInteger(POSITION_TYPE);
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      bool match = false;
      switch(role)
      {
         case ROLE_CLOSE:   match = true; break;
         case ROLE_TP_BUY:  match = (pType == POSITION_TYPE_BUY);  break;
         case ROLE_TP_SELL: match = (pType == POSITION_TYPE_SELL); break;
         case ROLE_TP_ALL:  match = InpTPOnlyIfProfit ? (profit >= 0.0) : true; break;
         case ROLE_SL_BUY:  match = (pType == POSITION_TYPE_BUY);  break;
         case ROLE_SL_SELL: match = (pType == POSITION_TYPE_SELL); break;
         case ROLE_SL_ALL:  match = InpSLOnlyIfLoss   ? (profit <= 0.0) : true; break;
         default:           match = false; break;
      }

      if(!match) continue;

      for(int attempt = 0; attempt <= maxTry && !IsStopped(); attempt++)
      {
         if(attempt > 0 && !MQLInfoInteger(MQL_TESTER))
            Sleep(80);

         g_trade.SetExpertMagicNumber(InpMagicNumber);
         g_trade.SetDeviationInPoints(InpSlippagePts);
         g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

         if(g_trade.PositionClose(ticket, InpSlippagePts) && RetcodeOK(g_trade.ResultRetcode()))
         {
            closedCnt++;
            closedPL += profit;
            break;
         }

         if(!IsRetryableRetcode(g_trade.ResultRetcode()))
            break;
      }
   }

   if(closedCnt > 0)
   {
      string tag = (role == ROLE_SL_ALL || role == ROLE_SL_BUY || role == ROLE_SL_SELL) ? "SL GARIS"
                 : (role == ROLE_CLOSE ? "CLOSE GARIS" : "TP GARIS");
      NotifyStatus(StringFormat("%s tersentuh (%s @ %.*f) -> Tutup %d posisi ($%+.2f)",
                                tag, lineName, g_digits, linePrice, closedCnt, closedPL),
                   true, InpSoundClose);
   }

   return closedCnt;
}

//+------------------------------------------------------------------+
//| [9] Pemindaian Real-Time Seluruh Garis Tren di Chart             |
//+------------------------------------------------------------------+
void ScanAndProcessTrendlines()
{
   ulong  nowMs = GetTickCount64();
   double tolPx = MathMax(0.0, InpTouchTolerancePts) * g_point;

   int tCount = ArraySize(g_tracks);
   for(int k = 0; k < tCount; k++)
      g_tracks[k].seenThisPass = false;

   g_cntBuyLines   = 0;
   g_cntSellLines  = 0;
   g_cntTPLines    = 0;
   g_cntSLLines    = 0;
   g_cntAlertLines = 0;

   string         activeNames[];
   ENUM_LINE_ROLE activeRoles[];
   int found = 0;

   int totalObj = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < totalObj; i++)
   {
      string objName = ObjectName(0, i, 0, -1);
      if(objName == "") continue;

      ENUM_LINE_ROLE role = DetectLineRole(objName);
      if(role == ROLE_NONE) continue;

      ArrayResize(activeNames, found + 1);
      ArrayResize(activeRoles, found + 1);
      activeNames[found] = objName;
      activeRoles[found] = role;
      found++;

      if(role == ROLE_BUY)                                                        g_cntBuyLines++;
      else if(role == ROLE_SELL)                                                  g_cntSellLines++;
      else if(role == ROLE_TP_ALL || role == ROLE_TP_BUY || role == ROLE_TP_SELL) g_cntTPLines++;
      else if(role == ROLE_ALERT)                                                 g_cntAlertLines++;
      else                                                                        g_cntSLLines++;
   }

   static ulong lastTipMs = 0;
   bool updateTips = (nowMs - lastTipMs >= 1000);
   if(updateTips) lastTipMs = nowMs;

   for(int i = 0; i < found; i++)
   {
      string         name = activeNames[i];
      ENUM_LINE_ROLE role = activeRoles[i];

      int    rangeState = 0;
      double linePx     = GetLineCurrentPrice(name, rangeState);
      if(linePx <= 0.0)
      {
         if(updateTips)
         {
            string tip = (rangeState < 0)
                         ? (name + " [TIDAK AKTIF: ujung kanan garis sudah lewat di belakang candle berjalan]")
                         : (name + " [MENUNGGU: garis masih di depan/kanan candle berjalan]");
            ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
         }
         continue;
      }

      double refPx = GetReferencePriceForRole(role);
      if(refPx <= 0.0) continue;

      int idx = FindTrackIndex(name);
      if(idx < 0)
      {
         ArmOrResetTrack(name, role);
         continue;
      }

      g_tracks[idx].seenThisPass = true;
      g_tracks[idx].role         = role;
      g_tracks[idx].lastLinePx   = linePx;

      if(updateTips)
      {
         string stateTxt = (nowMs < g_tracks[idx].armedAfterMs) ? "COOLDOWN" : "SIAGA";
         ObjectSetString(0, name, OBJPROP_TOOLTIP,
                         StringFormat("%s | Harga di Bar 0: %.*f [%s]", name, g_digits, linePx, stateTxt));
      }

      if(nowMs < g_tracks[idx].armedAfterMs)
      {
         if(refPx > linePx)      g_tracks[idx].prevSide =  1;
         else if(refPx < linePx) g_tracks[idx].prevSide = -1;
         continue;
      }

      int prevSide = g_tracks[idx].prevSide;
      if(prevSide == 0)
      {
         if(refPx > linePx)      g_tracks[idx].prevSide =  1;
         else if(refPx < linePx) g_tracks[idx].prevSide = -1;
         continue;
      }

      // Deteksi sentuhan real-time (atas->bawah maupun bawah->atas)
      bool touched = false;
      if(prevSide == 1 && refPx <= linePx + tolPx)
         touched = true;
      else if(prevSide == -1 && refPx >= linePx - tolPx)
         touched = true;

      if(!touched)
      {
         if(refPx > linePx + tolPx)      g_tracks[idx].prevSide =  1;
         else if(refPx < linePx - tolPx) g_tracks[idx].prevSide = -1;
         continue;
      }

      // --- GARIS TERSENTUH! EKSEKUSI SESUAI PERAN ---
      if(role == ROLE_ALERT)
      {
         TriggerPlainLineAlert(name, linePx, refPx);
      }
      else if(role == ROLE_BUY || role == ROLE_SELL)
      {
         double lot = ParseLineLot(name);
         ENUM_POSITION_TYPE pType = (role == ROLE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         if(ExecuteTrendlineEntry(pType, lot, name, linePx))
            FinalizeTriggeredLine(name, true);
         else
            ArmOrResetTrack(name, role, 3);
      }
      else
      {
         int res = ClosePositionsByTrendline(role, name, linePx);
         if(res > 0)
         {
            FinalizeTriggeredLine(name, false);
         }
         else if(res == -1)
         {
            g_tracks[idx].armedAfterMs = nowMs + 3000;
         }
         else
         {
            if(refPx > linePx)      g_tracks[idx].prevSide =  1;
            else if(refPx < linePx) g_tracks[idx].prevSide = -1;
         }
      }
   }

   for(int k = ArraySize(g_tracks) - 1; k >= 0; k--)
   {
      if(!g_tracks[k].seenThisPass)
         RemoveTrackByIndex(k);
   }
}

//+------------------------------------------------------------------+
//| [10] Pembuat Garis Tren 1-Klik Standar (Tanpa Ray Left/Right)    |
//+------------------------------------------------------------------+
void SpawnTrendline(ENUM_LINE_ROLE role)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) return;

   double chartMax = ChartGetDouble(0, CHART_PRICE_MAX, 0);
   double chartMin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   double visRange = chartMax - chartMin;
   double offset   = (visRange > 0.0) ? (visRange * 0.14) : (g_point * 200.0);

   double stagger  = offset * 0.22 * ((g_lineCounter - 1) % 4);
   offset += stagger;

   bool placeAbove = true;
   string tag      = "BUY";
   string desc     = "";
   color  clr      = InpColorBuy;

   switch(role)
   {
      case ROLE_BUY:
         placeAbove = false;
         tag  = "BUY";
         desc = StringFormat("BUY %.2f", g_activeLot);
         clr  = InpColorBuy;
         break;
      case ROLE_SELL:
         placeAbove = true;
         tag  = "SELL";
         desc = StringFormat("SELL %.2f", g_activeLot);
         clr  = InpColorSell;
         break;
      case ROLE_TP_ALL:
         placeAbove = true;
         tag  = "TP";
         desc = "TP";
         clr  = InpColorTP;
         break;
      case ROLE_TP_BUY:
         placeAbove = true;
         tag  = "TP_BUY";
         desc = "TP BUY";
         clr  = InpColorTP;
         break;
      case ROLE_TP_SELL:
         placeAbove = false;
         tag  = "TP_SELL";
         desc = "TP SELL";
         clr  = InpColorTP;
         break;
      case ROLE_SL_ALL:
         placeAbove = false;
         tag  = "SL";
         desc = "SL";
         clr  = InpColorSL;
         break;
      case ROLE_SL_BUY:
         placeAbove = false;
         tag  = "SL_BUY";
         desc = "SL BUY";
         clr  = InpColorSL;
         break;
      case ROLE_SL_SELL:
         placeAbove = true;
         tag  = "SL_SELL";
         desc = "SL SELL";
         clr  = InpColorSL;
         break;
      default:
         return;
   }

   double   pBase = NormalizeDouble(placeAbove ? (bid + offset) : (bid - offset), g_digits);
   int      sec   = MathMax(60, PeriodSeconds(PERIOD_CURRENT));
   int      bars  = MathMax(3, InpDefaultLineBars);
   datetime t0    = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t0 <= 0) t0 = TimeCurrent();

   // Gunakan bar historis asli di kiri dan jarak bar rapi di kanan (tanpa Ray Left & tanpa Ray Right)
   datetime t1 = iTime(_Symbol, PERIOD_CURRENT, MathMin(bars, MathMax(1, iBars(_Symbol, PERIOD_CURRENT) - 1)));
   if(t1 <= 0) t1 = t0 - (datetime)(sec * bars);
   datetime t2 = t0 + (datetime)(sec * bars);

   string objName = StringFormat("TL_%s_%d", tag, g_lineCounter++);
   while(ObjectFind(0, objName) >= 0)
      objName = StringFormat("TL_%s_%d", tag, g_lineCounter++);

   if(!ObjectCreate(0, objName, OBJ_TREND, 0, t1, pBase, t2, pBase))
   {
      NotifyStatus("Gagal membuat garis " + objName, false);
      return;
   }

   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, MathMax(1, MathMin(5, InpLineWidth)));
   ObjectSetInteger(0, objName, OBJPROP_STYLE, (role == ROLE_BUY || role == ROLE_SELL) ? STYLE_SOLID : STYLE_DASH);
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, InpDefaultRayRight); // Standar: False (Tanpa Ray Right)
   ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT,  InpDefaultRayLeft);  // Standar: False (Tanpa Ray Left)
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetString(0, objName, OBJPROP_TEXT, desc);
   ObjectSetString(0, objName, OBJPROP_TOOLTIP, desc + " — geser titik kiri/kanan (ujung kanan wajib melewati candle berjalan)");

   ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, true);

   ArmOrResetTrack(objName, role);
   NotifyStatus(StringFormat("Garis %s dibuat (%s, tanpa Ray) — geser ke posisi tren Anda", objName, desc), false);
   ChartRedraw(0);
}

void ClearAllTrendlines()
{
   int delCnt = 0;
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(name == "" || StringFind(name, UI_PFX) == 0) continue;
      ENUM_LINE_ROLE role = DetectLineRole(name);
      if(StringFind(name, "TL_") == 0 || (role != ROLE_NONE && role != ROLE_ALERT))
      {
         ObjectDelete(0, name);
         delCnt++;
      }
   }
   ArrayResize(g_tracks, 0);
   NotifyStatus(StringFormat("Menghapus %d garis order/TP/SL dari chart", delCnt), false);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| [11] Panel Kontrol 1-Klik di Chart                               |
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void CreateLabel(string name, int x, int y, string text, color clr, int fontSize = 8, string font = "Segoe UI")
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color txtClr, int fontSize = 8)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'55,65,81');
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DestroyPanel()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, UI_PFX) == 0)
         ObjectDelete(0, name);
   }
}

void RenderPanel()
{
   if(!InpShowPanel || MQLInfoInteger(MQL_OPTIMIZATION))
      return;

   int x = InpPanelX;
   int y = InpPanelY;
   int w = 272;
   int h = g_panelMinimized ? 30 : 288;

   bool algoOK = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED));

   CreateRect(UI_PFX + "BG", x, y, w, h, C'17,24,39', algoOK ? C'55,65,81' : clrRed);
   CreateRect(UI_PFX + "HDR", x, y, w, 30, algoOK ? C'30,41,59' : C'127,29,29', C'55,65,81');
   CreateLabel(UI_PFX + "TITLE", x + 10, y + 7,
               algoOK ? "TRENDLINE TRADE MASTER v1.2" : "ALGO TRADING OFF! NYALAKAN",
               clrWhite, 9, "Segoe UI Bold");
   CreateButton(BTN_MINIMIZE, x + w - 28, y + 4, 22, 22, g_panelMinimized ? "+" : "-", C'51,65,85', clrWhite, 9);

   if(g_panelMinimized)
   {
      string bodyNames[] = {
         UI_PFX+"LBL_LOT", BTN_LOT_MINUS, UI_PFX+"VAL_LOT", BTN_LOT_PLUS,
         BTN_ADD_BUY, BTN_ADD_SELL, BTN_ADD_TP, BTN_ADD_SL,
         BTN_ADD_TPBUY, BTN_ADD_TPSELL, BTN_ADD_SLBUY, BTN_ADD_SLSELL,
         BTN_CLEAR_LN, BTN_CLOSE_ALL,
         UI_PFX+"INF1", UI_PFX+"INF2", UI_PFX+"INF3", UI_PFX+"INF4"
      };
      for(int i = 0; i < ArraySize(bodyNames); i++)
         ObjectDelete(0, bodyNames[i]);
      ChartRedraw(0);
      return;
   }

   int rowY = y + 38;
   CreateLabel(UI_PFX + "LBL_LOT", x + 10, rowY + 4, "Lot Garis Baru:", C'148,163,184', 8);
   CreateButton(BTN_LOT_MINUS, x + 114, rowY, 28, 22, "-", C'51,65,85', clrWhite, 9);
   CreateLabel(UI_PFX + "VAL_LOT", x + 152, rowY + 3, DoubleToString(g_activeLot, 2), clrYellow, 9, "Segoe UI Bold");
   CreateButton(BTN_LOT_PLUS, x + 210, rowY, 28, 22, "+", C'51,65,85', clrWhite, 9);

   rowY += 30;
   CreateButton(BTN_ADD_BUY,  x + 10,  rowY, 122, 28, "+ Garis BUY",  C'29,78,216',  clrWhite, 8);
   CreateButton(BTN_ADD_SELL, x + 140, rowY, 122, 28, "+ Garis SELL", C'185,28,28',  clrWhite, 8);

   rowY += 34;
   CreateButton(BTN_ADD_TP,   x + 10,  rowY, 122, 26, "+ Garis TP",   C'21,128,61',  clrWhite, 8);
   CreateButton(BTN_ADD_SL,   x + 140, rowY, 122, 26, "+ Garis SL",   C'180,83,9',   clrWhite, 8);

   rowY += 32;
   CreateButton(BTN_ADD_TPBUY,  x + 10,  rowY, 59, 22, "TP BUY",  C'20,83,45',  C'187,247,208', 7);
   CreateButton(BTN_ADD_TPSELL, x + 73,  rowY, 59, 22, "TP SELL", C'20,83,45',  C'187,247,208', 7);
   CreateButton(BTN_ADD_SLBUY,  x + 140, rowY, 59, 22, "SL BUY",  C'120,53,15', C'254,240,138', 7);
   CreateButton(BTN_ADD_SLSELL, x + 203, rowY, 59, 22, "SL SELL", C'120,53,15', C'254,240,138', 7);

   rowY += 30;
   CreateButton(BTN_CLEAR_LN,  x + 10,  rowY, 122, 24, "Hapus Garis", C'51,65,85',  C'226,232,240', 8);
   CreateButton(BTN_CLOSE_ALL, x + 140, rowY, 122, 24, "Close All",   C'127,29,29', C'254,202,202', 8);

   rowY += 32;
   double spPts  = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   int    posCnt = CountManagedPositions(0);
   double fltPL  = GetManagedFloatingPL();

   CreateLabel(UI_PFX + "INF1", x + 10, rowY,
               StringFormat("BUY:%d | SELL:%d | TP:%d | SL:%d | Bell:%d",
                            g_cntBuyLines, g_cntSellLines, g_cntTPLines, g_cntSLLines, g_cntAlertLines),
               C'203,213,225', 8);
   CreateLabel(UI_PFX + "INF2", x + 10, rowY + 17,
               StringFormat("Posisi: %d | Float: $%+.2f | Spread: %.0f pts", posCnt, fltPL, spPts),
               (fltPL >= 0.0) ? C'134,239,172' : C'252,165,165', 8);
   CreateLabel(UI_PFX + "INF3", x + 10, rowY + 34,
               algoOK ? ("Algo: ON | Garis: Tanpa Ray | Bell: " + (InpAlertPlainLines ? "ON" : "OFF"))
                      : "PERINGATAN: Algo Trading OFF! Cek toolbar MT5",
               algoOK ? C'148,163,184' : clrRed, 7);

   string shortMsg = (StringLen(g_lastStatusMsg) > 43) ? (StringSubstr(g_lastStatusMsg, 0, 40) + "...") : g_lastStatusMsg;
   CreateLabel(UI_PFX + "INF4", x + 10, rowY + 51, shortMsg, clrGold, 7);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| [12] Event Handler MT5                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_point     = _Point;
   g_digits    = _Digits;
   g_activeLot = NormalizeLot(InpDefaultLot);

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePts);
   g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

   ArrayResize(g_tracks, 0);

   int totalObj = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < totalObj; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      ENUM_LINE_ROLE role = DetectLineRole(name);
      if(role != ROLE_NONE)
         ArmOrResetTrack(name, role, 0);
   }

   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      EventSetTimer(1);

   RenderPanel();
   PrintFormat("=== Trendline Trade Master v1.20 Aktif | %s | Lot=%.2f | Ray=%s/%s | PlainAlert=%s ===",
               _Symbol, g_activeLot,
               InpDefaultRayLeft ? "L" : "NoL",
               InpDefaultRayRight ? "R" : "NoR",
               InpAlertPlainLines ? "ON" : "OFF");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DestroyPanel();
   Print("=== Trendline Trade Master v1.20 Dihentikan ===");
}

void OnTick()
{
   ScanAndProcessTrendlines();

   static uint lastUiMs = 0;
   uint now = GetTickCount();
   if(now - lastUiMs >= 300)
   {
      lastUiMs = now;
      RenderPanel();
   }
}

void OnTimer()
{
   RenderPanel();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CHANGE)
   {
      if(StringFind(sparam, UI_PFX) == 0) return;
      ENUM_LINE_ROLE role = DetectLineRole(sparam);
      if(role != ROLE_NONE)
      {
         ArmOrResetTrack(sparam, role);
         RenderPanel();
      }
      return;
   }

   if(id == CHARTEVENT_OBJECT_DELETE)
   {
      int idx = FindTrackIndex(sparam);
      if(idx >= 0) RemoveTrackByIndex(idx);
      RenderPanel();
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(StringFind(sparam, UI_PFX) != 0) return;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);

      if(sparam == BTN_MINIMIZE)
      {
         g_panelMinimized = !g_panelMinimized;
         RenderPanel();
         return;
      }
      if(sparam == BTN_LOT_MINUS)
      {
         double step = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), InpLotStepBtn);
         g_activeLot = NormalizeLot(g_activeLot - step);
         RenderPanel();
         return;
      }
      if(sparam == BTN_LOT_PLUS)
      {
         double step = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), InpLotStepBtn);
         g_activeLot = NormalizeLot(g_activeLot + step);
         RenderPanel();
         return;
      }
      if(sparam == BTN_ADD_BUY)    { SpawnTrendline(ROLE_BUY);     RenderPanel(); return; }
      if(sparam == BTN_ADD_SELL)   { SpawnTrendline(ROLE_SELL);    RenderPanel(); return; }
      if(sparam == BTN_ADD_TP)     { SpawnTrendline(ROLE_TP_ALL);  RenderPanel(); return; }
      if(sparam == BTN_ADD_SL)     { SpawnTrendline(ROLE_SL_ALL);  RenderPanel(); return; }
      if(sparam == BTN_ADD_TPBUY)  { SpawnTrendline(ROLE_TP_BUY);  RenderPanel(); return; }
      if(sparam == BTN_ADD_TPSELL) { SpawnTrendline(ROLE_TP_SELL); RenderPanel(); return; }
      if(sparam == BTN_ADD_SLBUY)  { SpawnTrendline(ROLE_SL_BUY);  RenderPanel(); return; }
      if(sparam == BTN_ADD_SLSELL) { SpawnTrendline(ROLE_SL_SELL); RenderPanel(); return; }
      if(sparam == BTN_CLEAR_LN)   { ClearAllTrendlines();         RenderPanel(); return; }
      if(sparam == BTN_CLOSE_ALL)
      {
         int cnt = ClosePositionsByTrendline(ROLE_CLOSE, "BTN_CLOSE_ALL", SymbolInfoDouble(_Symbol, SYMBOL_BID));
         if(cnt == 0) NotifyStatus("Tidak ada posisi terbuka untuk ditutup", false);
         RenderPanel();
         return;
      }
   }
}
//+------------------------------------------------------------------+
