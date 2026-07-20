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
/// Harita, oyun modlarıyla AYNI [TurkeyMapCanvas] bileşenini kullanır — böylece
/// yakınlaştırma/uzaklaştırma davranışı (kademeli animasyon, min/max ölçek,
/// çift dokunuşla sıfırlama) ve en/boy oranını koruyan yerleşim uygulamanın
/// TÜM haritalarında birebir aynıdır.
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
              // NOT: Harita artık kendi en/boy oranını KORUYARAK alana sığar
              // (sıkışmaz/yayvanlaşmaz) ve arkasında beyaz bir dolgu/çerçeve
              // ÇİZİLMEZ — artan boşluk şeffaf kalır.
              Expanded(
                child: TurkeyMapCanvas(
                  provinces: kTurkeyProvinces,
                  colorFor: (p) => highlighted.contains(p.id)
                      ? colors.violet
                      : colors.textFaint.withValues(alpha: 0.18),
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
                    // NOT: Alttaki "Kaynak: ..." satırı kullanıcı isteğiyle
                    // KALDIRILDI. Kaynak bilgisi verinin kendisinde
                    // ([LearnMapItem.kaynak], bkz. lib/data/learn_map_data.dart)
                    // doğruluk denetimi için KORUNUYOR, sadece ekranda
                    // gösterilmiyor.
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
