import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../theme/theme_provider.dart';
import 'tools_hub_screen.dart';

class MentorTip {
  final String title;
  final String text;
  const MentorTip(this.title, this.text);
}

/// JS: MENTOR_TIPS — birebir taşındı.
const List<MentorTip> kMentorTips = [
  MentorTip(
    '⏳ Zaman Yönetimi',
    'Sınavda bir soruya 60-70 saniyeden fazla takılma. Emin olamadığın soruyu işaretleyip geç, '
        'tur sonunda geri dön.',
  ),
  MentorTip(
    '🎯 Eleme Tekniği',
    "Doğru şıkkı bilmesen bile önce kesin yanlış olan şıkları ele. 5 şıktan 2'sini eleyip kalanlar "
        'arasından seçmek isabet oranını ciddi artırır.',
  ),
  MentorTip(
    '📉 Zayıf Konuya Öncelik Ver',
    'Profil sayfandaki "çalışman gereken ders" önerisini haftada en az 2 kez tekrar et; '
        'en çok net, en zayıf dersten gelir.',
  ),
  MentorTip(
    '🧪 Deneme Ritmi',
    'Haftada en az 1 tam deneme çöz ve gerçek sınav saatinde, gerçek süre baskısıyla otur. '
        'Zamana alışmak kadar önemli bir şey yok.',
  ),
  MentorTip(
    '🔁 Yanlış Tekrarı',
    'Her denemeden sonra yanlışlarını 24 saat içinde tekrar et. Unutma eğrisi en hızlı ilk gün işler.',
  ),
  MentorTip(
    '😴 Sınav Öncesi Bakım',
    'Sınavdan önceki gece erken yat, ağır yemekten kaçın. Dinlenmiş beyin, ezberden çok daha iyi '
        'çıkarım yapar.',
  ),
  MentorTip(
    '🍅 Pomodoro ile Odaklan',
    '25 dakika kesintisiz çalış, 5 dakika mola ver. 4 turda bir 20-30 dakikalık uzun mola yap. '
        'Mola sırasında telefona bakmak yerine ayağa kalkıp yürü; dikkat kası böyle dinlenir.',
  ),
  MentorTip(
    '📆 Aralıklı Tekrar Takvimi',
    'Yeni öğrendiğin konuyu 1. gün, 3. gün, 7. gün ve 21. gün tekrar et. Bu aralıklı tekrar '
        'düzeni, bilgiyi kısa süreli hafızadan kalıcı hafızaya taşımanın en kanıtlanmış yolu.',
  ),
  MentorTip(
    '🧠 Aktif Hatırlama',
    'Konuyu tekrar okumak yerine kitabı kapat ve hatırladıklarını boş kağıda yaz. Hatırlayamadığın '
        'yerler gerçek eksiklerin; sadece o kısımlara geri dön. Okumak tanıdıklık, yazmak öğrenme sağlar.',
  ),
  MentorTip(
    '👨‍🏫 Feynman Tekniği',
    'Çalıştığın konuyu hiç bilmeyen birine anlatır gibi kendi cümlelerinle sesli anlat. '
        'Takıldığın yerde durup kaynağa dön. Anlatamıyorsan öğrenmemişsindir; bu en hızlı eksik tespitidir.',
  ),
  MentorTip(
    '🔄 Turlama Tekniği',
    'Sınavda 3 tur yap: ilk turda anında çözdüklerini işaretle, ikinci turda düşünmeni gerektirenleri, '
        'son turda kalanları dene. Böylece kolay sorulardan alacağın netleri zora takılıp yakma.',
  ),
  MentorTip(
    '🚫 Boş Bırakma Kararı',
    "4 yanlış 1 doğruyu götürür; ama 2 şık eleyebildiysen işaretlemek istatistiksel olarak kârlıdır. "
        'Hiç fikrin yoksa ve şık eleyemiyorsan boş bırak, tahmine net yatırma.',
  ),
  MentorTip(
    '🧮 Net Hedefi Belirle',
    'Hedef puanını belirle ve geçen yılın taban puanlarına bakarak ders ders net hedefine çevir. '
        '"Çok net yapmalıyım" yerine "GY 45, GK 40 net" gibi ölçülebilir bir hedefle çalış.',
  ),
  MentorTip(
    '📓 Yanlış Defteri Tut',
    'Her yanlış soruyu deftere yaz: sorunun konusu, senin cevabın, doğru cevap ve yanılma sebebin. '
        'Deneme öncesi sadece bu defteri tekrar et; en verimli tekrar kaynağın kendi hatalarındır.',
  ),
  MentorTip(
    '🔍 Hata Tipini Teşhis Et',
    'Yanlışlarını üçe ayır: bilgi eksiği, dikkat hatası, süre yetmedi. Bilgi eksiğine konu tekrarı, '
        'dikkat hatasına soru okuma disiplini, süre sorununa bol deneme çözümü reçetedir. Tedavi teşhise göre değişir.',
  ),
  MentorTip(
    '🎯 Gerçekçi Günlük Hedef',
    'Günlük hedefini en kötü gününe göre koy: 300 soru değil, her gün mutlaka yapabileceğin 80-100 soru. '
        'Küçük ama kesintisiz ilerleme, ara ara yapılan maratonlardan her zaman daha çok net getirir.',
  ),
  MentorTip(
    '🔥 Seriyi Koru',
    "Zincirini kırma: her gün en az 20 dakika çalışarak seriyi sürdür. Kötü günlerde hedef 'mükemmel "
        "çalışmak' değil 'sıfır çekmemek'tir; alışkanlık motivasyondan daha güvenilirdir.",
  ),
  MentorTip(
    '🪫 Tükenmişlik Sinyali',
    'Üst üste birkaç gün verim düştüyse suçluluk duymadan yarım gün tam mola ver: yürüyüş, film, arkadaş. '
        'Planlı mola tembellik değil bakım onarımdır; molasız devam etmek haftalar kaybettirir.',
  ),
  MentorTip(
    '🌅 Sınav Sabahı Rutini',
    'Sınav günü alışık olduğun kahvaltıyı yap; ilk kez deneyeceğin yiyecek ve içeceklerden uzak dur. '
        'Aşırı kafein el titremesi ve tuvalet ihtiyacı demektir, ölçülü ol.',
  ),
  MentorTip(
    '🧘 Kaygıyı Nefesle Yönet',
    '4 saniye nefes al, 4 saniye tut, 6 saniyede ver. Sınav başlamadan ve zorlandığın anlarda 3-4 kez '
        'uygula; uzun nefes verme, kalp atışını fizyolojik olarak yavaşlatır ve paniği keser.',
  ),
  MentorTip(
    '🏫 Salon Stratejisi',
    'Sınava optik kodlamayı 10 soruda bir yaparak git; tek tek kodlamak süre yer, en sona bırakmak '
        'kaydırma riskini büyütür. Saatini kontrol etmeyi ilk 40. dakikaya kadar erteleme.',
  ),
  MentorTip(
    '📖 Paragrafta Hız Tekniği',
    'Paragraf sorusunda önce soru kökünü oku, sonra metne geç. Ne arayacağını bilerek okumak hem hızı '
        'hem isabeti artırır. Metni kendi görüşünle değil sadece yazarın söyledikleriyle değerlendir.',
  ),
  MentorTip(
    '➗ Matematikte İşlem Disiplini',
    'İşlem hatalarının çoğu zihinden atlanan adımlardan çıkar. Adımları kısa da olsa yaz, dağınık '
        'karalama yerine düzenli sütun kullan. Sonucu şıklara bakıp mantık süzgecinden geçir: negatif yaş, küsuratlı kişi sayısı olamaz.',
  ),
  MentorTip(
    '📜 Tarihte Kronoloji Haritası',
    'Tarihi konu konu değil zaman şeridi üzerinde çalış: her döneme padişah, savaş ve ıslahatı aynı '
        'şeride yerleştir. KPSS tarih sorularının çoğu "hangisi önce/sonra" mantığıyla çözülür.',
  ),
  MentorTip(
    '🗞️ Vatandaşlıkta Güncel Takip',
    'Güncel bilgi soruları için son 1 yılın önemli gelişmelerini aylık özetlerden takip et; '
        'anayasa değişikliklerini ve yeni kurulan kurumları ayrı bir sayfada listele. Bu 2-3 soru sıralamada binlerce kişi fark ettirir.',
  ),
  MentorTip(
    '🌙 Uyku Düzenini Sınava Ayarla',
    'Son 2 hafta uyku saatini sınav gününe göre sabitle: sınav sabah 10.15\'teyse beynin en geç '
        '8.00\'de uyanmaya alışmış olmalı. Gece çalışıp gündüz uyuyan beyin, sınav saatinde pik performans veremez.',
  ),
];

/// Mentörlük Seansları — JS: renderMentor.
class MentorScreen extends StatelessWidget {
  const MentorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    if (!storage.isPremiumUser()) {
      return const LockedFeatureCard(
        title: 'Mentörlük Seansları',
        desc: "Sınav stratejileri ve haftalık çalışma planı önerileri için Premium'a geç.",
      );
    }

    final c = context.watch<ThemeProvider>().colors;
    final acikTema = c.isLight;
    return Scaffold(
      appBar: AppBar(title: const Text('🎓 Mentörlük Seansları')),
      body: LayoutBuilder(
        builder: (context, cons) {
          final sutun = cons.maxWidth > 760 ? 3 : 2;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Sınavda işine yarayacak, denenmiş çalışma stratejileri.',
                style: TextStyle(fontSize: 13, color: c.textFaint),
              ),
              const SizedBox(height: 16),
              _masonry(sutun, acikTema),
            ],
          );
        },
      ),
    );
  }

  /// Yapışkan notları (Akılda Kalıcı Kodlama ekranıyla AYNI dil — kullanıcı
  /// isteği) en kısa sütuna ekleyen basit masonry.
  Widget _masonry(int sutun, bool acikTema) {
    final sutunlar = List.generate(sutun, (_) => <Widget>[]);
    final yuk = List.filled(sutun, 0.0);
    for (var i = 0; i < kMentorTips.length; i++) {
      var enKisa = 0;
      for (var k = 1; k < sutun; k++) {
        if (yuk[k] < yuk[enKisa]) enKisa = k;
      }
      final t = kMentorTips[i];
      sutunlar[enKisa].add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _MentorNotu(
            baslik: t.title, metin: t.text, index: i, acikTema: acikTema),
      ));
      yuk[enKisa] += 120 + t.text.length * 0.32;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var k = 0; k < sutun; k++) ...[
          if (k > 0) const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sutunlar[k]),
          ),
        ],
      ],
    );
  }
}

// Yapışkan not paleti — mnemonics_screen ile aynı ton dizisi.
const _kMentorTonlari = <double>[48, 96, 168, 200, 256, 320, 12];
Color _mentorKagit(int i, bool acikTema) {
  final h = _kMentorTonlari[i % _kMentorTonlari.length];
  return HSLColor.fromAHSL(
          1, h, acikTema ? 0.82 : 0.30, acikTema ? 0.90 : 0.17)
      .toColor();
}

Color _mentorMurekkep(bool acikTema) =>
    acikTema ? const Color(0xFF241C33) : const Color(0xFFEFE9F7);

/// Bir mentörlük ipucunu YAPIŞKAN NOT gibi gösteren kart (Akılda Kalıcı
/// Kodlama ekranıyla aynı tasarım): hafif eğik kağıt, üstte yapışkan bant,
/// sağ altta kıvrık köşe, dönen kağıt tonları.
class _MentorNotu extends StatelessWidget {
  final String baslik;
  final String metin;
  final int index;
  final bool acikTema;
  const _MentorNotu({
    required this.baslik,
    required this.metin,
    required this.index,
    required this.acikTema,
  });

  @override
  Widget build(BuildContext context) {
    final kagit = _mentorKagit(index, acikTema);
    final ink = _mentorMurekkep(acikTema);
    final egim = ((index % 5) - 2) * 0.008;

    return Transform.rotate(
      angle: egim,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: acikTema ? 0.16 : 0.42),
              blurRadius: 12,
              offset: const Offset(2, 6),
            ),
          ],
        ),
        child: Material(
          color: kagit,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ink.withValues(alpha: 0.10)),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        baslik,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                            color: ink),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        metin,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: ink.withValues(alpha: 0.85)),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.push_pin_rounded,
                              size: 11, color: ink.withValues(alpha: 0.35)),
                          const SizedBox(width: 4),
                          Text('mentör notu',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: ink.withValues(alpha: 0.45))),
                        ],
                      ),
                    ],
                  ),
                ),
                // Üstteki yapışkan bant.
                Positioned(
                  top: 4,
                  left: 16,
                  child: Transform.rotate(
                    angle: -0.10,
                    child: Container(
                      width: 46,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withValues(alpha: acikTema ? 0.65 : 0.16),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                // Sağ alt kıvrık köşe.
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(10)),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Transform.rotate(
                        angle: 0.785,
                        origin: const Offset(6, 6),
                        child: Container(
                            color: ink.withValues(alpha: acikTema ? 0.10 : 0.18)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
