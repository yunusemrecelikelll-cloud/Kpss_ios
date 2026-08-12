import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/karalama_not_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/design_system.dart';
import '../../theme/theme_provider.dart';

/// KPSS Düello "Not Defteri" (kullanıcı isteği): oyun/oda ekranlarında hızlıca
/// açılan, serbest metin alınabilen bir defter. Notlar StorageService üzerinden
/// aktif kullanıcıya özel kalıcı olarak saklanır (oturumlar arası korunur).
///
/// [DuelNotepadButton] bir AppBar aksiyonudur; basınca alt sayfada defteri açar.
class DuelNotepadButton extends StatelessWidget {
  const DuelNotepadButton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return IconButton(
      icon: const Icon(Icons.edit_note),
      tooltip: 'Not Defteri',
      color: c.violetL,
      onPressed: () => showDuelNotepad(context),
    );
  }
}

/// Not defterini bir alt sayfada (modal bottom sheet) açar.
Future<void> showDuelNotepad(BuildContext context) {
  final c = context.read<ThemeProvider>().colors;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.bg2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _DuelNotepadSheet(),
  );
}

class _DuelNotepadSheet extends StatefulWidget {
  const _DuelNotepadSheet();

  @override
  State<_DuelNotepadSheet> createState() => _DuelNotepadSheetState();
}

class _DuelNotepadSheetState extends State<_DuelNotepadSheet> {
  late final TextEditingController _ctrl;
  late final StorageService _storage;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    _ctrl = TextEditingController(text: _storage.getDuelNote());
    // Her değişiklikte otomatik kaydet (buton beklemeden).
    _ctrl.addListener(_save);
  }

  // KPSS Düello notunun Notlarım'daki SABİT kaydı — hep aynı not güncellenir.
  static const String _duelNotId = 'kpss_duel_note';
  final KaralamaNotService _notSvc = KaralamaNotService();

  void _save() {
    _storage.setDuelNote(_ctrl.text);
  }

  /// Notu, anasayfadaki "Notlarım" listesine "KPSS Düello" kaynağıyla yazar
  /// (kullanıcı isteği). Sabit id ile upsert edildiği için tek not güncellenir;
  /// metin boşsa kayıt silinir.
  void _notlarimaKaydet() {
    _notSvc.upsert(
      _storage,
      KaralamaNot(
        id: _duelNotId,
        metin: _ctrl.text,
        metinRenk: 0xFF241C33,
        cizgiler: const [],
        w: 300,
        h: 200,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        kaynak: 'KPSS Düello',
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.removeListener(_save);
    _save();
    // Çıkınca/kapanınca otomatik olarak Notlarım'a da kaydet.
    _notlarimaKaydet();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Padding(
      padding: EdgeInsets.only(
        left: 18, right: 18, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(
            children: [
              Icon(Icons.edit_note, color: c.violetL, size: 22),
              const SizedBox(width: 8),
              Text('Not Defteri',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900, color: c.text)),
              const Spacer(),
              // Notu temizle
              TextButton.icon(
                onPressed: _ctrl.text.isEmpty
                    ? null
                    : () {
                        context.read<SoundService>().click();
                        setState(() => _ctrl.clear());
                      },
                icon: Icon(Icons.delete_outline, size: 18, color: c.danger),
                label: Text('Temizle', style: TextStyle(color: c.danger)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('İşlem, hatırlatma ya da eleme takibi için karalama alanı. '
              'Otomatik kaydedilir.',
              style: TextStyle(fontSize: 11.5, color: c.textFaint)),
          const SizedBox(height: 12),
          DsCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              minLines: 6,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 15, height: 1.4, color: c.text),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Notlarını buraya yaz…',
              ),
              onChanged: (_) => setState(() {}), // Temizle butonunun aktifliği için
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: DsPillButton(
              label: 'Kapat',
              color: c.violetL,
              onPressed: () {
                context.read<SoundService>().click();
                Navigator.of(context).maybePop();
              },
            ),
          ),
        ],
      ),
    );
  }
}
