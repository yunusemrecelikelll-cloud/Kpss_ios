import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/league_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';

/// Prestij sırası: en üst kademe en başta (podyum sıralaması bu listeye göre).
const _tiersByRank = [
  LeagueTier.efsane,
  LeagueTier.elmas,
  LeagueTier.platin,
  LeagueTier.altin,
  LeagueTier.gumus,
  LeagueTier.bronz,
];

/// Kademenin kısa niteliksel etiketi (kişi sayısı satırında gösterilir).
String _esikMetni(LeagueTier t) => switch (t) {
      LeagueTier.efsane => 'Zirvedekiler',
      LeagueTier.elmas => 'Üst kademe',
      LeagueTier.platin => 'İleri kademe',
      LeagueTier.altin => 'Orta-üst kademe',
      LeagueTier.gumus => 'Gelişen kademe',
      LeagueTier.bronz => 'Başlangıç kademesi',
    };

/// Her kademenin HAFTALIK PUAN aralığı — TEK KAYNAK LeagueTier.pointRange
/// (bkz. league_service.dart). Kademe ataması da aynı sınırları kullandığı için
/// ekranda yazan aralık ile kullanıcının bulunduğu lig HER ZAMAN tutarlıdır.
String _puanAraligi(LeagueTier t) => t.pointRange;

/// Podyum renkleri — ilk üç sıra için altın / gümüş / bronz aksan.
/// KASITLI SABİT: madalya sıralaması evrensel bir kimliktir (1. altın, 2. gümüş,
/// 3. bronz); temaya göre değişirse "kaçıncı sıradayım" bilgisi kaybolur.
const _kAltin = Color(0xFFD4AF37);
const _kGumus = Color(0xFFB8C0C8);
const _kBronz = Color(0xFFC08457);

Color _madalyaRengi(int sira, Color varsayilan) => switch (sira) {
      0 => _kAltin,
      1 => _kGumus,
      2 => _kBronz,
      _ => varsayilan,
    };

/// Lig — JS: renderLeague.
///
/// Haftalık lig puanına (bkz. StorageService.getWeeklyPoints — her doğru
/// cevap +5 puan, her Pazartesi sıfırlanır) göre, Firestore'daki `league_scores`
/// koleksiyonunda BU HAFTA yayınlanmış diğer kullanıcılarla karşılaştırılarak
/// gerçek zamanlı bir yüzdelik dilim + kademe (Bronz→Efsane) hesaplanır
/// (bkz. LeagueService). Firebase yapılandırılmamışsa / giriş yapılmamışsa /
/// offlineysa sadece yerel haftalık puan gösterilir, çevrimiçi karşılaştırma
/// atlanır.
class LeagueScreen extends StatefulWidget {
  const LeagueScreen({super.key});

  @override
  State<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends State<LeagueScreen> {
  late final Future<LeagueResult?> _future;

  // Haftalık turnuvanın bitişine geri sayım için saniyede bir tetiklenen saat.
  Timer? _saat;
  DateTime _simdi = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = LeagueService().computeMyLeagueTier(context.read<StorageService>());
    _saat = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _simdi = DateTime.now());
    });
  }

  @override
  void dispose() {
    _saat?.cancel();
    super.dispose();
  }

  /// Bu haftalık turnuvanın bitişi = GELECEK Pazartesi 00:00 (her Pazartesi
  /// puanlar sıfırlanır, bkz. StorageService haftalık puan mantığı).
  DateTime _haftaBitisi() {
    final n = _simdi;
    // weekday: Pzt=1 ... Paz=7. Gelecek Pazartesi'ye kalan gün.
    final kalanGun = (8 - n.weekday) % 7;
    final gun = kalanGun == 0 ? 7 : kalanGun; // bugün Pazartesi ise +7
    final hedef = DateTime(n.year, n.month, n.day).add(Duration(days: gun));
    return hedef;
  }

  @override
  Widget build(BuildContext context) {
    // LİG ARTIK ÜCRETSİZ (kullanıcı isteği): premium kilidi kaldırıldı, tüm
    // kullanıcılar haftalık ligi görür ve katılır.
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final weeklyPoints = storage.getWeeklyPoints();
    final userName = storage.getUserName();

    return Scaffold(
      appBar: AppBar(title: const Text('🏆 Lig')),
      body: FutureBuilder<LeagueResult?>(
        future: _future,
        builder: (context, snap) {
          final result = snap.data;
          final loading = snap.connectionState == ConnectionState.waiting;
          final tier = result?.tier ?? _localTierFallback(weeklyPoints);

          final kalan = _haftaBitisi().difference(_simdi);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              // ── Haftanın birincisi (kullanıcı isteği) — ligin ÜSTÜNDE, taçlı,
              // premium lüks isim arkası. Online veri yoksa gizlenir.
              if (result?.leaderName != null) ...[
                _girisAnimasyonu(
                  sira: 0,
                  child: _HaftaninBirincisi(
                    ad: result!.leaderName!,
                    puan: result.leaderPoints,
                    benMiyim: result.leaderIsMe,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // ── Turnuva bitişine geri sayım (kullanıcı isteği).
              _girisAnimasyonu(
                sira: 0,
                child: _GeriSayim(kalan: kalan),
              ),
              const SizedBox(height: 16),
              _girisAnimasyonu(
                sira: 0,
                child: _VitrinKarti(
                  tier: tier,
                  userName: userName,
                  weeklyPoints: weeklyPoints,
                  result: result,
                  loading: loading,
                ),
              ),
              const SizedBox(height: 22),
              _girisAnimasyonu(
                sira: 1,
                child: Row(
                  children: [
                    Icon(Icons.workspace_premium_rounded, size: 18, color: c.gold),
                    const SizedBox(width: 8),
                    Text(
                      'Kademe Sıralaması',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c.text, letterSpacing: 0.2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _tiersByRank.length; i++)
                _girisAnimasyonu(
                  sira: i + 2,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _KademeSatiri(
                      sira: i,
                      tier: _tiersByRank[i],
                      benimKademem: _tiersByRank[i] == tier,
                      ulasildi: i > _tiersByRank.indexOf(tier),
                      userName: userName,
                      weeklyPoints: weeklyPoints,
                      kisiSayisi: result?.tierCounts[_tiersByRank[i]] ?? 0,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              _girisAnimasyonu(
                sira: 8,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.glass,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: c.textFaint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Her hafta Pazartesi puanlar sıfırlanır ve yeni bir haftalık turnuva başlar — '
                          'her doğru cevap 5 puan kazandırır.',
                          style: TextStyle(fontSize: 11.5, height: 1.5, color: c.textFaint, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Zarif giriş animasyonu — sırayla hafif yukarı kayarak belirir.
  Widget _girisAnimasyonu({required int sira, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + sira * 55),
      curve: Curves.easeOutCubic,
      builder: (context, t, ch) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: ch),
      ),
      child: child,
    );
  }

  /// Çevrimiçi karşılaştırma yapılamadığında (offline/giriş yok) yerel puana
  /// göre kademe — çevrimiçi ile AYNI mutlak eşikleri kullanır (tek kaynak).
  LeagueTier _localTierFallback(int weeklyPoints) => tierForPoints(weeklyPoints);
}

/// Üstteki premium vitrin: koyu lacivert–mor degrade zemin + altın aksan.
class _VitrinKarti extends StatelessWidget {
  final LeagueTier tier;
  final String userName;
  final int weeklyPoints;
  final LeagueResult? result;
  final bool loading;

  const _VitrinKarti({
    required this.tier,
    required this.userName,
    required this.weeklyPoints,
    required this.result,
    required this.loading,
  });

  /// Vitrin zemini her temada KOYU kalır (kupa/ödül töreni hissi) ama tonu
  /// artık sabit değil: temanın vurgu renginden siyaha doğru karıştırılarak
  /// üretilir. Böylece 9 temanın hepsinde kart farklı görünür, üzerindeki
  /// beyaz yazı ise her zaman okunur kalır.
  static Color _koyult(Color renk, double oran) => Color.lerp(Colors.black, renk, oran)!;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // Vitrinin altın aksanı artık temanın kendi altın tonundan gelir.
    final vurgu = c.gold;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _koyult(c.violet, 0.20),
            _koyult(c.violet, 0.34),
            _koyult(vurgu, 0.26),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: vurgu.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          children: [
            // Altın lig şeridi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: vurgu.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: vurgu.withValues(alpha: 0.45)),
              ),
              child: Text(
                'HAFTALIK TURNUVA',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: vurgu),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [vurgu.withValues(alpha: 0.28), Colors.transparent],
                ),
                border: Border.all(color: vurgu.withValues(alpha: 0.5), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(tier.icon, style: const TextStyle(fontSize: 44)),
            ),
            const SizedBox(height: 12),
            Text(
              '${tier.label} Lig',
              textAlign: TextAlign.center,
              // Koyu vitrin zemini üzerinde başlık: temanın altın tonuna hafifçe
              // çalan kırık beyaz (eski sabit krem yerine).
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color.lerp(Colors.white, vurgu, 0.16),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              userName.isEmpty ? 'Sen' : userName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 18),
            // Puan / katılımcı / dilim rozetleri
            Row(
              children: [
                Expanded(child: _rozet('Puanın', '$weeklyPoints', Icons.bolt_rounded, vurgu)),
                const SizedBox(width: 10),
                Expanded(
                  child: _rozet(
                    'Yarışan',
                    result == null ? '—' : '${result!.totalParticipants}',
                    Icons.groups_rounded,
                    vurgu,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _rozet(
                    'Sıra',
                    result == null ? '—' : '${result!.myRank}.',
                    Icons.leaderboard_rounded,
                    vurgu,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: vurgu),
              )
            else if (result != null)
              Text(
                'Bu hafta puan yayınlayan ${result!.totalParticipants} kullanıcının '
                '%${result!.percentile.round()}\'inden daha iyi durumdasın.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600),
              )
            else
              Text(
                'Çevrimiçi karşılaştırma için giriş yapman ve internete bağlı olman gerekiyor — '
                'şimdilik sadece yerel haftalık puanın gösteriliyor.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
              ),
            if (result != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (result!.percentile / 100).clamp(0.0, 1.0),
                  minHeight: 7,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(vurgu),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// NOT: Buradaki beyaz tonlar KASITLI — rozetler her temada KOYU kalan vitrin
  /// zemininin üstünde duruyor, dolayısıyla beyaz yazı/çizgi her temada okunur.
  Widget _rozet(String etiket, String deger, IconData ikon, Color vurgu) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(ikon, size: 15, color: vurgu.withValues(alpha: 0.9)),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              deger,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            etiket,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}

/// Ligin en üstünde "HAFTANIN BİRİNCİSİ" — taçlı, altın degrade lüks isim
/// arkası (kullanıcı isteği). Birinci kullanıcının kendisiyse özel vurgu.
class _HaftaninBirincisi extends StatelessWidget {
  final String ad;
  final int puan;
  final bool benMiyim;
  const _HaftaninBirincisi({
    required this.ad,
    required this.puan,
    required this.benMiyim,
  });

  @override
  Widget build(BuildContext context) {
    final bas = (ad.trim().isEmpty ? '?' : ad.trim().characters.first).toUpperCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Colors.black, _kAltin, 0.30)!,
            Color.lerp(Colors.black, _kAltin, 0.55)!,
            Color.lerp(Colors.black, const Color(0xFFB8860B), 0.42)!,
          ],
        ),
        border: Border.all(color: _kAltin.withValues(alpha: 0.6), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: _kAltin.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          // Taç + baş harfi rozeti
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFE9A8), _kAltin],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(bas,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF4A3B00))),
              ),
              const Positioned(
                top: -16,
                child: Text('👑', style: TextStyle(fontSize: 22)),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 5),
                    Text(
                      'HAFTANIN BİRİNCİSİ',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  benMiyim ? '$ad (sen!)' : ad,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$puan',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, height: 1.1)),
              Text('puan',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Turnuva bitişine (gelecek Pazartesi) geri sayım şeridi — gün/saat/dakika/sn.
class _GeriSayim extends StatelessWidget {
  final Duration kalan;
  const _GeriSayim({required this.kalan});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final k = kalan.isNegative ? Duration.zero : kalan;
    final gun = k.inDays;
    final saat = k.inHours % 24;
    final dk = k.inMinutes % 60;
    final sn = k.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            c.violet.withValues(alpha: c.isLight ? 0.14 : 0.24),
            c.rose.withValues(alpha: c.isLight ? 0.10 : 0.18),
          ],
        ),
        border: Border.all(color: c.violet.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 18, color: c.violetL),
          const SizedBox(width: 10),
          Text(
            'Bitişe',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: c.textDim),
          ),
          const Spacer(),
          _kutu(context, gun, 'GÜN'),
          _ikiNokta(c),
          _kutu(context, saat, 'SA'),
          _ikiNokta(c),
          _kutu(context, dk, 'DK'),
          _ikiNokta(c),
          _kutu(context, sn, 'SN'),
        ],
      ),
    );
  }

  Widget _ikiNokta(dynamic c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text(':',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900, color: c.textFaint)),
      );

  Widget _kutu(BuildContext context, int deger, String etiket) {
    final c = context.watch<ThemeProvider>().colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: c.glass2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          alignment: Alignment.center,
          child: Text(
            deger.toString().padLeft(2, '0'),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w900, color: c.text),
          ),
        ),
        const SizedBox(height: 3),
        Text(etiket,
            style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.w800, color: c.textFaint)),
      ],
    );
  }
}

/// Sıralama listesindeki tek kademe satırı — ilk üçte madalya vurgusu,
/// kullanıcının kendi kademesi belirgin şekilde öne çıkar.
class _KademeSatiri extends StatelessWidget {
  final int sira;
  final LeagueTier tier;
  final bool benimKademem;

  /// Kullanıcının kademesinin altındaki (yani geçilmiş) kademeler.
  final bool ulasildi;
  final String userName;
  final int weeklyPoints;

  /// Bu kademede bu hafta yer alan kişi sayısı (0 ise gösterilmez — offline).
  final int kisiSayisi;

  const _KademeSatiri({
    required this.sira,
    required this.tier,
    required this.benimKademem,
    required this.ulasildi,
    required this.userName,
    required this.weeklyPoints,
    required this.kisiSayisi,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final madalya = _madalyaRengi(sira, c.textFaint);
    final podyum = sira < 3;
    final bas = (userName.trim().isEmpty ? 'S' : userName.trim().characters.first).toUpperCase();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: benimKademem
            ? LinearGradient(
                colors: [c.violet.withValues(alpha: 0.30), madalya.withValues(alpha: 0.16)],
              )
            : null,
        color: benimKademem ? null : c.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: benimKademem
              ? c.violetL.withValues(alpha: 0.75)
              : (podyum ? madalya.withValues(alpha: 0.40) : c.border),
          width: benimKademem ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (benimKademem ? c.violet : Colors.black).withValues(alpha: benimKademem ? 0.28 : 0.14),
            blurRadius: benimKademem ? 18 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Sıra numarası / madalya
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: madalya.withValues(alpha: podyum ? 0.22 : 0.10),
              border: Border.all(color: madalya.withValues(alpha: podyum ? 0.8 : 0.3)),
            ),
            alignment: Alignment.center,
            child: Text(
              '${sira + 1}',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: podyum ? madalya : c.textDim),
            ),
          ),
          const SizedBox(width: 12),
          // Kademe rozeti
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.glass2,
              border: Border.all(color: madalya.withValues(alpha: podyum ? 0.55 : 0.25)),
            ),
            alignment: Alignment.center,
            child: Text(tier.icon, style: const TextStyle(fontSize: 19)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Kademenin PUAN ARALIĞI — adının ÜZERİNDE (kullanıcı isteği:
                // "hangi puan hangi lig, liglerin üzerinde yazsın").
                Text(
                  _puanAraligi(tier),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: benimKademem ? c.gold : madalya,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${tier.label} Lig',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: benimKademem ? c.text : c.textDim,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kisiSayisi > 0
                      ? '${_esikMetni(tier)} • $kisiSayisi kişi'
                      : _esikMetni(tier),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: c.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (benimKademem)
            // Kullanıcının kendi satırı: baş harf rozeti + puanı
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$weeklyPoints',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.gold, height: 1.1),
                    ),
                    Text('puan', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: c.textFaint)),
                  ],
                ),
                const SizedBox(width: 10),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [c.violet, c.rose]),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    bas,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
              ],
            )
          else
            Icon(
              ulasildi ? Icons.check_circle_outline_rounded : Icons.lock_outline_rounded,
              size: 16,
              color: (ulasildi ? c.success : c.textFaint).withValues(alpha: 0.6),
            ),
        ],
      ),
    );
  }
}
