import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../services/study_plan_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import 'premium_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Günlük Çalışma Planı ekranı
/// ─────────────────────────────────────────────────────────────────────────
///
/// Kullanıcı haftanın günlerinden birine (ücretsiz) ya da istediği kadarına
/// (premium) çalışma saati aralığı atar. Plan kaydedildiği anda
/// [NotificationService] haftalık tekrarlayan hatırlatıcıları yeniden kurar.
///
/// Ayrıca ekranın altında, çözülen testlerin ortalamalarına bakarak
/// "en zayıf ders" önerisi gösterilir (bkz. StudyPlanService.weakestSubject).
/// [plan] içinde [gun] gününe ait kayıt varsa döner, yoksa null.
StudyPlanEntry? _gunKaydi(List<StudyPlanEntry> plan, int gun) {
  for (final e in plan) {
    if (e.gun == gun) return e;
  }
  return null;
}

class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  /// Bildirim izni bu oturumda bir kez istensin diye tutulan bayrak.
  bool _izinIstendi = false;

  StudyPlanService _servis(BuildContext context) =>
      StudyPlanService(context.read<StorageService>());

  void _tik() {
    try {
      context.read<SoundService>().click();
    } catch (_) {
      // Ses servisi yoksa/başlatılamadıysa sessizce geç.
    }
  }

  // ── Bildirimleri planla ──────────────────────────────────────────────────

  /// Plan her değiştiğinde çağrılır: izin (bir kez) + bildirimleri yeniden kur.
  Future<void> _bildirimleriYenile() async {
    final storage = context.read<StorageService>();
    final servis = StudyPlanService(storage);
    final bildirim = NotificationService.instance;

    try {
      if (!_izinIstendi && servis.getActivePlan().isNotEmpty) {
        _izinIstendi = true;
        await bildirim.requestPermission();
      }
      await bildirim.schedulePlan(servis.getActivePlan(), storage: storage);
    } catch (_) {
      // NotificationService zaten kendi içinde yutuyor; burası ekstra ağ.
    }
  }

  // ── Kullanıcı eylemleri ──────────────────────────────────────────────────

  Future<void> _gunuDuzenle(int gun) async {
    _tik();
    final servis = _servis(context);
    final mevcut = _gunKaydi(servis.getPlan(), gun);

    // Ücretsiz kullanıcı ikinci günü eklemeye çalışıyorsa premium'a yönlendir.
    if (mevcut == null && !servis.canAddDay(gun)) {
      await _premiumBilgisiGoster();
      return;
    }

    final baslangic = await showTimePicker(
      context: context,
      helpText: '${StudyPlanService.gunAdi(gun)} — Başlangıç saati',
      confirmText: 'İLERİ',
      cancelText: 'VAZGEÇ',
      initialTime: mevcut == null
          ? const TimeOfDay(hour: 19, minute: 0)
          : TimeOfDay(hour: mevcut.baslangicSaat, minute: mevcut.baslangicDakika),
    );
    if (baslangic == null || !mounted) return;

    final bitis = await showTimePicker(
      context: context,
      helpText: '${StudyPlanService.gunAdi(gun)} — Bitiş saati',
      confirmText: 'KAYDET',
      cancelText: 'VAZGEÇ',
      initialTime: mevcut == null
          ? TimeOfDay(hour: (baslangic.hour + 1) % 24, minute: baslangic.minute)
          : TimeOfDay(hour: mevcut.bitisSaat, minute: mevcut.bitisDakika),
    );
    if (bitis == null || !mounted) return;

    final entry = StudyPlanEntry(
      gun: gun,
      baslangicSaat: baslangic.hour,
      baslangicDakika: baslangic.minute,
      bitisSaat: bitis.hour,
      bitisDakika: bitis.minute,
      aktif: mevcut?.aktif ?? true,
    );

    final sonuc = await servis.upsertEntry(entry);
    if (!mounted) return;

    switch (sonuc) {
      case StudyPlanSaveResult.basarili:
        await _bildirimleriYenile();
        if (!mounted) return;
        setState(() {});
        _mesaj('${StudyPlanService.gunAdi(gun)} planına eklendi ✅');
      case StudyPlanSaveResult.premiumGerekli:
        await _premiumBilgisiGoster();
      case StudyPlanSaveResult.gecersizSaat:
        _mesaj('Bitiş saati, başlangıçtan sonra olmalı ⏰');
      case StudyPlanSaveResult.hata:
        _mesaj('Plan kaydedilemedi, tekrar dener misin?');
    }
  }

  Future<void> _gunuSil(int gun) async {
    _tik();
    final servis = _servis(context);
    await servis.removeEntry(gun);
    if (!mounted) return;
    await _bildirimleriYenile();
    if (!mounted) return;
    setState(() {});
    _mesaj('${StudyPlanService.gunAdi(gun)} plandan çıkarıldı');
  }

  Future<void> _gunuAcKapa(int gun, bool aktif) async {
    _tik();
    final servis = _servis(context);
    await servis.toggleEntry(gun, aktif);
    if (!mounted) return;
    await _bildirimleriYenile();
    if (!mounted) return;
    setState(() {});
  }

  void _mesaj(String metin) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(metin)));
  }

  /// Ücretsiz kullanıcı gün limitini aştığında gösterilen bilgi kutusu.
  Future<void> _premiumBilgisiGoster() async {
    final c = context.read<ThemeProvider>().colors;
    final gitsinMi = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kDsRadius)),
        title: Row(
          children: [
            Text('💎', style: TextStyle(fontSize: 22, color: c.gold)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Haftanın tamamını planla',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: c.text),
              ),
            ),
          ],
        ),
        content: Text(
          'Ücretsiz planda haftada ${StudyPlanService.kFreeMaxDays} gün '
          'planlayabilirsin. Premium ile haftanın 7 gününe ayrı ayrı çalışma '
          'saati koyabilir, her biri için hatırlatma alabilirsin.',
          style: TextStyle(fontSize: 13.5, height: 1.45, color: c.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Şimdi değil', style: TextStyle(color: c.textFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Premium\'a Geç',
                style: TextStyle(color: c.gold, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (gitsinMi == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PremiumScreen()),
      );
      if (mounted) setState(() {});
    }
  }

  // ── Görünüm ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    // StorageService'i watch ediyoruz: plan kaydedildiğinde (saveSettings →
    // notifyListeners) ekran kendiliğinden tazelenir.
    final storage = context.watch<StorageService>();
    final servis = StudyPlanService(storage);
    final plan = servis.getPlan();

    return Scaffold(
      appBar: AppBar(
        title: const Text('🗓️ Çalışma Planı'),
        actions: [
          if (plan.isNotEmpty)
            IconButton(
              tooltip: 'Planı temizle',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                _tik();
                await servis.clearPlan();
                if (!mounted) return;
                await NotificationService.instance.cancelPlanNotifications();
                if (!mounted) return;
                setState(() {});
                _mesaj('Plan temizlendi');
              },
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _OzetKart(servis: servis),
            const SizedBox(height: kDsGap),
            const DsSectionHeader(title: 'Haftalık Plan'),
            const SizedBox(height: 4),
            for (var gun = 1; gun <= 7; gun++) ...[
              _GunSatiri(
                gun: gun,
                entry: _gunKaydi(plan, gun),
                onDuzenle: () => _gunuDuzenle(gun),
                onSil: () => _gunuSil(gun),
                onAcKapa: (v) => _gunuAcKapa(gun, v),
              ),
              const SizedBox(height: kDsGap),
            ],
            if (!servis.isPremium) ...[
              _UcretsizLimitKarti(onPremium: _premiumBilgisiGoster),
              const SizedBox(height: kDsGap),
            ],
            const DsSectionHeader(title: 'Ders Önerisi'),
            const SizedBox(height: 4),
            _OneriKarti(servis: servis),
            const SizedBox(height: kDsGap),
            _BilgiNotu(colors: c),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Ekranın tepesindeki özet: bir sonraki seans ya da "henüz plan yok" daveti.
class _OzetKart extends StatelessWidget {
  final StudyPlanService servis;
  const _OzetKart({required this.servis});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final sonraki = servis.nextSession();
    final planVar = servis.getPlan().isNotEmpty;

    final baslik = sonraki != null
        ? servis.nextSessionLabel()
        : (planVar ? 'Tüm günlerin kapalı' : 'Henüz planın yok');
    final altBaslik = sonraki != null
        ? '${servis.nextSessionCountdown()} • ${sonraki.entry.sureDakika} dakikalık seans'
        : (planVar
            ? 'Aşağıdan bir günü tekrar açarsan hatırlatma gönderirim.'
            : 'Aşağıdan bir gün seç, çalışma saatini belirle. O saatte seni dürteceğim.');

    return DsCard(
      accent: c.violet,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DsIconBadge(
            emoji: sonraki != null ? '⏰' : '🗓️',
            color: sonraki?.suAnDevamEdiyor == true ? c.success : c.violet,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  baslik,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c.text),
                ),
                const SizedBox(height: 5),
                Text(
                  altBaslik,
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Haftanın tek bir günü: planlıysa saat aralığı + aç/kapa + sil, değilse ekle.
class _GunSatiri extends StatelessWidget {
  final int gun;
  final StudyPlanEntry? entry;
  final VoidCallback onDuzenle;
  final VoidCallback onSil;
  final ValueChanged<bool> onAcKapa;

  const _GunSatiri({
    required this.gun,
    required this.entry,
    required this.onDuzenle,
    required this.onSil,
    required this.onAcKapa,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final e = entry;
    final planli = e != null;
    final bugunMu = DateTime.now().weekday == gun;
    final vurgu = planli ? (e.aktif ? c.violet : c.textFaint) : c.textFaint;

    return DsCard(
      accent: planli ? vurgu : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onTap: onDuzenle,
      child: Row(
        children: [
          DsIconBadge(
            emoji: planli ? '✅' : '➕',
            color: vurgu,
            size: 44,
            circle: false,
            glow: false,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        StudyPlanService.gunAdi(gun),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w800, color: c.text),
                      ),
                    ),
                    if (bugunMu) ...[
                      const SizedBox(width: 6),
                      DsChip(label: 'BUGÜN', color: c.gold),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  planli
                      ? '${e.araliqMetni} • ${e.sureDakika} dk'
                          '${e.aktif ? '' : ' • kapalı'}'
                      : 'Saat belirlemek için dokun',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.textFaint),
                ),
              ],
            ),
          ),
          if (planli) ...[
            const SizedBox(width: 4),
            Switch(
              value: e.aktif,
              onChanged: onAcKapa,
              activeThumbColor: c.violet,
            ),
            IconButton(
              tooltip: 'Kaldır',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 20, color: c.textFaint),
              onPressed: onSil,
            ),
          ] else
            Icon(Icons.chevron_right, size: 20, color: c.textFaint),
        ],
      ),
    );
  }
}

/// Ücretsiz kullanıcıya limiti hatırlatan ve premium'a yönlendiren kart.
class _UcretsizLimitKarti extends StatelessWidget {
  final Future<void> Function() onPremium;
  const _UcretsizLimitKarti({required this.onPremium});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      accent: c.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconBadge(emoji: '💎', color: c.gold, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Ücretsiz plan: ${StudyPlanService.kFreeMaxDays} gün',
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w900, color: c.text)),
                    const SizedBox(height: 4),
                    Text(
                      'Premium ile haftanın 7 gününü ayrı ayrı planla, her gün için '
                      'hatırlatma al.',
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: DsPillButton(
              label: 'Premium\'a Geç',
              color: c.gold,
              trailingIcon: Icons.arrow_forward,
              onPressed: () => onPremium(),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Bence şu derse daha fazla çalışmalısın" bölümü.
class _OneriKarti extends StatelessWidget {
  final StudyPlanService servis;
  const _OneriKarti({required this.servis});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final zayif = servis.weakestSubject();

    if (zayif == null) {
      return DsCard(
        child: Row(
          children: [
            DsIconBadge(emoji: '🔎', color: c.violetL, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Önce birkaç test çöz, sana özel öneri hazırlayayım.',
                style: TextStyle(fontSize: 13, height: 1.4, color: c.textDim),
              ),
            ),
          ],
        ),
      );
    }

    // Ortalama düştükçe uyarıcı, yükseldikçe olumlu bir renk kullan.
    final renk = zayif.ortalama < 50
        ? c.danger
        : (zayif.ortalama < 70 ? c.warn : c.success);

    return DsCard(
      accent: renk,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DsIconBadge(emoji: zayif.ders.icon, color: renk, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bence ${zayif.ders.ad} dersine daha fazla çalışmalısın',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w900, color: c.text),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${zayif.ders.ad} ortalaman %${zayif.ortalama} — en zayıf dersin.',
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DsProgressBar(value: zayif.ortalama / 100, color: renk),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ortalaman', style: TextStyle(fontSize: 11.5, color: c.textFaint)),
              Text('%${zayif.ortalama}',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w900, color: renk)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bildirimlerin nasıl çalıştığını anlatan küçük bilgi notu.
class _BilgiNotu extends StatelessWidget {
  final KpssColors colors;
  const _BilgiNotu({required this.colors});

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: colors.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Planladığın gün ve saatte telefonuna hatırlatma gönderilir; '
              'hatırlatmalar her hafta aynı saatte tekrarlanır. Bildirimleri '
              'Ayarlar\'dan tamamen kapatabilirsin.',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: colors.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
