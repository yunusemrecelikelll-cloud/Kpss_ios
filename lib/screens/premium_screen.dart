import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/theme_provider.dart';
import 'privacy_policy_screen.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  late final PurchaseService _purchases;

  /// Seçili plan — alttaki sabit "Devam Et" butonu bu planı satın alır
  /// (referans tasarımdaki gibi: satırlar seçilebilir, tek bir CTA en altta).
  String _selectedProductId = kTamPremiumId;

  @override
  void initState() {
    super.initState();
    // NOT: PurchaseService bilerek burada, ekrana özel olarak oluşturuluyor
    // (main.dart'taki global Provider ağacına eklenmedi) — bu satın alma
    // görevi sadece premium_screen.dart + purchase_service.dart dosyalarını
    // değiştirmekle sınırlı tutuldu.
    _purchases = PurchaseService(context.read<StorageService>());
    _purchases.addListener(_onPurchaseServiceChanged);
    _purchases.init();
  }

  void _onPurchaseServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _purchases.removeListener(_onPurchaseServiceChanged);
    _purchases.dispose();
    super.dispose();
  }

  Future<void> _buy(BuildContext context, String productId) async {
    context.read<SoundService>().click();
    if (_purchases.status == PurchaseServiceStatus.unavailable) {
      _showStoreUnavailableSheet(context, productId);
      return;
    }
    await _purchases.buy(productId);
    if (!mounted) return;
    if (_purchases.status == PurchaseServiceStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_purchases.lastError ?? 'Satın alma başarısız oldu.')),
      );
    }
  }

  /// Mağaza gerçekten kullanılamıyorsa (emülatör, App Store Connect/Play
  /// Console'da ürünler henüz tanımlanmamış, mağaza hesabı yok vb.) kullanıcıya
  /// bunu açıkça söyler.
  void _showStoreUnavailableSheet(BuildContext context, String productId) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mağaza şu an kullanılamıyor',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _purchases.lastError ??
                    'Gerçek satın alma için App Store Connect / Play Console\'da '
                        'ürünlerin tanımlanmış olması ve cihazda bir mağaza '
                        'hesabının oturum açmış olması gerekir.',
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  context.read<SoundService>().click();
                  Navigator.of(ctx).pop();
                },
                child: const Text('Kapat'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context) async {
    context.read<SoundService>().click();
    await _purchases.restorePurchases();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Önceki satın alımlar kontrol ediliyor…')),
    );
  }

  /// Apple'ın standart Kullanım Koşulları (EULA) sayfasını tarayıcıda açar.
  /// App Store Guideline 3.1.2, abonelik satılan ekranda EULA bağlantısının
  /// bulunmasını zorunlu kılar. Açma başarısız olursa uygulama ÇÖKMEZ —
  /// kullanıcıya kısa bir bilgi mesajı gösterilir.
  Future<void> _openTermsOfUse(BuildContext context) async {
    context.read<SoundService>().click();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final acildi = await launchUrl(
        Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
        mode: LaunchMode.externalApplication,
      );
      if (!acildi) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Kullanım Koşulları açılamadı.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Kullanım Koşulları açılamadı.')),
      );
    }
  }

  /// Mağazadan gelen GERÇEK fiyatı, abonelik süresiyle birlikte döndürür
  /// (ör. "₺300,00 / ay"). `ProductDetails.price` yalnızca tutarı içerdiği
  /// için süre burada açıkça ekleniyor (Guideline 3.1.2).
  ///
  /// Ürün henüz yüklenmediyse `null` döner — çağıran taraf uydurma bir fiyat
  /// YAZMAZ, "—" ya da yükleniyor göstergesi gösterir (Guideline 2.3.1).
  String? _fiyatMetni(String productId) {
    final p = _purchases.productFor(productId);
    if (p == null) return null;
    return '${p.price} / ay';
  }

  /// Mağaza hâlâ başlatılıyorsa true — fiyat yerine küçük bir yükleniyor
  /// göstergesi çıkar.
  bool get _fiyatYukleniyor =>
      _purchases.status == PurchaseServiceStatus.idle && _purchases.products.isEmpty;

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          'Premium ile Sınırsız Erişim',
          style: TextStyle(color: c.gold, fontWeight: FontWeight.w800, fontSize: 16.5),
        ),
        actions: [
          // Geçmiş satın alımları geri yükleme — mevcut _restore akışı.
          IconButton(
            tooltip: 'Satın Alımları Geri Yükle',
            icon: const Icon(Icons.history),
            onPressed: () => _restore(context),
          ),
        ],
      ),
      body: SafeArea(
        child: premium ? _buildActiveState(context, c) : _buildOfferState(context, c),
      ),
      bottomNavigationBar: premium ? null : _buildStickyCta(context, c),
    );
  }

  Widget _buildActiveState(BuildContext context, KpssColors c) {
    // ÖNEMLİ: Bu ekran daha önce premium kullanıcıya sadece "hesabın aktif"
    // yazıp geçiyordu, hangi ayrıcalıkların dahil olduğunu GÖSTERMİYORDU —
    // "Premium Ayrıntıları Gör" butonuna basınca boş görünmesinin sebebi
    // buydu. Artık premium kullanıcı da tam özellik tablosunu görüyor.
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        DsCard(
          accent: c.gold,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              DsIllustration(emoji: '👑', glowColor: c.gold, size: 84),
              const SizedBox(height: 6),
              Text(
                'Premium hesabın aktif ✨',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, color: c.gold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Aşağıdaki tüm ayrıcalıklar hesabında açık.',
                style: TextStyle(fontSize: 12.5, color: c.textFaint),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              // NOT: Buradaki eski "Ücretsiz Plan" butonu KALDIRILDI. Uygulama
              // içinden plan düşürmek, App Store'da abonelik devam ederken
              // kullanıcıyı yanıltıyordu. Abonelik yönetimi tek yerden —
              // mağazadan — yapılır.
              Text(
                'Aboneliğini yönetmek veya iptal etmek için '
                'App Store > Abonelikler bölümünü kullanabilirsin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: c.textFaint, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _FeatureComparisonTable(),
      ],
    );
  }

  Widget _buildOfferState(BuildContext context, KpssColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        if (_purchases.status == PurchaseServiceStatus.unavailable) ...[
          DsCard(
            accent: c.danger,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                DsIconBadge(icon: Icons.store_mall_directory_outlined, color: c.danger, size: 38, circle: false, glow: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mağaza şu an kullanılamıyor: ${_purchases.lastError ?? "bilinmeyen sebep"}',
                    style: TextStyle(fontSize: 12, height: 1.4, color: c.text),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _PremiumHero(c: c),
        const SizedBox(height: 22),
        DsSectionHeader(title: 'Ücretsiz mi, Premium mi?'),
        const SizedBox(height: 6),
        const _FeatureComparisonTable(),
        const SizedBox(height: 24),
        DsSectionHeader(title: 'Planını seç'),
        const SizedBox(height: 6),
        _PlanCard(
          title: 'Öğrenci Premium',
          tag: '🎓 Öğrenciler için',
          price: _fiyatMetni(kOgrenciPremiumId),
          priceLoading: _fiyatYukleniyor,
          caption: '🎓 Tam premium ile aynı özellikler burada da var. Sizden, '
              'öğrencilerden hiç ücret almak istemezdim ama uygulamanın '
              'giderleri için biraz almam gerekiyor. İdare edin, ileride '
              'telafi ederim dostlarım. 💙🙏',
          selected: _selectedProductId == kOgrenciPremiumId,
          onTap: () => setState(() => _selectedProductId = kOgrenciPremiumId),
        ),
        const SizedBox(height: kDsGap),
        _PlanCard(
          title: 'Tam Premium',
          tag: '⭐ Standart',
          price: _fiyatMetni(kTamPremiumId),
          priceLoading: _fiyatYukleniyor,
          caption: '☕ Sadece bir kahve parasına... hayatın değişebilir mi? 😌✨',
          selected: _selectedProductId == kTamPremiumId,
          onTap: () => setState(() => _selectedProductId = kTamPremiumId),
        ),
        const SizedBox(height: 16),
        Text(
          'Abonelik aylıktır ve otomatik yenilenir; istediğin zaman iptal '
          'edebilirsin. Ücret, satın alma onayında App Store hesabından '
          'tahsil edilir. Yenilemeyi durdurmak için dönem bitmeden en az 24 '
          'saat önce App Store > Abonelikler bölümünden iptal etmen yeterli.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: c.textFaint, height: 1.45),
        ),
        const SizedBox(height: 10),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              DsPillButton(
                label: 'Satın Alımları Geri Yükle',
                color: c.gold,
                filled: false,
                leadingIcon: Icons.history,
                onPressed: () => _restore(context),
              ),
              DsPillButton(
                label: 'Gizlilik Politikası',
                color: c.violetL,
                filled: false,
                leadingIcon: Icons.privacy_tip_outlined,
                onPressed: () {
                  context.read<SoundService>().click();
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                },
              ),
              // Guideline 3.1.2 gereği abonelik ekranında Kullanım Koşulları
              // (EULA) bağlantısı zorunlu — Apple'ın standart EULA'sı açılır.
              DsPillButton(
                label: 'Kullanım Koşulları',
                color: c.mint,
                filled: false,
                leadingIcon: Icons.description_outlined,
                onPressed: () => _openTermsOfUse(context),
              ),
            ],
          ),
        ),
        // ── Geliştirme derlemesine özel test kısayolu ──
        //
        // ÖNEMLİ: Bu buton ödemeyi atladığı için App Store denetiminde
        // sorun çıkarır (Guideline 2.1 / 3.1.1). Bu yüzden SADECE debug
        // derlemesinde derlenir: `kDebugMode` sabit olduğundan release ve
        // profile derlemelerinde tree-shaking ile koddan tamamen çıkar.
        // Bu koşulun dışına ASLA taşınmamalıdır.
        if (kDebugMode) ...[
          const SizedBox(height: 18),
          DsCard(
            accent: c.warn,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🛠️ Geliştirici Aracı',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 13.5, color: c.warn),
                ),
                const SizedBox(height: 6),
                Text(
                  'Yalnızca geliştirme derlemesinde görünür. '
                  'TestFlight ve App Store sürümlerinde yer almaz.',
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: c.textFaint),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DsPillButton(
                    label: 'Ücretsiz Aç (Test)',
                    color: c.warn,
                    filled: false,
                    leadingIcon: Icons.bug_report_outlined,
                    onPressed: () async {
                      context.read<SoundService>().click();
                      await context.read<StorageService>().setUserPlan('premium');
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildStickyCta(BuildContext context, KpssColors c) {
    // Alttaki birincil eylem: altın degradeli, tam genişlikte hap buton.
    // (DsPillButton içerik genişliğinde durduğu için burada aynı görsel dil
    // tam genişlik + yükleniyor göstergesiyle birlikte kuruluyor.)
    // Satın alma yalnızca mağazadan GERÇEK ürün bilgisi geldiyse mümkün —
    // ürün yüklenmemişken buton pasif kalır (Guideline 2.3.1).
    final urunHazir = _purchases.productFor(_selectedProductId) != null;
    final aktif = !_purchases.isPurchasing && urunHazir;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: aktif ? () => _buy(context, _selectedProductId) : null,
            child: Ink(
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: aktif
                      ? [c.gold, Color.lerp(c.gold, c.rose, 0.35)!]
                      : [
                          Color.lerp(c.gold, c.textFaint, 0.6)!,
                          Color.lerp(c.gold, c.textFaint, 0.75)!,
                        ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.gold.withValues(alpha: aktif ? 0.34 : 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Center(
                child: _purchases.isPurchasing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          aktif ? 'Devam Et' : 'Şu an satın alınamıyor',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ── Kahraman bölümü ───────────────────────────────────────────────────────
///
/// Kart değil; sayfanın üstünde serbest yerleşim: solda iki satırlık büyük
/// başlık (ikinci satırın son kelimesi altın), sağda taç illüstrasyonu.
class _PremiumHero extends StatelessWidget {
  final KpssColors c;
  const _PremiumHero({required this.c});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, cons) {
        // Çok dar ekran / büyük yazı ölçeğinde illüstrasyon küçülür, taşma olmaz.
        final gorselBoyut = cons.maxWidth < 320
            ? 74.0
            : cons.maxWidth < 380
                ? 92.0
                : 110.0;
        final baslikBoyut = cons.maxWidth < 340 ? 23.0 : 27.0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: baslikBoyut,
                        fontWeight: FontWeight.w900,
                        height: 1.18,
                        color: c.text,
                      ),
                      children: [
                        const TextSpan(text: 'Senin hedefin,\n'),
                        const TextSpan(text: 'bizim '),
                        TextSpan(text: 'desteğimiz.', style: TextStyle(color: c.gold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 12.5, height: 1.45, color: c.textDim),
                      children: [
                        const TextSpan(text: 'Ücretsiz sürüm temel içerikleri sunar.\n'),
                        TextSpan(
                          text: 'Premium',
                          style: TextStyle(color: c.gold, fontWeight: FontWeight.w900),
                        ),
                        const TextSpan(text: ' ile sınırları kaldır!'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DsIllustration(emoji: '👑', glowColor: c.gold, size: gorselBoyut),
          ],
        );
      },
    );
  }
}

/// ── Karşılaştırma tablosu ─────────────────────────────────────────────────
///
/// Ekranın ana öğesi: iki sütunlu (Ücretsiz / Premium) özellik karşılaştırması.
/// Premium sütunu, başlığıyla birlikte boydan boya altın çerçeve içinde durur —
/// görsel olarak "seçilmiş plan" hissi verir.
///
/// Satır içerikleri uygulamadaki gerçek limitlerle uyumludur:
/// oyun limitleri `kFreeGameDailyLimit` (10/gün), konu havuzu 20 soru,
/// ücretsiz temalar 3 / toplam 9 tema.
class _FeatureComparisonTable extends StatelessWidget {
  const _FeatureComparisonTable();

  /// (emoji, özellik adı, ücretsiz değeri — null ise ✕, premium değeri)
  static const _rows = <(String, String, String?, String)>[
    ('📚', 'Konu başına soru havuzu', '20 soru', 'Sınırsıza yakın'),
    ('❌', 'Yanlışlarım Bankası', null, 'Tüm yanlışları tekrar çöz'),
    ('🃏', 'Kart Oyunu & Solitaire', 'Günde 10 oyun', 'Sınırsız oyun'),
    ('⚔️', 'KPSS Düello & Royale', 'Günde 10 maç', 'Sınırsız maç'),
    ('🗺️', 'Harita Oyunu', 'Günde 10 mini oyun', 'Sınırsız oyun'),
    ('🎨', 'Uygulama Temaları', '3 tema', '9 tema'),
    ('🧠', 'Akılda Kalıcı Kodlama', null, 'Tüm mnemonik teknikleri'),
    ('🎯', 'Sınav Puanı Tahmini', null, 'Anlık net/puan tahmini'),
    ('⏱️', 'Çalışma Kronometresi', null, 'Detaylı zaman analizi'),
    ('🎓', 'Mentörlük Seansları', null, 'Tüm seanslara erişim'),
    ('🏆', 'Özel Lig', null, 'Haftalık sıralama ve kademe'),
    ('📊', 'İstatistik Derinliği', 'Temel özet', 'Konu bazlı detaylı istatistikler'),
  ];

  /// Satır rozetlerinin renkleri — tema token'larından döngüyle seçilir.
  List<Color> _rozetRenkleri(KpssColors c) => [
        c.violetL,
        c.rose,
        c.mint,
        c.gold,
        c.violet,
        c.roseL,
        c.success,
        c.warn,
      ];

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final renkler = _rozetRenkleri(c);

    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        // Sütun genişlikleri oranla belirlenir; Premium sütunu altın çerçeve
        // olarak Stack'te konumlanacağı için piksel değeri gerekiyor.
        final premiumW = (w * 0.30).clamp(92.0, 160.0);
        final ucretsizW = (w * 0.24).clamp(70.0, 128.0);
        final ozellikW = (w - premiumW - ucretsizW).clamp(80.0, w);

        final govde = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _baslikSatiri(c, ozellikW, ucretsizW, premiumW),
            for (var i = 0; i < _rows.length; i++) ...[
              if (i > 0) Container(height: 1, color: c.border),
              _satir(c, _rows[i], renkler[i % renkler.length], ozellikW, ucretsizW, premiumW),
            ],
            const SizedBox(height: 10),
          ],
        );

        return Stack(
          children: [
            // Premium sütununu boydan boya saran altın çerçeve.
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: premiumW,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kDsRadius),
                  color: c.gold.withValues(alpha: c.isLight ? 0.07 : 0.10),
                  border: Border.all(
                    color: c.gold.withValues(alpha: c.isLight ? 0.45 : 0.55),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.gold.withValues(alpha: c.isLight ? 0.14 : 0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
            govde,
          ],
        );
      },
    );
  }

  /// İki ayrı başlık kartı: solda nötr "👤 Ücretsiz", sağda altın "👑 Premium".
  Widget _baslikSatiri(KpssColors c, double ozellikW, double ucretsizW, double premiumW) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: ozellikW,
          child: Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 12),
            child: Text(
              'Özellikler',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: c.textDim),
            ),
          ),
        ),
        SizedBox(
          width: ucretsizW,
          child: _baslikKarti(
            c: c,
            emoji: '👤',
            label: 'Ücretsiz',
            renk: c.textDim,
            vurgulu: false,
          ),
        ),
        SizedBox(
          width: premiumW,
          child: _baslikKarti(
            c: c,
            emoji: '👑',
            label: 'Premium',
            renk: c.gold,
            vurgulu: true,
          ),
        ),
      ],
    );
  }

  Widget _baslikKarti({
    required KpssColors c,
    required String emoji,
    required String label,
    required Color renk,
    required bool vurgulu,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: vurgulu ? 6 : 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kDsRadiusSm),
        color: vurgulu
            ? renk.withValues(alpha: c.isLight ? 0.14 : 0.18)
            : c.glass,
        border: Border.all(
          color: vurgulu ? renk.withValues(alpha: 0.6) : c.border,
          width: vurgulu ? 1.3 : 1,
        ),
        boxShadow: vurgulu
            ? [BoxShadow(color: renk.withValues(alpha: 0.26), blurRadius: 14)]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: vurgulu ? renk : c.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _satir(
    KpssColors c,
    (String, String, String?, String) row,
    Color rozetRengi,
    double ozellikW,
    double ucretsizW,
    double premiumW,
  ) {
    final (emoji, ad, ucretsiz, premium) = row;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: ozellikW,
            child: Row(
              children: [
                DsIconBadge(
                  emoji: emoji,
                  color: rozetRengi,
                  size: 34,
                  circle: false,
                  glow: false,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    ad,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          // Ücretsiz sütunu — özellik yoksa soluk ✕.
          SizedBox(
            width: ucretsizW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: ucretsiz == null
                  ? Icon(Icons.close_rounded,
                      size: 18, color: c.danger.withValues(alpha: 0.55))
                  : Text(
                      ucretsiz,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, height: 1.3, color: c.textFaint),
                    ),
            ),
          ),
          // Premium sütunu — değer + yeşil onay ikonu.
          SizedBox(
            width: premiumW,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 17, color: c.success),
                  const SizedBox(height: 3),
                  Text(
                    premium,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ── Plan kartı ────────────────────────────────────────────────────────────
///
/// Seçilebilir abonelik kartı — seçiliyken altın vurgulu görünür.
class _PlanCard extends StatelessWidget {
  final String title;
  final String tag;

  /// Mağazadan gelen gerçek fiyat + süre (ör. "₺300,00 / ay").
  /// null ise fiyat HENÜZ BİLİNMİYOR demektir — sabit/uydurma bir fiyat
  /// gösterilmez, yerine "—" ya da yükleniyor göstergesi çıkar.
  final String? price;
  final bool priceLoading;
  final String? caption;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.tag,
    required this.price,
    this.priceLoading = false,
    this.caption,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;

    return DsCard(
      accent: selected ? c.gold : null,
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? c.gold : c.textFaint,
                size: 21,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14.5, color: c.text),
                    ),
                    const SizedBox(height: 3),
                    Text(tag, style: TextStyle(fontSize: 11, color: c.textFaint)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: price != null
                    ? Text(
                        price!,
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15, color: c.gold),
                      )
                    : priceLoading
                        // Mağaza fiyatı hâlâ yükleniyor.
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(c.gold),
                              ),
                            ),
                          )
                        // Fiyat bilinmiyor — asla uydurma bir tutar yazılmaz.
                        : Text(
                            '—',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: c.textFaint),
                          ),
              ),
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 10),
            Text(
              caption!,
              style: TextStyle(
                  fontSize: 11.5, color: c.textDim, height: 1.45, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}
