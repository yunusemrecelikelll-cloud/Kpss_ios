import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show anasayfaKokunde, hakPiliGizle, rootNavigatorKey;
import '../screens/hak_satin_al_screen.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/in_app_notice_service.dart';
import '../services/notification_service.dart';
import '../services/presence_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';

/// Uygulamanın TAMAMINI saran bildirim katmanı (main.dart → MaterialApp.builder).
///
/// İKİ iş yapar:
///  1. GÖZCÜ: Giriş yapılmışsa DM thread'lerini ve gelen arkadaşlık isteklerini
///     dinler. Yeni bir mesaj/istek geldiğinde:
///       • uygulama AÇIKTAYSA  → üstten kayan afiş (InAppNoticeService kuyruğu;
///         test sırasında otomatik ertelenir, test bitince gösterilir),
///       • uygulama ARKA PLANDAYSA → yerel telefon bildirimi (best-effort;
///         işletim sistemi süreci öldürmüşse bildirim gösterilemez — gerçek
///         push için FCM + sunucu tetikleyicisi gerekir).
///  2. ÇİZİM: InAppNoticeService'in aktif afişini üstten aşağı kaydırır,
///     ~4 sn bekletir, yukarı geri kaydırıp kuyruktaki sıradakine geçer.
class InAppNoticeOverlay extends StatefulWidget {
  final Widget child;
  const InAppNoticeOverlay({super.key, required this.child});

  @override
  State<InAppNoticeOverlay> createState() => _InAppNoticeOverlayState();
}

class _InAppNoticeOverlayState extends State<InAppNoticeOverlay>
    with WidgetsBindingObserver {
  final ChatService _chat = ChatService();
  final InAppNoticeService _servis = InAppNoticeService.instance;

  StreamSubscription? _threadAboneligi;
  StreamSubscription? _istekAboneligi;
  String? _dinlenenUid;

  // İlk anlık görüntü TABAN alınır: uygulama açılırken zaten var olan
  // okunmamışlar/istekler için afiş yağmuru olmasın.
  bool _threadTabanAlindi = false;
  bool _istekTabanAlindi = false;
  final Map<String, int> _sonOkunmamis = {};
  final Set<String> _bilinenIstekler = {};

  AppLifecycleState _yasamDurumu = AppLifecycleState.resumed;

  // Afiş animasyon durumu.
  bool _afisGorunur = false;
  InAppNotice? _cizilen;
  Timer? _kapatmaZamanlayici;

  // ── Uygulamada geçirilen süre sayacı (yönetici paneli için) ──────────────
  // Uygulama ön plandayken çalışan kronometre; periyodik olarak ve arka plana
  // geçince yerel toplama eklenir (bkz. StorageService.addAppUsageSeconds).
  final Stopwatch _kullanimSw = Stopwatch();
  Timer? _kullanimFlush;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _servis.addListener(_servisDegisti);
    // Ön plan süre sayacını başlat ve dakikada bir yerel toplama yaz (uygulama
    // aniden kapansa bile kaybı en fazla ~1 dk olsun).
    _kullanimSw.start();
    _kullanimFlush = Timer.periodic(
        const Duration(seconds: 60), (_) => _kullanimYaz(devamEt: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _servis.removeListener(_servisDegisti);
    _threadAboneligi?.cancel();
    _istekAboneligi?.cancel();
    _kapatmaZamanlayici?.cancel();
    _kullanimFlush?.cancel();
    _kullanimYaz(devamEt: false);
    super.dispose();
  }

  /// Kronometredeki süreyi yerel toplama ekler. [devamEt] true ise (periyodik
  /// akış / hâlâ ön plan) sayaç sıfırlanıp yeniden başlatılır.
  void _kullanimYaz({required bool devamEt}) {
    final sn = _kullanimSw.elapsed.inSeconds;
    if (sn > 0 && mounted) {
      // ignore: unawaited_futures
      context.read<StorageService>().addAppUsageSeconds(sn);
    }
    _kullanimSw.reset();
    if (devamEt && _yasamDurumu == AppLifecycleState.resumed) {
      _kullanimSw.start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final oncekiDurum = _yasamDurumu;
    _yasamDurumu = state;

    // Süre sayacı: öne gelince başlat, arka plana geçince durdurup yaz.
    if (state == AppLifecycleState.resumed) {
      if (!_kullanimSw.isRunning) _kullanimSw.start();
    } else if (oncekiDurum == AppLifecycleState.resumed) {
      _kullanimSw.stop();
      _kullanimYaz(devamEt: false);
    }

    // Uygulama öne geldiğinde canlılık kaydını tazele (yönetici panelindeki
    // "online" sayısı bundan beslenir) ve panelden premium verildiyse uygula.
    if (state == AppLifecycleState.resumed && mounted) {
      final storage = context.read<StorageService>();
      // ignore: unawaited_futures
      PresenceService.instance.bildir(storage);
      // ignore: unawaited_futures
      PresenceService.instance.premiumKontrol(storage);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Giriş/çıkışta aboneliği tazele.
    final uid = context.watch<AuthService>().currentUser?.uid;
    if (uid == _dinlenenUid) return;
    _dinlenenUid = uid;
    _threadAboneligi?.cancel();
    _istekAboneligi?.cancel();
    _threadTabanAlindi = false;
    _istekTabanAlindi = false;
    _sonOkunmamis.clear();
    _bilinenIstekler.clear();
    if (uid == null) return;

    // Giriş algılandı: canlılık kaydı + panelden verilen premium kontrolü.
    final storage = context.read<StorageService>();
    // ignore: unawaited_futures
    PresenceService.instance.bildir(storage);
    // ignore: unawaited_futures
    PresenceService.instance.premiumKontrol(storage);

    _threadAboneligi = _chat.streamMyThreads(uid).listen((threadler) {
      if (!_threadTabanAlindi) {
        for (final t in threadler) {
          _sonOkunmamis[t.threadId] = t.unreadCount;
        }
        _threadTabanAlindi = true;
        return;
      }
      for (final t in threadler) {
        final onceki = _sonOkunmamis[t.threadId] ?? 0;
        _sonOkunmamis[t.threadId] = t.unreadCount;
        final yeniGeldi = t.unreadCount > onceki && t.lastSenderUid != uid;
        if (!yeniGeldi) continue;
        // O sohbetin İÇİNDEYSEK afiş gösterme — mesaj zaten gözünün önünde.
        if (_servis.aktifDmPeerUid == t.peerUid) continue;
        final ad = t.peerName.isNotEmpty ? t.peerName : 'Yeni mesaj';
        _bildir(InAppNotice(baslik: ad, govde: t.lastMessage, emoji: '💬'));
      }
    });

    _istekAboneligi = _chat.streamIncomingRequests(uid).listen((istekler) {
      if (!_istekTabanAlindi) {
        _bilinenIstekler.addAll(istekler.map((i) => i.id));
        _istekTabanAlindi = true;
        return;
      }
      for (final i in istekler) {
        if (!_bilinenIstekler.add(i.id)) continue;
        _bildir(InAppNotice(
          baslik: i.fromName,
          govde: 'Sana arkadaşlık isteği gönderdi',
          emoji: '🤝',
        ));
      }
    });
  }

  /// Uygulama öndeyse afiş kuyruğuna, arka plandaysa yerel bildirime yönlendir.
  void _bildir(InAppNotice bildirim) {
    if (_yasamDurumu == AppLifecycleState.resumed) {
      _servis.goster(bildirim);
    } else {
      // Best-effort: süreç hayattaysa telefon bildirimi göster.
      NotificationService.instance
          .showBasit(baslik: bildirim.baslik, govde: bildirim.govde);
    }
  }

  // ── Çizim tarafı ─────────────────────────────────────────────────────────

  void _servisDegisti() {
    if (!mounted) return;
    final yeni = _servis.aktif;
    // Yeni bir afiş geldiyse kaydırma animasyonunu + kapanma zamanlayıcısını
    // başlat. (testAktif gibi diğer değişimlerde yalnızca yeniden çizilir ki
    // global hak pili teste girince gizlenip çıkınca geri gelsin.)
    if (yeni != null && yeni != _cizilen) {
      _cizilen = yeni;
      _afisGorunur = true;
      _kapatmaZamanlayici?.cancel();
      _kapatmaZamanlayici = Timer(const Duration(milliseconds: 3800), _kapat);
    }
    setState(() {});
  }

  void _kapat() {
    if (!mounted) return;
    setState(() => _afisGorunur = false);
    // Kayma animasyonu bitince kuyruktaki sıradakine geç.
    Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      setState(() => _cizilen = null);
      _servis.aktifKapandi();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final b = _cizilen;
    // Global hak göstergesi: premium DEĞİLSE, test AÇIK DEĞİLSE ve anasayfa
    // kökünde DEĞİLSEK (anasayfa kendi çipini gösterir) sağ üstte küçük bir pil
    // olarak görünür — kullanıcı nerede olursa olsun hak bakiyesini görür.
    final hakPiliGoster = !storage.isPremiumUser() && !_servis.testAktif;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          if (hakPiliGoster)
            ValueListenableBuilder<bool>(
              valueListenable: anasayfaKokunde,
              builder: (context, kokte, _) {
                if (kokte) return const SizedBox.shrink();
                return ValueListenableBuilder<bool>(
                  valueListenable: hakPiliGizle,
                  builder: (context, gizle, _) {
                    if (gizle) return const SizedBox.shrink();
                    return Positioned(
                  top: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 10),
                      child: _GlobalHakPili(
                        haklar: storage.getHaklar(),
                        onTap: () {
                          context.read<SoundService>().click();
                          rootNavigatorKey.currentState?.push(
                            MaterialPageRoute(
                                builder: (_) => const HakSatinAlScreen()),
                          );
                        },
                      ),
                    ),
                  ),
                    );
                  },
                );
              },
            ),
          if (b != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: AnimatedSlide(
                  offset: _afisGorunur ? Offset.zero : const Offset(0, -1.4),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: GestureDetector(
                    onTap: _kapat,
                    // Yukarı kaydırarak da kapatılabilsin.
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < 0) _kapat();
                    },
                    // PREMIUM afiş: cam (glass) yüzey üstünde ince tema-moru →
                    // gül degrade, hafif iç parlama, çok katmanlı gölge ve
                    // halkalı emoji rozeti. Sistem bildirimleri (tema/rozet/
                    // ödül) TEK SATIRDIR (govde boş); yalnızca mesaj/istek
                    // afişlerinde ikinci satır önizleme çıkar.
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.alphaBlend(
                                c.violet.withValues(alpha: 0.16), c.bg2),
                            c.bg2,
                            Color.alphaBlend(
                                c.rose.withValues(alpha: 0.10), c.bg2),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: c.violet.withValues(alpha: 0.35), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.30),
                            blurRadius: 26,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: c.violet.withValues(alpha: 0.20),
                            blurRadius: 30,
                            spreadRadius: -6,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Sol degrade vurgu şeridi — mor→gül.
                          Container(
                            width: 5,
                            height: 58,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [c.violet, c.rose],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Halkalı emoji rozeti — DsIconBadge dili, çift katman.
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  c.violet.withValues(alpha: 0.28),
                                  c.rose.withValues(alpha: 0.20),
                                ],
                              ),
                              border: Border.all(
                                  color: c.violet.withValues(alpha: 0.45),
                                  width: 1),
                            ),
                            child: Center(
                              child: Text(b.emoji,
                                  style: const TextStyle(fontSize: 19)),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(b.baslik,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          letterSpacing: 0.2,
                                          color: c.text)),
                                  if (b.govde.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(b.govde,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            height: 1.3,
                                            color: c.textDim)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Kapatma ipucu — ince aşağı ok / grabber.
                          Icon(Icons.keyboard_arrow_up_rounded,
                              size: 20,
                              color: c.textFaint.withValues(alpha: 0.7)),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ekranın sağ üstünde yüzen küçük hak (bilet) göstergesi — anasayfadaki üst
/// panel çipiyle aynı dil. Test dışında her ekranda görünür (bkz.
/// InAppNoticeOverlay). Dokununca Hak Satın Al ekranına gider. Yalnızca
/// ücretsiz kullanıcıda çizilir.
class _GlobalHakPili extends StatelessWidget {
  final int haklar;
  final VoidCallback onTap;
  const _GlobalHakPili({required this.haklar, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          decoration: BoxDecoration(
            color: Color.alphaBlend(c.violet.withValues(alpha: 0.18), c.bg2),
            borderRadius: BorderRadius.circular(999),
            border:
                Border.all(color: c.violet.withValues(alpha: 0.40), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎟️', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Text('$haklar',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14, color: c.text)),
              const SizedBox(width: 5),
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: c.violet, shape: BoxShape.circle),
                child: const Icon(Icons.add, size: 13, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
