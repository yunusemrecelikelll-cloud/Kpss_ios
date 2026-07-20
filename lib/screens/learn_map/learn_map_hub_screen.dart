import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/learn_map_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';
import '../map_game/map_shared.dart';
import 'learn_map_detail_screen.dart';

const String _kHowToPlay =
    'Bir kategori seç (Bölgeler, Tarım, Hayvancılık, Madenler, Enerji), '
    'ardından üstteki çiplerden bir maddeye dokun — o maddeyle ilgili iller '
    'haritada vurgulanır ve altta kısa bir açıklama görünür. Haritayı iki '
    'parmakla yakınlaştırıp uzaklaştırabilir, çift dokunarak sıfırlayabilirsin. '
    'Bu bir öğrenme modudur, puan/skor tutulmaz, günlük hak sınırı yoktur.';

/// "Haritadan Öğren" kütüphanesinin giriş ekranı — kategori kartlarını
/// (Bölgeler, Tarım, Hayvancılık, Madenler, Enerji Kaynakları) gösterir.
/// Rakip uygulamalardaki (KPSS SınavBank vb.) aynı adlı özelliğe benzer
/// biçimde tasarlanmıştır: her kategori kartında madde sayısı görünür,
/// dokunulduğunda [LearnMapDetailScreen] açılır.
///
/// NOT: Bu ekran ARTIK ayrı bir "Haritadan Öğren" giriş noktası olarak
/// lib/screens/tools_hub_screen.dart'ta YOKTUR — "Harita Oyunu" ve
/// "Haritadan Öğren" TEK bir ekranda (bkz. map_game_screen.dart) birleştirildi;
/// buraya SADECE MapGameScreen'deki "Haritadan Öğren" kartından girilir.
class LearnMapHubScreen extends StatefulWidget {
  const LearnMapHubScreen({super.key});

  @override
  State<LearnMapHubScreen> createState() => _LearnMapHubScreenState();
}

class _LearnMapHubScreenState extends State<LearnMapHubScreen> {
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    _sessionStart = DateTime.now();
  }

  @override
  void dispose() {
    final start = _sessionStart;
    if (start != null) {
      context.read<StorageService>().addGameTimeSpent(kHaritadanOgrenGameId, DateTime.now().difference(start));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final categories = kLearnMapCategories;
    final palette = mapModePaletteFor(kHaritadanOgrenGameId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🗺️📚 Haritadan Öğren'),
        actions: [
          IconButton(
            tooltip: 'Nasıl kullanılır?',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showHowToPlaySheet(context, title: 'Haritadan Öğren', body: _kHowToPlay),
          ),
        ],
      ),
      body: Container(
        decoration: mapModeBackgroundDecoration(palette, colors.isLight),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Türkiye haritası üzerinde konulara göre grupladık: bir kategoriye dokun, "
                  'illeri haritada gör.',
                  style: TextStyle(fontSize: 13.5, color: colors.textFaint),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.05,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, i) {
                      final cat = categories[i];
                      return _CategoryCard(
                        category: cat,
                        onTap: () {
                          context.read<SoundService>().click();
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => LearnMapDetailScreen(category: cat)),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final LearnMapCategory category;
  final VoidCallback onTap;
  const _CategoryCard({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category.icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 8),
              Text(
                category.title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  category.description,
                  style: TextStyle(fontSize: 11.5, color: colors.textFaint),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${category.items.length} harita',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colors.violet),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
