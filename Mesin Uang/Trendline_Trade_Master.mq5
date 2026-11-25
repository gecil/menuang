//+------------------------------------------------------------------+
//|                                       Trendline_Trade_Master.mq5 |
//|     Trendline Trade Master v1.00 — Real-Time Touch Order/TP/SL   |
//|  Panel 1-Klik + Deteksi Garis Manual | Multi-Order | XM Ready    |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Trendline Trade Master"
#property version     "1.00"
#property description "EA Visual Garis Tren: Eksekusi Real-Time Tick saat Garis Tersentuh (BUY, SELL, TP, SL)"
#property description "Panel 1-Klik + Garis Manual (OBJ_TREND & OBJ_HLINE) | Multi-Order | Auto Hapus/Nonaktif Pasca-Entry"
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
   ROLE_CLOSE   = 9
};

input group "=== 1. LOT & MULTI-ORDER ==="
input double                  InpDefaultLot            = 0.01;              // Lot Default (bisa diubah langsung dari Panel Chart)
input double                  InpLotStepBtn            = 0.01;              // Kelipatan tombol [-] / [+] Lot di Panel
input int                     InpMaxOpenPositions      = 10;                // Maks posisi terbuka bersamaan (0 = tanpa batas)
input bool                    InpManageManualPositions = true;              // Garis TP/SL juga menutup posisi manual di simbol ini?

input group "=== 2. ATURAN SENTUHAN GARIS TREN (REAL-TIME TICK) ==="
input ENUM_TOUCH_PRICE_MODE   InpTouchPriceMode        = TOUCH_BID_CHART;   // Acuan harga sentuhan garis
input double                  InpTouchTolerancePts     = 0.0;               // Toleransi jarak sentuh (poin, 0 = tepat menyentuh)
input int                     InpDragCooldownSec       = 2;                 // Jeda aman (detik) setelah garis dibuat/digeser sebelum aktif
input ENUM_AFTER_ENTRY_ACTION InpAfterEntryAction      = ENTRY_LINE_DELETE; // Aksi pada garis Entry setelah order berhasil
input bool                    InpDeleteTPSLAfterHit    = true;              // Hapus garis TP/SL otomatis setelah menutup posisi?
input bool                    InpTPOnlyIfProfit        = true;              // Garis "TP" umum hanya tutup posisi yg sedang profit (aman multi-order)
input bool                    InpSLOnlyIfLoss          = true;              // Garis "SL" umum hanya tutup posisi yg sedang loss (aman multi-order)

input group "=== 3. BACKUP BROKER SL/TP DALAM USD (OPSIONAL) ==="
input bool                    InpUseBrokerSLTP         = false;             // Pasang SL/TP broker otomatis saat garis Entry tersentuh?
input double                  InpBrokerSLMoneyBase     = 3.0;               // SL Broker ($) untuk InpDefaultLot (proporsional jika lot beda)
input double                  InpBrokerTPMoneyBase     = 6.0;               // TP Broker ($) untuk InpDefaultLot (RR 1:2)
input double                  InpCommissionPerLot      = 0.0;               // Komisi per 1.00 lot (XM Std/UltraLow=0, XM Zero=7.0)

input group "=== 4. FILTER BROKER (XM READY) ==="
input int                     InpMaxSpreadPts          = 80;                // Spread maks untuk Entry baru (poin, 0=Off; TP/SL tidak diblokir)
input int                     InpSlippagePts           = 80;                // Toleransi Slippage (poin)
input int                     InpFastRetries           = 3;                 // Retry cepat (80ms) saat Requote/Off-Quotes
input long                    InpMagicNumber           = 990100;            // Magic Number EA

input group "=== 5. TAMPILAN PANEL & WARNA GARIS ==="
input bool                    InpShowPanel             = true;              // Tampilkan Panel Tombol 1-Klik di Chart
input int                     InpPanelX                = 14;                // Posisi X Panel
input int                     InpPanelY                = 24;                // Posisi Y Panel
input color                   InpColorBuy              = clrDodgerBlue;     // Warna Garis BUY
input color                   InpColorSell             = clrOrangeRed;      // Warna Garis SELL
input color                   InpColorTP               = clrLimeGreen;      // Warna Garis TP
input color                   InpColorSL               = clrGold;           // Warna Garis SL
input int                     InpLineWidth             = 2;                 // Ketebalan Garis Tren (1-5)
input bool                    InpEnableAlerts          = true;              // Pop-up Alert saat garis tersentuh?
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
   ulong          armedAfterMs;  // GetTickCount64() batas selesai cooldown geser
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
SLineTrack  g_tracks[];

int         g_cntBuyLines    = 0;
int         g_cntSellLines   = 0;
int         g_cntTPLines     = 0;
int         g_cntSLLines     = 0;

//+------------------------------------------------------------------+
//| [4] Helper Umum & Lot                                            |
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

void NotifyStatus(string msg, bool showAlert = false)
{
   g_lastStatusMsg = TimeToString(TimeCurrent(), TIME_SECONDS) + " | " + msg;
   Print("[Trendline Master] ", msg);
   if(showAlert && InpEnableAlerts && !MQLInfoInteger(MQL_OPTIMIZATION))
      Alert("[Trendline Master] ", _Symbol, " | ", msg);
   if(showAlert && InpEnablePush && !MQLInfoInteger(MQL_OPTIMIZATION))
      SendNotification("[Trendline Master] " + _Symbol + " | " + msg);
}

bool IsManagedPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   if(InpManageManualPositions) return true;
   return (PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}

int CountManagedPositions(int dirFilter = 0) // 0=semua, 1=BUY, -1=SELL
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
//| [6] Deteksi Peran & Parsing Lot dari Nama / Deskripsi Garis      |
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
         leftOK = !((chL >= 'A' && chL <= 'Z') || (chL >= '0' && chL <= '9'));
      }
      int endPos = pos + StringLen(token);
      bool rightOK = (endPos >= StringLen(upperText));
      if(!rightOK)
      {
         ushort chR = StringGetCharacter(upperText, endPos);
         rightOK = !((chR >= 'A' && chR <= 'Z') || (chR >= '0' && chR <= '9'));
      }
      if(leftOK && rightOK)
         return true;
      pos = StringFind(upperText, token, pos + 1);
   }
   return false;
}

ENUM_LINE_ROLE DetectLineRole(const string objName)
{
   // Abaikan objek UI milik panel
   if(StringFind(objName, UI_PFX) == 0)
      return ROLE_NONE;

   long objType = ObjectGetInteger(0, objName, OBJPROP_TYPE);
   if(objType != OBJ_TREND && objType != OBJ_HLINE)
      return ROLE_NONE;

   string desc = ObjectGetString(0, objName, OBJPROP_TEXT);
   string comb = objName + " " + desc;
   StringToUpper(comb);

   // Abaikan garis yang sudah selesai/dinonaktifkan
   if(HasToken(comb, "DONE") || HasToken(comb, "USED") || HasToken(comb, "OFF"))
      return ROLE_NONE;

   // 1. Cek CLOSE ALL terlebih dahulu
   if(HasToken(comb, "CLOSE") || HasToken(comb, "EXIT"))
      return ROLE_CLOSE;

   // 2. Cek TP spesifik (TP_BUY / TP BUY / TP_SELL / TP SELL / TP)
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

   // 3. Cek SL spesifik (SL_BUY / SL BUY / SL_SELL / SL SELL / SL)
   if(isSL)
   {
      if(isBuy && !isSell) return ROLE_SL_BUY;
      if(isSell && !isBuy) return ROLE_SL_SELL;
      return ROLE_SL_ALL;
   }

   // 4. Cek Entry BUY / SELL
   if(isBuy && !isSell) return ROLE_BUY;
   if(isSell && !isBuy) return ROLE_SELL;

   return ROLE_NONE;
}

// Parsing lot kustom dari nama/deskripsi garis, contoh: "BUY 0.05" atau "SELL_0.10"
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
         // Hanya terima angka desimal (mengandung titik, mis. 0.01 / 0.05 / 1.00)
         // agar nomor urut garis seperti TL_BUY_1 atau TL_BUY_2 tidak dianggap 1.0 / 2.0 lot!
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

double GetLineCurrentPrice(const string objName)
{
   long objType = ObjectGetInteger(0, objName, OBJPROP_TYPE);
   if(objType == OBJ_HLINE)
      return ObjectGetDouble(0, objName, OBJPROP_PRICE);

   if(objType == OBJ_TREND)
   {
      // Ambil proyeksi harga garis tren pada waktu/bar berjalan saat ini
      double p = ObjectGetValueByTime(0, objName, TimeCurrent(), 0);
      if(p <= 0.0)
         p = ObjectGetValueByTime(0, objName, iTime(_Symbol, PERIOD_CURRENT, 0), 0);
      return p;
   }

   return 0.0;
}

double GetReferencePriceForRole(ENUM_LINE_ROLE role)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(InpTouchPriceMode == TOUCH_BID_CHART)
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

void ArmOrResetTrack(const string name, ENUM_LINE_ROLE role, bool withCooldown)
{
   double lp = GetLineCurrentPrice(name);
   double rp = GetReferencePriceForRole(role);
   int side  = 0;
   if(lp > 0.0 && rp > 0.0)
   {
      if(rp > lp)      side =  1;
      else if(rp < lp) side = -1;
   }

   ulong coolMs = withCooldown ? (ulong)MathMax(0, InpDragCooldownSec) * 1000 : 0;
   ulong armAt  = GetTickCount64() + coolMs;

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
      // Nonaktifkan secara visual (abu-abu putus-putus + tandai _DONE di deskripsi)
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

//+------------------------------------------------------------------+
//| [8] Eksekusi Order & Penutupan Posisi (XM Fast-Retry Ready)      |
//+------------------------------------------------------------------+
bool ExecuteTrendlineEntry(ENUM_POSITION_TYPE type, double lot, const string lineName, double linePrice)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      NotifyStatus("GAGAL: Algo Trading belum aktif di MT5!", true);
      return false;
   }

   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
   {
      NotifyStatus("GAGAL: Simbol ini tidak mendukung open posisi (cek simbol XM)!", true);
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
                                   dirTxt, lot, g_digits, fillPx, lineName, g_digits, linePrice), true);
         return true;
      }

      if(attempt < maxTry && IsRetryableRetcode(rc))
         continue;

      NotifyStatus(StringFormat("GAGAL %s %.2f (%s) kode %u: %s",
                                dirTxt, lot, lineName, rc, g_trade.ResultRetcodeDescription()), true);
      return false;
   }

   return false;
}

int ClosePositionsByTrendline(ENUM_LINE_ROLE role, const string lineName, double linePrice)
{
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
         case ROLE_CLOSE:
            match = true;
            break;
         case ROLE_TP_BUY:
            match = (pType == POSITION_TYPE_BUY);
            break;
         case ROLE_TP_SELL:
            match = (pType == POSITION_TYPE_SELL);
            break;
         case ROLE_TP_ALL:
            match = InpTPOnlyIfProfit ? (profit >= 0.0) : true;
            break;
         case ROLE_SL_BUY:
            match = (pType == POSITION_TYPE_BUY);
            break;
         case ROLE_SL_SELL:
            match = (pType == POSITION_TYPE_SELL);
            break;
         case ROLE_SL_ALL:
            match = InpSLOnlyIfLoss ? (profit <= 0.0) : true;
            break;
         default:
            match = false;
            break;
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
                                tag, lineName, g_digits, linePrice, closedCnt, closedPL), true);
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

   g_cntBuyLines  = 0;
   g_cntSellLines = 0;
   g_cntTPLines   = 0;
   g_cntSLLines   = 0;

   // Kumpulkan daftar objek aktif dulu (aman bila ada objek dihapus saat loop)
   string activeNames[];
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

      if(role == ROLE_BUY)                                         g_cntBuyLines++;
      else if(role == ROLE_SELL)                                   g_cntSellLines++;
      else if(role == ROLE_TP_ALL || role == ROLE_TP_BUY || role == ROLE_TP_SELL) g_cntTPLines++;
      else                                                         g_cntSLLines++;
   }

   for(int i = 0; i < found; i++)
   {
      string         name = activeNames[i];
      ENUM_LINE_ROLE role = activeRoles[i];

      double linePx = GetLineCurrentPrice(name);
      if(linePx <= 0.0) continue;

      double refPx = GetReferencePriceForRole(role);
      if(refPx <= 0.0) continue;

      int idx = FindTrackIndex(name);
      if(idx < 0)
      {
         // Garis baru ditemukan (mis. baru digambar manual oleh user) -> beri jeda cooldown geser
         ArmOrResetTrack(name, role, true);
         continue;
      }

      g_tracks[idx].seenThisPass = true;
      g_tracks[idx].role         = role;
      g_tracks[idx].lastLinePx   = linePx;

      // Selama masih dalam jeda cooldown geser (2 detik), perbarui sisi harga tanpa memicu eksekusi
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

      // Deteksi sentuhan real-time (baik dari atas ke bawah maupun dari bawah ke atas)
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
      if(role == ROLE_BUY || role == ROLE_SELL)
      {
         double lot = ParseLineLot(name);
         ENUM_POSITION_TYPE pType = (role == ROLE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         if(ExecuteTrendlineEntry(pType, lot, name, linePx))
         {
            FinalizeTriggeredLine(name, true);
         }
         else
         {
            // Jika gagal (mis. spread tinggi/batas posisi), re-arm agar tidak spam tiap tick
            ArmOrResetTrack(name, role, true);
         }
      }
      else
      {
         // Garis TP / SL / CLOSE -> hanya dieksekusi & dihapus jika ada posisi yang benar-benar ditutup
         int closed = ClosePositionsByTrendline(role, name, linePx);
         if(closed > 0)
         {
            FinalizeTriggeredLine(name, false);
         }
         else
         {
            // Belum ada posisi cocok -> balik sisi tracking agar tetap siap jika nanti harga menyentuh lagi
            if(refPx > linePx)      g_tracks[idx].prevSide =  1;
            else if(refPx < linePx) g_tracks[idx].prevSide = -1;
         }
      }
   }

   // Bersihkan catatan tracking untuk garis yang sudah dihapus manual oleh user
   for(int k = ArraySize(g_tracks) - 1; k >= 0; k--)
   {
      if(!g_tracks[k].seenThisPass)
         RemoveTrackByIndex(k);
   }
}

//+------------------------------------------------------------------+
//| [10] Pembuat Garis Tren 1-Klik Siap Geser                        |
//+------------------------------------------------------------------+
void SpawnTrendline(ENUM_LINE_ROLE role)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0) return;

   // Hitung jarak spawn proporsional agar tidak langsung menempel di harga berjalan
   double chartMax = ChartGetDouble(0, CHART_PRICE_MAX, 0);
   double chartMin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   double visRange = chartMax - chartMin;
   double offset   = (visRange > 0.0) ? (visRange * 0.14) : (g_point * 200.0);

   // Sedikit geser bertingkat jika user klik berkali-kali (multi-order)
   double stagger  = offset * 0.22 * ((g_lineCounter - 1) % 4);
   offset += stagger;

   bool placeAbove = true;
   string tag      = "BUY";
   string desc     = "";
   color  clr      = InpColorBuy;

   switch(role)
   {
      case ROLE_BUY:
         placeAbove = false; // Default di bawah harga (area support/bounce), bebas digeser ke atas untuk breakout!
         tag  = "BUY";
         desc = StringFormat("BUY %.2f", g_activeLot);
         clr  = InpColorBuy;
         break;
      case ROLE_SELL:
         placeAbove = true;  // Default di atas harga (area resistance), bebas digeser ke bawah untuk breakdown!
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

   double pBase = NormalizeDouble(placeAbove ? (bid + offset) : (bid - offset), g_digits);
   int    sec   = MathMax(60, PeriodSeconds(PERIOD_CURRENT));
   datetime t0  = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t0 <= 0) t0 = TimeCurrent();

   datetime t1  = t0 - (datetime)(sec * 20);
   datetime t2  = t0 + (datetime)(sec * 5);

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
   ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, objName, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, objName, OBJPROP_SELECTED, true);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetString(0, objName, OBJPROP_TEXT, desc);
   ObjectSetString(0, objName, OBJPROP_TOOLTIP, desc + " — geser titik garis ke area tren Anda");

   // Aktifkan tampilan deskripsi objek di chart agar label garis langsung terlihat
   ChartSetInteger(0, CHART_SHOW_OBJECT_DESCR, true);

   ArmOrResetTrack(objName, role, true);
   NotifyStatus(StringFormat("Garis %s dibuat (%s) — geser ke posisi tren Anda", objName, desc), false);
   ChartRedraw(0);
}

void ClearAllTrendlines()
{
   int delCnt = 0;
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(name == "" || StringFind(name, UI_PFX) == 0) continue;
      if(DetectLineRole(name) != ROLE_NONE || StringFind(name, "TL_") == 0)
      {
         ObjectDelete(0, name);
         delCnt++;
      }
   }
   ArrayResize(g_tracks, 0);
   NotifyStatus(StringFormat("Menghapus %d garis tren dari chart", delCnt), false);
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
   int w = 264;
   int h = g_panelMinimized ? 30 : 284;

   CreateRect(UI_PFX + "BG", x, y, w, h, C'17,24,39', C'55,65,81');
   CreateRect(UI_PFX + "HDR", x, y, w, 30, C'30,41,59', C'55,65,81');
   CreateLabel(UI_PFX + "TITLE", x + 10, y + 7, "TRENDLINE TRADE MASTER v1.0", clrWhite, 9, "Segoe UI Bold");
   CreateButton(BTN_MINIMIZE, x + w - 28, y + 4, 22, 22, g_panelMinimized ? "+" : "-", C'51,65,85', clrWhite, 9);

   if(g_panelMinimized)
   {
      // Sembunyikan elemen body saat minimize
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

   // Baris Lot
   int rowY = y + 38;
   CreateLabel(UI_PFX + "LBL_LOT", x + 10, rowY + 4, "Lot Garis Baru:", C'148,163,184', 8);
   CreateButton(BTN_LOT_MINUS, x + 112, rowY, 28, 22, "-", C'51,65,85', clrWhite, 9);
   CreateLabel(UI_PFX + "VAL_LOT", x + 150, rowY + 3, DoubleToString(g_activeLot, 2), clrYellow, 9, "Segoe UI Bold");
   CreateButton(BTN_LOT_PLUS, x + 206, rowY, 28, 22, "+", C'51,65,85', clrWhite, 9);

   // Baris Tombol Utama: + BUY / + SELL
   rowY += 30;
   CreateButton(BTN_ADD_BUY,  x + 10,  rowY, 118, 28, "+ Garis BUY",  C'29,78,216',  clrWhite, 8);
   CreateButton(BTN_ADD_SELL, x + 136, rowY, 118, 28, "+ Garis SELL", C'185,28,28',  clrWhite, 8);

   // Baris Tombol TP / SL Umum
   rowY += 34;
   CreateButton(BTN_ADD_TP,   x + 10,  rowY, 118, 26, "+ Garis TP",   C'21,128,61',  clrWhite, 8);
   CreateButton(BTN_ADD_SL,   x + 136, rowY, 118, 26, "+ Garis SL",   C'180,83,9',   clrWhite, 8);

   // Baris Tombol TP/SL Spesifik Arah (untuk Multi-Order)
   rowY += 32;
   CreateButton(BTN_ADD_TPBUY,  x + 10,  rowY, 57, 22, "TP BUY",  C'20,83,45',  C'187,247,208', 7);
   CreateButton(BTN_ADD_TPSELL, x + 71,  rowY, 57, 22, "TP SELL", C'20,83,45',  C'187,247,208', 7);
   CreateButton(BTN_ADD_SLBUY,  x + 136, rowY, 57, 22, "SL BUY",  C'120,53,15', C'254,240,138', 7);
   CreateButton(BTN_ADD_SLSELL, x + 197, rowY, 57, 22, "SL SELL", C'120,53,15', C'254,240,138', 7);

   // Baris Aksi Bersih
   rowY += 30;
   CreateButton(BTN_CLEAR_LN,  x + 10,  rowY, 118, 24, "Hapus Garis", C'51,65,85',  C'226,232,240', 8);
   CreateButton(BTN_CLOSE_ALL, x + 136, rowY, 118, 24, "Close All",   C'127,29,29', C'254,202,202', 8);

   // Footer Informasi Real-Time
   rowY += 32;
   double spPts   = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   int    posCnt  = CountManagedPositions(0);
   double fltPL   = GetManagedFloatingPL();
   string algoTxt = (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED)) ? "ON" : "OFF!";

   CreateLabel(UI_PFX + "INF1", x + 10, rowY,
               StringFormat("Garis Aktif: BUY %d | SELL %d | TP %d | SL %d", g_cntBuyLines, g_cntSellLines, g_cntTPLines, g_cntSLLines),
               C'203,213,225', 8);
   CreateLabel(UI_PFX + "INF2", x + 10, rowY + 17,
               StringFormat("Posisi: %d | Float: $%+.2f | Spread: %.0f pts", posCnt, fltPL, spPts),
               (fltPL >= 0.0) ? C'134,239,172' : C'252,165,165', 8);
   CreateLabel(UI_PFX + "INF3", x + 10, rowY + 34,
               StringFormat("Algo: %s | Manual: ketik BUY/SELL/TP/SL di garis", algoTxt),
               (algoTxt == "ON") ? C'148,163,184' : clrRed, 7);

   string shortMsg = (StringLen(g_lastStatusMsg) > 42) ? (StringSubstr(g_lastStatusMsg, 0, 39) + "...") : g_lastStatusMsg;
   CreateLabel(UI_PFX + "INF4", x + 10, rowY + 50, shortMsg, clrGold, 7);

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

   // Daftarkan garis tren yang sudah ada di chart saat EA dipasang (tanpa langsung memicu)
   int totalObj = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < totalObj; i++)
   {
      string name = ObjectName(0, i, 0, -1);
      ENUM_LINE_ROLE role = DetectLineRole(name);
      if(role != ROLE_NONE)
         ArmOrResetTrack(name, role, false);
   }

   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      EventSetTimer(1);

   RenderPanel();
   PrintFormat("=== Trendline Trade Master v1.00 Aktif | %s | Lot=%.2f | MaxSpread=%d pts ===",
               _Symbol, g_activeLot, InpMaxSpreadPts);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DestroyPanel();
   Print("=== Trendline Trade Master v1.00 Dihentikan ===");
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
   // 1. User membuat / menggeser / mengubah nama garis tren -> reset cooldown & sisi harga agar tidak misfire!
   if(id == CHARTEVENT_OBJECT_CREATE || id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CHANGE)
   {
      if(StringFind(sparam, UI_PFX) == 0) return;
      ENUM_LINE_ROLE role = DetectLineRole(sparam);
      if(role != ROLE_NONE)
      {
         ArmOrResetTrack(sparam, role, true);
         RenderPanel();
      }
      return;
   }

   // 2. User menghapus garis manual
   if(id == CHARTEVENT_OBJECT_DELETE)
   {
      int idx = FindTrackIndex(sparam);
      if(idx >= 0) RemoveTrackByIndex(idx);
      RenderPanel();
      return;
   }

   // 3. Klik tombol pada Panel 1-Klik
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
