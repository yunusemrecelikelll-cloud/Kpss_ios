import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../games/card_game_engine.dart' show ciftRengi, kYanlisRengi;
import '../games/card_game_v2_engine.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/design_system.dart';
import '../theme/subject_colors.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

/// JS: FREE_GAME_DAILY / GAME2_MAX_MISTAKES
const int kFreeGameDaily = 10;
const int kGame2MaxMistakes = 3;
const String kGame2Id = 'cardgame2';

/// Kullanılmış çiftlerin KALICI olarak saklandığı ayar anahtarı.
/// (StorageService'in mevcut public API'si `getSettings()`/`saveSettings()`
/// üzerinden; biçim: `{ dersId: [çift anahtarı, ...] }`.)
const String kKartV2KullanilanKey = 'kartV2Kullanilan';

/// Cihazda saklanan "ders id → kullanılmış çift anahtarları" haritasını okur.
Map<String, Set<String>> kartV2KullanilanOku(StorageService storage) {
  final ham = storage.getSettings()[kKartV2KullanilanKey];
  final sonuc = <String, Set<String>>{};
  if (ham is Map) {
    ham.forEach((k, v) {
      if (v is List) sonuc['$k'] = {for (final e in v) '$e'};
    });
  }
  return sonuc;
}

/// Haritayı JSON'a çevirip ayarlara yazar (uygulama kapansa da kaybolmaz).
Future<void> kartV2KullanilanYaz(StorageService storage, Map<String, Set<String>> harita) {
  return storage.saveSettings({
    kKartV2KullanilanKey: {for (final e in harita.entries) e.key: e.value.toList()},
  });
}

/// Kart Oyunu V2 — ders seçme ekranı.
///
/// Oyun ancak EN AZ BİR DERS seçildiğinde başlar; seçilen derslerin ortak
/// havuzundan her turda tam [CardGameV2Engine.kSabitCiftSayisi] çift çekilir.
class CardGameV2Screen extends StatefulWidget {
  final List<Subject> subjects;
  const CardGameV2Screen({super.key, required this.subjects});

  @override
  State<CardGameV2Screen> createState() => _CardGameV2ScreenState();
}

class _CardGameV2ScreenState extends State<CardGameV2Screen> {
  final Set<String> _secili = {};

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final colors = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();
    final gp = storage.getGamePlayState(kGame2Id);
    final kalanHak = (kFreeGameDaily - (gp['plays'] as int)).clamp(0, kFreeGameDaily);
    final totalSeconds = storage.getGameTimeSpent(kKartOyunuGameId);
    final kullanilan = kartV2KullanilanOku(storage);

    // Havuzu boş olan dersler (henüz eşleştirme içeriği yok) seçilemez.
    final oynanabilir = [
      for (final s in widget.subjects)
        if (CardGameV2Engine.dersHavuzu(s).isNotEmpty) s
    ];
    final secilenDersler = [for (final s in oynanabilir) if (_secili.contains(s.id)) s];
    final hazir = secilenDersler.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🃏 Kart Oyunu V2'),
        actions: const [
          HowToPlayButton(
            title: '🃏 Nasıl Oynanır?',
            body: 'Önce çalışmak istediğin dersleri seç (birden fazla seçebilirsin), '
                'sonra Başla\'ya bas. Her turda seçtiğin derslerin havuzundan tam 8 '
                'eşleştirme gelir; soldaki terimi sağdaki doğru tanımıyla eşleştirmek '
                'için ikisine sırayla dokun. Her yeni turda farklı çiftler gelir, '
                'havuz tükenince karıştırılıp baştan verilir.',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: [
                  const DsSectionHeader(title: 'Ders Seç'),
                  Text(
                    'Oynamak istediğin dersleri seç. Her turda tam '
                    '${CardGameV2Engine.kSabitCiftSayisi} eşleştirme gelir. '
                    '${premium ? "Sınırsız oynarsın." : "Bugün $kalanHak hakkın kaldı."}',
                    style: TextStyle(fontSize: 13, color: colors.textFaint),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toplam: ${formatPlayDuration(totalSeconds)} oynadın',
                    style: TextStyle(fontSize: 11.5, color: colors.textFaint),
                  ),
                  const SizedBox(height: 14),
                  for (final s in oynanabilir) ...[
                    _DersSecimKarti(
                      subject: s,
                      secili: _secili.contains(s.id),
                      ilerleme: CardGameV2Engine.dersIlerlemesi(s, kullanilan[s.id]),
                      onTap: () {
                        context.read<SoundService>().click();
                        setState(() {
                          if (!_secili.remove(s.id)) _secili.add(s.id);
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (oynanabilir.isEmpty)
                    Text(
                      'Bu oyun için henüz eşleştirme içeriği yok.',
                      style: TextStyle(color: colors.textFaint),
                    ),
                ],
              ),
            ),
            // ── Alt bar: "Başla" yalnızca ders seçiliyken aktif ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                color: colors.glass,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hazir
                          ? '${secilenDersler.length} ders seçildi'
                          : 'En az bir ders seç',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: hazir ? colors.text : colors.warn,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Opacity(
                    opacity: hazir ? 1 : 0.45,
                    child: DsPillButton(
                      label: 'Başla',
                      color: hazir ? colors.violet : colors.textFaint,
                      trailingIcon: Icons.play_arrow_rounded,
                      onPressed: !hazir
                          ? null
                          : () {
                              context.read<SoundService>().click();
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => _V2PlayScreen(dersler: secilenDersler),
                              ));
                            },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seçilebilir ders kartı — eski "0/5 konu geçildi" yazısının yerine o dersin
/// EŞLEŞTİRME HAVUZU ilerlemesini yüzde + çubuk olarak gösterir.
class _DersSecimKarti extends StatelessWidget {
  final Subject subject;
  final bool secili;
  final double ilerleme; // 0..1
  final VoidCallback onTap;
  const _DersSecimKarti({
    required this.subject,
    required this.secili,
    required this.ilerleme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final palet = subjectPaletteFor(subject.id);
    final yuzde = (ilerleme * 100).round();
    final tamam = yuzde >= 100;

    return DsCard(
      accent: secili ? palet.a : null,
      onTap: onTap,
      child: Row(
        children: [
          DsIconBadge(emoji: subject.icon, color: palet.a, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subject.ad,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w800, color: colors.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Havuz ilerlemesi — başlangıçta %0, havuz tükenince %100,
                    // sıfırlanınca yeniden %0.
                    Text(
                      '%$yuzde',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: tamam ? colors.success : palet.a,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                DsProgressBar(
                  value: ilerleme,
                  color: tamam ? colors.success : palet.a,
                  height: 5,
                ),
                const SizedBox(height: 5),
                Text(
                  tamam ? 'Havuz tamamlandı — sıradaki turda karışacak' : 'Eşleştirme havuzu ilerlemen',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: colors.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            secili ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 22,
            color: secili ? palet.a : colors.border,
          ),
        ],
      ),
    );
  }
}

/// Eşleşen bir çifti birleştiren ok — [renk] çiftin palet rengidir.
///
/// [pairId] hangi çifte ait olduğunu söyler. Animasyonun DOĞRU ok üzerinde
/// oynaması buna bağlı: oklar kart indeksi sırasına göre dizildiği için
/// "listenin sonuncusu" ile "en son eşleşen" AYNI ŞEY DEĞİLDİR.
class _EslesmeOku {
  final Offset a, b;
  final Color renk;
  final int pairId;
  const _EslesmeOku(this.a, this.b, this.renk, this.pairId);
}

/// Okları çizer. YALNIZCA [animasyonluPairId] ile eşleşen ok [ilerleme]
/// (0→1) değerine göre soldan sağa animasyonlu uzar; diğerleri tam çizilir.
///
/// ÖNCEDEN burada "listenin son elemanı" animasyonlanıyordu. Ama
/// `_recomputeLines()` okları `_engine.left` indeks sırasına göre üretiyor,
/// eşleşme sırasına göre değil. Bu yüzden düşük indeksli bir çift
/// eşleştirildiğinde ok listenin ORTASINA giriyor ve animasyon, daha önce
/// eşleşmiş BAŞKA bir çiftin üzerinde oynuyordu.
class _MatchLinePainter extends CustomPainter {
  final List<_EslesmeOku> lines;
  final double ilerleme;
  final int? animasyonluPairId;
  _MatchLinePainter(this.lines, this.ilerleme, this.animasyonluPairId);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final t = (l.pairId == animasyonluPairId) ? ilerleme.clamp(0.0, 1.0) : 1.0;
      if (t <= 0) continue;
      final uc = Offset.lerp(l.a, l.b, t)!;

      final linePaint = Paint()
        ..color = l.renk
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(l.a, uc, linePaint);
      canvas.drawCircle(l.a, 3, Paint()..color = l.renk);

      final dir = l.b - l.a;
      final len = dir.distance;
      if (len == 0) continue;
      final unit = dir / len;
      final normal = Offset(-unit.dy, unit.dx);
      final back = uc - unit * 9;
      final p1 = back + normal * 4.5;
      final p2 = back - normal * 4.5;
      final path = Path()
        ..moveTo(uc.dx, uc.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = l.renk);
    }
  }

  @override
  bool shouldRepaint(covariant _MatchLinePainter oldDelegate) =>
      oldDelegate.lines.length != lines.length ||
      oldDelegate.ilerleme != ilerleme ||
      oldDelegate.animasyonluPairId != animasyonluPairId;
}

/// Kart Oyunu V2 tahtası + sonuç ekranı — JS: _renderGame2Board / _renderGameResult.
class _V2PlayScreen extends StatefulWidget {
  final List<Subject> dersler;
  const _V2PlayScreen({required this.dersler});

  @override
  State<_V2PlayScreen> createState() => _V2PlayScreenState();
}

class _V2PlayScreenState extends State<_V2PlayScreen> with TickerProviderStateMixin {
  final _engine = CardGameV2Engine();
  final _boardKey = GlobalKey();
  late List<GlobalKey> _leftKeys;
  late List<GlobalKey> _rightKeys;
  late AnimationController _shakeCtrl;

  /// Yeni bir eşleşme okunun soldan sağa çizilme animasyonu.
  late AnimationController _okCtrl;

  bool _locked = false;
  bool _started = false;
  bool _flashWrong = false;
  bool? _passed; // null: oynanıyor, true/false: bitti
  List<_EslesmeOku> _lines = [];

  /// Şu an animasyonu oynayan okun çift kimliği. Painter yalnızca bunu
  /// [_okCtrl] ilerlemesine göre çizer, diğerlerini tam çizer.
  int? _animasyonluPairId;

  /// Bu turda çekilen çiftlerin geldiği konu id'leri — tur kazanılınca
  /// "geçilen konu" olarak işaretlenir (rozetler bu kaydı kullanır).
  List<String> _turKonuIdleri = [];

  // Toplam oynama süresi takibi (Kart Oyunu ortak kimliği, bkz. tools_hub_screen.dart) —
  // ekran açık kaldığı sürece (tekrar denemeler dahil) TEK oturum sayılır; erken
  // çıkışta da dispose her zaman çağrıldığından kısmi süre kaydedilir.
  DateTime? _sessionStart;
  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _okCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _flushPlayTime();
    _shakeCtrl.dispose();
    _okCtrl.dispose();
    super.dispose();
  }

  void _flushPlayTime() {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;
    _storage.addGameTimeSpent(kKartOyunuGameId, DateTime.now().difference(start));
  }

  Future<void> _boot() async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final gp = storage.getGamePlayState(kGame2Id);
      if ((gp['plays'] as int) >= kFreeGameDaily) {
        if (!mounted) return;
        setState(() => _locked = true);
        return;
      }
      await storage.useGamePlay(kGame2Id);
    }

    // Havuzdan bu turun çiftlerini çek; kullanılmış çift takibini kalıcı yaz.
    final cekim = CardGameV2Engine.cek(
      dersler: widget.dersler,
      kullanilan: kartV2KullanilanOku(storage),
    );
    await kartV2KullanilanYaz(storage, cekim.kullanilan);

    _turKonuIdleri = {for (final c in cekim.ciftler) c.konuId}.toList();
    _engine.startCiftlerle(cekim.ciftler, maxMistakes: kGame2MaxMistakes);
    _leftKeys = List.generate(_engine.left.length, (_) => GlobalKey());
    _rightKeys = List.generate(_engine.right.length, (_) => GlobalKey());
    if (!mounted) return;
    setState(() {
      _started = true;
      _passed = null;
      _flashWrong = false;
      _lines = [];
      // Yeni turda eski turun ok animasyonu kimliği kalmasın — aksi halde
      // aynı pairId tekrar gelirse ok baştan çizilmiş gibi görünür.
      _animasyonluPairId = null;
    });
    _sessionStart ??= DateTime.now();
  }

  void _retry() {
    setState(() {
      _started = false;
      _locked = false;
      _passed = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  void _recomputeLines() {
    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (boardBox == null || !boardBox.hasSize) return;
    final newLines = <_EslesmeOku>[];
    for (var i = 0; i < _engine.left.length; i++) {
      final c = _engine.left[i];
      if (!c.matched) continue;
      final ri = _engine.right.indexWhere((r) => r.matched && r.pairId == c.pairId);
      if (ri < 0) continue;
      final lBox = _leftKeys[i].currentContext?.findRenderObject() as RenderBox?;
      final rBox = _rightKeys[ri].currentContext?.findRenderObject() as RenderBox?;
      if (lBox == null || rBox == null || !lBox.hasSize || !rBox.hasSize) continue;
      final lTopLeft = lBox.localToGlobal(Offset.zero, ancestor: boardBox);
      final rTopLeft = rBox.localToGlobal(Offset.zero, ancestor: boardBox);
      final p1 = lTopLeft + Offset(lBox.size.width, lBox.size.height / 2);
      final p2 = rTopLeft + Offset(0, rBox.size.height / 2);
      newLines.add(_EslesmeOku(p1, p2, ciftRengi(c.renkIndex), c.pairId));
    }
    if (newLines.length != _lines.length && mounted) {
      // YENİ eşleşen çifti kimliğinden bul — liste sırasına GÜVENME.
      // Oklar kart indeksi sırasına göre üretiliyor, dolayısıyla yeni ok
      // listenin sonunda olmak zorunda değil.
      final eskiIdler = _lines.map((l) => l.pairId).toSet();
      final yeniOk = newLines.where((l) => !eskiIdler.contains(l.pairId)).toList();
      setState(() {
        _lines = newLines;
        _animasyonluPairId = yeniOk.isNotEmpty ? yeniOk.last.pairId : null;
      });
      if (yeniOk.isNotEmpty) _okCtrl.forward(from: 0);
    }
  }

  void _triggerShake() {
    setState(() => _flashWrong = true);
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _flashWrong = false;
        _engine.clearLastWrong();
      });
    });
  }

  void _checkEnd() {
    if (_engine.isComplete) {
      final storage = context.read<StorageService>();
      for (final konuId in _turKonuIdleri) {
        storage.markGameTopicPassed(kGame2Id, konuId);
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() => _passed = true);
      });
    } else if (_engine.isFailed) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() => _passed = false);
      });
    }
  }

  void _handleTap(String side, int i) {
    final res = side == 'left' ? _engine.selectLeft(i) : _engine.selectRight(i);
    if (res.status == 'ignored') return;
    context.read<SoundService>().click();
    setState(() {});
    if (res.status == 'match') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeLines());
    }
    if (res.status == 'nomatch') {
      _triggerShake();
    }
    _checkEnd();
  }

  String get _dersBasligi => widget.dersler.length == 1
      ? widget.dersler.first.ad
      : '${widget.dersler.length} ders';

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const LockedFeatureCard(
        title: 'Kart Oyunu V2',
        desc: "Bugünkü $kFreeGameDaily ücretsiz hakkını kullandın. Yarın tekrar oyna ya da Premium'a geçip sınırsız oyna.",
      );
    }
    if (!_started) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_engine.pairsTotal < 2) {
      return Scaffold(
        appBar: AppBar(title: const Text('🃏 Kart Oyunu V2')),
        body: const Center(child: Text('Seçtiğin dersler için yeterli içerik yok.')),
      );
    }
    if (_passed != null) {
      return _V2Result(
        dersAdi: _dersBasligi,
        passed: _passed!,
        onRetry: _retry,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeLines());
    final colors = context.watch<ThemeProvider>().colors;

    return Scaffold(
      appBar: AppBar(
        title: Text('🃏 Kart Oyunu V2 — $_dersBasligi', overflow: TextOverflow.ellipsis),
        actions: const [
          HowToPlayButton(
            title: '🃏 Nasıl Oynanır?',
            body: 'Soldaki terimi sağdaki doğru tanımıyla eşleştirmek için ikisine '
                'sırayla dokun; doğru eşleşmeler bir okla birleşir. Belirli bir '
                'yanlış sayısını geçersen turu kaybedersin, tüm eşleşmeleri '
                'tamamlarsan turu kazanırsın.',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sol taraftaki terimi sağdaki tanımıyla eşleştir. '
              'Eşleşen: ${_engine.matchedCount}/${_engine.pairsTotal} • '
              'Yanlış: ${_engine.mistakes}/${_engine.maxMistakes}',
              style: TextStyle(fontSize: 13, color: colors.textFaint),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  color: _flashWrong ? colors.danger.withValues(alpha: 0.14) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                // Kartlar KARŞILIKLI iki sütunda, hepsi EŞİT boyutta duracak
                // şekilde dizilir: her satır Expanded olduğundan yükseklikler
                // eşitlenir, sıralama karışıktır ama ızgara hizalı kalır.
                child: Stack(
                  key: _boardKey,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              for (var i = 0; i < _engine.left.length; i++)
                                Expanded(
                                  child: _buildCard(
                                      side: 'left', i: i, key: _leftKeys[i], card: _engine.left[i]),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 34),
                        Expanded(
                          child: Column(
                            children: [
                              for (var i = 0; i < _engine.right.length; i++)
                                Expanded(
                                  child: _buildCard(
                                      side: 'right', i: i, key: _rightKeys[i], card: _engine.right[i]),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _okCtrl,
                          builder: (context, _) => CustomPaint(
                            painter: _MatchLinePainter(
                                _lines, _okCtrl.value, _animasyonluPairId),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required String side, required int i, required Key key, required Match2Card card}) {
    final colors = context.watch<ThemeProvider>().colors;
    final selected = side == 'left' ? _engine.selectedLeft == i : _engine.selectedRight == i;
    final isWrong = side == 'left' ? _engine.lastWrong?.leftIdx == i : _engine.lastWrong?.rightIdx == i;

    // Eşleşen çift AYNI paleti paylaşır; farklı çiftler farklı renk alır.
    final Color? vurgu = isWrong
        ? kYanlisRengi
        : card.matched
            ? ciftRengi(card.renkIndex)
            : null;

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: vurgu != null
            ? vurgu.withValues(alpha: 0.20)
            : selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
                : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: vurgu ??
              (selected ? Theme.of(context).colorScheme.primary : colors.border),
          width: vurgu != null || selected ? 1.8 : 1,
        ),
      ),
      alignment: Alignment.center,
      // Tüm kartlar eşit boyutta olduğundan metin, kartın içine sığacak
      // şekilde gerektiğinde küçültülür.
      child: LayoutBuilder(
        builder: (context, kisit) => FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: kisit.maxWidth.isFinite ? kisit.maxWidth : 140,
            child: Text(
              card.text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.text),
            ),
          ),
        ),
      ),
    );

    if (isWrong) {
      content = AnimatedBuilder(
        animation: _shakeCtrl,
        builder: (context, child) {
          final dx = _shakeCtrl.isAnimating ? sin(_shakeCtrl.value * pi * 6) * 6 : 0.0;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: content,
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: card.matched ? null : () => _handleTap(side, i),
      child: content,
    );
  }
}

class _V2Result extends StatelessWidget {
  final String dersAdi;
  final bool passed;
  final VoidCallback onRetry;
  const _V2Result({required this.dersAdi, required this.passed, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: const Text('🃏 Kart Oyunu V2')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: DsCard(
          accent: passed ? colors.success : colors.danger,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(passed ? '🎉' : '📚', style: const TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(
                passed ? 'Turu tamamladın!' : 'Bu turu kaybettin',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colors.text),
              ),
              const SizedBox(height: 8),
              Text(
                passed
                    ? '$dersAdi havuzundan gelen ${CardGameV2Engine.kSabitCiftSayisi} eşleşmenin hepsini buldun. Yeni turda farklı çiftler gelecek.'
                    : '$dersAdi havuzundan gelen eşleşmeleri tamamlayamadın. Yeni turda farklı çiftler gelecek.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textFaint),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  DsPillButton(
                    label: '🔄 Yeni Tur',
                    color: colors.violet,
                    onPressed: () {
                      context.read<SoundService>().click();
                      onRetry();
                    },
                  ),
                  DsPillButton(
                    label: 'Derslere Dön',
                    color: colors.violet,
                    filled: false,
                    onPressed: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
