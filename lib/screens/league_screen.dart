import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/league_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

/// Prestij sırası: en üst kademe en başta (podyum sıralaması bu listeye göre).
const _tiersByRank = [
  LeagueTier.efsane,
  LeagueTier.elmas,
  LeagueTier.platin,
  LeagueTier.altin,
  LeagueTier.gumus,
  LeagueTier.bronz,
];

/// Her kademenin gerektirdiği yüzdelik dilim eşiği (bkz. LeagueService._tierFor).
String _esikMetni(LeagueTier t) => switch (t) {
      LeagueTier.efsane => 'En üst %5',
      LeagueTier.elmas => 'İlk %15',
      LeagueTier.platin => 'İlk %30',
      LeagueTier.altin => 'İlk %50',
      LeagueTier.gumus => 'İlk %75',
      LeagueTier.bronz => 'Başlangıç kademesi',
    };

/// Podyum renkleri — ilk üç sıra için altın / gümüş / bronz aksan.
const _kAltin = Color(0xFFD4AF37);
const _kGumus = Color(0xFFB8C0C8);
const _kBronz = Color(0xFFC08457);

Color _madalyaRengi(int sira, Color varsayilan) => switch (sira) {
      0 => _kAltin,
      1 => _kGumus,
      2 => _kBronz,
      _ => varsayilan,
    };

/// Özel Lig — JS: renderLeague.
///
/// Haftalık lig puanına (bkz. StorageService.getWeeklyPoints — her doğru
/// cevap +10 puan, her Pazartesi sıfırlanır) göre, Firestore'daki `league_scores`
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

  @override
  void initState() {
    super.initState();
    _future = LeagueService().computeMyLeagueTier(context.read<StorageService>());
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.isPremiumUser()) {
      return const LockedFeatureCard(
        title: 'Özel Lig',
        desc: "Haftalık lig puanına göre kademeni ve diğer kullanıcılara kıyasla yerini görmek için Premium'a geç.",
      );
    }

    final c = context.watch<ThemeProvider>().colors;
    final weeklyPoints = storage.getWeeklyPoints();
    final userName = storage.getUserName();

    return Scaffold(
      appBar: AppBar(title: const Text('🏆 Özel Lig')),
      body: FutureBuilder<LeagueResult?>(
        future: _future,
        builder: (context, snap) {
          final result = snap.data;
          final loading = snap.connectionState == ConnectionState.waiting;
          final tier = result?.tier ?? _localTierFallback(weeklyPoints);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
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
                          'her doğru cevap 10 puan kazandırır.',
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

  /// Çevrimiçi karşılaştırma yapılamadığında (offline/giriş yok) sadece
  /// yerel puana göre kaba bir kademe tahmini gösterir.
  LeagueTier _localTierFallback(int weeklyPoints) {
    if (weeklyPoints >= 500) return LeagueTier.efsane;
    if (weeklyPoints >= 300) return LeagueTier.elmas;
    if (weeklyPoints >= 150) return LeagueTier.platin;
    if (weeklyPoints >= 60) return LeagueTier.altin;
    if (weeklyPoints >= 20) return LeagueTier.gumus;
    return LeagueTier.bronz;
  }
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15122B), Color(0xFF241A44), Color(0xFF3B2A1A)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: _kAltin.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          children: [
            // Altın "ÖZEL LİG" şeridi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _kAltin.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: _kAltin.withValues(alpha: 0.45)),
              ),
              child: const Text(
                'HAFTALIK TURNUVA',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: _kAltin),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [_kAltin.withValues(alpha: 0.28), Colors.transparent],
                ),
                border: Border.all(color: _kAltin.withValues(alpha: 0.5), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(tier.icon, style: const TextStyle(fontSize: 44)),
            ),
            const SizedBox(height: 12),
            Text(
              '${tier.label} Lig',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFFFF3D6), letterSpacing: 0.3),
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
                Expanded(child: _rozet('Puanın', '$weeklyPoints', Icons.bolt_rounded)),
                const SizedBox(width: 10),
                Expanded(
                  child: _rozet(
                    'Yarışan',
                    result == null ? '—' : '${result!.totalParticipants}',
                    Icons.groups_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _rozet(
                    'Dilim',
                    result == null ? '—' : '%${result!.percentile.round()}',
                    Icons.trending_up_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kAltin),
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
                  valueColor: const AlwaysStoppedAnimation<Color>(_kAltin),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rozet(String etiket, String deger, IconData ikon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(ikon, size: 15, color: _kAltin.withValues(alpha: 0.9)),
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

  const _KademeSatiri({
    required this.sira,
    required this.tier,
    required this.benimKademem,
    required this.ulasildi,
    required this.userName,
    required this.weeklyPoints,
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
                  _esikMetni(tier),
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
