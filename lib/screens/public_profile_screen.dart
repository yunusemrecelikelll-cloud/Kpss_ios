import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/badge.dart';
import '../services/league_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';

/// Sohbet/DM üzerinden BAŞKA bir kullanıcının avatarına dokunulduğunda açılan
/// salt-okunur profil ekranı — kendi ProfileScreen'imizdeki stat/rozet
/// kartlarıyla aynı görsel dili kullanır, ama veri kaynağı Firestore'daki
/// 'league_scores/{uid}' dokümanıdır (bkz. LeagueService.fetchUserProfile).
///
/// Üç olası durum:
/// 1. Doküman hiç yok (kullanıcı hiç profil/lig ekranını açmadı) → nazik bir
///    "henüz görüntülenebilir profili yok" mesajı.
/// 2. Kullanıcı "İstatistiklerimi Gizle" ayarını açmış → gerçek sayılar
///    GÖSTERİLMEZ, sadece gizli tutulduğu bilgisi gösterilir.
/// 3. Aksi halde → başarı oranı, çözülen soru, seri, haftalık puan ve
///    açılmış rozetler gösterilir.
class PublicProfileScreen extends StatefulWidget {
  final String uid;
  final String fallbackName;
  const PublicProfileScreen({super.key, required this.uid, required this.fallbackName});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late final Future<PublicUserProfile?> _future;

  @override
  void initState() {
    super.initState();
    _future = LeagueService().fetchUserProfile(widget.uid);
  }

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Scaffold(
      appBar: AppBar(title: Text('👤 ${widget.fallbackName}')),
      body: SafeArea(
        child: FutureBuilder<PublicUserProfile?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final profile = snap.data;
            if (profile == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🕵️', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 12),
                      Text(
                        '${widget.fallbackName} için henüz görüntülenebilir bir profil yok.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.text),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bu kullanıcı Profil ekranını henüz açmamış olabilir.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: c.textFaint),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (profile.hideStats) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔒', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 12),
                      Text(
                        '${profile.displayName} istatistiklerini gizli tutuyor.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              );
            }

            final unlocked = kBadgeDefs.where((b) => profile.unlockedBadgeIds.contains(b.id)).toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('👤 ${profile.displayName}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        if (profile.updatedAt != null)
                          Text(
                            'Son güncelleme: ${_fmtDate(profile.updatedAt!)}',
                            style: TextStyle(fontSize: 11, color: c.textFaint),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.8,
                  children: [
                    _StatTile(label: 'Genel Başarı', value: '%${profile.rate}', colors: c),
                    _StatTile(label: 'Çözülen Soru', value: '${profile.solved}', colors: c),
                    _StatTile(label: 'Günlük Seri', value: '${profile.streakCount}', colors: c),
                    _StatTile(label: 'Haftalık Puan', value: '${profile.weeklyPoints}', colors: c),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🏅 Rozetler (${unlocked.length}/${kBadgeDefs.length})',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 12),
                        if (unlocked.isEmpty)
                          Text('Henüz rozet açılmamış.', style: TextStyle(fontSize: 12.5, color: c.textFaint))
                        else
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final b in unlocked)
                                Tooltip(
                                  message: b.desc,
                                  child: Container(
                                    width: 72,
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: b.color.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: b.color.withValues(alpha: 0.4)),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(b.icon, style: const TextStyle(fontSize: 22)),
                                        const SizedBox(height: 4),
                                        Text(
                                          b.name,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final KpssColors colors;
  const _StatTile({required this.label, required this.value, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: colors.textFaint)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}
