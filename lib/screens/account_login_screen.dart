import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/invite_service.dart';
import '../services/presence_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import '../utils/ust_bildirim.dart';

/// Hesap giriş ekranı — YALNIZCA Google ve Apple ile giriş.
///
/// E-POSTA/ŞİFRE/KULLANICI ADI KAYIT VE GİRİŞİ KALDIRILDI (kullanıcı kararı):
/// şifre unutma, yarım kayıt, silinen hesapla giriş denemesi gibi bir dizi
/// destek yükü tek hamlede ortadan kalktı. Firebase Auth'ta e-posta sağlayıcısı
/// açık kalsa da uygulama içinden erişilen tek yol Google/Apple.
///
/// Apple ile giriş SADECE iOS'ta gösterilir (App Store kuralı gereği üçüncü
/// taraf girişi olan iOS uygulamasında Apple zorunlu; Android'de gereksiz).
class AccountLoginScreen extends StatefulWidget {
  const AccountLoginScreen({super.key});

  @override
  State<AccountLoginScreen> createState() => _AccountLoginScreenState();
}

class _AccountLoginScreenState extends State<AccountLoginScreen> {
  bool _busy = false;

  Future<void> _signIn(Future<AuthResult> Function() method) async {
    context.read<SoundService>().click();
    setState(() => _busy = true);
    final result = await method();
    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.success) {
      ustBildirim(result.errorMessage ?? 'Giriş başarısız oldu.', tur: UstBildirimTuru.hata);
      return;
    }

    final storage = context.read<StorageService>();

    // 1) HESABA BAĞLI PROFİL: her hesabın KENDİ yerel verisi var. Girişte o
    //    hesabın profiline geçilir — başka hesabın istatistiği/premium'u
    //    asla görünmez, hesap değişiminde veri karışmaz (kök sorun buydu).
    final uid = result.user?.uid;
    if (uid != null) {
      await storage.hesapProfilineGec(uid);
    }

    // 2) İSİM ÖN DOLGUSU: bu hesabın profili BOŞSA hesap adıyla (Google adı ya
    //    da e-posta öneki) doldurulur — birazdan açılacak isim penceresine
    //    hazır metin olsun diye. Kullanıcı Profil'den kendi ismini yazdıysa o
    //    isim KALICIDIR, ezilmez.
    if (storage.getUserName().isEmpty) {
      final displayName = result.user?.displayName?.trim();
      if (displayName != null && displayName.isNotEmpty) {
        await storage.setUserName(displayName);
      } else {
        final epostaOnEki = result.user?.email?.split('@').first.trim();
        if (epostaOnEki != null && epostaOnEki.isNotEmpty) {
          await storage.setUserName(epostaOnEki);
        }
      }
    }

    // Bulut yedeklemeyi giriş başarılı olur olmaz aç (syncUp bu ayara bakar).
    await storage.setCloudBackupEnabled(true);

    final cloud = CloudSyncService();

    // 3) Önce buluttaki ilerlemeyi indir (isim + isim-onayı da geri gelir; böylece
    //    cihaz değiştiren dönüş kullanıcısına isim TEKRAR sorulmaz). Zaman aşımı +
    //    try/catch: ağ/bozuk veri GİRİŞİ ASLA çökertmesin.
    try {
      await cloud
          .syncDown(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (e) {
      debugPrint('Giriş sonrası syncDown hatası (giriş yine de başarılı): $e');
    }

    // YENİ HESAP MI? syncDown sonrası isim ONAYLI ise bu hesap DAHA ÖNCE
    // kullanılmış demektir (dönüş kullanıcısı); onaylı değilse yeni hesap.
    // Davet ödülü yalnızca YENİ hesaplara verilir (kullanıcı isteği).
    final yeniHesap = !storage.getNameConfirmed();

    // 4) İSMİ SOR: bu hesap ismini daha önce onaylamadıysa bir kez sor. Aktif
    //    profil ARTIK bu hesabın profili olduğu için (adım 1) isim doğru yere
    //    yazılır — hesaplar arası karışma olmaz. Onaylanınca bir daha sorulmaz.
    if (mounted && !storage.getNameConfirmed()) {
      final girilen = await _isimSor(storage.getUserName());
      if (!mounted) return;
      if (girilen != null && girilen.trim().isNotEmpty) {
        await storage.setUserName(girilen);
      }
      await storage.setNameConfirmed(true);
    }

    // 5) Onaylanan ismi + ilerlemeyi buluta yükle.
    try {
      await cloud
          .syncUp(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (e) {
      debugPrint('Giriş sonrası syncUp hatası (giriş yine de başarılı): $e');
    }

    // Yönetici panelden bu hesaba premium verdiyse hemen uygula + canlılık
    // kaydını düş (bkz. PresenceService).
    await PresenceService.instance.premiumKontrol(storage);
    // ignore: unawaited_futures
    PresenceService.instance.bildir(storage);

    // 6) DAVET KODU: kullanıcı giriş öncesinde bir davet kodu girdiyse ŞİMDİ
    //    (giriş doğrulandıktan sonra) uygula. Cihaz/hesap tekilliği burada
    //    kontrol edilir; sonuç kullanıcıya bildirilir.
    final davetSonuc =
        await InviteService().bekleyenDavetiUygula(storage, yeniHesap: yeniHesap);
    if (!mounted) return;
    _davetSonucBildir(davetSonuc);

    if (!mounted) return;
    ustBildirim('Giriş başarılı! 🎉', tur: UstBildirimTuru.basari);
    Navigator.of(context).pop();
  }

  /// Davet uygulama sonucunu kullanıcıya bildirir (uygulama içi uyarı).
  void _davetSonucBildir(DavetSonuc s) {
    switch (s) {
      case DavetSonuc.basari:
        ustBildirim(
            '🎉 Davet onaylandı! Sana 1 gün premium tanımlandı; seni davet eden '
            'kişiye de 1 gün premium eklendi.',
            tur: UstBildirimTuru.basari);
      case DavetSonuc.cihazKullanildi:
        ustBildirim(
            '⚠️ Bu cihazda daha önce bir davet kodu kullanılmış. '
            'Her cihaz davet kodunu yalnızca bir kez kullanabilir.',
            tur: UstBildirimTuru.hata);
      case DavetSonuc.hesapKullanildi:
        ustBildirim('⚠️ Bu hesap zaten bir davet kodu kullanmış.',
            tur: UstBildirimTuru.hata);
      case DavetSonuc.hesapEski:
        ustBildirim(
            '⚠️ Davet ödülü yalnızca YENİ hesaplara verilir. Bu hesap daha önce '
            'oluşturulduğu için davet kodu geçerli değil.',
            tur: UstBildirimTuru.hata);
      case DavetSonuc.kendiKodun:
        ustBildirim('⚠️ Kendi davet kodunu kullanamazsın.',
            tur: UstBildirimTuru.hata);
      case DavetSonuc.gecersizKod:
        ustBildirim('⚠️ Girdiğin davet kodu geçersiz.', tur: UstBildirimTuru.hata);
      case DavetSonuc.koddYok:
        break; // sessiz
      case DavetSonuc.hata:
        ustBildirim('Davet kodu şu an işlenemedi, internetini kontrol et.',
            tur: UstBildirimTuru.hata);
    }
  }

  /// Giriş sonrası bir kez gösterilen isim penceresi. [onDolgu] ön-dolgu metni
  /// (Google adı / e-posta öneki / buluttaki isim). Kullanıcının onayladığı adı
  /// döner; boş bırakılamaz (Kaydet yalnızca dolu metinde aktif). Pencere
  /// kapatılamaz (barrierDismissible: false) — isim uygulamada her yerde
  /// göründüğü için mutlaka bir değer alınır.
  Future<String?> _isimSor(String onDolgu) async {
    final ctrl = TextEditingController(text: onDolgu);
    final sonuc = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final c = context.read<ThemeProvider>().colors;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Adın ne olsun?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uygulamada (ana sayfa, sohbet, düello, lig) bu isim görünecek. '
                  'İstediğin zaman Profil’den değiştirebilirsin.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textFaint),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'İsim',
                    hintText: 'Örn. Ahmet',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.of(dialogCtx).pop(v.trim());
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
                child: const Text('Kaydet'),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    return sonuc;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Hesap')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Temaya uygun gradyanlı hero ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        c.violet.withValues(alpha: 0.28),
                        c.violetL.withValues(alpha: 0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: c.violetL.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: [
                      DsIllustration(emoji: '🔐', glowColor: c.violetL),
                      const SizedBox(height: 14),
                      Text('Hesabınla devam et',
                          style: TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w900, color: c.text)),
                      const SizedBox(height: 8),
                      Text(
                        'Giriş yap; ilerlemen buluta yedeklensin, cihaz değiştirsen '
                        'de kaldığın yerden devam et.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, height: 1.5, color: c.textDim),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _AvantajCipi(c: c, emoji: '☁️', metin: 'Bulut yedek'),
                          _AvantajCipi(c: c, emoji: '💬', metin: 'Sohbet'),
                          _AvantajCipi(c: c, emoji: '⚔️', metin: 'Düello'),
                          _AvantajCipi(c: c, emoji: '🎁', metin: 'Davet ödülü'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  )
                else ...[
                  SizedBox(
                    width: 300,
                    child: DsPillButton(
                      label: 'Google ile Giriş Yap',
                      color: c.violet,
                      leadingIcon: Icons.g_mobiledata_rounded,
                      onPressed: () => _signIn(auth.signInWithGoogle),
                    ),
                  ),
                  if (auth.isAppleSignInAvailable) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 300,
                      // DÜZELTİLDİ: dolu (filled) buton koyu temada c.text
                      // beyaza yakın olduğu için beyaz yazıyla birleşip
                      // okunmuyordu. Dış çizgili stilde yazı/simge vurgu
                      // renginin kendisi olur — her temada zeminle kontrastlı.
                      child: DsPillButton(
                        label: 'Apple ile Giriş Yap',
                        color: c.text,
                        filled: false,
                        leadingIcon: Icons.apple,
                        onPressed: () => _signIn(auth.signInWithApple),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                Text(
                  'Hesabın yoksa endişelenme — ilk girişte otomatik oluşturulur.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: c.textFaint),
                ),
                const SizedBox(height: 22),
                // ── Davet kodum var (kullanıcı isteği) ──
                SizedBox(width: 320, child: _DavetKoduBolumu()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Giriş ekranındaki "Davet kodum var" bölümü: kullanıcı önce kodu girer,
/// "Kontrol Et" ile geçerliliği doğrulanır; geçerliyse kod BEKLEMEYE alınır ve
/// GİRİŞ YAPTIKTAN SONRA otomatik onaylanacağı uzun bir açıklamayla bildirilir.
class _DavetKoduBolumu extends StatefulWidget {
  @override
  State<_DavetKoduBolumu> createState() => _DavetKoduBolumuState();
}

class _DavetKoduBolumuState extends State<_DavetKoduBolumu> {
  final _ctrl = TextEditingController();
  final _invite = InviteService();
  bool _acik = false;
  bool _kontrol = false;
  String? _gecerliAd; // kod geçerliyse davet edenin adı
  String? _hata;

  @override
  void initState() {
    super.initState();
    // Daha önce girilip beklemede kalan kod varsa alanı ön-doldur.
    final bekleyen = context.read<StorageService>().getPendingInviteCode();
    if (bekleyen.isNotEmpty) {
      _ctrl.text = bekleyen;
      _acik = true;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _kontrolEt() async {
    final kod = _ctrl.text.trim();
    if (kod.length != 6) {
      setState(() {
        _hata = 'Davet kodu 6 haneli olmalı.';
        _gecerliAd = null;
      });
      return;
    }
    context.read<SoundService>().click();
    setState(() {
      _kontrol = true;
      _hata = null;
      _gecerliAd = null;
    });
    final sonuc = await _invite.koduDogrula(kod);
    if (!mounted) return;
    setState(() => _kontrol = false);
    if (sonuc == null) {
      setState(() => _hata = 'Bu kod geçerli değil. Doğru yazdığından emin ol.');
      return;
    }
    // Geçerli: kodu beklemeye al.
    await context.read<StorageService>().setPendingInviteCode(kod);
    if (!mounted) return;
    setState(() => _gecerliAd = sonuc.name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Aç/kapa başlığı
        InkWell(
          onTap: () => setState(() => _acik = !_acik),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.card_giftcard_rounded, size: 18, color: c.violetL),
                const SizedBox(width: 6),
                Text('Davet kodum var',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: c.violetL)),
                Icon(_acik ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: c.violetL),
              ],
            ),
          ),
        ),
        if (_acik) ...[
          const SizedBox(height: 6),
          TextField(
            controller: _ctrl,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 6, color: c.text),
            decoration: InputDecoration(
              counterText: '',
              hintText: '6 haneli kod',
              filled: true,
              fillColor: c.glass2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
            ),
            onChanged: (_) => setState(() {
              _gecerliAd = null;
              _hata = null;
            }),
          ),
          const SizedBox(height: 8),
          DsPillButton(
            label: _kontrol ? 'Kontrol ediliyor…' : 'Kontrol Et',
            color: c.violetL,
            onPressed: _kontrol ? null : _kontrolEt,
          ),
          if (_hata != null) ...[
            const SizedBox(height: 8),
            Text(_hata!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.danger, fontWeight: FontWeight.w700)),
          ],
          if (_gecerliAd != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.success.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Text('✅ Kod geçerli — $_gecerliAd seni davet ediyor',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800, color: c.text)),
                  const SizedBox(height: 8),
                  Text(
                    'Bu davet kodu KAYDEDİLDİ. Şimdi yukarıdan Google ya da Apple ile '
                    'giriş yaptığında davet otomatik olarak ONAYLANACAK: HEM SANA hem de '
                    'seni davet eden kişiye 1’er gün premium hediye edilecek.\n\n'
                    'Güvenlik: Ödül yalnızca YENİ hesaplara verilir (daha önce hesabın '
                    'varsa geçerli olmaz). Her cihaz davet kodunu yalnızca BİR KEZ '
                    'kullanabilir; aynı cihazda farklı hesaplarla tekrar tekrar davet '
                    'kullanılamaz ve kendi kodunu kullanamazsın. Bu yüzden giriş yapmadan '
                    'ödül tanımlanmaz — önce giriş yapman gerekir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, height: 1.45, color: c.textDim),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Giriş hero'sundaki küçük avantaj çipi (emoji + kısa metin).
class _AvantajCipi extends StatelessWidget {
  final dynamic c;
  final String emoji;
  final String metin;
  const _AvantajCipi({required this.c, required this.emoji, required this.metin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.glass2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Text('$emoji $metin',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.text)),
    );
  }
}
