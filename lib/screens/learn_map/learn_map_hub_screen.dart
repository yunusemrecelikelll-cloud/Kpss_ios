import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/learn_map_data.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';
import '../map_game/map_shared.dart';
import 'learn_map_detail_screen.dart';

const String _kHowToPlay =
    'Bir kategori seç (Bölgeler, Tarım, Hayvancılık, Madenler, Enerji, Sanayi, '
    'Coğrafya, Ulaşım-Turizm), ardından üstteki çiplerden bir maddeye dokun — o '
    'maddeyle ilgili iller haritada vurgulanır ve altta kısa bir açıklama '
    'görünür. Haritayı iki parmakla yakınlaştırıp uzaklaştırabilir, sağ alttaki '
    'düğmeyle sıfırlayabilirsin. Sağ üstteki 🎨 ile harita rengini '
    'değiştirebilirsin (seçimin hatırlanır). Bu bir öğrenme modudur, puan/skor '
    'tutulmaz, günlük hak sınırı yoktur.';

/// Her kategori kartına, temanın vurgu renklerinden türetilen ayırt edici bir
/// gradyan atamak için kullanılan renk çiftleri (sırayla dönülür). Temaya
/// uygun kalsın diye doğrudan sabit renkler değil, tema renk anahtarları
/// üzerinden seçilir (bkz. build içindeki eşleme).
List<List<Color>> _kartGradyanlari(ThemeProvider tp) {
  final c = tp.colors;
  return [
    [c.violet, c.rose],
    [c.mint, c.violet],
    [c.gold, c.rose],
    [c.rose, c.violetL],
    [c.violetL, c.mint],
    [c.mint, c.gold],
    [c.violet, c.mint],
    [c.gold, c.violet],
  ];
}

/// "Haritadan Öğren" kütüphanesinin giriş ekranı — kategori kartlarını gösterir.
/// Kart tasarımı temaya uygun gradyanlarla yeniden düzenlendi (kullanıcı isteği:
/// "Haritadan Öğren tarafını komple düzelt, temaya uygun renkler, yeniden
/// tasarla").
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
      context
          .read<StorageService>()
          .addGameTimeSpent(kHaritadanOgrenGameId, DateTime.now().difference(start));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final colors = tp.colors;
    final categories = kLearnMapCategories;
    final gradyanlar = _kartGradyanlari(tp);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🗺️📚 Haritadan Öğren'),
        actions: [
          IconButton(
            tooltip: 'Nasıl kullanılır?',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showHowToPlaySheet(context,
                title: 'Haritadan Öğren', body: _kHowToPlay),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(colors.violet.withValues(alpha: 0.10), colors.bg),
              colors.bg,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst tanıtım şeridi.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors.violet.withValues(alpha: colors.isLight ? 0.16 : 0.28),
                        colors.mint.withValues(alpha: colors.isLight ? 0.12 : 0.20),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.violet.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    children: [
                      const Text('🧭', style: TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Konulara göre grupladık: bir kategoriye dokun, illeri '
                          'Türkiye haritasında renkli renkli gör ve öğren.',
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: colors.text,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.98,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, i) {
                      final cat = categories[i];
                      return _CategoryCard(
                        category: cat,
                        gradient: gradyanlar[i % gradyanlar.length],
                        onTap: () {
                          context.read<SoundService>().click();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    LearnMapDetailScreen(category: cat)),
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
  final List<Color> gradient;
  final VoidCallback onTap;
  const _CategoryCard({
    required this.category,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradient[0].withValues(alpha: colors.isLight ? 0.18 : 0.30),
                gradient[1].withValues(alpha: colors.isLight ? 0.12 : 0.20),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: gradient[0].withValues(alpha: 0.40)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // İkon rozeti.
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [gradient[0], gradient[1]],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: gradient[0].withValues(alpha: 0.45),
                        blurRadius: 10,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Text(category.icon, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(height: 10),
              Text(
                category.title,
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 15, color: colors.text),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  category.description,
                  style: TextStyle(
                      fontSize: 11.5, height: 1.3, color: colors.textDim),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: gradient[0].withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${category.items.length} harita',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: colors.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
