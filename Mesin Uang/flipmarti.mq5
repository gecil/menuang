//+------------------------------------------------------------------+
//|                                           Mesin Uang.mq5         |
//|  Mesin Uang v9.00 - Standard Precision Flip Martingale (RR 1:2)  |
//|  Fix Anti-Tumpuk 0.01, SL $3 / TP $6 Bersih, Presisi XM Detik 00 |
//|                                      https://sagu.pages.dev      |
//+------------------------------------------------------------------+
#property copyright   "Mochamad Tabrani & Antigravity AI"
#property link        "https://sagu.pages.dev"
#property version     "9.00"
#property description "Mesin Uang v9.00: 1 Posisi Bersih/Step (Fix Bug Tumpuk 0.01), SL $3 & TP $6 Bersih (RR 1:2), Presisi Flip Martingale & Timer Detik :00 XM"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| [1] Enum & Parameter Input                                       |
//+------------------------------------------------------------------+
enum ENUM_TRIGGER_MODE
{
   TRIGGER_CANDLE   = 0,   // Candle: close kotak naik = BUY, turun = SELL (Detik :00)
   TRIGGER_CROSSING = 1    // Crossing level angka bulat
};

enum ENUM_LOT_MODE
{
   LOT_PRECISION_RECOVERY = 0, // Presisi Otomatis RR 1:2 (Tutup Rugi Aktual + Target Profit, Lot ~1.5x)
   LOT_MULTIPLIER         = 1  // Pengali Tetap (Lot x InpLotMultiplier, mis. 1.5x atau 2.0x)
};

enum ENUM_AFTER_TP_MODE
{
   AFTER_TP_WAIT_SIGNAL = 0, // Kembali STANDBY tunggu detik :00 / sinyal baru (Rapi & Aman)
   AFTER_TP_CONTINUE    = 1  // Langsung tembak searah (jika lolos filter)
};

input group "=== STRATEGI FLIP MARTINGALE STANDAR (1 POSISI / STEP) ==="
input bool                InpEnableBot        = true;                   // Aktifkan Mesin Uang Otomatis?
input ENUM_TRIGGER_MODE   InpTriggerMode      = TRIGGER_CANDLE;         // Pemicu entri siklus baru
input ENUM_TIMEFRAMES     InpTriggerTF        = PERIOD_M1;              // Timeframe kotak (mode Candle)
input bool                InpExactZeroTimer   = true;                   // Timer Presisi Detik :00 (tidak menunggu tick XM)
input int                 InpTimerPeriodMs    = 100;                    // Interval cek timer detik :00 (ms, 50-500)
input double              InpPriceInterval    = 1.0;                    // Jarak level angka bulat (mode Crossing)
input ENUM_AFTER_TP_MODE  InpAfterTPMode      = AFTER_TP_WAIT_SIGNAL;   // Aksi setelah TP tercapai (Default: Standby rapi di :00)

input group "=== SL & TP NILAI BERSIH PRESISI (RR 1:2 CONTOH XM) ==="
input double              InpStartLot         = 0.01;                   // Lot Awal Step 1 (acuan nilai SL & TP di bawah)
input double              InpSLMoneyBase      = 3.0;                    // Nilai SL Bersih untuk Lot Awal (mis. $3.00 pada 0.01 lot)
input double              InpTPMoneyBase      = 6.0;                    // Nilai TP Bersih untuk Lot Awal (mis. $6.00 pada 0.01 lot -> RR 1:2)
input double              InpCommissionPerLot = 0.0;                    // Komisi Round-Turn per 1.00 lot (XM Std/UltraLow=0, XM Zero=7.0)

input group "=== PENGATURAN LOT FLIP MARTINGALE PRESISI ==="
input ENUM_LOT_MODE       InpLotMode          = LOT_PRECISION_RECOVERY; // Mode hitung lot Flip (Default: Presisi RR 1:2)
input double              InpCycleTargetUSD   = 6.0;                    // Target Profit Bersih Siklus mode Presisi ($, 0 = ikut InpTPMoneyBase)
input double              InpLotMultiplier    = 2.0;                    // Pengali Lot (khusus mode Pengali Tetap)
input int                 InpMaxSteps         = 0;                      // Step maks (0 = tanpa batas)
input double              InpMaxLotPerOrder   = 81.92;                  // Maks Lot per 1 Tiket (jika melebihi baru dipecah)
input bool                InpFitLotToMargin   = true;                   // Jika margin kurang, pakai lot maksimal yang muat (anti-reset 0.01)

input group "=== PROTEKSI BREAK-EVEN (OPSIONAL) ==="
input int                 InpBEStartStep      = 0;                      // Aktifkan Break-Even mulai Step ke- (0 = nonaktif agar RR 1:2 murni)
input double              InpBETriggerPct     = 65.0;                   // Geser SL ke BE saat harga capai % dari target TP
input int                 InpBELockPts        = 10;                     // Poin profit yang dikunci saat BE (poin)

input group "=== AUTO LOT SALDO (OPSIONAL) ==="
input bool                InpAutoLot          = false;                  // Lot awal mengikuti saldo?
input double              InpAutoLotBase      = 0.01;                   // Lot per kelipatan saldo
input double              InpAutoLotEvery     = 100.0;                  // Kelipatan saldo (mata uang akun)

input group "=== FILTER ENTRI SIKLUS BARU (XM GOLD SPREAD 55+) ==="
input double              InpMinCandleBody    = 0.0;                    // Body candle min (0 = selalu entry di :00; mis. 0.20 untuk filter sideways)
input double              InpMinBodyRatio     = 0.0;                    // Rasio Body/Range candle min (0 = nonaktif; mis. 0.35)
input double              InpMinATRValue      = 0.0;                    // ATR minimum untuk mulai Step 1 (0 = nonaktif)
input ENUM_TIMEFRAMES     InpATRTF            = PERIOD_M5;              // Timeframe ATR (jika filter ATR aktif)
input int                 InpATRPeriod        = 14;                     // Periode ATR
input bool                InpUseTrendFilter   = false;                  // Hanya entri searah EMA + kemiringan EMA?
input ENUM_TIMEFRAMES     InpTrendTF          = PERIOD_M5;              // Timeframe EMA
input int                 InpTrendMAPeriod    = 50;                     // Periode EMA
input int                 InpMaxSpreadPts     = 80;                     // Spread maks (poin, 0 = nonaktif; default 80 aman untuk XM Gold ~55)
input bool                InpUseTimeFilter    = false;                  // Filter jam server?
input int                 InpStartHour        = 1;                      // Jam mulai (0-23)
input int                 InpEndHour          = 23;                     // Jam selesai (1-24)
input double              InpDailyTargetPct   = 0.0;                    // Stop siklus baru bila untung harian >= % (0 = nonaktif)
input double              InpDailyLossPct     = 0.0;                    // Stop bila rugi harian >= % (0 = nonaktif)
input bool                InpHardDailyStop    = false;                  // Hentikan rantai Martingale jika rugi harian tembus batas?

input group "=== NOTIFIKASI & BROKER (XM) ==="
input bool                InpEnableAlert      = true;                   // Popup Alert di Layar MT5?
input bool                InpEnablePush       = false;                  // Notifikasi ke HP (MetaQuotes ID)?
input bool                InpVerbose          = true;                   // Catat log detail di tab Experts?
input int                 InpEntryFastRetries = 3;                      // Retry cepat (80ms) jika kena Requote/Off-Quotes di detik :00
input int                 InpMaxRetryCount    = 15;                     // Maks percobaan ulang order Flip jika gagal
input int                 InpSlippage         = 80;                     // Toleransi Slippage (pts)
input long                InpMagicBot         = 888100;                 // Magic Number Khusus Bot Ini

//+------------------------------------------------------------------+
//| [2] Variabel Global                                              |
//+------------------------------------------------------------------+
CTrade            g_trade;
double            g_point;
int               g_digits;
string            g_gvPrefix;

int               g_currentStep      = 1;
double            g_currentBotLot    = 0.01;
double            g_lastPrice        = 0.0;
double            g_lastSLDist       = 3.0;     // Jarak harga SL presisi (mis. 3.00 di XM Gold -> -$3.00 per 0.01 lot)
double            g_lastTPDist       = 6.0;     // Jarak harga TP presisi (mis. 6.00 di XM Gold -> +$6.00 per 0.01 lot)
double            g_cycleNet         = 0.0;     // Akumulasi profit/loss bersih siklus berjalan
datetime          g_lastSlot         = 0;       // Slot waktu candle terakhir yang sudah diproses
datetime          g_syncServerSec    = 0;       // Detik TimeCurrent() terakhir dari server broker
ulong             g_syncLocalMs      = 0;       // GetTickCount64() saat g_syncServerSec berubah
string            g_lastTriggerInfo  = "Menunggu detik :00 berikutnya";

// Variabel keranjang (Basket) untuk menangani Split Order (hanya aktif jika lot > InpMaxLotPerOrder)
bool              g_isOpeningBasket  = false;   // Lock anti-reentrancy saat membuka order
double            g_stepAnchorPrice  = 0.0;     // Harga isi aktual tiket pertama agar TP/SL presisi 100%
double            g_stepClosedNet    = 0.0;     // Akumulasi net dari tiket yang sudah tutup pada step ini
long              g_stepLastReason   = -1;      // Alasan tutup utama pada step ini (TP/SL/SO)
ulong             g_processedPos[];             // Daftar Position ID yang sudah dihitung agar tidak dobel

int               g_pendingDir       = -1;      // -1 tidak ada, 0 BUY, 1 SELL
int               g_failCount        = 0;
uint              g_lastTryMs        = 0;

int               g_hATR             = INVALID_HANDLE;
int               g_hMA              = INVALID_HANDLE;

int               g_dayStamp         = 0;
double            g_dayStartEquity   = 0.0;

int               g_cntTP            = 0;
int               g_cntSL            = 0;
int               g_maxStepReached   = 1;
double            g_sessionNet       = 0.0;

//+------------------------------------------------------------------+
//| [3] Lifecycle                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpLotMultiplier < 1.0 || InpMaxSteps < 0 || InpPriceInterval <= 0.0 ||
      InpSLMoneyBase <= 0.0 || InpTPMoneyBase <= 0.0 || InpStartLot <= 0.0)
   {
      Print("Mesin Uang v9.00: parameter tidak valid. Periksa lot awal, SL $, TP $, dan pengali.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   g_point    = _Point;
   g_digits   = _Digits;
   g_gvPrefix = StringFormat("MU90_%s_%I64d_", _Symbol, InpMagicBot);

   g_trade.SetExpertMagicNumber(InpMagicBot);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

   if(InpMinATRValue > 0.0)
   {
      g_hATR = iATR(_Symbol, InpATRTF, InpATRPeriod);
      if(g_hATR == INVALID_HANDLE)
         Print("Mesin Uang: ATR gagal dibuat, filter ATR dinonaktifkan.");
   }
   if(InpUseTrendFilter)
   {
      g_hMA = iMA(_Symbol, InpTrendTF, InpTrendMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_hMA == INVALID_HANDLE)
         Print("Mesin Uang: EMA gagal dibuat, filter tren dinonaktifkan.");
   }

   g_currentStep     = 1;
   g_currentBotLot   = CalcStartLot();
   g_pendingDir      = -1;
   g_lastPrice       = 0.0;
   g_cycleNet        = 0.0;
   g_stepAnchorPrice = 0.0;
   g_stepClosedNet   = 0.0;
   g_stepLastReason  = -1;
   g_syncServerSec   = 0;
   g_syncLocalMs     = 0;
   g_dayStamp        = DayStamp(TimeCurrent());
   g_dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);

   CalcPrecisionSLTPDist(g_lastSLDist, g_lastTPDist);

   // Sinkronkan jam server sejak OnInit agar detik :00 berikutnya langsung tereksekusi
   SyncServerClock();
   datetime initSrv = GetEstimatedServerTime();
   g_lastSlot = (initSrv > 0) ? CalcBarSlot(initSrv, InpTriggerTF) : iTime(_Symbol, InpTriggerTF, 0);
   g_lastTriggerInfo = "Siap — menunggu detik :00 berikutnya";

   if(!MQLInfoInteger(MQL_TESTER))
   {
      LoadState();
      if(InpExactZeroTimer)
      {
         int timerMs = MathMax(50, MathMin(500, InpTimerPeriodMs));
         if(!EventSetMillisecondTimer(timerMs))
            Print("Mesin Uang: gagal mengaktifkan timer ms, fallback ke OnTick.");
      }
   }

   SaveState();

   double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   long   tradeMode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   double rrVal     = (g_lastSLDist > 0.0) ? (g_lastTPDist / g_lastSLDist) : 0.0;
   double slPts     = g_lastSLDist / g_point;
   double tpPts     = g_lastTPDist / g_point;

   PrintFormat("=== Mesin Uang v9.00 (Precision Flip RR 1:%.2f) Aktif | %s | Lot0=%.2f | SL=$%.2f (%.*f / %.0f pts) | TP=$%.2f (%.*f / %.0f pts) | Spread=%.0f/%d pts ===",
               rrVal, _Symbol, g_currentBotLot,
               InpSLMoneyBase, g_digits, g_lastSLDist, slPts,
               InpTPMoneyBase, g_digits, g_lastTPDist, tpPts,
               spreadPts, InpMaxSpreadPts);

   if(tradeMode != SYMBOL_TRADE_MODE_FULL)
      PrintFormat("[PERINGATAN XM] Simbol %s berstatus trade mode=%I64d (bukan FULL). Pastikan memakai simbol sesuai akun XM (GOLD / GOLD# / GOLDmicro).",
                  _Symbol, tradeMode);

   if(InpMaxSpreadPts > 0 && spreadPts > InpMaxSpreadPts)
      PrintFormat("[PERINGATAN SPREAD] Spread saat ini %.0f pts > InpMaxSpreadPts %d pts!", spreadPts, InpMaxSpreadPts);

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      Print("[PERINGATAN] Algo Trading belum aktif di MT5 atau di properti EA!");

   UpdateChartComment();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hMA  != INVALID_HANDLE) IndicatorRelease(g_hMA);
   if(MQLInfoInteger(MQL_TESTER)) GlobalVariablesDeleteAll(g_gvPrefix);
   Comment("");
   Print("=== Mesin Uang v9.00 Dihentikan ===");
}

//+------------------------------------------------------------------+
//| [4] Eksekusi Tiap Tick & Timer Presisi Detik :00                 |
//+------------------------------------------------------------------+
void OnTick()
{
   SyncServerClock();
   ProcessEngine(false);
}

void OnTimer()
{
   SyncServerClock();
   ProcessEngine(true);
}

void ProcessEngine(bool fromTimer)
{
   UpdateDay();

   if(InpEnableBot)
   {
      // Kelola Auto Break-Even (hanya jika InpBEStartStep > 0)
      ManageBreakEven();

      if(g_pendingDir >= 0)
         ProcessPending();
      else if(InpTriggerMode == TRIGGER_CANDLE)
         CheckCandleTrigger(fromTimer);
      else if(!fromTimer)
         CheckDirectionalCrossing();
   }
   else if(g_pendingDir >= 0)
   {
      ResetCycleToStep1();
      Print("Bot dinonaktifkan saat order lanjutan menunggu: siklus direset ke Step 1.");
   }

   UpdateChartComment();
}

//+------------------------------------------------------------------+
//| [4b] Sinkronisasi Jam Server Presisi (Anti-Delay Tick XM)        |
//+------------------------------------------------------------------+
void SyncServerClock()
{
   datetime tc = TimeCurrent();
   if(tc <= 0) return;

   ulong nowMs = GetTickCount64();
   if(g_syncServerSec == 0 || tc > g_syncServerSec)
   {
      g_syncServerSec = tc;
      g_syncLocalMs   = nowMs;
   }
}

datetime GetEstimatedServerTime()
{
   SyncServerClock();
   if(MQLInfoInteger(MQL_TESTER) || !InpExactZeroTimer || g_syncServerSec <= 0)
      return TimeCurrent();

   ulong nowMs     = GetTickCount64();
   ulong elapsedMs = (nowMs >= g_syncLocalMs) ? (nowMs - g_syncLocalMs) : 0;

   // Jangan memajukan jam jika server tidak mengirim tick sama sekali > 120 detik (market tutup/putus)
   if(elapsedMs > 120000)
      return g_syncServerSec;

   return g_syncServerSec + (datetime)(elapsedMs / 1000);
}

datetime CalcBarSlot(datetime t, ENUM_TIMEFRAMES tf)
{
   int sec = PeriodSeconds(tf);
   if(sec <= 0 || sec >= 86400)
      return iTime(_Symbol, tf, 0);
   return (datetime)(t - (t % sec));
}

void SetTriggerInfo(string txt)
{
   datetime t = GetEstimatedServerTime();
   g_lastTriggerInfo = TimeToString(t, TIME_SECONDS) + " | " + txt;
}

//+------------------------------------------------------------------+
//| [5a] Pemicu Candle: Detik :00 Presisi (1 Posisi Bersih)          |
//+------------------------------------------------------------------+
void CheckCandleTrigger(bool fromTimer)
{
   int      tfSec    = PeriodSeconds(InpTriggerTF);
   datetime bar0Time = iTime(_Symbol, InpTriggerTF, 0);
   if(bar0Time == 0 || tfSec <= 0) return;

   datetime estNow   = GetEstimatedServerTime();
   datetime curSlot  = (estNow > 0) ? CalcBarSlot(estNow, InpTriggerTF) : bar0Time;
   if(bar0Time > curSlot)
      curSlot = bar0Time;

   if(g_lastSlot == 0)
   {
      g_lastSlot = curSlot;
      return;
   }
   if(curSlot <= g_lastSlot) return;

   // Kunci slot candle agar tidak pernah double-entry di menit yang sama
   g_lastSlot = curSlot;

   // Wajib 1 posisi bersih per step: jika sudah ada posisi aktif, abaikan sinyal baru
   if(CountPositions(InpMagicBot) > 0) return;

   // Tentukan candle yang BARU SAJA tutup di detik :00:
   // - bar0Time >= curSlot       -> tick menit baru sudah masuk, candle tutup ada di shift 1
   // - bar0Time == curSlot-tfSec -> timer memicu tepat di :00 sebelum tick masuk, candle tutup ada di shift 0
   int shift = -1;
   if(bar0Time >= curSlot)
      shift = 1;
   else if(tfSec < 86400 && bar0Time == (curSlot - tfSec))
      shift = 0;

   if(shift < 0)
   {
      SetTriggerInfo("Skip: tidak ada tick pada candle sebelumnya");
      if(InpVerbose) Print("Kotak dilewati: tidak ada tick pada candle sebelumnya (market jeda/sepi).");
      return;
   }

   // Pastikan quote simbol masih segar (bukan market libur/tutup)
   datetime symTime = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);
   if(!MQLInfoInteger(MQL_TESTER) && symTime > 0 && estNow > symTime && (estNow - symTime) > MathMax(180, tfSec * 2))
   {
      SetTriggerInfo("Skip: quote simbol tidak aktif/market tutup");
      if(InpVerbose) Print("Kotak dilewati: quote simbol sudah tidak aktif (kemungkinan market tutup).");
      return;
   }

   double o = iOpen(_Symbol, InpTriggerTF, shift);
   double c = iClose(_Symbol, InpTriggerTF, shift);
   double h = iHigh(_Symbol, InpTriggerTF, shift);
   double l = iLow(_Symbol, InpTriggerTF, shift);

   double body  = MathAbs(c - o);
   double range = h - l;

   if(body < g_point * 0.5)
   {
      SetTriggerInfo("Skip: Doji (open = close)");
      if(InpVerbose) Print("Kotak doji (open = close): tidak entri.");
      return;
   }

   if(InpMinCandleBody > 0.0 && body < InpMinCandleBody)
   {
      SetTriggerInfo(StringFormat("Skip: body %.*f < min %.*f", g_digits, body, g_digits, InpMinCandleBody));
      if(InpVerbose) Print(StringFormat("Kotak dilewati: body %.*f < min %.*f.", g_digits, body, g_digits, InpMinCandleBody));
      return;
   }

   if(InpMinBodyRatio > 0.0 && range > 0.0 && (body / range) < InpMinBodyRatio)
   {
      SetTriggerInfo(StringFormat("Skip: rasio %.2f < %.2f", body / range, InpMinBodyRatio));
      if(InpVerbose) Print(StringFormat("Kotak dilewati: rasio body/range %.2f < %.2f.", body / range, InpMinBodyRatio));
      return;
   }

   bool isBuy = (c > o);
   string why = BlockReason(isBuy);
   if(why != "")
   {
      SetTriggerInfo("Skip: " + why);
      if(InpVerbose) Print(StringFormat("Kotak %s dilewati: %s.", isBuy ? "naik" : "turun", why));
      return;
   }

   string srcTag = fromTimer ? "TIMER :00" : "TICK :00";
   Print(StringFormat("[KOTAK %s | %s | shift=%d] Open %.*f Close %.*f (Body %.*f) -> %s Lot %.2f",
         isBuy ? "NAIK" : "TURUN", srcTag, shift, g_digits, o, g_digits, c, g_digits, body,
         isBuy ? "BUY" : "SELL", g_currentBotLot));

   if(OpenBotOrder(isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, g_currentBotLot))
      SetTriggerInfo(StringFormat("ENTRY %s %.2f (%s)", isBuy ? "BUY" : "SELL", g_currentBotLot, srcTag));
   else
      SetTriggerInfo(StringFormat("GAGAL %s (kode %u)", isBuy ? "BUY" : "SELL", g_trade.ResultRetcode()));
}

//+------------------------------------------------------------------+
//| [5b] Pemicu Crossing Level Angka Bulat (Presisi Anti-Float Bug)  |
//+------------------------------------------------------------------+
void CheckDirectionalCrossing()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(CountPositions(InpMagicBot) > 0)
   {
      g_lastPrice = bid;
      return;
   }

   if(g_lastPrice <= 0.0)
   {
      g_lastPrice = bid;
      return;
   }

   double step = InpPriceInterval;
   double eps  = g_point * 0.1;

   double levelUp = NormalizeDouble(MathFloor((bid + eps) / step) * step, g_digits);
   if(g_lastPrice < levelUp - eps && bid >= levelUp - eps)
   {
      g_lastPrice = bid;
      string why = BlockReason(true);
      if(why != "")
      {
         SetTriggerInfo("Skip crossing: " + why);
         if(InpVerbose) Print(StringFormat("Crossing naik %.*f dilewati: %s.", g_digits, levelUp, why));
         return;
      }
      Print(StringFormat("[CROSSING BUY] Melintas naik level %.*f", g_digits, levelUp));
      if(OpenBotOrder(POSITION_TYPE_BUY, g_currentBotLot))
         SetTriggerInfo(StringFormat("ENTRY BUY %.2f (CROSSING)", g_currentBotLot));
      return;
   }

   double levelDown = NormalizeDouble(MathCeil((bid - eps) / step) * step, g_digits);
   if(g_lastPrice > levelDown + eps && bid <= levelDown + eps)
   {
      g_lastPrice = bid;
      string why = BlockReason(false);
      if(why != "")
      {
         SetTriggerInfo("Skip crossing: " + why);
         if(InpVerbose) Print(StringFormat("Crossing turun %.*f dilewati: %s.", g_digits, levelDown, why));
         return;
      }
      Print(StringFormat("[CROSSING SELL] Melintas turun level %.*f", g_digits, levelDown));
      if(OpenBotOrder(POSITION_TYPE_SELL, g_currentBotLot))
         SetTriggerInfo(StringFormat("ENTRY SELL %.2f (CROSSING)", g_currentBotLot));
      return;
   }

   g_lastPrice = bid;
}

//+------------------------------------------------------------------+
//| [6] Filter Entri Siklus Baru                                     |
//+------------------------------------------------------------------+
string BlockReason(bool isBuy)
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return "Algo Trading MT5 nonaktif";
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return "Allow Algo Trading di properti EA nonaktif";
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
      return "simbol tidak bisa open order (cek simbol XM: GOLD/GOLD#/GOLDmicro)";
   if(!SpreadOK())
   {
      double sp = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
      return StringFormat("spread %.0f pts > batas %d pts", sp, InpMaxSpreadPts);
   }
   if(!InTradingHours())  return "di luar jam trading";
   string d = DailyBlock();
   if(d != "")            return d;
   if(!VolatilityOK())    return "volatilitas ATR terlalu rendah";
   if(!TrendOK(isBuy))    return "melawan tren/kemiringan EMA";
   return "";
}

bool SpreadOK()
{
   if(InpMaxSpreadPts <= 0) return true;
   double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   return (spreadPts <= InpMaxSpreadPts);
}

bool InTradingHours()
{
   if(!InpUseTimeFilter) return true;
   MqlDateTime d;
   TimeToStruct(GetEstimatedServerTime(), d);
   if(InpStartHour <= InpEndHour)
      return (d.hour >= InpStartHour && d.hour < InpEndHour);
   return (d.hour >= InpStartHour || d.hour < InpEndHour);
}

bool VolatilityOK()
{
   if(InpMinATRValue <= 0.0 || g_hATR == INVALID_HANDLE) return true;
   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(g_hATR, 0, 1, 1, a) != 1) return true;
   return (a[0] >= InpMinATRValue);
}

bool TrendOK(bool isBuy)
{
   if(!InpUseTrendFilter || g_hMA == INVALID_HANDLE) return true;
   double ma[];
   ArraySetAsSeries(ma, true);
   if(CopyBuffer(g_hMA, 0, 1, 3, ma) != 3) return true;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(isBuy)
      return (bid > ma[0] && ma[0] >= ma[2]);
   else
      return (bid < ma[0] && ma[0] <= ma[2]);
}

string DailyBlock()
{
   if(g_dayStartEquity <= 0.0) return "";
   double pct = (AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity) / g_dayStartEquity * 100.0;
   if(InpDailyTargetPct > 0.0 && pct >= InpDailyTargetPct) return "target untung harian tercapai";
   if(InpDailyLossPct   > 0.0 && pct <= -InpDailyLossPct)  return "batas rugi harian tercapai";
   return "";
}

void UpdateDay()
{
   int today = DayStamp(GetEstimatedServerTime());
   if(today != g_dayStamp)
   {
      g_dayStamp       = today;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      SaveState();
   }
}

int DayStamp(datetime t)
{
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.year * 10000 + d.mon * 100 + d.day;
}

//+------------------------------------------------------------------+
//| [7] Perhitungan Presisi Uang <-> Harga & Lot Flip Martingale     |
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

// Konversi SL $3 & TP $6 bersih (untuk Lot Awal) menjadi jarak harga presisi
void CalcPrecisionSLTPDist(double &outSLDist, double &outTPDist)
{
   double baseLot = NormalizeSingleOrderLot(InpStartLot);
   if(baseLot <= 0.0) baseLot = 0.01;

   double moneyPerPrice1Lot = GetMoneyPerPriceUnit1Lot();
   double moneyPerPriceBase = moneyPerPrice1Lot * baseLot;
   if(moneyPerPriceBase <= 0.0) moneyPerPriceBase = 1.0;

   double commBase = MathMax(0.0, InpCommissionPerLot) * baseLot;
   double slGross  = MathMax(0.01, InpSLMoneyBase - commBase);
   double tpGross  = MathMax(0.01, InpTPMoneyBase + commBase);

   double rawSL = slGross / moneyPerPriceBase;
   double rawTP = tpGross / moneyPerPriceBase;

   // Pengaman batas minimal StopsLevel + Spread broker (untuk $3 di XM Gold tidak akan tersentuh)
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = stopLvl + spread + 2.0 * g_point;

   if(rawSL < minDist)
   {
      double rr = (InpSLMoneyBase > 0.0) ? (InpTPMoneyBase / InpSLMoneyBase) : 2.0;
      rawSL = minDist;
      rawTP = MathMax(rawTP, rawSL * rr);
   }

   outSLDist = NormalizeDouble(rawSL, g_digits);
   outTPDist = NormalizeDouble(rawTP, g_digits);
}

// Estimasi nilai bersih TP ($) per 1.00 lot untuk jarak TP berjalan
double GetNetTPMoneyPer1Lot(double tpDist)
{
   double grossPer1Lot = tpDist * GetMoneyPerPriceUnit1Lot();
   double netPer1Lot   = grossPer1Lot - MathMax(0.0, InpCommissionPerLot);
   return MathMax(0.01, netPer1Lot);
}

// Estimasi nilai bersih SL ($) per 1.00 lot untuk jarak SL berjalan
double GetNetSLMoneyPer1Lot(double slDist)
{
   double grossPer1Lot = slDist * GetMoneyPerPriceUnit1Lot();
   return grossPer1Lot + MathMax(0.0, InpCommissionPerLot);
}

// Hitung lot Flip Martingale berikutnya secara presisi
double CalcNextFlipLot(double prevLot, double realizedCycleNet)
{
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 0.01;

   double nextLot = prevLot;

   if(InpLotMode == LOT_PRECISION_RECOVERY)
   {
      double slDist = 0.0, tpDist = 0.0;
      CalcPrecisionSLTPDist(slDist, tpDist);

      double tpNetPer1Lot = GetNetTPMoneyPer1Lot(tpDist);
      double targetProfit = (InpCycleTargetUSD > 0.0) ? InpCycleTargetUSD : InpTPMoneyBase;
      double lossToCover  = (realizedCycleNet < 0.0) ? MathAbs(realizedCycleNet) : 0.0;

      // Rumus Presisi RR 1:2: Lot = Ceil((|Akumulasi Rugi| + Target Profit) / TP_Bersih_Per_1Lot)
      // Contoh SL $3 / TP $6 (Target $6): 0.01 -> 0.02 -> 0.03 -> 0.04 -> 0.06 -> 0.09 -> 0.14 -> 0.21 ...
      double exactNeed = (lossToCover + targetProfit) / tpNetPer1Lot;
      nextLot = CeilTotalLot(exactNeed);
   }
   else
   {
      // Mode Pengali Tetap (mis. 1.5x atau 2.0x)
      nextLot = CeilTotalLot(prevLot * InpLotMultiplier);
   }

   // Pastikan lot progresif (minimal naik 1 step lot bila masih sama)
   if(nextLot <= prevLot + 1e-9)
      nextLot = CeilTotalLot(prevLot + stepLot);

   return nextLot;
}

void ResetCycleToStep1()
{
   g_pendingDir      = -1;
   g_failCount       = 0;
   g_currentStep     = 1;
   g_currentBotLot   = CalcStartLot();
   g_cycleNet        = 0.0;
   g_stepAnchorPrice = 0.0;
   g_stepClosedNet   = 0.0;
   g_stepLastReason  = -1;
   SaveState();
}

void StartOrQueue(ENUM_POSITION_TYPE type)
{
   g_failCount = 0;
   if(!InpEnableBot)
   {
      g_pendingDir = -1;
      SaveState();
      return;
   }

   if(OpenBotOrder(type, g_currentBotLot))
      g_pendingDir = -1;
   else
      g_pendingDir = (type == POSITION_TYPE_BUY) ? 0 : 1;
   SaveState();
}

void ProcessPending()
{
   if(CountPositions(InpMagicBot) > 0) return;

   uint now = GetTickCount();
   if(now - g_lastTryMs < 1000) return;
   g_lastTryMs = now;

   ENUM_POSITION_TYPE t = (g_pendingDir == 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   if(OpenBotOrder(t, g_currentBotLot))
   {
      g_pendingDir = -1;
      g_failCount  = 0;
      SaveState();
      return;
   }

   g_failCount++;
   int maxRetry = MathMax(5, InpMaxRetryCount);
   if(g_failCount >= maxRetry)
   {
      string msg = StringFormat("Order Step %d (Lot %.2f) gagal %dx. Siklus direset ke Step 1.",
                                g_currentStep, g_currentBotLot, maxRetry);
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      ResetCycleToStep1();
   }
}

//+------------------------------------------------------------------+
//| [8] Transaksi: Kalibrasi Presisi & Flip Martingale               |
//+------------------------------------------------------------------+
bool IsPosProcessed(ulong posId)
{
   int n = ArraySize(g_processedPos);
   for(int i = 0; i < n; i++)
      if(g_processedPos[i] == posId) return true;
   return false;
}

void MarkPosProcessed(ulong posId)
{
   int n = ArraySize(g_processedPos);
   if(n >= 200)
   {
      for(int i = 0; i < n - 1; i++)
         g_processedPos[i] = g_processedPos[i + 1];
      g_processedPos[n - 1] = posId;
   }
   else
   {
      ArrayResize(g_processedPos, n + 1);
      g_processedPos[n] = posId;
   }
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket)) return;

   long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);

   // Deposit / penarikan: sesuaikan patokan equity harian
   if(dealType == DEAL_TYPE_BALANCE)
   {
      g_dayStartEquity += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      SaveState();
      return;
   }

   string sym   = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   long   magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(sym != _Symbol || magic != InpMagicBot) return;

   long  dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   ulong posId     = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

   if(dealEntry == DEAL_ENTRY_IN)
   {
      double exactPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      if(g_stepAnchorPrice <= 0.0)
         g_stepAnchorPrice = exactPrice;

      ENUM_POSITION_TYPE pType = (dealType == DEAL_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      CalibratePositionTPSL(posId, g_stepAnchorPrice, pType);
      return;
   }

   if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT)
   {
      if(posId == 0 || IsPosProcessed(posId)) return;
      if(PositionSelectByTicket(posId)) return;

      MarkPosProcessed(posId);

      long   reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
      double net    = CalcPositionClosedNet(posId, dealTicket);

      g_sessionNet    += net;
      g_cycleNet      += net;
      g_stepClosedNet += net;

      // Prioritaskan pencatatan reason: SO > SL > TP
      if(reason == DEAL_REASON_SO || g_stepLastReason == -1)
         g_stepLastReason = reason;
      else if(reason == DEAL_REASON_SL && g_stepLastReason != DEAL_REASON_SO)
         g_stepLastReason = reason;
      else if(reason == DEAL_REASON_TP && g_stepLastReason != DEAL_REASON_SO && g_stepLastReason != DEAL_REASON_SL)
         g_stepLastReason = reason;

      // Tunggu sampai seluruh posisi pada step ini benar-benar tertutup
      if(g_isOpeningBasket || CountPositions(InpMagicBot) > 0)
         return;

      ENUM_POSITION_TYPE origType = (dealType == DEAL_TYPE_SELL) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      FinalizeClosedStep(origType);
   }
}

double CalcPositionClosedNet(ulong posId, ulong fallbackDeal)
{
   if(HistorySelectByPosition(posId))
   {
      double totalNet = 0.0;
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
      {
         ulong dt = HistoryDealGetTicket(i);
         if(dt == 0) continue;
         long entry = HistoryDealGetInteger(dt, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_IN)
         {
            totalNet += HistoryDealGetDouble(dt, DEAL_PROFIT)
                      + HistoryDealGetDouble(dt, DEAL_COMMISSION)
                      + HistoryDealGetDouble(dt, DEAL_SWAP)
                      + HistoryDealGetDouble(dt, DEAL_FEE);
         }
      }
      return totalNet;
   }

   return HistoryDealGetDouble(fallbackDeal, DEAL_PROFIT)
        + HistoryDealGetDouble(fallbackDeal, DEAL_COMMISSION)
        + HistoryDealGetDouble(fallbackDeal, DEAL_SWAP)
        + HistoryDealGetDouble(fallbackDeal, DEAL_FEE);
}

void FinalizeClosedStep(ENUM_POSITION_TYPE origType)
{
   long   reason  = g_stepLastReason;
   double stepNet = g_stepClosedNet;

   // Reset akumulator step berjalan
   g_stepClosedNet   = 0.0;
   g_stepLastReason  = -1;
   g_stepAnchorPrice = 0.0;

   // [A] Kena TP, atau kena SL Break-Even yang sudah menutup kerugian siklus
   if(reason == DEAL_REASON_TP || (reason == DEAL_REASON_SL && stepNet >= 0.0 && g_cycleNet >= 0.0))
   {
      g_cntTP++;
      int    finishedStep     = g_currentStep;
      double totalCycleProfit = g_cycleNet;

      ResetCycleToStep1();

      if(InpAfterTPMode == AFTER_TP_WAIT_SIGNAL)
      {
         string msg = StringFormat("[STEP %d TP SELESAI] Profit Step: $%+.2f | Net Siklus: $%+.2f. Reset Step 1 & standby detik :00.",
                                   finishedStep, stepNet, totalCycleProfit);
         SetTriggerInfo(StringFormat("TP $%+.2f (Siklus $%+.2f) -> Standby :00", stepNet, totalCycleProfit));
         Print(msg);
         if(InpEnableAlert) Alert(msg);
         return;
      }

      bool isBuy = (origType == POSITION_TYPE_BUY);
      string why = BlockReason(isBuy);
      if(why != "")
      {
         string msg = StringFormat("[STEP %d TP SELESAI] Net Siklus: $%+.2f. Stop lanjut karena: %s.",
                                   finishedStep, totalCycleProfit, why);
         SetTriggerInfo("TP selesai — stop: " + why);
         Print(msg);
         if(InpEnableAlert) Alert(msg);
         return;
      }

      string msg = StringFormat("[STEP %d TP] Hasil $%+.2f (Net Siklus $%+.2f). Reset Step 1, lanjut searah.",
                                finishedStep, stepNet, totalCycleProfit);
      SetTriggerInfo(StringFormat("TP $%+.2f -> Lanjut searah Step 1", totalCycleProfit));
      Print(msg);
      if(InpEnableAlert) Alert(msg);

      StartOrQueue(origType);
   }
   // [B] Kena SL Break-Even (stepNet >= 0), tetapi siklus masih minus -> Tahan Step & Lot!
   else if(reason == DEAL_REASON_SL && stepNet >= 0.0 && g_cycleNet < 0.0)
   {
      string msg = StringFormat("[STEP %d BREAK-EVEN] Step impas ($%+.2f), sisa siklus $%+.2f. Tahan Step %d (Lot %.2f).",
                                g_currentStep, stepNet, g_cycleNet, g_currentStep, g_currentBotLot);
      SetTriggerInfo(StringFormat("BE Step %d — tahan lot %.2f", g_currentStep, g_currentBotLot));
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      StartOrQueue(origType);
   }
   // [C] Kena SL Rugi Normal -> Hitung Lot Presisi + Langsung FLIP Balik Arah (BUY <-> SELL)
   else if(reason == DEAL_REASON_SL)
   {
      g_cntSL++;
      int slStep = g_currentStep;

      if(InpHardDailyStop)
      {
         string dBlock = DailyBlock();
         if(dBlock != "")
         {
            string msg = StringFormat("[HARD STOP HARIAN] Step %d SL ($%+.2f) menyentuh %s. Siklus dihentikan & reset ke Step 1!",
                                      slStep, stepNet, dBlock);
            SetTriggerInfo("Hard Stop: " + dBlock);
            Print(msg);
            if(InpEnableAlert) Alert(msg);
            if(InpEnablePush)  SendNotification(msg);
            ResetCycleToStep1();
            return;
         }
      }

      bool capped = (InpMaxSteps > 0 && g_currentStep >= InpMaxSteps);
      if(!capped)
      {
         g_currentStep++;
         g_currentBotLot = CalcNextFlipLot(g_currentBotLot, g_cycleNet);
      }
      if(g_currentStep > g_maxStepReached) g_maxStepReached = g_currentStep;

      ENUM_POSITION_TYPE flipDir = (origType == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      double estSLUsd = g_currentBotLot * GetNetSLMoneyPer1Lot(g_lastSLDist);
      double estTPUsd = g_currentBotLot * GetNetTPMoneyPer1Lot(g_lastTPDist);
      double estNetTP = g_cycleNet + estTPUsd;

      string msg = capped
         ? StringFormat("[STEP %d SL] Hasil $%+.2f (Siklus $%+.2f). Step maks: FLIP %s Lot %.2f (SL -$%.2f / TP +$%.2f).",
                        slStep, stepNet, g_cycleNet, (flipDir == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                        g_currentBotLot, estSLUsd, estTPUsd)
         : StringFormat("[STEP %d SL] Hasil $%+.2f (Siklus $%+.2f). FLIP %s Step %d Lot %.2f (SL -$%.2f | TP +$%.2f | Est Net TP $%+.2f).",
                        slStep, stepNet, g_cycleNet, (flipDir == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                        g_currentStep, g_currentBotLot, estSLUsd, estTPUsd, estNetTP);

      SetTriggerInfo(StringFormat("FLIP %s S%d Lot %.2f (Est TP $%+.2f)",
                                  (flipDir == POSITION_TYPE_BUY) ? "BUY" : "SELL", g_currentStep, g_currentBotLot, estNetTP));
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      if(InpEnablePush && capped) SendNotification(msg);

      StartOrQueue(flipDir);
   }
   // [D] Stop Out / Ditutup Manual
   else
   {
      string why = (reason == DEAL_REASON_SO) ? "STOP OUT oleh broker" : "ditutup manual/sebab lain";
      string msg = StringFormat("Posisi %s (hasil bersih $%+.2f). Siklus direset ke Step 1.", why, stepNet);
      SetTriggerInfo("Reset Step 1 (" + why + ")");
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      if(InpEnablePush)  SendNotification(msg);

      ResetCycleToStep1();
   }
}

//+------------------------------------------------------------------+
//| [9] Kalibrasi SL/TP Presisi Pasca-Eksekusi & Break-Even          |
//+------------------------------------------------------------------+
void CalibratePositionTPSL(ulong posTicket, double anchorPrice, ENUM_POSITION_TYPE posType)
{
   if(!PositionSelectByTicket(posTicket)) return;

   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;

   // Gunakan jarak SL ($3) & TP ($6) presisi TANPA double-spread!
   // Karena OpenPrice BUY = Ask dan SELL = Bid, jarak OpenPrice +- SL/TP menghasilkan nilai $ bersih yang presisi.
   double slDist  = g_lastSLDist;
   double tpDist  = g_lastTPDist;

   double exactTP = (posType == POSITION_TYPE_BUY) ? (anchorPrice + tpDist) : (anchorPrice - tpDist);
   double exactSL = (posType == POSITION_TYPE_BUY) ? (anchorPrice - slDist) : (anchorPrice + slDist);

   double safePad = stopLvl + 2.0 * g_point;
   if(posType == POSITION_TYPE_BUY)
   {
      if(exactSL > bid - safePad) exactSL = bid - safePad;
      if(exactTP < ask + safePad) exactTP = ask + safePad;
   }
   else
   {
      if(exactSL < ask + safePad) exactSL = ask + safePad;
      if(exactTP > bid - safePad) exactTP = bid - safePad;
   }

   exactTP = NormalizeDouble(exactTP, g_digits);
   exactSL = NormalizeDouble(exactSL, g_digits);

   double currentTP = PositionGetDouble(POSITION_TP);
   double currentSL = PositionGetDouble(POSITION_SL);

   if(MathAbs(currentTP - exactTP) > (g_point * 0.1) || MathAbs(currentSL - exactSL) > (g_point * 0.1))
   {
      g_trade.SetExpertMagicNumber(InpMagicBot);
      if(g_trade.PositionModify(posTicket, exactSL, exactTP) && RetcodeOK(g_trade.ResultRetcode()))
         Print(StringFormat("[KALIBRASI PRESISI] Tiket #%I64u | Open %.*f | SL %.*f (-%.*f) | TP %.*f (+%.*f)",
                            posTicket, g_digits, anchorPrice,
                            g_digits, exactSL, g_digits, slDist,
                            g_digits, exactTP, g_digits, tpDist));
      else
         Print(StringFormat("Kalibrasi tiket #%I64u gagal (kode %u), TP/SL awal dipertahankan.",
                            posTicket, g_trade.ResultRetcode()));
   }
}

void ManageBreakEven()
{
   if(InpBEStartStep <= 0 || g_currentStep < InpBEStartStep || InpBETriggerPct <= 0.0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicBot)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      long   pType     = PositionGetInteger(POSITION_TYPE);

      if(tp <= 0.0) continue;

      double lockDist  = InpBELockPts * g_point;
      double stopLvl   = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;

      if(pType == POSITION_TYPE_BUY)
      {
         double targetDist = tp - openPrice;
         if(targetDist <= 0.0) continue;
         double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL  = NormalizeDouble(openPrice + lockDist, g_digits);

         if(sl < newSL - (g_point * 0.1) && (bid - openPrice) >= (targetDist * InpBETriggerPct / 100.0))
         {
            if(bid - newSL >= stopLvl)
            {
               g_trade.SetExpertMagicNumber(InpMagicBot);
               if(g_trade.PositionModify(ticket, newSL, tp))
                  Print(StringFormat("[PROFIT LOCK BUY] Step %d Tiket #%I64u: SL digeser ke %.*f", g_currentStep, ticket, g_digits, newSL));
            }
         }
      }
      else if(pType == POSITION_TYPE_SELL)
      {
         double targetDist = openPrice - tp;
         if(targetDist <= 0.0) continue;
         double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL  = NormalizeDouble(openPrice - lockDist, g_digits);

         if((sl <= 0.0 || sl > newSL + (g_point * 0.1)) && (openPrice - ask) >= (targetDist * InpBETriggerPct / 100.0))
         {
            if(newSL - ask >= stopLvl)
            {
               g_trade.SetExpertMagicNumber(InpMagicBot);
               if(g_trade.PositionModify(ticket, newSL, tp))
                  Print(StringFormat("[PROFIT LOCK SELL] Step %d Tiket #%I64u: SL digeser ke %.*f", g_currentStep, ticket, g_digits, newSL));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| [10] Eksekutor Order Standar (Fix Anti-Tumpuk + Fast Retry XM)   |
//+------------------------------------------------------------------+
double GetMaxLotPerTicket()
{
   double brokerMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(brokerMax <= 0.0) brokerMax = 100.0;
   double maxTicket = (InpMaxLotPerOrder > 0.0) ? MathMin(InpMaxLotPerOrder, brokerMax) : brokerMax;
   return NormalizeSingleOrderLot(maxTicket);
}

double CalcMaxAffordableLot(ENUM_ORDER_TYPE orderType, double price, double desiredLot)
{
   if(HasMargin(orderType, desiredLot, price))
      return desiredLot;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double margin1 = 0.0;
   if(!OrderCalcMargin(orderType, _Symbol, 1.0, price, margin1) || margin1 <= 0.0)
      return 0.0;

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double maxAfford  = NormalizeSingleOrderLot((freeMargin * 0.98) / margin1);
   if(maxAfford < minLot) return 0.0;
   return MathMin(desiredLot, maxAfford);
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

bool OpenBotOrder(ENUM_POSITION_TYPE type, double totalLot)
{
   // GUARD WAJIB: Mencegah order ganda / bertumpuk!
   if(g_isOpeningBasket || CountPositions(InpMagicBot) > 0)
      return false;

   totalLot = NormalizeTotalLot(totalLot);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxTicket = GetMaxLotPerTicket();
   if(totalLot < minLot) return false;

   double slDist = 0.0, tpDist = 0.0;
   CalcPrecisionSLTPDist(slDist, tpDist);

   g_lastSLDist      = slDist;
   g_lastTPDist      = tpDist;
   g_stepAnchorPrice = 0.0;
   g_stepClosedNet   = 0.0;
   g_stepLastReason  = -1;
   SaveState();

   // Untuk lot standar <= 81.92, totalParts SELALU = 1 (1 order bersih!)
   int totalParts = (int)MathCeil((totalLot - 1e-8) / maxTicket);
   if(totalParts < 1) totalParts = 1;

   double remLot     = totalLot;
   int    openedCnt  = 0;
   double openedLots = 0.0;
   int    partIdx    = 1;

   double refPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice  = (type == POSITION_TYPE_BUY) ? NormalizeDouble(refPrice - slDist, g_digits)
                                                 : NormalizeDouble(refPrice + slDist, g_digits);
   double tpPrice  = (type == POSITION_TYPE_BUY) ? NormalizeDouble(refPrice + tpDist, g_digits)
                                                 : NormalizeDouble(refPrice - tpDist, g_digits);

   int maxFastTry = MathMax(0, InpEntryFastRetries);
   g_isOpeningBasket = true;

   // Safety cap partIdx <= totalParts memastikan MUSTAHIL terjadi infinite loop!
   while(remLot >= minLot - 1e-8 && partIdx <= totalParts && !IsStopped())
   {
      double chunkLot = NormalizeSingleOrderLot(MathMin(remLot, maxTicket));
      if(chunkLot < minLot) break;

      ENUM_ORDER_TYPE ordType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double curPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                    : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(!HasMargin(ordType, chunkLot, curPrice))
      {
         if(InpFitLotToMargin)
         {
            double afford = CalcMaxAffordableLot(ordType, curPrice, chunkLot);
            if(afford >= minLot)
            {
               Print(StringFormat("[PENYESUAIAN MARGIN] Margin tidak cukup untuk %.2f lot, disesuaikan ke %.2f lot.",
                                  chunkLot, afford));
               chunkLot = afford;
               remLot   = chunkLot; // Selesaikan pada chunk terakhir yang muat
            }
            else
            {
               Print("Margin bebas tidak cukup untuk membuka lot ", DoubleToString(remLot, 2));
               break;
            }
         }
         else
         {
            Print("Margin tidak cukup untuk ", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL", " lot ", DoubleToString(chunkLot, 2));
            break;
         }
      }

      string cmt = (totalParts > 1)
         ? StringFormat("MesinUang %s S%d (%d/%d)", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL", g_currentStep, partIdx, totalParts)
         : StringFormat("MesinUang %s S%d", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL", g_currentStep);

      bool chunkSent = false;
      for(int attempt = 0; attempt <= maxFastTry && !IsStopped(); attempt++)
      {
         if(attempt > 0)
         {
            if(!MQLInfoInteger(MQL_TESTER)) Sleep(80);
            curPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(openedCnt == 0)
            {
               CalcPrecisionSLTPDist(slDist, tpDist);
               g_lastSLDist = slDist;
               g_lastTPDist = tpDist;
               slPrice = (type == POSITION_TYPE_BUY) ? NormalizeDouble(curPrice - slDist, g_digits)
                                                     : NormalizeDouble(curPrice + slDist, g_digits);
               tpPrice = (type == POSITION_TYPE_BUY) ? NormalizeDouble(curPrice + tpDist, g_digits)
                                                     : NormalizeDouble(curPrice - tpDist, g_digits);
            }
         }

         g_trade.SetExpertMagicNumber(InpMagicBot);
         g_trade.SetDeviationInPoints(InpSlippage);
         g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

         bool ok;
         if(type == POSITION_TYPE_BUY)
            ok = g_trade.Buy(chunkLot, _Symbol, curPrice, slPrice, tpPrice, cmt);
         else
            ok = g_trade.Sell(chunkLot, _Symbol, curPrice, slPrice, tpPrice, cmt);

         uint rc = g_trade.ResultRetcode();
         if(ok && RetcodeOK(rc))
         {
            chunkSent = true;
            break;
         }

         if(attempt < maxFastTry && IsRetryableRetcode(rc))
         {
            Print(StringFormat("[RETRY %d/%d] Order #%d (%.2f lot) kode %u (%s), mencoba ulang...",
                               attempt + 1, maxFastTry, partIdx, chunkLot, rc, g_trade.ResultRetcodeDescription()));
            continue;
         }

         Print(StringFormat("Order #%d (%.2f lot) gagal. Kode: %u (%s)",
                            partIdx, chunkLot, rc, g_trade.ResultRetcodeDescription()));
         break;
      }

      if(!chunkSent)
         break;

      openedCnt++;
      openedLots += chunkLot;

      // FIX BUG v8.10: Gunakan NormalizeRemainingLot (BOLEH mengembalikan 0.0!)
      // Sebelumnya NormalizeTotalLot(0.0) memaksa naik ke 0.01 sehingga loop menembak 0.01 terus-menerus!
      remLot = NormalizeRemainingLot(remLot - chunkLot);
      partIdx++;
   }

   g_isOpeningBasket = false;

   if(openedCnt > 0)
   {
      if(openedCnt > 1)
         Print(StringFormat("[SPLIT ORDER STEP %d] Berhasil membuka %d posisi dengan Total Lot %.2f (Target %.2f).",
                            g_currentStep, openedCnt, openedLots, totalLot));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| [11] Penyimpanan State Lengkap (tahan restart / ganti timeframe) |
//+------------------------------------------------------------------+
void SaveState()
{
   if(MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(g_gvPrefix + "step",     (double)g_currentStep);
   GlobalVariableSet(g_gvPrefix + "lot",      g_currentBotLot);
   GlobalVariableSet(g_gvPrefix + "pending",  (double)g_pendingDir);
   GlobalVariableSet(g_gvPrefix + "sldist",   g_lastSLDist);
   GlobalVariableSet(g_gvPrefix + "tpdist",   g_lastTPDist);
   GlobalVariableSet(g_gvPrefix + "cyclenet", g_cycleNet);
   GlobalVariableSet(g_gvPrefix + "daystamp", (double)g_dayStamp);
   GlobalVariableSet(g_gvPrefix + "dayeq",    g_dayStartEquity);
   GlobalVariableSet(g_gvPrefix + "time",     (double)TimeCurrent());
}

void LoadState()
{
   if(GlobalVariableCheck(g_gvPrefix + "daystamp") && GlobalVariableCheck(g_gvPrefix + "dayeq"))
   {
      int savedDay = (int)GlobalVariableGet(g_gvPrefix + "daystamp");
      double savedEq = GlobalVariableGet(g_gvPrefix + "dayeq");
      if(savedDay == DayStamp(TimeCurrent()) && savedEq > 0.0)
      {
         g_dayStamp       = savedDay;
         g_dayStartEquity = savedEq;
      }
   }

   if(!GlobalVariableCheck(g_gvPrefix + "step")) return;

   int      step = (int)GlobalVariableGet(g_gvPrefix + "step");
   double   lot  = GlobalVariableGet(g_gvPrefix + "lot");
   int      pend = (int)GlobalVariableGet(g_gvPrefix + "pending");
   datetime t    = (datetime)GlobalVariableGet(g_gvPrefix + "time");

   bool hasPos = (CountPositions(InpMagicBot) > 0);
   bool fresh  = ((TimeCurrent() - t) <= 120);

   if(!hasPos && !fresh) return;
   if(step < 1 || lot <= 0.0) return;

   g_currentStep   = step;
   g_currentBotLot = NormalizeTotalLot(lot);
   g_pendingDir    = (!hasPos && fresh && pend >= 0 && pend <= 1) ? pend : -1;
   if(GlobalVariableCheck(g_gvPrefix + "sldist"))   g_lastSLDist = GlobalVariableGet(g_gvPrefix + "sldist");
   if(GlobalVariableCheck(g_gvPrefix + "tpdist"))   g_lastTPDist = GlobalVariableGet(g_gvPrefix + "tpdist");
   if(GlobalVariableCheck(g_gvPrefix + "cyclenet")) g_cycleNet   = GlobalVariableGet(g_gvPrefix + "cyclenet");
   if(g_currentStep > g_maxStepReached) g_maxStepReached = g_currentStep;

   Print(StringFormat("State v9.00 dipulihkan: Step %d, Lot %.2f, Siklus $%+.2f, Pending=%d",
                      g_currentStep, g_currentBotLot, g_cycleNet, g_pendingDir));
}

//+------------------------------------------------------------------+
//| [12] Helper                                                      |
//+------------------------------------------------------------------+
double CalcStartLot()
{
   double lot = InpStartLot;
   if(InpAutoLot && InpAutoLotEvery > 0.0)
   {
      double units = MathFloor(AccountInfoDouble(ACCOUNT_BALANCE) / InpAutoLotEvery);
      lot = MathMax(units, 1.0) * InpAutoLotBase;
   }
   return NormalizeTotalLot(lot);
}

int CountPositions(long magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
         count++;
   }
   return count;
}

double BotOpenLots(long magic)
{
   double lots = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic)
         lots += PositionGetDouble(POSITION_VOLUME);
   }
   return lots;
}

double BotFloatingPL()
{
   double p = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicBot)
         p += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   return p;
}

bool RetcodeOK(uint code)
{
   return (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_PLACED);
}

bool HasMargin(ENUM_ORDER_TYPE type, double lot, double price)
{
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lot, price, margin)) return false;
   return (AccountInfoDouble(ACCOUNT_MARGIN_FREE) >= margin * 1.02);
}

ENUM_ORDER_TYPE_FILLING GetOptimalFilling(string symbol)
{
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

int GetLotDigits(double stepLot)
{
   int dig = 0;
   double s = stepLot;
   while(dig < 8 && MathAbs(s - MathRound(s)) > 1e-8) { s *= 10.0; dig++; }
   return dig;
}

// Normalisasi untuk 1 tiket order (dibatasi SYMBOL_VOLUME_MAX broker)
double NormalizeSingleOrderLot(double lot)
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

// Normalisasi Total Lot Martingale (pembulatan terdekat, minimal minLot)
double NormalizeTotalLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 0.01;

   int dig = GetLotDigits(stepLot);
   lot = MathMax(lot, minLot);
   return NormalizeDouble(MathRound(lot / stepLot) * stepLot, dig);
}

// Pembulatan KE ATAS ke kelipatan stepLot agar profit recovery TIDAK PERNAH kurang dari target
double CeilTotalLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 0.01;

   int dig = GetLotDigits(stepLot);
   if(lot < minLot) return NormalizeDouble(minLot, dig);
   double units = MathCeil((lot / stepLot) - 1e-9);
   return NormalizeDouble(units * stepLot, dig);
}

// Normalisasi sisa lot pada split-order (WAJIB bisa kembali 0.0 agar loop berhenti bersih!)
double NormalizeRemainingLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0.0) stepLot = 0.01;

   if(lot < minLot - 1e-8)
      return 0.0;

   int dig = GetLotDigits(stepLot);
   double res = NormalizeDouble(MathRound(lot / stepLot) * stepLot, dig);
   return (res < minLot - 1e-8) ? 0.0 : res;
}

//+------------------------------------------------------------------+
//| [13] Dashboard di Chart (murni tampilan)                         |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   static uint lastMs = 0;
   uint now = GetTickCount();
   if(now - lastMs < 500) return;
   lastMs = now;

   int    posCount = CountPositions(InpMagicBot);
   double openLots = BotOpenLots(InpMagicBot);

   string status;
   if(!InpEnableBot)
      status = "NONAKTIF";
   else if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      status = "ALGO TRADING OFF!";
   else if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
      status = "SIMBOL TRADE DISABLED (CEK SIMBOL XM!)";
   else if(g_pendingDir >= 0)
      status = StringFormat("MENUNGGU FLIP STEP %d (Lot %.2f - %s)", g_currentStep, g_currentBotLot, (g_pendingDir == 0) ? "BUY" : "SELL");
   else if(posCount == 0)
   {
      string d = DailyBlock();
      if(d != "")
         status = "STANDBY - " + d;
      else
         status = (InpTriggerMode == TRIGGER_CANDLE)
                  ? (InpExactZeroTimer ? "STANDBY (Timer Presisi Detik :00)" : "STANDBY (menunggu kotak baru)")
                  : "STANDBY (menunggu crossing level)";
   }
   else if(posCount > 1)
      status = StringFormat("AKTIF - STEP %d (Total Lot: %.2f | %d Tiket)", g_currentStep, openLots, posCount);
   else
      status = StringFormat("AKTIF - STEP %d (1 Posisi | Lot: %.2f)", g_currentStep, openLots);

   double liveSLDist = 0.0, liveTPDist = 0.0;
   CalcPrecisionSLTPDist(liveSLDist, liveTPDist);
   double showSLDist = (posCount > 0) ? g_lastSLDist : liveSLDist;
   double showTPDist = (posCount > 0) ? g_lastTPDist : liveTPDist;
   double activeLot  = (posCount > 0) ? openLots : g_currentBotLot;

   double stepSLUsd  = activeLot * GetNetSLMoneyPer1Lot(showSLDist);
   double stepTPUsd  = activeLot * GetNetTPMoneyPer1Lot(showTPDist);
   double estNetTP   = g_cycleNet + stepTPUsd;
   double rrVal      = (showSLDist > 0.0) ? (showTPDist / showSLDist) : 0.0;

   string stepLimit = (InpMaxSteps > 0) ? IntegerToString(InpMaxSteps) : "tanpa batas";
   string lotModeTx = (InpLotMode == LOT_PRECISION_RECOVERY) ? "Presisi RR 1:2 (Auto)" : StringFormat("Pengali %.2fx", InpLotMultiplier);
   double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   string spStatus  = (InpMaxSpreadPts > 0 && spreadPts > InpMaxSpreadPts) ? " [TERBLOKIR!]" : " [OK]";
   double dayPct    = (g_dayStartEquity > 0.0) ? (AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity) / g_dayStartEquity * 100.0 : 0.0;
   int    total     = g_cntTP + g_cntSL;
   double winRate   = (total > 0) ? (100.0 * g_cntTP / total) : 0.0;
   string srvClock  = TimeToString(GetEstimatedServerTime(), TIME_SECONDS);

   string s = "";
   s += "===============================================\n";
   s += "  MESIN UANG v9.00 — PRECISION FLIP (RR 1:2)\n";
   s += "===============================================\n";
   s += " Simbol    : " + _Symbol + " | Jam Srv: " + srvClock + "\n";
   s += " Status    : " + status + "\n";
   s += " Info :00  : " + g_lastTriggerInfo + "\n";
   s += " Mode Lot  : " + lotModeTx + "\n";
   s += " Step/Maks : " + IntegerToString(g_currentStep) + " / " + stepLimit + " | Lot Step Ini: " + DoubleToString(activeLot, 2) + "\n";
   s += StringFormat(" SL Bersih : -$%.2f (jarak %.*f / %.0f pts)\n", stepSLUsd, g_digits, showSLDist, showSLDist / g_point);
   s += StringFormat(" TP Bersih : +$%.2f (jarak %.*f / %.0f pts) [1:%.2f]\n", stepTPUsd, g_digits, showTPDist, showTPDist / g_point, rrVal);
   s += StringFormat(" Est Net TP: $%+.2f (tutup rugi siklus $%+.2f)\n", estNetTP, g_cycleNet);
   s += " Spread    : " + DoubleToString(spreadPts, 0) + " / " + ((InpMaxSpreadPts > 0) ? IntegerToString(InpMaxSpreadPts) : "OFF") + " poin" + spStatus + "\n";
   s += "-----------------------------------------------\n";
   s += " Floating  : $" + DoubleToString(BotFloatingPL(), 2) + " | Siklus: $" + DoubleToString(g_cycleNet, 2) + "\n";
   s += " Hari ini  : " + DoubleToString(dayPct, 2) + " %\n";
   s += " Sesi      : TP " + IntegerToString(g_cntTP) + " | SL " + IntegerToString(g_cntSL)
        + " | Win " + DoubleToString(winRate, 1) + " %\n";
   s += " Hasil sesi: $" + DoubleToString(g_sessionNet, 2) + " | Step maks: " + IntegerToString(g_maxStepReached) + "\n";
   s += " Magic ID  : " + IntegerToString((int)InpMagicBot) + "\n";
   s += "===============================================";
   Comment(s);
}
//+------------------------------------------------------------------+
