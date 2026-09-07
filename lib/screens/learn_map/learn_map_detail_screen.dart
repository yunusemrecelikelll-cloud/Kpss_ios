import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/learn_map_data.dart';
import '../../data/turkey_map_data.dart';
import '../../services/sound_service.dart';
import '../../theme/theme_provider.dart';
import '../map_game/map_shared.dart';

/// Bir "Haritadan Öğren" kategorisi (ör. "Tarım") seçildiğinde açılan ekran.
/// Üstte kategorideki maddelerin (ör. "Fındık", "Çay", "Zeytin"...) yatay
/// seçim çipleri, altında seçili maddeye göre vurgulanmış GERÇEK Türkiye
/// haritası ve en altta madde açıklaması gösterilir.
///
/// Harita, oyun modlarıyla AYNI [TurkeyMapCanvas] bileşenini kullanır. Vurgu
/// rengi kullanıcının seçtiği harita rengidir (bkz. mapHighlightColor /
/// MapColorPickerAction) — sağ üstteki 🎨 ile değiştirilir ve hatırlanır.
class LearnMapDetailScreen extends StatefulWidget {
  final LearnMapCategory category;
  const LearnMapDetailScreen({super.key, required this.category});

  @override
  State<LearnMapDetailScreen> createState() => _LearnMapDetailScreenState();
}

class _LearnMapDetailScreenState extends State<LearnMapDetailScreen> {
  late LearnMapItem _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.category.items.first;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeProvider>().colors;
    final vurgu = mapHighlightColor(context);
    final highlighted = _selected.provinceIds.toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.category.icon} ${widget.category.title}'),
        actions: const [MapColorPickerAction()],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(vurgu.withValues(alpha: 0.08), colors.bg),
              colors.bg,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Madde seçim çipleri — seçili çip harita rengiyle vurgulanır.
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.category.items.length,
                    separatorBuilder: (context, i) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final item = widget.category.items[i];
                      final isSelected = item.id == _selected.id;
                      return _MaddeCipi(
                        label: item.title,
                        selected: isSelected,
                        renk: vurgu,
                        onTap: () {
                          context.read<SoundService>().click();
                          setState(() => _selected = item);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                // Vurgulanan il sayısı göstergesi (lejant).
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: vurgu,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${highlighted.length} il vurgulandı',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textDim),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TurkeyMapCanvas(
                    provinces: kTurkeyProvinces,
                    colorFor: (p) => highlighted.contains(p.id)
                        ? vurgu
                        : colors.textFaint.withValues(alpha: 0.16),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.alphaBlend(vurgu.withValues(alpha: 0.14), colors.bg2),
                        colors.bg2,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: vurgu.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: vurgu.withValues(alpha: 0.20),
                              shape: BoxShape.circle,
                            ),
                            child: Text(widget.category.icon,
                                style: const TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _selected.title,
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: colors.text),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_selected.subtitle,
                          style: TextStyle(
                              fontSize: 12.5, color: colors.textDim, height: 1.4)),
                    ],
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

/// "Haritadan Öğren" madde seçim çipi — seçiliyken harita rengiyle dolar.
class _MaddeCipi extends StatelessWidget {
  final String label;
  final bool selected;
  final Color renk;
  final VoidCallback onTap;
  const _MaddeCipi({
    required this.label,
    required this.selected,
    required this.renk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? renk : c.glass2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? renk : c.border,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: renk.withValues(alpha: 0.4), blurRadius: 8)]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : c.text,
            ),
          ),
        ),
      ),
    );
  }
}
