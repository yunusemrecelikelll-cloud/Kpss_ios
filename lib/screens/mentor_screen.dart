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
    return Scaffold(
      appBar: AppBar(title: const Text('🎓 Mentörlük Seansları')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            // NOT: Buradaki "yakında canlı mentörlük açılacak" vaadi kaldırıldı.
            // Ekran premium'a kapalı; ücretli bir özellikte var olmayan bir
            // şeyi vaat etmek hem App Store Guideline 2.1 hem Play'in
            // yanıltıcı satın alma değerlendirmesi açısından risklidir.
            'Sınavda işine yarayacak, denenmiş çalışma stratejileri.',
            style: TextStyle(fontSize: 13, color: c.textFaint),
          ),
          const SizedBox(height: 16),
          for (final t in kMentorTips)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 6),
                    Text(t.text, style: const TextStyle(fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
