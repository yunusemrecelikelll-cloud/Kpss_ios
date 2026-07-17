import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/learn_map_data.dart';
import '../../data/turkey_map_data.dart';
import '../../services/sound_service.dart';
import '../../theme/theme_provider.dart';
import '../../widgets/turkey_map_painter.dart';

/// Bir "Haritadan Öğren" kategorisi (ör. "Tarım") seçildiğinde açılan ekran.
/// Üstte kategorideki maddelerin (ör. "Fındık", "Çay", "Zeytin"...) yatay
/// seçim çipleri, altında seçili maddeye göre vurgulanmış GERÇEK Türkiye
/// haritası ([TurkeyMapWidget]) ve en altta madde açıklaması + veri kaynağı
/// gösterilir.
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
    final highlighted = _selected.provinceIds.toSet();

    final fillColors = <String, Color>{
      for (final p in kTurkeyProvinces)
        p.id: highlighted.contains(p.id) ? colors.violet : colors.textFaint.withValues(alpha: 0.18),
    };

    return Scaffold(
      appBar: AppBar(title: Text('${widget.category.icon} ${widget.category.title}')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.category.items.length,
                  separatorBuilder: (context, i) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final item = widget.category.items[i];
                    final isSelected = item.id == _selected.id;
                    return ChoiceChip(
                      label: Text(item.title),
                      selected: isSelected,
                      onSelected: (_) {
                        context.read<SoundService>().click();
                        setState(() => _selected = item);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.glass,
                      border: Border.all(color: colors.border),
                    ),
                    child: InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 3.2,
                      child: TurkeyMapWidget(
                        fillColors: fillColors,
                        defaultFillColor: colors.textFaint.withValues(alpha: 0.18),
                        borderColor: colors.border,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.glass2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selected.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                    ),
                    const SizedBox(height: 6),
                    Text(_selected.subtitle, style: TextStyle(fontSize: 12.5, color: colors.text, height: 1.4)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_outlined, size: 14, color: colors.mint),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Kaynak: ${_selected.kaynak}',
                            style: TextStyle(fontSize: 10.5, color: colors.textFaint, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
