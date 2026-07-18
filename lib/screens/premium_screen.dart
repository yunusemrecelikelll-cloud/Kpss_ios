import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/purchase_service.dart';
import '../services/sound_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
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

  /// TEST AŞAMASI İÇİN GEÇİCİ BUTON — ödeme akışını atlayıp premium'u doğrudan
  /// açar. Mağaza ürünleri/gerçek ödeme akışı tam kurulup test edildiğinde
  /// BU BUTON KALDIRILACAK.
  void _openFreeForTesting(BuildContext context) {
    context.read<SoundService>().click();
    context.read<StorageService>().setUserPlan('premium');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Test modu: Premium açıldı (ödeme alınmadı).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final premium = storage.isPremiumUser();

    return Scaffold(
      appBar: AppBar(
        title: Text('Premium ile Sınırsız Erişim',
            style: TextStyle(color: c.gold, fontWeight: FontWeight.w800, fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'Satın Alımları Geri Yükle',
            icon: const Icon(Icons.restore),
            onPressed: () => _restore(context),
          ),
        ],
      ),
      body: SafeArea(
        child: premium ? _buildActiveState(context, storage, c) : _buildOfferState(context, c),
      ),
      bottomNavigationBar: premium ? null : _buildStickyCta(context, c),
    );
  }

  Widget _buildActiveState(BuildContext context, StorageService storage, KpssColors c) {
    // ÖNEMLİ: Bu ekran daha önce premium kullanıcıya sadece "hesabın aktif"
    // yazıp geçiyordu, hangi ayrıcalıkların dahil olduğunu GÖSTERMİYORDU —
    // "Premium Ayrıntıları Gör" butonuna basınca boş görünmesinin sebebi
    // buydu. Artık premium kullanıcı da tam özellik tablosunu görüyor.
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('Premium hesabın aktif ✨',
                    style: TextStyle(fontWeight: FontWeight.w800, color: c.gold, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  'Aşağıdaki tüm ayrıcalıklar hesabında açık.',
                  style: TextStyle(fontSize: 12.5, color: c.textFaint),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    context.read<SoundService>().click();
                    storage.setUserPlan('free');
                  },
                  child: const Text('Ücretsiz Plan'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _FeatureComparisonTable(c: c),
      ],
    );
  }

  Widget _buildOfferState(BuildContext context, KpssColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (_purchases.status == PurchaseServiceStatus.unavailable)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Mağaza şu an kullanılamıyor: ${_purchases.lastError ?? "bilinmeyen sebep"}',
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          ),
        Text(
          'Premium\'da konu başına soru havuzu limiti kalkar, tüm oyunlar '
          'sınırsız oynanır ve kilitli tüm araçların (Yanlışlarım Bankası, '
          'Akılda Kalıcı Kodlama, Özel Lig ve daha fazlası) kilidi açılır.',
          style: TextStyle(fontSize: 12.5, color: c.textFaint, height: 1.5),
        ),
        const SizedBox(height: 18),
        _FeatureComparisonTable(c: c),
        const SizedBox(height: 22),
        Text('Planını seç', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c.text)),
        const SizedBox(height: 10),
        _PlanRow(
          title: 'Öğrenci Premium',
          tag: '🎓 Öğrenciler için',
          price: _purchases.productFor(kOgrenciPremiumId)?.price ?? '100,00 ₺ / ay',
          caption: '🎓 Tam premium ile aynı özellikler burada da var. Sizden, '
              'öğrencilerden hiç ücret almak istemezdim ama uygulamanın '
              'giderleri için uygun bir fiyat belirledim. 💙',
          selected: _selectedProductId == kOgrenciPremiumId,
          c: c,
          onTap: () => setState(() => _selectedProductId = kOgrenciPremiumId),
        ),
        const SizedBox(height: 10),
        _PlanRow(
          title: 'Tam Premium',
          tag: '⭐ Standart',
          price: _purchases.productFor(kTamPremiumId)?.price ?? '300,00 ₺ / ay',
          caption: '☕ Sadece bir kahve parasına... hayatın değişebilir mi? 😌✨',
          selected: _selectedProductId == kTamPremiumId,
          c: c,
          onTap: () => setState(() => _selectedProductId = kTamPremiumId),
        ),
        const SizedBox(height: 16),
        Text(
          'Abonelikler otomatik yenilenir. İstediğin zaman mağaza hesabının '
          'abonelik ayarlarından iptal edebilirsin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: c.textFaint),
        ),
        const SizedBox(height: 6),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: () => _restore(context),
                child: const Text('Satın Alımları Geri Yükle'),
              ),
              TextButton(
                onPressed: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                },
                child: const Text('Gizlilik Politikası'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Test aşaması — aşağıdaki buton geliştirme amaçlıdır, ilerleyen '
          'zamanlarda kaldırılacaktır.',
          style: TextStyle(fontSize: 11, color: c.textFaint),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _openFreeForTesting(context),
            child: const Text('🧪 Ücretsiz Aç (Test)'),
          ),
        ),
      ],
    );
  }

  Widget _buildStickyCta(BuildContext context, KpssColors c) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.gold,
              foregroundColor: Colors.black,
            ),
            onPressed: _purchases.isPurchasing ? null : () => _buy(context, _selectedProductId),
            child: _purchases.isPurchasing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Devam Et', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          ),
        ),
      ),
    );
  }
}

/// Referans tasarımdaki gibi "Özellikler | Ücretsiz | Premium" tablo görünümü
/// — çoğu özellik kilitli/açık (✓/✗) olduğundan işaretle, miktar bazlı olanlar
/// (soru havuzu, tema sayısı, günlük oyun hakkı gibi) kısa metinle gösterilir.
class _FeatureComparisonTable extends StatelessWidget {
  final KpssColors c;
  const _FeatureComparisonTable({required this.c});

  static const _rows = [
    ('📚 Konu başına soru havuzu', '20 soru', 'Sınırsıza yakın'),
    ('❌ Yanlışlarım Bankası', null, 'Tüm yanlışları tekrar çöz'),
    ('🃏 Kart Oyunu & Solitaire', 'Günde 10 oyun', 'Sınırsız oyun'),
    ('⚔️ KPSS Düello & Royale', 'Günde 10 maç', 'Sınırsız maç'),
    ('🗺️ Harita Oyunu', 'Günde 10 mini oyun', 'Sınırsız oyun'),
    ('🎨 Uygulama Temaları', '3 tema', '9 tema'),
    ('🧠 Akılda Kalıcı Kodlama', null, 'Tüm mnemonik teknikleri'),
    ('🎯 Sınav Puanı Tahmini', null, 'Anlık net/puan tahmini'),
    ('⏱️ Çalışma Kronometresi', null, 'Detaylı zaman analizi'),
    ('🎓 Mentörlük Seansları', null, 'Tüm seanslara erişim'),
    ('🏆 Özel Lig', null, 'Haftalık sıralama ve kademe'),
    ('📊 İstatistik Derinliği', 'Temel özet', 'Konu bazlı detaylı analiz'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(flex: 5, child: Text('Özellikler', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                Expanded(
                  flex: 3,
                  child: Text('Ücretsiz', textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: c.textFaint)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Premium', textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: c.gold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            for (final row in _rows) _buildRow(row.$1, row.$2, row.$3),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String title, String? free, String premiumValue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          Expanded(
            flex: 3,
            child: Center(
              child: free == null
                  ? Icon(Icons.close, size: 17, color: c.textFaint.withValues(alpha: 0.6))
                  : Text(free, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: c.textFaint)),
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: premiumValue.trim().isEmpty
                  ? Icon(Icons.check_circle, size: 17, color: c.success)
                  : Text(
                      premiumValue,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.success),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Seçilebilir bir abonelik satırı — referans tasarımdaki fiyat kartlarına
/// benzer, seçiliyken altın çerçeveyle vurgulanır.
class _PlanRow extends StatelessWidget {
  final String title;
  final String tag;
  final String price;
  final String? caption;
  final bool selected;
  final KpssColors c;
  final VoidCallback onTap;
  const _PlanRow({
    required this.title,
    required this.tag,
    required this.price,
    this.caption,
    required this.selected,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? c.gold.withValues(alpha: 0.10) : c.glass2,
          border: Border.all(color: selected ? c.gold : c.border, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? c.gold : c.textFaint,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(tag, style: TextStyle(fontSize: 11, color: c.textFaint)),
                    ],
                  ),
                ),
                Text(price, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: c.gold)),
              ],
            ),
            if (caption != null) ...[
              const SizedBox(height: 10),
              Text(
                caption!,
                style: TextStyle(fontSize: 11.5, color: c.textDim, height: 1.45, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
