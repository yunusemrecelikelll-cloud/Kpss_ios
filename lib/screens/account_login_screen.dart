import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';

/// Anasayfa'daki "Giriş yap" banner'ından açılan, isteğe bağlı hesap girişi
/// ekranı. Uygulama girişsiz de tam çalıştığı için bu ekran zorunlu bir adım
/// değil — sadece hesabın getirdiği ekstraları (sohbet kimliği, bulut
/// yedekleme, satın alma eşleşmesi) anlatır.
///
/// Giriş yolları: e-posta VEYA kullanıcı adı + şifre (kayıt/giriş), Google
/// (her platform) ve Apple (sadece iOS).
///
/// KULLANICI ADI: Kayıtta hem e-posta hem kullanıcı adı istenir. E-posta
/// ZORUNLUDUR — "şifremi unuttum" akışı Firebase Auth'un e-posta sıfırlama
/// mekanizmasına dayanır ve kullanıcı adıyla çalışmaz. Girişte ise kullanıcı
/// ikisinden birini yazabilir; '@' içeriyorsa e-posta, içermiyorsa kullanıcı
/// adı kabul edilir.
class AccountLoginScreen extends StatefulWidget {
  const AccountLoginScreen({super.key});

  @override
  State<AccountLoginScreen> createState() => _AccountLoginScreenState();
}

class _AccountLoginScreenState extends State<AccountLoginScreen> {
  bool _busy = false;

  /// false → "Giriş Yap" sekmesi, true → "Kayıt Ol" sekmesi.
  bool _kayitModu = false;
  bool _sifreGizli = true;

  // KARAR: Eski "Ad" alanı kaldırılmadı, KULLANICI ADINA DÖNÜŞTÜRÜLDÜ. İki ayrı
  // alan (ad + kullanıcı adı) tutmak kullanıcıya iki kimlik sorup ikisini de
  // aynı yere (displayName) yazmak anlamına gelirdi. Uygulama zaten her yerde
  // `displayName`'i gösteriyor (sohbet, lig, anasayfa), bu yüzden tek bir
  // kullanıcı adı hem daha temiz hem de sohbetteki kimlikle tutarlı.
  final _kullaniciAdiCtrl = TextEditingController();
  final _epostaCtrl = TextEditingController();
  final _sifreCtrl = TextEditingController();

  // Alan altında gösterilen istemci tarafı doğrulama hataları.
  String? _kullaniciAdiHata;
  String? _epostaHata;
  String? _sifreHata;

  // Kullanıcı adı canlı müsaitlik kontrolü (yazma durduktan ~600ms sonra).
  Timer? _usernameDebounce;
  bool _usernameKontrolEdiliyor = false;
  UsernameDurumu? _usernameDurumu;
  // Sonucun HANGİ metne ait olduğunu tutar: kullanıcı yazmaya devam ederse
  // eski sonucu göstermeyelim.
  String _usernameKontrolEdilenMetin = '';

  @override
  void initState() {
    super.initState();
    _kullaniciAdiCtrl.addListener(_kullaniciAdiDegisti);
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _kullaniciAdiCtrl.removeListener(_kullaniciAdiDegisti);
    _kullaniciAdiCtrl.dispose();
    _epostaCtrl.dispose();
    _sifreCtrl.dispose();
    super.dispose();
  }

  static final RegExp _epostaDeseni = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _epostaGecerli => _epostaDeseni.hasMatch(_epostaCtrl.text.trim());

  /// Kullanıcı yazdıkça çalışır: 600ms sessizlik sonrası müsaitliği sorar.
  void _kullaniciAdiDegisti() {
    _usernameDebounce?.cancel();
    final metin = _kullaniciAdiCtrl.text.trim();

    // Yazmaya başlar başlamaz eski sonucu temizle — yanlış bir "✓ Kullanılabilir"
    // ekranda asılı kalmasın.
    if (_usernameDurumu != null || _usernameKontrolEdiliyor) {
      setState(() {
        _usernameDurumu = null;
        _usernameKontrolEdiliyor = false;
      });
    }
    if (metin.isEmpty) return;

    // Biçim hatalıysa sunucuya hiç gitme, anında yerel hatayı göster.
    if (AuthService.usernameHatasi(metin) != null) return;

    setState(() => _usernameKontrolEdiliyor = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () async {
      final auth = context.read<AuthService>();
      final durum = await auth.usernameDurumu(metin);
      if (!mounted) return;
      // Kullanıcı bu arada metni değiştirdiyse sonucu at.
      if (_kullaniciAdiCtrl.text.trim() != metin) return;
      setState(() {
        _usernameKontrolEdiliyor = false;
        _usernameDurumu = durum;
        _usernameKontrolEdilenMetin = metin;
      });
    });
  }

  /// Formu doğrular; hatalıysa alan altı mesajları yazıp false döner.
  bool _formGecerliMi() {
    final kullaniciAdi = _kullaniciAdiCtrl.text.trim();
    final kimlik = _epostaCtrl.text.trim();
    final sifre = _sifreCtrl.text;

    String? kullaniciAdiHata;
    String? epostaHata;
    String? sifreHata;

    if (_kayitModu) {
      // Kayıtta kullanıcı adı ZORUNLU ve biçim kuralları AuthService'ten gelir
      // (tek kaynak — ekran ile servis kuralları ayrışmasın).
      kullaniciAdiHata = kullaniciAdi.isEmpty
          ? 'Kullanıcı adı boş bırakılamaz.'
          : AuthService.usernameHatasi(kullaniciAdi);
      // Canlı kontrol "alınmış" dediyse gönderime hiç izin verme.
      if (kullaniciAdiHata == null &&
          _usernameDurumu == UsernameDurumu.alinmis &&
          _usernameKontrolEdilenMetin == kullaniciAdi) {
        kullaniciAdiHata = 'Bu kullanıcı adı alınmış. Başka bir tane dene.';
      }
    }

    if (kimlik.isEmpty) {
      // Etiket moda göre değiştiği için hata mesajı da değişiyor.
      epostaHata = _kayitModu
          ? 'E-posta boş bırakılamaz.'
          : 'E-posta veya kullanıcı adı boş bırakılamaz.';
    } else if (_kayitModu) {
      // KAYIT: e-posta ZORUNLU ve gerçekten e-posta olmalı (şifre sıfırlama
      // akışının çalışabilmesi için şart).
      if (!_epostaDeseni.hasMatch(kimlik)) {
        epostaHata = 'Geçersiz e-posta adresi.';
      }
    } else {
      // GİRİŞ: '@' varsa e-posta kabul edip biçimini doğrula; yoksa kullanıcı
      // adıdır — e-posta biçim doğrulaması YAPMA.
      if (kimlik.contains('@') && !_epostaDeseni.hasMatch(kimlik)) {
        epostaHata = 'Geçersiz e-posta adresi.';
      }
    }

    if (sifre.isEmpty) {
      sifreHata = 'Şifre boş bırakılamaz.';
    } else if (sifre.length < 6) {
      sifreHata = 'Şifre en az 6 karakter olmalı.';
    }

    setState(() {
      _kullaniciAdiHata = kullaniciAdiHata;
      _epostaHata = epostaHata;
      _sifreHata = sifreHata;
    });
    return kullaniciAdiHata == null && epostaHata == null && sifreHata == null;
  }

  Future<void> _signIn(Future<AuthResult> Function() method) async {
    context.read<SoundService>().click();
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final result = await method();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.success) {
      // ÖNEMLİ: Firebase Auth'ta oturum açmak yerel StorageService'teki
      // isim/aktif kullanıcı alanlarını KENDİLİĞİNDEN güncellemez — bu yüzden
      // giriş sonrası anasayfa "Misafir" gösteriyordu. Gerçek hesap adını
      // burada senkronize ediyoruz.
      final displayName = result.user?.displayName?.trim();
      final storage = context.read<StorageService>();
      if (displayName != null && displayName.isNotEmpty) {
        await storage.setUserName(displayName);
      }
      // ÖNEMLİ: Bulut yedeklemeyi giriş BAŞARILI olur olmaz aç. Bu satır
      // syncDown/syncUp'tan ÖNCE olmalı: CloudSyncService.syncUp bu ayarı
      // kontrol ediyor, kapalıyken hiçbir şey yüklemiyor — yani ilk senkron
      // sessizce boşa giderdi. Kullanıcı istemezse Ayarlar > Hesap
      // bölümünden istediği zaman kapatabilir.
      await storage.setCloudBackupEnabled(true);
      // ÖNEMLİ: Bu hesapla daha önce başka bir cihazda/kurulumda ilerleme
      // kaydedilmişse önce onu indir (syncDown — yerelde eksik olanı tamamlar,
      // var olanı ÇİFTLEMEZ), sonra güncel yerel durumu buluta yaz (syncUp) —
      // böylece "giriş yap, ilerlemen/satın alman geri gelsin" gerçekten çalışır.
      // Zaman aşımı: ağ kötüyse giriş akışı burada asılı kalmasın —
      // senkronizasyon başarısız olsa bile giriş BAŞARILIDIR, veri bir
      // sonraki açılışta/test bitiminde tekrar denenir.
      final cloud = CloudSyncService();
      await cloud
          .syncDown(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      await cloud
          .syncUp(storage)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giriş başarılı! 🎉')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Giriş başarısız oldu.')),
      );
    }
  }

  /// Ana butonun işi: moda göre kayıt ya da giriş.
  Future<void> _epostaIleDevam(AuthService auth) async {
    if (!_formGecerliMi()) return;
    final kimlik = _epostaCtrl.text.trim();
    final sifre = _sifreCtrl.text;
    final kullaniciAdi = _kullaniciAdiCtrl.text.trim();
    if (_kayitModu) {
      await _signIn(() => auth.registerWithEmail(
            email: kimlik,
            password: sifre,
            username: kullaniciAdi.isEmpty ? null : kullaniciAdi,
          ));
    } else {
      // Giriş alanı e-posta da olabilir kullanıcı adı da — ayrımı servis yapar.
      await _signIn(() =>
          auth.signInWithEmailOrUsername(kimlik: kimlik, password: sifre));
    }
  }

  /// "Şifremi unuttum": Firebase sıfırlama bağlantısı yalnızca E-POSTA ile
  /// çalışır. Alanda kullanıcı adı yazılıysa önce e-postaya çeviririz;
  /// çözülemezse kullanıcıdan doğrudan e-posta isteriz.
  Future<void> _sifremiUnuttum(AuthService auth) async {
    context.read<SoundService>().click();
    String hedef = _epostaCtrl.text.trim();

    // Alanda '@' yoksa kullanıcı adı yazılmış demektir → e-postaya çevir.
    if (hedef.isNotEmpty && !hedef.contains('@')) {
      setState(() => _busy = true);
      final cozulen = await auth.emailForUsername(hedef);
      if (!mounted) return;
      setState(() => _busy = false);
      if (cozulen == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Bu kullanıcı adına ait hesap bulunamadı, e-posta adresini yaz.'),
          ),
        );
        final girilen = await _epostaSorDialog('');
        if (girilen == null) return;
        hedef = girilen;
      } else {
        hedef = cozulen;
      }
    }

    if (hedef.isEmpty || !_epostaDeseni.hasMatch(hedef)) {
      final girilen = await _epostaSorDialog(_epostaGecerli ? hedef : '');
      if (girilen == null) return;
      hedef = girilen;
    }

    if (!mounted) return;
    setState(() => _busy = true);
    final sonuc = await auth.sendPasswordResetEmail(hedef);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sonuc.success
            ? 'Şifre sıfırlama bağlantısı $hedef adresine gönderildi.'
            : (sonuc.errorMessage ?? 'Sıfırlama e-postası gönderilemedi.')),
      ),
    );
  }

  Future<String?> _epostaSorDialog(String baslangic) async {
    final ctrl = TextEditingController(text: baslangic);
    final c = context.read<ThemeProvider>().colors;
    final sonuc = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? hata;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: c.bg2,
            title: Text('Şifremi unuttum',
                style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hesabının e-posta adresini yaz, sıfırlama bağlantısı gönderelim.',
                  style: TextStyle(fontSize: 13, color: c.textDim),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: c.text),
                  decoration: InputDecoration(
                    hintText: 'ornek@eposta.com',
                    hintStyle: TextStyle(color: c.textFaint),
                    errorText: hata,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: c.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: c.violetL),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Vazgeç', style: TextStyle(color: c.textDim)),
              ),
              TextButton(
                onPressed: () {
                  final deger = ctrl.text.trim();
                  if (!_epostaDeseni.hasMatch(deger)) {
                    setLocal(() => hata = 'Geçersiz e-posta adresi.');
                    return;
                  }
                  Navigator.of(ctx).pop(deger);
                },
                child: Text('Gönder',
                    style: TextStyle(
                        color: c.violetL, fontWeight: FontWeight.w800)),
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
    final auth = context.watch<AuthService>();
    final c = context.watch<ThemeProvider>().colors;

    return Scaffold(
      // Klavye açıkken taşma olmasın diye içerik kaydırılabilir kalsın.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Hesap')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: DsIconBadge(emoji: '🔐', color: c.violetL, size: 62),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'Hesabına Bağlan',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: c.text),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'İlerlemen bulutta güvende kalsın',
                  style: TextStyle(fontSize: 13, color: c.textDim),
                ),
              ),
              const SizedBox(height: 18),

              // Firebase yapılandırılmamışsa (web vb.) ekran çökmesin —
              // açıklayıcı bir kart göster, giriş alanlarını hiç çizme.
              if (!auth.isConfigured) ...[
                DsCard(
                  accent: c.warn,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DsIconBadge(
                          icon: Icons.info_outline, color: c.warn, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          kFirebaseNotConfiguredMessage,
                          style: TextStyle(fontSize: 13, color: c.textDim),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ] else ...[
                _SekmeSecici(
                  kayitModu: _kayitModu,
                  onChanged: _busy
                      ? null
                      : (deger) {
                          context.read<SoundService>().click();
                          setState(() {
                            _kayitModu = deger;
                            _kullaniciAdiHata = null;
                            _epostaHata = null;
                            _sifreHata = null;
                          });
                        },
                ),
                const SizedBox(height: 16),
                DsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_kayitModu) ...[
                        _Alan(
                          controller: _kullaniciAdiCtrl,
                          label: 'Kullanıcı adı',
                          hint: 'kullanici_adi',
                          icon: Icons.person_outline,
                          hata: _kullaniciAdiHata,
                          enabled: !_busy,
                          textInputAction: TextInputAction.next,
                          // Kullanıcı adı büyük/küçük harf duyarsız eşlenir ama
                          // otomatik büyütme kafa karıştırır — kapalı.
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                        ),
                        _KullaniciAdiDurumu(
                          metin: _kullaniciAdiCtrl.text.trim(),
                          kontrolEdiliyor: _usernameKontrolEdiliyor,
                          durum: _usernameDurumu,
                          // Alan altı hata zaten gösteriliyorsa iki mesaj
                          // üst üste binmesin.
                          gizle: _kullaniciAdiHata != null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _Alan(
                        controller: _epostaCtrl,
                        label: _kayitModu
                            ? 'E-posta'
                            : 'E-posta veya kullanıcı adı',
                        hint: _kayitModu
                            ? 'ornek@eposta.com'
                            : 'ornek@eposta.com veya kullanici_adi',
                        icon: Icons.alternate_email,
                        hata: _epostaHata,
                        enabled: !_busy,
                        // Girişte kullanıcı adı da yazılabildiği için e-posta
                        // klavyesini yalnızca kayıt modunda zorluyoruz.
                        keyboardType: _kayitModu
                            ? TextInputType.emailAddress
                            : TextInputType.text,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                      ),
                      const SizedBox(height: 12),
                      _Alan(
                        controller: _sifreCtrl,
                        label: 'Şifre',
                        hint: 'En az 6 karakter',
                        icon: Icons.lock_outline,
                        hata: _sifreHata,
                        enabled: !_busy,
                        obscure: _sifreGizli,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) =>
                            _busy ? null : _epostaIleDevam(auth),
                        suffix: IconButton(
                          onPressed: () =>
                              setState(() => _sifreGizli = !_sifreGizli),
                          icon: Icon(
                            _sifreGizli
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 19,
                            color: c.textFaint,
                          ),
                          tooltip: _sifreGizli ? 'Şifreyi göster' : 'Şifreyi gizle',
                        ),
                      ),
                      if (!_kayitModu) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy ? null : () => _sifremiUnuttum(auth),
                            child: Text(
                              'Şifremi unuttum',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.violetL),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Center(
                        child: _busy
                            ? SizedBox(
                                height: 42,
                                child: Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.4, color: c.violetL),
                                  ),
                                ),
                              )
                            : DsPillButton(
                                label: _kayitModu ? 'Kayıt Ol' : 'Giriş Yap',
                                color: c.violetL,
                                leadingIcon: _kayitModu
                                    ? Icons.person_add_alt_1
                                    : Icons.login,
                                onPressed: () => _epostaIleDevam(auth),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _Ayirac(label: 'veya'),
                const SizedBox(height: 16),
                Center(
                  child: DsPillButton(
                    label: 'Google ile devam et',
                    color: c.roseL,
                    filled: false,
                    leadingIcon: Icons.g_mobiledata,
                    onPressed: _busy ? null : () => _signIn(auth.signInWithGoogle),
                  ),
                ),
                if (auth.isAppleSignInAvailable) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: DsPillButton(
                      label: 'Apple ile devam et',
                      color: c.text,
                      filled: false,
                      leadingIcon: Icons.apple,
                      onPressed:
                          _busy ? null : () => _signIn(auth.signInWithApple),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
              ],

              const DsSectionHeader(title: 'Hesabın ne kazandırır?'),
              const SizedBox(height: 6),
              const _Perk(
                  icon: '💬', text: 'Sohbette gerçek adınla mesajlaşabilirsin'),
              const _Perk(
                  icon: '☁️',
                  text:
                      'İlerlemen hesabına bağlanır, telefon değiştirsen de kaybolmaz'),
              const _Perk(
                  icon: '🔒',
                  text: 'Satın alımların hesabınla eşleşir, güvenle geri yüklenir'),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          context.read<SoundService>().click();
                          Navigator.of(context).pop();
                        },
                  child: Text('Şimdi değil',
                      style: TextStyle(color: c.textDim, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Giriş Yap" / "Kayıt Ol" segment seçici.
class _SekmeSecici extends StatelessWidget {
  final bool kayitModu;
  final ValueChanged<bool>? onChanged;

  const _SekmeSecici({required this.kayitModu, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.glass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          _sekme(context, c, 'Giriş Yap', !kayitModu, () => onChanged?.call(false)),
          _sekme(context, c, 'Kayıt Ol', kayitModu, () => onChanged?.call(true)),
        ],
      ),
    );
  }

  Widget _sekme(BuildContext context, KpssColors c, String etiket, bool aktif,
      VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onChanged == null ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: aktif ? c.violetL : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            etiket,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: aktif ? Colors.white : c.textDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiketli, hata mesajı gösterebilen tek satırlık form alanı.
class _Alan extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? hata;
  final bool enabled;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autocorrect;
  final TextCapitalization textCapitalization;

  const _Alan({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.hata,
    this.enabled = true,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autocorrect = true,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final hatali = hata != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: c.textDim),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          autocorrect: autocorrect,
          textCapitalization: textCapitalization,
          style: TextStyle(fontSize: 14.5, color: c.text),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: c.glass2,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 13.5, color: c.textFaint),
            prefixIcon: Icon(icon, size: 19, color: c.textFaint),
            suffixIcon: suffix,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  BorderSide(color: hatali ? c.danger : c.border, width: 1.2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                  color: hatali ? c.danger : c.violetL, width: 1.6),
            ),
          ),
        ),
        if (hatali) ...[
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 14, color: c.danger),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  hata!,
                  style: TextStyle(
                      fontSize: 12, color: c.danger, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Kullanıcı adı alanının HEMEN ALTINDA görünen canlı müsaitlik göstergesi.
///
/// Dört hâli var: kontrol ediliyor (küçük spinner), kullanılabilir, alınmış ve
/// kontrol edilemedi (ağ/izin sorunu). Boş ya da biçimi geçersiz bir metinde
/// hiçbir şey göstermez — o durumda zaten alan altı hata mesajı çıkar.
class _KullaniciAdiDurumu extends StatelessWidget {
  final String metin;
  final bool kontrolEdiliyor;
  final UsernameDurumu? durum;
  final bool gizle;

  const _KullaniciAdiDurumu({
    required this.metin,
    required this.kontrolEdiliyor,
    required this.durum,
    this.gizle = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    if (gizle || metin.isEmpty) return const SizedBox.shrink();

    if (kontrolEdiliyor) {
      return _satir(
        c.textFaint,
        'Kontrol ediliyor…',
        gosterge: SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(strokeWidth: 1.8, color: c.textFaint),
        ),
      );
    }

    switch (durum) {
      case UsernameDurumu.musait:
        return _satir(c.success, '✓ Kullanılabilir');
      case UsernameDurumu.alinmis:
        return _satir(c.danger, '✗ Bu kullanıcı adı alınmış');
      case UsernameDurumu.kontrolEdilemedi:
        return _satir(c.warn, 'Kontrol edilemedi, bağlantını kontrol et');
      case UsernameDurumu.gecersiz:
      case null:
        return const SizedBox.shrink();
    }
  }

  Widget _satir(Color renk, String yazi, {Widget? gosterge}) {
    return Padding(
      padding: const EdgeInsets.only(top: 5, left: 2),
      child: Row(
        children: [
          if (gosterge != null) ...[gosterge, const SizedBox(width: 6)],
          Expanded(
            child: Text(
              yazi,
              style: TextStyle(
                  fontSize: 12, color: renk, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ortasında yazı olan yatay ayırıcı ("── veya ──").
class _Ayirac extends StatelessWidget {
  final String label;
  const _Ayirac({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Row(
      children: [
        Expanded(child: Divider(color: c.border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: c.textFaint),
          ),
        ),
        Expanded(child: Divider(color: c.border, thickness: 1)),
      ],
    );
  }
}

class _Perk extends StatelessWidget {
  final String icon, text;
  const _Perk({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: c.textDim)),
          ),
        ],
      ),
    );
  }
}
