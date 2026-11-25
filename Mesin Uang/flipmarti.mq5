//+------------------------------------------------------------------+
//|                                           Mesin Uang.mq5         |
//|  Mesin Uang v8.10 - Gold Scalper & Split-Order Flip Martingale   |
//|  Auto Split Lot (81.92 x N), Anti-Reset 0.01, Spread Comp & BE   |
//|                                      https://sagu.pages.dev      |
//+------------------------------------------------------------------+
#property copyright   "Mochamad Tabrani & Antigravity AI"
#property link        "https://sagu.pages.dev"
#property version     "8.10"
#property description "Mesin Uang v8.10: Auto Pecah Lot Besar (81.92 x N), Anti-Reset 0.01, Auto BE, Spread Comp & Filter Gergaji"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| [1] Enum & Parameter Input                                       |
//+------------------------------------------------------------------+
enum ENUM_TRIGGER_MODE
{
   TRIGGER_CANDLE   = 0,   // Candle: close kotak naik = BUY, turun = SELL
   TRIGGER_CROSSING = 1    // Crossing level angka bulat
};

enum ENUM_DIST_MODE
{
   DIST_FIXED = 0,         // Jarak SL tetap
   DIST_ATR   = 1          // Jarak SL mengikuti ATR
};

enum ENUM_RR_MODE
{
   RR_1_1    = 0,          // 1:1 (SL 1, TP 1)
   RR_1_2    = 1,          // 1:2 (SL 1, TP 2)
   RR_1_3    = 2,          // 1:3 (SL 1, TP 3)
   RR_CUSTOM = 3           // Kustom (isi pengali TP di bawah)
};

enum ENUM_AFTER_TP_MODE
{
   AFTER_TP_CONTINUE    = 0, // Langsung tembak searah (jika lolos filter)
   AFTER_TP_WAIT_SIGNAL = 1  // Kembali STANDBY tunggu sinyal baru (Lebih Aman di Gold)
};

input group "=== STRATEGI UTAMA & PECAH LOT BESAR ==="
input bool                InpEnableBot        = true;              // Aktifkan Mesin Uang Otomatis?
input ENUM_TRIGGER_MODE   InpTriggerMode      = TRIGGER_CANDLE;    // Pemicu entri siklus baru
input ENUM_TIMEFRAMES     InpTriggerTF        = PERIOD_M1;         // Timeframe kotak (mode Candle)
input double              InpPriceInterval    = 1.0;               // Jarak level angka bulat (mode Crossing)
input ENUM_AFTER_TP_MODE  InpAfterTPMode      = AFTER_TP_CONTINUE; // Aksi setelah TP tercapai
input double              InpStartLot         = 0.01;              // Lot Dasar Awal (Step 1)
input double              InpLotMultiplier    = 2.0;               // Faktor Pengali Martingale
input int                 InpMaxSteps         = 0;                 // Step maks (0 = tanpa batas, terus lipat lot)
input double              InpMaxLotPerOrder   = 81.92;             // Maks Lot per 1 Order (lebih dari ini otomatis dipecah beberapa kali)
input bool                InpFitLotToMargin   = true;              // Jika margin kurang untuk lot penuh, buka sebesar margin yang muat (jangan reset 0.01)

input group "=== JARAK TP, SL & KOMPENSASI SPREAD ==="
input ENUM_RR_MODE        InpRRMode           = RR_1_1;            // Rasio SL : TP
input double              InpCustomRR         = 1.5;               // Pengali TP terhadap SL (jika rasio Kustom)
input ENUM_DIST_MODE      InpDistMode         = DIST_FIXED;        // Mode jarak SL
input double              InpTargetDistance   = 1.0;               // Jarak SL tetap (harga); mis. 1.00 di Gold
input ENUM_TIMEFRAMES     InpATRTF            = PERIOD_M5;         // Timeframe ATR (mode ATR & Filter)
input int                 InpATRPeriod        = 14;                // Periode ATR
input double              InpATRMultiplier    = 1.0;               // Pengali ATR untuk jarak TP/SL
input bool                InpCompensateSpread = true;              // Tambahkan Spread otomatis ke jarak TP?

input group "=== PROTEKSI PROFIT LOCK / BREAK-EVEN (GOLD) ==="
input int                 InpBEStartStep      = 3;                 // Aktifkan Break-Even mulai Step ke- (0 = nonaktif, 1 = semua step)
input double              InpBETriggerPct     = 65.0;              // Geser SL ke BE saat harga capai % dari target TP
input int                 InpBELockPts        = 10;                // Poin profit yang dikunci saat BE (poin)

input group "=== AUTO LOT (OPSIONAL) ==="
input bool                InpAutoLot          = false;             // Lot awal mengikuti saldo?
input double              InpAutoLotBase      = 0.01;              // Lot per kelipatan saldo
input double              InpAutoLotEvery     = 100.0;             // Kelipatan saldo (mata uang akun)

input group "=== FILTER ANTI-SIDEWAYS & ENTRI SIKLUS BARU ==="
input double              InpMinCandleBody    = 0.20;              // Body candle min (harga, mis 0.20 di Gold; 0 = nonaktif)
input double              InpMinBodyRatio     = 0.35;              // Rasio Body/Range candle min (0.0 - 1.0; 0 = nonaktif)
input double              InpMinATRValue      = 0.0;               // ATR minimum untuk mulai Step 1 (0 = nonaktif)
input bool                InpUseTrendFilter   = false;             // Hanya entri searah EMA + kemiringan EMA?
input ENUM_TIMEFRAMES     InpTrendTF          = PERIOD_M5;         // Timeframe EMA
input int                 InpTrendMAPeriod    = 50;                // Periode EMA
input int                 InpMaxSpreadPts     = 35;                // Spread maks (poin), 0 = nonaktif
input bool                InpUseTimeFilter    = false;             // Filter jam server?
input int                 InpStartHour        = 1;                 // Jam mulai (0-23)
input int                 InpEndHour          = 23;                // Jam selesai (1-24)
input double              InpDailyTargetPct   = 0.0;               // Stop siklus baru bila untung harian >= % (0 = nonaktif)
input double              InpDailyLossPct     = 0.0;               // Stop bila rugi harian >= % (0 = nonaktif)
input bool                InpHardDailyStop    = false;             // Hentikan rantai Martingale jika rugi harian tembus batas?

input group "=== NOTIFIKASI & BROKER ==="
input bool                InpEnableAlert      = true;              // Popup Alert di Layar MT5?
input bool                InpEnablePush       = false;             // Notifikasi ke HP (MetaQuotes ID)?
input bool                InpVerbose          = true;              // Catat alasan entri dilewati di tab Experts?
input int                 InpMaxRetryCount    = 15;                // Maks percobaan ulang jika koneksi/eksekusi gagal
input int                 InpSlippage         = 50;                // Toleransi Slippage (pts)
input long                InpMagicBot         = 888100;            // Magic Number Khusus Bot Ini

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
double            g_lastDist         = 0.0;
double            g_cycleNet         = 0.0;     // Akumulasi profit/loss bersih siklus berjalan
datetime          g_lastBarTime      = 0;

// Variabel keranjang (Basket) untuk menangani Split Order (mis. 81.92 x 2 = 163.84)
bool              g_isOpeningBasket  = false;   // Flag sedang membuka rangkaian split order
double            g_stepAnchorPrice  = 0.0;     // Harga patokan tiket pertama agar TP/SL semua pecahan sama persis
double            g_stepClosedNet    = 0.0;     // Akumulasi net dari pecahan tiket yang sudah tutup pada step ini
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
      InpTargetDistance <= 0.0 || InpStartLot <= 0.0)
   {
      Print("Mesin Uang: parameter tidak valid. Periksa lot, pengali, step, interval, dan jarak TP/SL.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   g_point    = _Point;
   g_digits   = _Digits;
   g_gvPrefix = StringFormat("MU81_%s_%I64d_", _Symbol, InpMagicBot);

   g_trade.SetExpertMagicNumber(InpMagicBot);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFilling(GetOptimalFilling(_Symbol));

   if(InpDistMode == DIST_ATR || InpMinATRValue > 0.0)
   {
      g_hATR = iATR(_Symbol, InpATRTF, InpATRPeriod);
      if(g_hATR == INVALID_HANDLE)
         Print("Mesin Uang: ATR gagal dibuat, jarak TP/SL memakai nilai tetap.");
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
   g_lastDist        = InpTargetDistance;
   g_cycleNet        = 0.0;
   g_stepAnchorPrice = 0.0;
   g_stepClosedNet   = 0.0;
   g_stepLastReason  = -1;
   g_lastBarTime     = 0;
   g_dayStamp        = DayStamp(TimeCurrent());
   g_dayStartEquity  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!MQLInfoInteger(MQL_TESTER))
      LoadState();

   SaveState();

   Print("=== Mesin Uang Advanced v8.10 (Split-Lot Gold Edition) Aktif ===");
   UpdateChartComment();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hMA  != INVALID_HANDLE) IndicatorRelease(g_hMA);
   if(MQLInfoInteger(MQL_TESTER)) GlobalVariablesDeleteAll(g_gvPrefix);
   Comment("");
   Print("=== Mesin Uang v8.10 Dihentikan ===");
}

//+------------------------------------------------------------------+
//| [4] Eksekusi Tiap Tick                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDay();

   if(InpEnableBot)
   {
      // Kelola Auto Break-Even pada semua posisi aktif di step berjalan
      ManageBreakEven();

      if(g_pendingDir >= 0)
         ProcessPending();
      else if(InpTriggerMode == TRIGGER_CANDLE)
         CheckCandleTrigger();
      else
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
//| [5a] Pemicu Candle: kotak baru + Filter Kualitas Candle Gold     |
//+------------------------------------------------------------------+
void CheckCandleTrigger()
{
   datetime barTime = iTime(_Symbol, InpTriggerTF, 0);
   if(barTime == 0) return;

   if(g_lastBarTime == 0)          // tick pertama: catat saja
   {
      g_lastBarTime = barTime;
      return;
   }
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;        // kotak baru (detik 00)

   if(CountPositions(InpMagicBot) > 0) return;

   double o = iOpen(_Symbol, InpTriggerTF, 1);
   double c = iClose(_Symbol, InpTriggerTF, 1);
   double h = iHigh(_Symbol, InpTriggerTF, 1);
   double l = iLow(_Symbol, InpTriggerTF, 1);

   double body  = MathAbs(c - o);
   double range = h - l;

   if(body < g_point * 0.5)
   {
      if(InpVerbose) Print("Kotak doji (open = close): tidak entri.");
      return;
   }

   if(InpMinCandleBody > 0.0 && body < InpMinCandleBody)
   {
      if(InpVerbose) Print(StringFormat("Kotak dilewati: body %.*f < min %.*f (rawan sideways).",
                                        g_digits, body, g_digits, InpMinCandleBody));
      return;
   }

   if(InpMinBodyRatio > 0.0 && range > 0.0 && (body / range) < InpMinBodyRatio)
   {
      if(InpVerbose) Print(StringFormat("Kotak dilewati: rasio body/range %.2f < %.2f (ekor terlalu panjang).",
                                        body / range, InpMinBodyRatio));
      return;
   }

   bool isBuy = (c > o);
   string why = BlockReason(isBuy);
   if(why != "")
   {
      if(InpVerbose) Print(StringFormat("Kotak %s dilewati: %s.", isBuy ? "naik" : "turun", why));
      return;
   }

   Print(StringFormat("[KOTAK %s] Open %.*f Close %.*f (Body %.*f) -> %s",
         isBuy ? "NAIK" : "TURUN", g_digits, o, g_digits, c, g_digits, body, isBuy ? "BUY" : "SELL"));
   OpenBotOrder(isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL, g_currentBotLot);
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
         if(InpVerbose) Print(StringFormat("Crossing naik %.*f dilewati: %s.", g_digits, levelUp, why));
         return;
      }
      Print(StringFormat("[CROSSING BUY] Melintas naik level %.*f", g_digits, levelUp));
      OpenBotOrder(POSITION_TYPE_BUY, g_currentBotLot);
      return;
   }

   double levelDown = NormalizeDouble(MathCeil((bid - eps) / step) * step, g_digits);
   if(g_lastPrice > levelDown + eps && bid <= levelDown + eps)
   {
      g_lastPrice = bid;
      string why = BlockReason(false);
      if(why != "")
      {
         if(InpVerbose) Print(StringFormat("Crossing turun %.*f dilewati: %s.", g_digits, levelDown, why));
         return;
      }
      Print(StringFormat("[CROSSING SELL] Melintas turun level %.*f", g_digits, levelDown));
      OpenBotOrder(POSITION_TYPE_SELL, g_currentBotLot);
      return;
   }

   g_lastPrice = bid;
}

//+------------------------------------------------------------------+
//| [6] Filter Entri Siklus Baru                                     |
//+------------------------------------------------------------------+
string BlockReason(bool isBuy)
{
   if(!SpreadOK())        return "spread melebihi batas";
   if(!InTradingHours())  return "di luar jam trading";
   string d = DailyBlock();
   if(d != "")            return d;
   if(!VolatilityOK())    return "volatilitas ATR terlalu rendah (sideways)";
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
   TimeToStruct(TimeCurrent(), d);
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
   int today = DayStamp(TimeCurrent());
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
//| [7] Order Lanjutan (Martingale / Searah)                         |
//+------------------------------------------------------------------+
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
//| [8] Transaksi: Kalibrasi & Basket Split-Order Martingale         |
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
      // Simpan harga tiket pertama di step ini agar seluruh pecahan order punya level TP/SL yang identik
      if(g_stepAnchorPrice <= 0.0)
         g_stepAnchorPrice = exactPrice;

      ENUM_POSITION_TYPE pType = (dealType == DEAL_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      CalibratePositionTPSL(posId, g_stepAnchorPrice, pType);
      return;
   }

   if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT)
   {
      if(posId == 0 || IsPosProcessed(posId)) return;
      // Pastikan tiket posisi ini sudah tertutup penuh
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

      // PENTING: Jika pada Step ini ada beberapa order pecahan (mis. 2x 81.92),
      // tunggu sampai SEMUA posisi pada Step ini selesai tertutup baru evaluasi kenaikan Step!
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

   // [A] Kena TP, atau kena SL dalam kondisi Profit/Break-Even yang sudah menutup kerugian siklus
   if(reason == DEAL_REASON_TP || (reason == DEAL_REASON_SL && stepNet >= 0.0 && g_cycleNet >= 0.0))
   {
      g_cntTP++;
      int finishedStep = g_currentStep;
      double totalCycleProfit = g_cycleNet;

      ResetCycleToStep1();

      if(InpAfterTPMode == AFTER_TP_WAIT_SIGNAL)
      {
         string msg = StringFormat("[STEP %d TP SELESAI] Profit Step: %.2f | Total Siklus: %.2f. Kembali STANDBY tunggu sinyal.",
                                   finishedStep, stepNet, totalCycleProfit);
         Print(msg);
         if(InpEnableAlert) Alert(msg);
         return;
      }

      bool isBuy = (origType == POSITION_TYPE_BUY);
      string why = BlockReason(isBuy);
      if(why != "")
      {
         string msg = StringFormat("[STEP %d TP SELESAI] Total Siklus: %.2f. Stop antrean baru karena: %s.",
                                   finishedStep, totalCycleProfit, why);
         Print(msg);
         if(InpEnableAlert) Alert(msg);
         return;
      }

      string msg = StringFormat("[STEP %d TP] Hasil bersih %.2f (Siklus %.2f). Reset ke Step 1, lanjut searah.",
                                finishedStep, stepNet, totalCycleProfit);
      Print(msg);
      if(InpEnableAlert) Alert(msg);

      StartOrQueue(origType);
   }
   // [B] Kena SL saat Break-Even (stepNet >= 0), tetapi akumulasi siklus masih rugi -> Tahan Step & Lot!
   else if(reason == DEAL_REASON_SL && stepNet >= 0.0 && g_cycleNet < 0.0)
   {
      string msg = StringFormat("[STEP %d BREAK-EVEN] Step impas (+%.2f), sisa rugi siklus %.2f. Tahan di Step %d (Lot %.2f).",
                                g_currentStep, stepNet, g_cycleNet, g_currentStep, g_currentBotLot);
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      StartOrQueue(origType);
   }
   // [C] Kena SL Rugi Normal -> Lipat Lot (Tanpa Terpotong MaxLotPerOrder!) + Balik Arah
   else if(reason == DEAL_REASON_SL)
   {
      g_cntSL++;
      int slStep = g_currentStep;

      if(InpHardDailyStop)
      {
         string dBlock = DailyBlock();
         if(dBlock != "")
         {
            string msg = StringFormat("[HARD STOP HARIAN] Step %d SL (%.2f) menyentuh %s. Siklus dihentikan & reset ke Step 1!",
                                      slStep, stepNet, dBlock);
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
         // PENTING: Gunakan NormalizeTotalLot (tidak dipotong SYMBOL_VOLUME_MAX)
         // sehingga setelah 81.92 kena SL, g_currentBotLot naik menjadi 163.84!
         g_currentBotLot = NormalizeTotalLot(g_currentBotLot * InpLotMultiplier);
      }
      if(g_currentStep > g_maxStepReached) g_maxStepReached = g_currentStep;

      double maxChunk = GetMaxLotPerTicket();
      int    chunks   = (int)MathCeil((g_currentBotLot - 1e-8) / maxChunk);

      string msg = capped
         ? StringFormat("[STEP %d SL] Bersih %.2f (Siklus %.2f). Step maks: lot ditahan %.2f (%d order), balik arah.",
                        slStep, stepNet, g_cycleNet, g_currentBotLot, chunks)
         : StringFormat("[STEP %d SL] Bersih %.2f (Siklus %.2f). Balik arah ke Step %d -> Total Lot %.2f (%d order).",
                        slStep, stepNet, g_cycleNet, g_currentStep, g_currentBotLot, chunks);
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      if(InpEnablePush && capped) SendNotification(msg);

      StartOrQueue((origType == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY);
   }
   // [D] Stop Out / Ditutup Manual
   else
   {
      string why = (reason == DEAL_REASON_SO) ? "STOP OUT oleh broker" : "ditutup manual/sebab lain";
      string msg = StringFormat("Posisi %s (hasil bersih %.2f). Siklus direset ke Step 1.", why, stepNet);
      Print(msg);
      if(InpEnableAlert) Alert(msg);
      if(InpEnablePush)  SendNotification(msg);

      ResetCycleToStep1();
   }
}

//+------------------------------------------------------------------+
//| [9] Kalibrasi TP/SL Pasca-Eksekusi & Auto Break-Even             |
//+------------------------------------------------------------------+
void CalibratePositionTPSL(ulong posTicket, double anchorPrice, ENUM_POSITION_TYPE posType)
{
   if(!PositionSelectByTicket(posTicket)) return;

   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist    = (g_lastDist > 0.0) ? g_lastDist : InpTargetDistance;
   double tpDist  = (dist * GetRR()) + (InpCompensateSpread ? spread : 0.0);

   double exactTP = (posType == POSITION_TYPE_BUY) ? (anchorPrice + tpDist) : (anchorPrice - tpDist);
   double exactSL = (posType == POSITION_TYPE_BUY) ? (anchorPrice - dist)   : (anchorPrice + dist);
   exactTP = NormalizeDouble(exactTP, g_digits);
   exactSL = NormalizeDouble(exactSL, g_digits);

   double currentTP = PositionGetDouble(POSITION_TP);
   double currentSL = PositionGetDouble(POSITION_SL);

   if(MathAbs(currentTP - exactTP) > (g_point * 0.1) || MathAbs(currentSL - exactSL) > (g_point * 0.1))
   {
      g_trade.SetExpertMagicNumber(InpMagicBot);
      if(g_trade.PositionModify(posTicket, exactSL, exactTP) && RetcodeOK(g_trade.ResultRetcode()))
         Print(StringFormat("[KALIBRASI] Tiket #%I64u | Anchor %.*f | TP %.*f | SL %.*f",
                            posTicket, g_digits, anchorPrice, g_digits, exactTP, g_digits, exactSL));
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
//| [10] Eksekutor Order (Support Pecah Lot Otomatis: 81.92 x N)     |
//+------------------------------------------------------------------+
double GetBaseDist()
{
   if(InpDistMode == DIST_ATR && g_hATR != INVALID_HANDLE)
   {
      double a[];
      ArraySetAsSeries(a, true);
      if(CopyBuffer(g_hATR, 0, 1, 1, a) == 1 && a[0] > 0.0)
         return a[0] * InpATRMultiplier;
   }
   return InpTargetDistance;
}

double GetRR()
{
   switch(InpRRMode)
   {
      case RR_1_2:    return 2.0;
      case RR_1_3:    return 3.0;
      case RR_CUSTOM: return MathMax(0.1, InpCustomRR);
      default:        return 1.0;
   }
}

double GetDist()
{
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   double spread  = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double need    = stopLvl + spread + 2.0 * g_point;
   return MathMax(GetBaseDist(), need);
}

double GetMaxLotPerTicket()
{
   double brokerMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(brokerMax <= 0.0) brokerMax = 100.0;
   double maxTicket = (InpMaxLotPerOrder > 0.0) ? MathMin(InpMaxLotPerOrder, brokerMax) : brokerMax;
   return NormalizeSingleOrderLot(maxTicket);
}

// Hitung berapa lot maksimal yang muat dengan Free Margin saat ini
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

bool OpenBotOrder(ENUM_POSITION_TYPE type, double totalLot)
{
   totalLot = NormalizeTotalLot(totalLot);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxTicket = GetMaxLotPerTicket();

   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist   = NormalizeDouble(GetDist(), g_digits);
   double tpDist = NormalizeDouble((dist * GetRR()) + (InpCompensateSpread ? spread : 0.0), g_digits);

   g_lastDist        = dist;
   g_stepAnchorPrice = 0.0;
   g_stepClosedNet   = 0.0;
   g_stepLastReason  = -1;
   SaveState();

   // Hitung jumlah pecahan order (misal 163.84 dengan batas 81.92 -> 2 order @ 81.92)
   int totalParts = (int)MathCeil((totalLot - 1e-8) / maxTicket);
   if(totalParts < 1) totalParts = 1;

   double remLot     = totalLot;
   int    openedCnt  = 0;
   double openedLots = 0.0;
   int    partIdx    = 1;

   // Anchor SL & TP awal dari harga saat mulai menembak keranjang
   double refPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slPrice  = (type == POSITION_TYPE_BUY) ? NormalizeDouble(refPrice - dist, g_digits)
                                                 : NormalizeDouble(refPrice + dist, g_digits);
   double tpPrice  = (type == POSITION_TYPE_BUY) ? NormalizeDouble(refPrice + tpDist, g_digits)
                                                 : NormalizeDouble(refPrice - tpDist, g_digits);

   g_isOpeningBasket = true;

   while(remLot >= minLot - 1e-8)
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
               Print(StringFormat("[PENYESUAIAN MARGIN] Margin tidak cukup untuk %.2f lot, disesuaikan ke %.2f lot agar tidak reset.",
                                  chunkLot, afford));
               chunkLot = afford;
               remLot   = chunkLot; // Habiskan sisa ke lot maksimal yang muat
            }
            else
            {
               Print("Margin bebas tidak cukup untuk membuka tambahan pecahan order (sisa ", DoubleToString(remLot, 2), " lot).");
               break;
            }
         }
         else
         {
            Print("Margin tidak cukup untuk ", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL", " lot ", DoubleToString(chunkLot, 2));
            break;
         }
      }

      g_trade.SetExpertMagicNumber(InpMagicBot);
      string cmt = (totalParts > 1)
         ? StringFormat("MesinUang %s S%d (%d/%d)", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL", g_currentStep, partIdx, totalParts)
         : StringFormat("MesinUang %s S%d", (type == POSITION_TYPE_BUY) ? "BUY" : "SELL", g_currentStep);

      bool ok;
      if(type == POSITION_TYPE_BUY)
         ok = g_trade.Buy(chunkLot, _Symbol, curPrice, slPrice, tpPrice, cmt);
      else
         ok = g_trade.Sell(chunkLot, _Symbol, curPrice, slPrice, tpPrice, cmt);

      if(!ok || !RetcodeOK(g_trade.ResultRetcode()))
      {
         Print(StringFormat("Order pecahan #%d (%.2f lot) gagal. Kode: %u (%s)",
                            partIdx, chunkLot, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription()));
         break;
      }

      openedCnt++;
      openedLots += chunkLot;
      remLot = NormalizeTotalLot(remLot - chunkLot);
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
   GlobalVariableSet(g_gvPrefix + "dist",     g_lastDist);
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
   if(GlobalVariableCheck(g_gvPrefix + "dist"))     g_lastDist = GlobalVariableGet(g_gvPrefix + "dist");
   if(GlobalVariableCheck(g_gvPrefix + "cyclenet")) g_cycleNet = GlobalVariableGet(g_gvPrefix + "cyclenet");
   if(g_currentStep > g_maxStepReached) g_maxStepReached = g_currentStep;

   Print(StringFormat("State v8.10 dipulihkan: Step %d, Total Lot %.2f, Siklus %.2f, Pending=%d",
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

// Normalisasi untuk 1 tiket order (dibatasi SYMBOL_VOLUME_MAX broker)
double NormalizeSingleOrderLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0) stepLot = 0.01;

   int dig = 0;
   double s = stepLot;
   while(dig < 8 && MathAbs(s - MathRound(s)) > 1e-8) { s *= 10.0; dig++; }

   lot = MathMax(lot, minLot);
   if(maxLot > 0.0) lot = MathMin(lot, maxLot);
   return NormalizeDouble(MathRound(lot / stepLot) * stepLot, dig);
}

// Normalisasi untuk Total Lot Martingale (TIDAK dibatasi SYMBOL_VOLUME_MAX agar bisa > 81.92 / 163.84+)
double NormalizeTotalLot(double lot)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0) stepLot = 0.01;

   int dig = 0;
   double s = stepLot;
   while(dig < 8 && MathAbs(s - MathRound(s)) > 1e-8) { s *= 10.0; dig++; }

   lot = MathMax(lot, minLot);
   return NormalizeDouble(MathRound(lot / stepLot) * stepLot, dig);
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
   else if(g_pendingDir >= 0)
      status = StringFormat("MENUNGGU EKSEKUSI STEP %d (Lot %.2f - %s)", g_currentStep, g_currentBotLot, (g_pendingDir == 0) ? "BUY" : "SELL");
   else if(posCount == 0)
   {
      string d = DailyBlock();
      if(d != "")
         status = "STANDBY - " + d;
      else
         status = (InpTriggerMode == TRIGGER_CANDLE) ? "STANDBY (menunggu kotak baru)" : "STANDBY (menunggu crossing level)";
   }
   else if(posCount > 1)
      status = StringFormat("AKTIF - STEP %d (Total Lot: %.2f | %d Order)", g_currentStep, openLots, posCount);
   else
      status = StringFormat("AKTIF - STEP %d (Lot: %.2f)", g_currentStep, openLots);

   string stepLimit = (InpMaxSteps > 0) ? IntegerToString(InpMaxSteps) : "tanpa batas";
   string distTxt   = (InpDistMode == DIST_ATR)
                      ? StringFormat("ATR x %.2f (sekarang %s)", InpATRMultiplier, DoubleToString(GetBaseDist(), g_digits))
                      : DoubleToString(InpTargetDistance, g_digits);
   double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / g_point;
   double dayPct    = (g_dayStartEquity > 0.0) ? (AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartEquity) / g_dayStartEquity * 100.0 : 0.0;
   int    total     = g_cntTP + g_cntSL;
   double winRate   = (total > 0) ? (100.0 * g_cntTP / total) : 0.0;
   string beTxt     = (InpBEStartStep > 0) ? StringFormat("Mulai Step %d (@%.0f%% TP)", InpBEStartStep, InpBETriggerPct) : "Nonaktif";

   string s = "";
   s += "===========================================\n";
   s += "  MESIN UANG ADVANCED v8.10 (SPLIT-LOT)\n";
   s += "===========================================\n";
   s += " Simbol    : " + _Symbol + "\n";
   s += " Status    : " + status + "\n";
   s += " Pemicu    : " + ((InpTriggerMode == TRIGGER_CANDLE) ? "Candle " + EnumToString(InpTriggerTF) : "Crossing level") + "\n";
   s += " Step/Maks : " + IntegerToString(g_currentStep) + " / " + stepLimit + " (Maks/Tiket: " + DoubleToString(GetMaxLotPerTicket(), 2) + ")\n";
   s += " Jarak SL  : " + distTxt + (InpCompensateSpread ? " (+Spread Komp)" : "") + "\n";
   s += " Rasio     : SL 1 : TP " + DoubleToString(GetRR(), 1) + "\n";
   s += " ProfitLock: " + beTxt + "\n";
   s += " Spread    : " + DoubleToString(spreadPts, 0) + " poin\n";
   s += "-------------------------------------------\n";
   s += " Floating  : " + DoubleToString(BotFloatingPL(), 2) + " | Siklus: " + DoubleToString(g_cycleNet, 2) + "\n";
   s += " Hari ini  : " + DoubleToString(dayPct, 2) + " %\n";
   s += " Sesi      : TP " + IntegerToString(g_cntTP) + " | SL " + IntegerToString(g_cntSL)
        + " | Win " + DoubleToString(winRate, 1) + " %\n";
   s += " Hasil sesi: " + DoubleToString(g_sessionNet, 2) + " | Step tertinggi: " + IntegerToString(g_maxStepReached) + "\n";
   s += " Magic ID  : " + IntegerToString((int)InpMagicBot) + "\n";
   s += "===========================================";
   Comment(s);
}
//+------------------------------------------------------------------+
