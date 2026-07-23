import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/in_app_notice_service.dart';
import '../services/notification_service.dart';
import '../services/presence_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _servis.addListener(_servisDegisti);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _servis.removeListener(_servisDegisti);
    _threadAboneligi?.cancel();
    _istekAboneligi?.cancel();
    _kapatmaZamanlayici?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _yasamDurumu = state;
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
    final yeni = _servis.aktif;
    if (yeni == null || !mounted) return;
    setState(() {
      _cizilen = yeni;
      _afisGorunur = true;
    });
    _kapatmaZamanlayici?.cancel();
    _kapatmaZamanlayici = Timer(const Duration(milliseconds: 3800), _kapat);
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
    final b = _cizilen;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
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
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.bg2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.violetL.withValues(alpha: 0.45)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Text(b.emoji, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(b.baslik,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13.5,
                                        color: c.text)),
                                if (b.govde.isNotEmpty)
                                  Text(b.govde,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.3,
                                          color: c.textDim)),
                              ],
                            ),
                          ),
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
