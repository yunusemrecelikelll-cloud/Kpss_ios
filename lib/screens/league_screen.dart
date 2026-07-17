import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/league_service.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

const _tiersInOrder = [
  LeagueTier.bronz,
  LeagueTier.gumus,
  LeagueTier.altin,
  LeagueTier.platin,
  LeagueTier.elmas,
  LeagueTier.efsane,
];

/// Özel Lig — JS: renderLeague.
///
/// Haftalık lig puanına (bkz. StorageService.getWeeklyPoints — her doğru
/// cevap +10 puan, her Pazartesi sıfırlanır) göre, Firestore'daki `league_scores`
/// koleksiyonunda BU HAFTA yayınlanmış diğer kullanıcılarla karşılaştırılarak
/// gerçek zamanlı bir yüzdelik dilim + kademe (Bronz→Efsane) hesaplanır
/// (bkz. LeagueService — daha önce yazılmış ama hiçbir ekrana bağlanmamıştı).
/// Firebase yapılandırılmamışsa / giriş yapılmamışsa / offlineysa sadece
/// yerel haftalık puan gösterilir, çevrimiçi karşılaştırma atlanır.
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

    return Scaffold(
      appBar: AppBar(title: const Text('🏆 Özel Lig')),
      body: FutureBuilder<LeagueResult?>(
        future: _future,
        builder: (context, snap) {
          final result = snap.data;
          final loading = snap.connectionState == ConnectionState.waiting;
          final tier = result?.tier ?? _localTierFallback(weeklyPoints);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      Text(tier.icon, style: const TextStyle(fontSize: 52)),
                      const SizedBox(height: 8),
                      Text('${tier.label} Lig', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('Bu haftaki puanın: $weeklyPoints',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (result != null)
                        Text(
                          'Bu hafta puan yayınlayan ${result.totalParticipants} kullanıcının '
                          '%${result.percentile.round()}\'inden daha iyi durumdasın.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: c.textFaint),
                        )
                      else
                        Text(
                          'Çevrimiçi karşılaştırma için giriş yapman ve internete bağlı olman gerekiyor — '
                          'şimdilik sadece yerel haftalık puanın gösteriliyor.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: c.textFaint),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _tiersInOrder)
                    Chip(
                      label: Text('${t.icon} ${t.label}'),
                      backgroundColor: t == tier
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Her hafta Pazartesi puanlar sıfırlanır ve yeni bir "haftalık turnuva" başlar — '
                'her doğru cevap 10 puan kazandırır.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: c.textFaint),
              ),
            ],
          );
        },
      ),
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
