import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/subject.dart';
import '../services/ders_bildirim_service.dart';
import '../services/notification_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import '../utils/ust_bildirim.dart';
import 'tools_hub_screen.dart';

/// "Ders Bildirimleri" ekranı (kullanıcı isteği): kullanıcı İSTEDİĞİ DERSTEN,
/// İSTEDİĞİ GÜN ve SAATTE, İSTEDİĞİ KADAR bildirim ekleyebilir. Bildirim içeriği
/// kısa akılda kalıcı kodlama / motivasyon / "bunu biliyor musun?" metinleridir.
/// Tasarım, anasayfadaki "Çalışma Planı Oluştur" akışıyla aynı dildedir.
class DersBildirimScreen extends StatefulWidget {
  const DersBildirimScreen({super.key});

  @override
  State<DersBildirimScreen> createState() => _DersBildirimScreenState();
}

class _DersBildirimScreenState extends State<DersBildirimScreen> {
  final _svc = DersBildirimService();
  List<DersBildirimi> _liste = [];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  void _yukle() {
    _liste = _svc.getir(context.read<StorageService>());
  }

  Future<void> _kaydetVeKur() async {
    final storage = context.read<StorageService>();
    await _svc.kaydet(storage, _liste);
    // İzin iste (ilk eklemede) ve bildirimleri yeniden kur.
    await NotificationService.instance.requestPermission();
    await NotificationService.instance
        .scheduleDersBildirimleri(_liste, storage: storage);
  }

  Future<void> _ekle() async {
    context.read<SoundService>().click();
    final sonuc = await showModalBottomSheet<List<DersBildirimi>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EkleSheet(),
    );
    if (sonuc == null || sonuc.isEmpty) return;
    setState(() => _liste = [..._liste, ...sonuc]);
    await _kaydetVeKur();
    if (mounted) ustBildirim('${sonuc.length} bildirim eklendi 🔔');
  }

  Future<void> _sil(DersBildirimi b) async {
    context.read<SoundService>().click();
    setState(() => _liste = _liste.where((x) => x.id != b.id).toList());
    await _kaydetVeKur();
  }

  Future<void> _acKapa(DersBildirimi b, bool v) async {
    setState(() => _liste =
        _liste.map((x) => x.id == b.id ? x.copyWith(aktif: v) : x).toList());
    await _kaydetVeKur();
  }

  @override
  Widget build(BuildContext context) {
    // Premium'a özel özellik (kullanıcı isteği): ücretsiz kullanıcı kilitli
    // vitrini görür, Premium'a yönlendirilir.
    if (!context.watch<StorageService>().isPremiumUser()) {
      return const LockedFeatureCard(
        title: 'Ders Bildirimleri',
        desc:
            "Seçtiğin dersten, seçtiğin gün ve saatte akılda kalıcı kodlama, "
            "motivasyon ve \"bunu biliyor musun?\" bildirimi almak için Premium'a geç.",
      );
    }
    final c = context.watch<ThemeProvider>().colors;
    final sirali = [..._liste]..sort((a, b) {
        final g = a.gun.compareTo(b.gun);
        if (g != 0) return g;
        return a.dakikaToplam.compareTo(b.dakikaToplam);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('🔔 Ders Bildirimleri')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _ekle,
        backgroundColor: c.violet,
        icon: const Icon(Icons.add_alarm_rounded, color: Colors.white),
        label: const Text('Bildirim Ekle',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            DsCard(
              accent: c.violet,
              child: Row(
                children: [
                  DsIconBadge(
                      icon: Icons.notifications_active_rounded,
                      color: c.violet,
                      size: 44,
                      glow: false),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'İstediğin dersten, istediğin gün ve saatte bildirim al. '
                      'İçerik: akılda kalıcı kodlama, motivasyon ve "bunu biliyor '
                      'musun?". Bir güne dilediğin kadar ekleyebilirsin.',
                      style: TextStyle(
                          fontSize: 12.5, height: 1.4, color: c.textDim),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (sirali.isEmpty)
              _BosDurum(colors: c)
            else
              for (final b in sirali) ...[
                _BildirimKart(
                  bildirim: b,
                  colors: c,
                  onSil: () => _sil(b),
                  onAcKapa: (v) => _acKapa(b, v),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _BosDurum extends StatelessWidget {
  final KpssColors colors;
  const _BosDurum({required this.colors});

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        children: [
          const Text('🔕', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('Henüz bildirim yok',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: colors.text)),
          const SizedBox(height: 4),
          Text(
            'Aşağıdaki "Bildirim Ekle" ile ilk ders bildirimini oluştur.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: colors.textFaint),
          ),
        ],
      ),
    );
  }
}

class _BildirimKart extends StatelessWidget {
  final DersBildirimi bildirim;
  final KpssColors colors;
  final VoidCallback onSil;
  final ValueChanged<bool> onAcKapa;
  const _BildirimKart({
    required this.bildirim,
    required this.colors,
    required this.onSil,
    required this.onAcKapa,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final ders = kSubjects.where((s) => s.id == bildirim.dersId);
    final dersAd = ders.isEmpty ? bildirim.dersId : ders.first.ad;
    final dersIcon = ders.isEmpty ? '📘' : ders.first.icon;
    return DsCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Saat + gün rozeti.
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: c.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.violet.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Text(bildirim.saatMetni,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: c.text)),
                Text(DersBildirimService.gunKisa(bildirim.gun),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.violet)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$dersIcon $dersAd',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: c.text)),
                const SizedBox(height: 1),
                Text(DersBildirimService.gunUzun(bildirim.gun),
                    style: TextStyle(fontSize: 11.5, color: c.textFaint)),
              ],
            ),
          ),
          Switch(
            value: bildirim.aktif,
            activeThumbColor: c.violet,
            onChanged: onAcKapa,
          ),
          IconButton(
            tooltip: 'Sil',
            icon: Icon(Icons.delete_outline_rounded, color: c.danger, size: 22),
            onPressed: onSil,
          ),
        ],
      ),
    );
  }
}

/// Alttan açılan ekleme sayfası: gün(ler) + saat + ders seçilir; her seçili gün
/// için bir bildirim üretilir.
class _EkleSheet extends StatefulWidget {
  const _EkleSheet();

  @override
  State<_EkleSheet> createState() => _EkleSheetState();
}

class _EkleSheetState extends State<_EkleSheet> {
  final Set<int> _gunler = {DateTime.now().weekday};
  TimeOfDay _saat = const TimeOfDay(hour: 20, minute: 0);
  String _dersId = kSubjects.last.id; // Türkçe varsayılan

  Future<void> _saatSec() async {
    final s = await showTimePicker(
      context: context,
      initialTime: _saat,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (s != null) setState(() => _saat = s);
  }

  void _onayla() {
    if (_gunler.isEmpty) {
      ustBildirim('En az bir gün seç.');
      return;
    }
    context.read<SoundService>().click();
    final yeni = _gunler.map((g) => DersBildirimi(
          id: DersBildirimi.yeniId(),
          gun: g,
          saat: _saat.hour,
          dakika: _saat.minute,
          dersId: _dersId,
        ));
    Navigator.of(context).pop(yeni.toList());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Container(
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Bildirim Ekle',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: c.text)),
              const SizedBox(height: 16),

              // ── GÜN(LER) ──
              Text('Gün(ler)',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.textDim)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var g = 1; g <= 7; g++)
                    _SecimChip(
                      etiket: DersBildirimService.gunKisa(g),
                      secili: _gunler.contains(g),
                      renk: c.violet,
                      onTap: () => setState(() {
                        if (_gunler.contains(g)) {
                          _gunler.remove(g);
                        } else {
                          _gunler.add(g);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // ── SAAT ──
              Text('Saat',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.textDim)),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _saatSec,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: c.glass2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time_rounded, color: c.violet, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        '${_saat.hour.toString().padLeft(2, '0')}:${_saat.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: c.text),
                      ),
                      const Spacer(),
                      Text('Değiştir',
                          style: TextStyle(fontSize: 12.5, color: c.violet)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ── DERS ──
              Text('Ders',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.textDim)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in kSubjects)
                    _SecimChip(
                      etiket: '${s.icon} ${s.ad}',
                      secili: _dersId == s.id,
                      renk: c.violet,
                      onTap: () => setState(() => _dersId = s.id),
                    ),
                ],
              ),
              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,
                child: DsPillButton(
                  label: 'Ekle',
                  color: c.violet,
                  trailingIcon: Icons.check_rounded,
                  onPressed: _onayla,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecimChip extends StatelessWidget {
  final String etiket;
  final bool secili;
  final Color renk;
  final VoidCallback onTap;
  const _SecimChip({
    required this.etiket,
    required this.secili,
    required this.renk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: secili ? renk.withValues(alpha: 0.16) : c.glass2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: secili ? renk : c.border,
            width: secili ? 1.6 : 1,
          ),
        ),
        child: Text(
          etiket,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: secili ? c.text : c.textDim,
          ),
        ),
      ),
    );
  }
}
