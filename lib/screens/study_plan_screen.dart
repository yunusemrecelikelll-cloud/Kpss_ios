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
/// (premium) çalışma saati aralığı atar. AYNI GÜNE birden fazla aralık (seans)
/// eklenebilir — ör. Pazartesi 09:00–11:00 ve 19:00–21:00. Plan kaydedildiği
/// anda [NotificationService] haftalık tekrarlayan hatırlatıcıları yeniden
/// kurar (her seans için ayrı bildirim).
///
/// Ayrıca ekranın altında, çözülen testlerin ortalamalarına bakarak
/// "en zayıf ders" önerisi gösterilir (bkz. StudyPlanService.weakestSubject).

/// Bir [TimeOfDay]'i metne çevirir.
///
/// Varsayılan 24 SAAT biçimidir ("19:00") — Türkiye'de standart budur ve
/// ekranda gösterilen tüm saatler bu biçimi kullanır. [onikiSaat] true
/// verilirse 12 saat biçimine düşülür; bu durumda İngilizce AM/PM yerine
/// Türkçe karşılıkları yazılır: "ÖÖ" (öğleden önce) / "ÖS" (öğleden sonra).
String saatMetni(TimeOfDay t, {bool onikiSaat = false}) {
  final dk = t.minute.toString().padLeft(2, '0');
  if (!onikiSaat) {
    return '${t.hour.toString().padLeft(2, '0')}:$dk';
  }
  final ek = t.hour < 12 ? 'ÖÖ' : 'ÖS';
  var saat = t.hour % 12;
  if (saat == 0) saat = 12;
  return '${saat.toString().padLeft(2, '0')}:$dk $ek';
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
        final izinVar = await bildirim.requestPermission();
        // SESSİZ BAŞARISIZLIK ENGELİ: izin reddedilmişse bildirimler hiç
        // gösterilmez ama kullanıcı bunu bilmiyordu ("bildirim gelmiyor").
        // Artık açıkça söylüyoruz ve nereden açacağını tarif ediyoruz.
        if (!izinVar && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 7),
              content: Text(
                  'Bildirim izni verilmemiş — hatırlatmalar gelmeyecek. '
                  'Telefon Ayarları > Uygulamalar > KPSS Hazırlık > '
                  'Bildirimler bölümünden izin verebilirsin.'),
            ),
          );
        }
      }
      await bildirim.schedulePlan(servis.getActivePlan(), storage: storage);
    } catch (_) {
      // NotificationService zaten kendi içinde yutuyor; burası ekstra ağ.
    }
  }

  // ── Saat seçimi ──────────────────────────────────────────────────────────

  /// Saat seçiciyi 24 SAAT biçimine zorlayarak açar. `MediaQuery` ile
  /// `alwaysUse24HourFormat: true` verildiği için AM/PM hiç görünmez; cihazın
  /// dil/bölge ayarı 12 saat biçiminde olsa bile plan saatleri Türkiye
  /// standardındaki gibi 00–23 arasında seçilir.
  Future<TimeOfDay?> _saatSec({
    required String yardimMetni,
    required String onayMetni,
    required TimeOfDay baslangic,
  }) {
    return showTimePicker(
      context: context,
      helpText: yardimMetni,
      confirmText: onayMetni,
      cancelText: 'VAZGEÇ',
      hourLabelText: 'Saat',
      minuteLabelText: 'Dakika',
      initialTime: baslangic,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  /// Başlangıç + bitiş saatini sırayla sorar. Kullanıcı vazgeçerse null döner.
  Future<({TimeOfDay bas, TimeOfDay bit})?> _araligiSor({
    required int gun,
    required String basligiOnEki,
    TimeOfDay? mevcutBas,
    TimeOfDay? mevcutBit,
  }) async {
    final gunAdi = StudyPlanService.gunAdi(gun);

    final bas = await _saatSec(
      yardimMetni: '$gunAdi — $basligiOnEki başlangıç saati',
      onayMetni: 'İLERİ',
      baslangic: mevcutBas ?? const TimeOfDay(hour: 19, minute: 0),
    );
    if (bas == null || !mounted) return null;

    final bit = await _saatSec(
      yardimMetni: '$gunAdi — bitiş saati (başlangıç ${saatMetni(bas)})',
      onayMetni: 'KAYDET',
      baslangic: mevcutBit ?? TimeOfDay(hour: (bas.hour + 1) % 24, minute: bas.minute),
    );
    if (bit == null || !mounted) return null;

    return (bas: bas, bit: bit);
  }

  // ── Kullanıcı eylemleri ──────────────────────────────────────────────────

  /// Verilen güne YENİ bir çalışma seansı ekler.
  Future<void> _seansEkle(int gun) async {
    _tik();
    final servis = _servis(context);

    // Ücretsiz kullanıcı YENİ bir gün açmaya çalışıyorsa premium'a yönlendir.
    // (Zaten planlı bir güne seans eklemek serbesttir.)
    if (!servis.canAddDay(gun)) {
      await _premiumBilgisiGoster();
      return;
    }

    final mevcutlar = servis.getGunSeanslari(gun);
    if (mevcutlar.length >= StudyPlanService.kMaxSeansPerGun) {
      _mesaj('Bir güne en fazla ${StudyPlanService.kMaxSeansPerGun} seans '
          'ekleyebilirsin.');
      return;
    }

    // Yeni seans için makul bir varsayılan: günün son seansının bitişinden
    // bir saat sonrası; hiç seans yoksa 19:00.
    TimeOfDay? onerilen;
    if (mevcutlar.isNotEmpty) {
      final son = mevcutlar.last;
      onerilen = TimeOfDay(hour: (son.bitisSaat + 1) % 24, minute: son.bitisDakika);
    }

    final aralik = await _araligiSor(
      gun: gun,
      basligiOnEki: 'yeni seans',
      mevcutBas: onerilen,
    );
    if (aralik == null || !mounted) return;

    await _kaydet(
      StudyPlanEntry(
        id: StudyPlanEntry.yeniId(),
        gun: gun,
        baslangicSaat: aralik.bas.hour,
        baslangicDakika: aralik.bas.minute,
        bitisSaat: aralik.bit.hour,
        bitisDakika: aralik.bit.minute,
      ),
      basariMesaji: '${StudyPlanService.gunAdi(gun)} planına eklendi ✅',
    );
  }

  /// Var olan bir seansın saatlerini değiştirir.
  Future<void> _seansDuzenle(StudyPlanEntry entry) async {
    _tik();
    final aralik = await _araligiSor(
      gun: entry.gun,
      basligiOnEki: 'seans',
      mevcutBas: TimeOfDay(hour: entry.baslangicSaat, minute: entry.baslangicDakika),
      mevcutBit: TimeOfDay(hour: entry.bitisSaat, minute: entry.bitisDakika),
    );
    if (aralik == null || !mounted) return;

    await _kaydet(
      entry.copyWith(
        baslangicSaat: aralik.bas.hour,
        baslangicDakika: aralik.bas.minute,
        bitisSaat: aralik.bit.hour,
        bitisDakika: aralik.bit.minute,
      ),
      basariMesaji: 'Seans güncellendi ✅',
    );
  }

  /// Ekleme/düzenleme sonrası ortak kayıt + geri bildirim akışı.
  Future<void> _kaydet(StudyPlanEntry entry, {required String basariMesaji}) async {
    final servis = _servis(context);
    final sonuc = await servis.upsertSession(entry);
    if (!mounted) return;

    switch (sonuc) {
      case StudyPlanSaveResult.basarili:
        await _bildirimleriYenile();
        if (!mounted) return;
        setState(() {});
        _mesaj(basariMesaji);
      case StudyPlanSaveResult.premiumGerekli:
        await _premiumBilgisiGoster();
      case StudyPlanSaveResult.gecersizSaat:
        _mesaj('Bitiş saati, başlangıç saatinden sonra olmalı ⏰');
      case StudyPlanSaveResult.cakisma:
        _mesaj('Bu aralık aynı gündeki başka bir seansla çakışıyor. '
            'Farklı bir saat seç ⏰');
      case StudyPlanSaveResult.seansLimiti:
        _mesaj('Bir güne en fazla ${StudyPlanService.kMaxSeansPerGun} seans '
            'ekleyebilirsin.');
      case StudyPlanSaveResult.hata:
        _mesaj('Plan kaydedilemedi, tekrar dener misin?');
    }
  }

  Future<void> _seansSil(StudyPlanEntry entry) async {
    _tik();
    final servis = _servis(context);
    await servis.removeSession(entry.id);
    if (!mounted) return;
    await _bildirimleriYenile();
    if (!mounted) return;
    setState(() {});
    _mesaj('${StudyPlanService.gunAdi(entry.gun)} ${entry.araliqMetni} '
        'seansı silindi');
  }

  Future<void> _gunuSil(int gun) async {
    _tik();
    final servis = _servis(context);
    await servis.removeDay(gun);
    if (!mounted) return;
    await _bildirimleriYenile();
    if (!mounted) return;
    setState(() {});
    _mesaj('${StudyPlanService.gunAdi(gun)} plandan çıkarıldı');
  }

  Future<void> _seansAcKapa(StudyPlanEntry entry, bool aktif) async {
    _tik();
    final servis = _servis(context);
    await servis.toggleSession(entry.id, aktif);
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

  /// Ücretsiz kullanıcı GÜN limitini aştığında gösterilen bilgi kutusu.
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
          'Ücretsiz planda haftada ${StudyPlanService.kFreeMaxDays} GÜN '
          'planlayabilirsin — o güne istediğin kadar çalışma aralığı '
          'ekleyebilirsin. Premium ile haftanın 7 gününü ayrı ayrı planla, '
          'her seans için ayrı hatırlatma al.',
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
              _GunKarti(
                gun: gun,
                seanslar: plan.where((e) => e.gun == gun).toList(),
                onEkle: () => _seansEkle(gun),
                onGunuSil: () => _gunuSil(gun),
                onSeansDuzenle: _seansDuzenle,
                onSeansSil: _seansSil,
                onSeansAcKapa: _seansAcKapa,
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
            // Bildirim sağlığı: kurulu bildirim sayısı + anında test + tam
            // alarm izni durumu. "Bildirim gelmiyor" şikayetinde sorunun
            // KURULUMDA mı (sayı 0) yoksa TESLİMATTA mı (sayı >0 ama
            // gelmiyor → izin/pil optimizasyonu) olduğunu telefonda gösterir.
            const DsSectionHeader(title: 'Bildirim Durumu'),
            const SizedBox(height: 4),
            const _BildirimDurumKarti(),
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
    final plan = servis.getPlan();
    final planVar = plan.isNotEmpty;
    final gunSayisi = servis.planlananGunler.length;

    final baslik = sonraki != null
        ? servis.nextSessionLabel()
        : (planVar ? 'Tüm seansların kapalı' : 'Henüz planın yok');
    final altBaslik = sonraki != null
        ? '${servis.nextSessionCountdown()} • ${sonraki.entry.sureDakika} dakikalık seans'
        : (planVar
            ? 'Aşağıdan bir seansı tekrar açarsan hatırlatma gönderirim.'
            : 'Aşağıdan bir gün seç, çalışma saatini belirle. Aynı güne birden '
                'fazla aralık ekleyebilirsin.');

    return DsCard(
      accent: c.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900, color: c.text),
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
          if (planVar) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                DsChip(label: '$gunSayisi GÜN', color: c.violetL),
                DsChip(label: '${plan.length} SEANS', color: c.mint),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Haftanın tek bir günü: o güne ait TÜM seanslar alt alta listelenir; her
/// seans ayrı ayrı düzenlenebilir, açılıp kapatılabilir ve silinebilir.
class _GunKarti extends StatelessWidget {
  final int gun;
  final List<StudyPlanEntry> seanslar;
  final VoidCallback onEkle;
  final VoidCallback onGunuSil;
  final ValueChanged<StudyPlanEntry> onSeansDuzenle;
  final ValueChanged<StudyPlanEntry> onSeansSil;
  final void Function(StudyPlanEntry entry, bool aktif) onSeansAcKapa;

  const _GunKarti({
    required this.gun,
    required this.seanslar,
    required this.onEkle,
    required this.onGunuSil,
    required this.onSeansDuzenle,
    required this.onSeansSil,
    required this.onSeansAcKapa,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final planli = seanslar.isNotEmpty;
    final aktifVar = seanslar.any((e) => e.aktif);
    final bugunMu = DateTime.now().weekday == gun;
    final vurgu = planli ? (aktifVar ? c.violet : c.textFaint) : c.textFaint;

    return DsCard(
      accent: planli ? vurgu : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      // Gün boşken kartın herhangi bir yerine dokunmak seans eklemeye götürür.
      onTap: planli ? null : onEkle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: c.text),
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
                          ? '${seanslar.length} seans • '
                              '${seanslar.fold<int>(0, (t, e) => t + e.sureDakika)} dk'
                          : 'Saat aralığı eklemek için dokun',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.textFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Seans ekle',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.add_circle_outline, size: 22, color: c.violetL),
                onPressed: onEkle,
              ),
              if (planli)
                IconButton(
                  tooltip: 'Günü plandan çıkar',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline, size: 20, color: c.textFaint),
                  onPressed: onGunuSil,
                ),
            ],
          ),
          if (planli) ...[
            const SizedBox(height: 10),
            for (final e in seanslar) ...[
              _SeansSatiri(
                entry: e,
                onDuzenle: () => onSeansDuzenle(e),
                onSil: () => onSeansSil(e),
                onAcKapa: (v) => onSeansAcKapa(e, v),
              ),
              if (e != seanslar.last) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

/// Bir gün kartının içindeki tek çalışma aralığı satırı.
class _SeansSatiri extends StatelessWidget {
  final StudyPlanEntry entry;
  final VoidCallback onDuzenle;
  final VoidCallback onSil;
  final ValueChanged<bool> onAcKapa;

  const _SeansSatiri({
    required this.entry,
    required this.onDuzenle,
    required this.onSil,
    required this.onAcKapa,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final vurgu = entry.aktif ? c.violetL : c.textFaint;

    return InkWell(
      onTap: onDuzenle,
      borderRadius: BorderRadius.circular(kDsRadiusSm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: c.glass2,
          borderRadius: BorderRadius.circular(kDsRadiusSm),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 17, color: vurgu),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // 24 saat biçimi: "19:00–20:30"
                    entry.araliqMetni,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: entry.aktif ? c.text : c.textFaint),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.sureDakika} dk${entry.aktif ? '' : ' • kapalı'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.textFaint),
                  ),
                ],
              ),
            ),
            Switch(
              value: entry.aktif,
              onChanged: onAcKapa,
              activeThumbColor: c.violet,
            ),
            IconButton(
              tooltip: 'Seansı kaldır',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 19, color: c.textFaint),
              onPressed: onSil,
            ),
          ],
        ),
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
                      'Tek bir güne istediğin kadar çalışma aralığı ekleyebilirsin. '
                      'Premium ile haftanın 7 gününü ayrı ayrı planla, her seans '
                      'için hatırlatma al.',
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
              'Planladığın her seansın başlangıç saatinde telefonuna ayrı bir '
              'hatırlatma gönderilir; hatırlatmalar her hafta aynı saatte '
              'tekrarlanır. Saatler 24 saat biçiminde gösterilir. Bildirimleri '
              'Ayarlar\'dan tamamen kapatabilirsin.',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: colors.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bildirim sağlığı kartı: kurulu bildirim sayısı, anında test butonu ve
/// (Android'de) tam alarm izni durumu + ayara gitme kısayolu.
///
/// "Bildirim gelmiyor" şikayetini teşhis edilebilir yapar:
///  • Kurulu sayı 0        → planlama tarafında sorun var.
///  • Sayı > 0 ama gelmiyor → teslimat engelleniyor: tam alarm izni kapalı
///    (Android 14+ varsayılanı) ya da üretici pil optimizasyonu öldürüyor.
class _BildirimDurumKarti extends StatefulWidget {
  const _BildirimDurumKarti();

  @override
  State<_BildirimDurumKarti> createState() => _BildirimDurumKartiState();
}

class _BildirimDurumKartiState extends State<_BildirimDurumKarti> {
  int _kurulu = 0;
  bool _exactVar = true;
  bool _yuklendi = false;

  @override
  void initState() {
    super.initState();
    _tazele();
  }

  Future<void> _tazele() async {
    final servis = NotificationService.instance;
    final kurulu = await servis.pendingPlanCount();
    final exact = await servis.exactIzinVarMi();
    if (!mounted) return;
    setState(() {
      _kurulu = kurulu;
      _exactVar = exact;
      _yuklendi = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    if (!_yuklendi) return const SizedBox.shrink();

    return DsCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _kurulu > 0 ? Icons.notifications_active : Icons.notifications_off,
                size: 18,
                color: _kurulu > 0 ? c.success : c.warn,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _kurulu > 0
                      ? 'Kurulu hatırlatma: $_kurulu bildirim'
                      : 'Kurulu hatırlatma yok — plana seans ekleyince kurulur.',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text),
                ),
              ),
            ],
          ),
          if (!_exactVar) ...[
            const SizedBox(height: 10),
            Text(
              '⚠️ "Alarmlar ve hatırlatıcılar" izni kapalı. Bu izin kapalıyken '
              'Android bildirimleri geciktirebilir ya da hiç göstermeyebilir. '
              'Tam saatinde bildirim için izni aç:',
              style: TextStyle(fontSize: 12, height: 1.4, color: c.textDim),
            ),
            const SizedBox(height: 8),
            DsPillButton(
              label: 'Alarm İznini Aç',
              color: c.warn,
              leadingIcon: Icons.alarm_on,
              onPressed: () async {
                context.read<SoundService>().click();
                await NotificationService.instance.exactIzinAyariniAc();
                // Ayardan dönünce durumu tazele.
                await _tazele();
                // Yeni izinle bildirimleri yeniden kur.
                if (!mounted) return;
                final storage = context.read<StorageService>();
                await NotificationService.instance.schedulePlan(
                  StudyPlanService(storage).getActivePlan(),
                  storage: storage,
                );
                await _tazele();
              },
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DsPillButton(
                  label: 'Test Bildirimi Gönder',
                  color: c.violetL,
                  filled: false,
                  leadingIcon: Icons.notifications,
                  onPressed: () async {
                    context.read<SoundService>().click();
                    final storage = context.read<StorageService>();
                    await NotificationService.instance
                        .showTestNotification(storage: storage);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Durumu yenile',
                icon: Icon(Icons.refresh, size: 20, color: c.textFaint),
                onPressed: () {
                  context.read<SoundService>().click();
                  _tazele();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Test bildirimi anında gelmelidir. Test geliyor ama planlı '
            'hatırlatma gelmiyorsa: telefonun Ayarlar > Pil bölümünden bu '
            'uygulama için pil optimizasyonunu "kısıtlamasız" yap (Xiaomi/'
            'Samsung gibi cihazlar planlı bildirimleri arka planda '
            'öldürebiliyor).',
            style: TextStyle(fontSize: 11, height: 1.4, color: c.textFaint),
          ),
        ],
      ),
    );
  }
}
