import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../models/question.dart';
import '../models/badge.dart';
import '../services/auth_service.dart';
import '../services/in_app_notice_service.dart';
import '../services/quiz_engine.dart';
import '../widgets/hak_kazan_sheet.dart';
import '../services/storage_service.dart';
import '../services/sound_service.dart';
import '../services/remote_question_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_system.dart';
import '../theme/subject_colors.dart';
import '../theme/theme_provider.dart';
import '../utils/exam_dates.dart';
import 'subject_screen.dart';
import 'quiz_screen.dart';
import 'profile_screen.dart';
import 'premium_screen.dart';
import '../widgets/ana_menu.dart';
import '../widgets/study_plan_card.dart';
import 'account_login_screen.dart';
import 'duel/duel_lobby_screen.dart';
import 'settings_screen.dart';
import 'placement_exam_screen.dart';
import 'mentor_screen.dart';
import 'mnemonics_screen.dart';

/// Ücretsiz pakette 120 soruluk TAM DENEME sınavı hakkı (toplam, günlük değil).
/// Deneme sınavı uygulamanın en ağır içeriği olduğu için ücretsiz tarafta
/// tek denemeyle sınırlı.
const int kFreeMaxFullTestAttempts = 1;

/// Anasayfa karşılama mesajı.
///
/// CİNSİYETE GÖRE HİTAP KALDIRILDI: "Prensesim"/"Aslanım" gibi seslenişler
/// kullanıcının cinsiyetine göre seçiliyordu. Bir sınav hazırlık uygulamasında
/// bu hem gereksiz bir samimiyet varsayımı hem de yanlış cinsiyetlendirme
/// riski taşıyor. Artık herkese aynı, adıyla hitap eden nötr mesaj gösteriliyor.
String _heroGreetingFor(String name) {
  return 'Merhaba, $name! Hazır mısın? ✨';
}

class HomeScreen extends StatefulWidget {
  final List<Subject> subjects;
  const HomeScreen({super.key, required this.subjects});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _startingFullTest = false;
  DateTime? _newContentAvailableAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBadges());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDailyLoginReward());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkContentUpdate());
  }

  /// Sunucudaki soru içeriği (bkz. RemoteQuestionService.getServerContentUpdatedAt)
  /// kullanıcının en son gördüğü sürümden daha yeniyse "Yeni sorular eklendi"
  /// banner'ını göstermek için işaretler — Ayarlar'dan "Tüm Soruları İndir"e
  /// basınca bu işaret temizlenir (bkz. settings_screen.dart).
  Future<void> _checkContentUpdate() async {
    final remote = context.read<RemoteQuestionService>();
    final storage = context.read<StorageService>();
    final serverUpdatedAt = await remote.getServerContentUpdatedAt();
    if (!mounted || serverUpdatedAt == null) return;
    final lastSeenMs = storage.getLastSeenContentVersionMs();
    if (serverUpdatedAt.millisecondsSinceEpoch > lastSeenMs) {
      setState(() => _newContentAvailableAt = serverUpdatedAt);
    }
  }

  Future<void> _checkBadges() async {
    final storage = context.read<StorageService>();
    final newlyUnlocked = await checkAndUnlockBadges(storage, widget.subjects);
    if (newlyUnlocked.isEmpty || !mounted) return;
    // Rozet bildirimi artık ALTTAN SnackBar değil, ÜSTTEN kayan temalı afiş
    // (kullanıcı isteği). Kuyruk sıralı çalışır: birden çok rozet varsa
    // sırayla gösterilir; test sırasında otomatik ertelenir.
    // TEK SATIR: sistem bildirimleri alt açıklama taşımaz (kullanıcı isteği —
    // sade, temaya uygun afiş).
    for (final b in newlyUnlocked) {
      InAppNoticeService.instance.goster(
        InAppNotice(baslik: 'Yeni rozet: ${b.name}', govde: '', emoji: '🏅'),
      );
    }
  }

  /// Uygulama bugün ilk kez açıldığında bir kerelik XP ödülü verir (bkz.
  /// StorageService.claimDailyLoginRewardIfNeeded) — bugün zaten alındıysa
  /// hiçbir şey yapmaz.
  Future<void> _checkDailyLoginReward() async {
    final storage = context.read<StorageService>();
    final claimed = await storage.claimDailyLoginRewardIfNeeded();
    if (!claimed || !mounted) return;
    // Üstten kayan temalı afiş (SnackBar yerine — kullanıcı isteği).
    InAppNoticeService.instance.goster(
      InAppNotice(
        baslik: 'Günlük ödül: +${StorageService.kDailyLoginRewardXp} XP',
        govde: '',
        emoji: '🎁',
      ),
    );
  }

  Future<void> _startFullTest(BuildContext context) async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final done = storage.getAttempts().where((a) => a.topicId == 'full-test').length;
      // Efektif hak = ücretsiz limit + reklam/hakla kazanılmış ekstra tekrarlar.
      final izinli = kFreeMaxFullTestAttempts + storage.getBonusFullTests();
      if (done >= izinli) {
        // Hak dolduğunda "Hak Kazan" sayfası: reklam izle (+2 hak) ya da hak
        // harcayarak bir deneme daha aç (kullanıcı isteği). Başarılıysa +1
        // bonus deneme ekleyip sınavı başlat.
        final oldu = await hakKazanSheet(
          context,
          baslik: 'Yeni deneme sınavı hakkı',
          aciklama:
              'Ücretsiz deneme sınavı hakkını kullandın. Reklam izleyerek '
              '(+2 hak) ya da hakkından 1 harcayarak bir deneme sınavı daha '
              'açabilirsin. Premium\'da sınırsızdır.',
          maliyet: 1,
        );
        if (!oldu) return;
        await storage.addBonusFullTests(1);
      }
    }
    if (!mounted) return;

    setState(() => _startingFullTest = true);
    final remote = context.read<RemoteQuestionService>();
    final rng = Random();
    final allQs = <Question>[];
    for (final s in widget.subjects) {
      final n = kFullTestDist[s.id] ?? 0;
      if (n == 0 || s.konular.isEmpty) continue;
      final pool = <Question>[];
      for (final t in s.konular) {
        final havuz = await remote.getPool(t.id, t.sorular);
        for (final q in havuz) {
          pool.add(q.copyWith(subjectId: s.id, subjectAd: s.ad));
        }
      }
      pool.shuffle(rng);
      allQs.addAll(pool.take(n));
    }
    if (!mounted) return;
    setState(() => _startingFullTest = false);
    if (allQs.length < 10) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Yeterli soru yüklenemedi.')));
      return;
    }
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => QuizScreen(
        subjectId: 'full',
        subjectAd: 'Genel Deneme',
        topicId: 'full-test',
        topicBaslik: '120 Soruluk Deneme Sınavı',
        questions: allQs,
        isFullTest: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final subjects = widget.subjects;
    final storage = context.watch<StorageService>();
    final c = context.watch<ThemeProvider>().colors;
    final auth = context.watch<AuthService>();
    // İsim önceliği (DÜZELTİLDİ — "Hoş geldin Misafir" hatası, 2. tur):
    //  1. GERÇEK girişin displayName'i (anonim oturum SAYILMAZ — düello/sohbet
    //     altyapısı sessizce anonim açabiliyor ve displayName'i yoktur;
    //     "Ayarlarda girişliyim ama anasayfa Misafir diyor" bundandı),
    //  2. yerel kayıtlı isim,
    //  3. gerçek giriş varsa e-posta öneki (silme sonrası yeniden kayıt gibi
    //     displayName'in henüz oluşmadığı durumlar — ASLA "Misafir" deme),
    //  4. en son yerel profil adı ("Misafir" yalnızca gerçekten girişsizken).
    final gercekGiris = auth.isRealSignedIn;
    // İSİM ÖNCELİĞİ (kullanıcı isteği: "Profil'den değiştirdiğim isim her
    // yerde geçerli olsun"): 1) Profil'de yazılan yerel isim, 2) hesap adı,
    // 3) e-posta öneki, 4) yerel profil adı. Yerel isim, girişte yalnızca
    // BOŞSA hesap adıyla doldurulur (account_login_screen) — kullanıcının
    // seçtiği isim Google adıyla asla ezilmez.
    final authName = gercekGiris ? auth.currentUser?.displayName?.trim() : null;
    final epostaOnEki = gercekGiris
        ? (auth.currentUser?.email?.split('@').first.trim() ?? '')
        : '';
    final name = storage.getUserName().isNotEmpty
        ? storage.getUserName()
        : ((authName != null && authName.isNotEmpty)
            ? authName
            : (epostaOnEki.isNotEmpty ? epostaOnEki : storage.getActiveUser()));
    final premium = storage.isPremiumUser();
    final overall = storage.computeOverall();
    final completed = storage.getCompletedTopics();
    final totalTopics = subjects.fold(0, (s, x) => s + x.konular.length);
    final doneTopics = subjects.fold(0, (s, x) => s + x.konular.where((t) => completed[t.id] == true).length);
    final fullTestDone = storage.getAttempts().where((a) => a.topicId == 'full-test').length;
    final examInfo = examInfoFor(storage.getExamType());
    final drafts = storage.getAllDrafts();

    return Scaffold(
      appBar: AppBar(
        title: Text('KPSS Hazırlık', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700, fontSize: 22)),
        actions: [
          _ProfileAvatarButton(
            name: name,
            onTap: () {
              context.read<SoundService>().click();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      drawer: AnaMenu(subjects: subjects, premium: premium, name: name),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1) Sınav geri sayım kartı.
            if (examInfo != null) _ExamCountdownCard(examInfo: examInfo),
            if (examInfo != null) const SizedBox(height: kDsGap),
            // 2) Giriş banner'ı — anonim oturum "girişli" SAYILMAZ; gerçek
            // hesabı olmayan herkese giriş daveti gösterilmeye devam eder.
            if (!auth.isRealSignedIn) ...[
              const _LoginBanner(),
              const SizedBox(height: kDsGap),
            ],
            if (_newContentAvailableAt != null) ...[
              _ContentUpdateBanner(colors: c, updatedAt: _newContentAvailableAt!),
              const SizedBox(height: kDsGap),
            ],
            for (final entry in drafts.entries) ...[
              _DraftResumeCard(draftKey: entry.key, draft: entry.value, colors: c),
              const SizedBox(height: kDsGap),
            ],
            // Karşılama kartı (mevcut davranış korunuyor, sadece yüzeyi
            // tasarım sistemine taşındı).
            DsCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_heroGreetingFor(name),
                      style: TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w900, color: c.text)),
                  const SizedBox(height: 6),
                  Text('2026 KPSS hazırlığında bugün ne çalışmak istersin?',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textDim)),
                  const SizedBox(height: 10),
                  DsChip(
                    label: premium ? 'PREMIUM' : 'ÜCRETSİZ',
                    color: premium ? c.gold : c.violetL,
                  ),
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            // 3) Günlük Çalışma Planı kartı — bugünkü/sıradaki çalışma
            // seansını ve teste dayalı ders önerisini gösterir. Plan yoksa
            // plan oluşturmaya çağırır. ("Hedef Belirle" banner'ı buradaydı,
            // yerini bu kart aldı.)
            const StudyPlanCard(),
            const SizedBox(height: kDsGap),
            // 3.5) Hızlı erişim: Akılda Kalıcı Kodlama + Mentörlük (kullanıcı
            // isteği — anasayfadan tek dokunuşla ulaşılsın). Yan yana iki
            // kompakt kart; dokununca ilgili sayfa açılır.
            Row(
              children: [
                Expanded(
                  child: _HizliErisimKarti(
                    emoji: '🧠',
                    baslik: 'Akılda Kalıcı\nKodlama',
                    renk: c.mint,
                    onTap: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MnemonicsScreen(subjects: subjects)));
                    },
                  ),
                ),
                const SizedBox(width: kDsGap),
                Expanded(
                  child: _HizliErisimKarti(
                    emoji: '🎓',
                    baslik: 'Mentörlük\nSeansları',
                    renk: c.gold,
                    onTap: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const MentorScreen()));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: kDsGap),
            // 4) İstatistik şeridi.
            _HomeStatsStrip(
              rate: overall.rate,
              solved: overall.solved,
              doneTopics: doneTopics,
              totalTopics: totalTopics,
            ),
            const SizedBox(height: kDsGap),
            // 5) "Beni Sına" banner'ı.
            _BeniSinaCard(
              alreadyTaken: storage.hasTakenPlacementExam,
              subjects: subjects,
            ),
            // 6) Premium kartı — premium kullanıcıya gösterilmez.
            if (!premium) ...[
              const SizedBox(height: kDsGap),
              DsBannerCard(
                emoji: '💎',
                accent: c.violet,
                highlighted: true,
                title: 'Premium ile sınırlarını aş!',
                subtitle: 'Reklamsız kullanım, gelişmiş analizler ve özel içeriklere eriş.',
                actionLabel: "👑 Premium'a Geç",
                onAction: () {
                  context.read<SoundService>().click();
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                },
              ),
            ],
            const SizedBox(height: kDsGap),
            // 7) Tam Deneme Sınavı hero kartı.
            DsHeroCard(
              emoji: '🎯',
              title: 'Tam Deneme Sınavı',
              subtitle: 'Gerçek KPSS formatında 120 soru',
              highlightLine: premium
                  ? '✨ Sınırsız deneme hakkın var'
                  : '✨ ${(kFreeMaxFullTestAttempts - fullTestDone).clamp(0, kFreeMaxFullTestAttempts)} / $kFreeMaxFullTestAttempts deneme hakkın kaldı',
              accent: c.violet,
              accent2: c.violetL,
              illustrationEmoji: '🚀',
              // Sınav hazırlanırken buton pasifleşir (eski spinner'ın yerine
              // etiket değişiyor) — mantık aynı.
              actionLabel: _startingFullTest ? 'Hazırlanıyor…' : 'Sınava Gir',
              onAction: _startingFullTest
                  ? null
                  : () {
                      context.read<SoundService>().click();
                      _startFullTest(context);
                    },
            ),
            const SizedBox(height: kDsGap),
            // 8) KPSS Düello hero kartı.
            DsHeroCard(
              emoji: '⚔️',
              title: 'KPSS Düello',
              badge: 'POPÜLER',
              subtitle: 'Rakiplerinle canlı yarış: 1v1 Düello veya çok kişilik Royale',
              accent: c.rose,
              accent2: c.roseL,
              illustrationEmoji: '🏆',
              actionLabel: 'Düelloya Gir',
              onAction: () {
                context.read<SoundService>().click();
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const DuelLobbyScreen()));
              },
            ),
            const SizedBox(height: 20),
            // 9) Dersler — projede ayrı bir "tüm dersler" ekranı olmadığı için
            // başlıkta aksiyon bağlantısı yok.
            const DsSectionHeader(title: 'Dersler'),
            const SizedBox(height: 8),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: kDsGap,
                crossAxisSpacing: kDsGap,
                // Sabit en-boy oranı yerine sabit yükseklik: büyük yazı
                // ölçeğinde kart da büyür, böylece taşma olmaz.
                mainAxisExtent: 168 *
                    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.6),
              ),
              children: [
                for (final s in subjects.where((s) => s.konular.isNotEmpty))
                  _SubjectCard(
                    subject: s,
                    completedCount: s.konular.where((t) => completed[t.id] == true).length,
                    studySeconds: storage.getStudyTime()[s.id] ?? 0,
                    onTap: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SubjectScreen(subject: s)),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ay/Gün/Saat/Dakika hassasiyetinde canlı geri sayım kartı — dakika
/// değiştikçe (ekranın geri kalanı yeniden çizilmeden) kendi kendine
/// güncellenir. Geri sayım metni yine `formatCountdown` tarafından üretilir;
/// burada yalnızca "12 Gün" gibi parçalara ayrılıp sayı büyük, birim küçük
/// olacak şekilde çizilir — hesaplama mantığı değişmez.
class _ExamCountdownCard extends StatefulWidget {
  final ExamInfo examInfo;
  const _ExamCountdownCard({required this.examInfo});

  @override
  State<_ExamCountdownCard> createState() => _ExamCountdownCardState();
}

class _ExamCountdownCardState extends State<_ExamCountdownCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final examInfo = widget.examInfo;
    final c = context.watch<ThemeProvider>().colors;
    final date = nextExamDate(examInfo);
    final countdown = formatCountdown(date);
    final dateStr = '${date.day} ${_monthName(date.month)}';
    final parts = _splitCountdown(countdown);

    return DsCard(
      accent: c.violet,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    DsIconBadge(
                      emoji: '📅',
                      color: c.violetL,
                      size: 38,
                      circle: false,
                      glow: false,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${examInfo.label} KPSS — $dateStr',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textFaint),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Sınava kalan süre',
                    style: TextStyle(fontSize: 11.5, color: c.textFaint)),
                const SizedBox(height: 4),
                if (parts.isEmpty)
                  // "Sınav bugün! 🎯" gibi parçalanamayan metin olduğu gibi.
                  Text(countdown,
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w900, color: c.text))
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      for (final p in parts)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(p.$1,
                                style: TextStyle(
                                    fontSize: 34,
                                    height: 1.05,
                                    fontWeight: FontWeight.w900,
                                    color: c.text)),
                            const SizedBox(width: 3),
                            Text(p.$2,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: c.textFaint)),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DsIllustration(emoji: '⏳', size: 76, glowColor: c.violetL),
        ],
      ),
    );
  }

  /// `formatCountdown` çıktısını ("2 Ay 5 Gün 3 Saat 20 Dk") (değer, birim)
  /// ikililerine böler. Beklenmedik bir biçim gelirse boş liste döner ve
  /// metin olduğu gibi gösterilir.
  static List<(String, String)> _splitCountdown(String text) {
    final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.length < 2 || tokens.length.isOdd) return const [];
    final out = <(String, String)>[];
    for (var i = 0; i + 1 < tokens.length; i += 2) {
      if (int.tryParse(tokens[i]) == null) return const [];
      out.add((tokens[i], tokens[i + 1]));
    }
    return out;
  }

  static String _monthName(int m) {
    const names = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    return names[m - 1];
  }
}

/// Anasayfa banner'ı — kullanıcı hesaba giriş yapmamışsa gösterilir ve
/// giriş yapmanın getirdiği artıları özetler.
class _LoginBanner extends StatelessWidget {
  const _LoginBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsBannerCard(
      icon: Icons.lock_outline,
      accent: c.violet,
      title: 'Hesabını koru, ilerlemeni kaybetme!',
      subtitle: 'Sohbette gerçek adınla mesajlaş, ilerlemen hesabına bağlansın.',
      actionLabel: 'Giriş Yap',
      onAction: () {
        context.read<SoundService>().click();
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AccountLoginScreen()));
      },
    );
  }
}

/// Anasayfadaki üç sütunlu istatistik şeridi. Değerlerin hepsi çağıran
/// taraftan (mevcut hesaplamalardan) gelir.
class _HomeStatsStrip extends StatelessWidget {
  final int rate;
  final int solved;
  final int doneTopics;
  final int totalTopics;

  const _HomeStatsStrip({
    required this.rate,
    required this.solved,
    required this.doneTopics,
    required this.totalTopics,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsStatStrip(
      items: [
        DsStatItem(
          // Dairesel ilerleme halkasının ortasında yüzde değeri.
          visual: SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: (rate / 100).clamp(0.0, 1.0),
                    strokeWidth: 5.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: c.border,
                    valueColor: AlwaysStoppedAnimation<Color>(c.violetL),
                  ),
                ),
                Text('%$rate',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900, color: c.text)),
              ],
            ),
          ),
          value: '',
          label: 'Genel Başarı',
          sublabel: 'Ortalama',
        ),
        DsStatItem(
          visual: DsIconBadge(emoji: '📋', color: c.gold, size: 44, glow: false),
          value: '$solved',
          label: 'Çözülen Soru',
          sublabel: 'Toplam',
        ),
        DsStatItem(
          visual: DsIconBadge(
              icon: Icons.check_rounded, color: c.success, size: 44, glow: false),
          value: '$doneTopics/$totalTopics',
          label: 'Konu',
          sublabel: 'Tamamlanan',
        ),
      ],
    );
  }
}

/// Anasayfa'daki "Beni Sına" kartı — kısa bir teşhis (yerleştirme) sınavına
/// giden davetkâr giriş noktası (bkz. placement_exam_screen.dart,
/// placement_result_screen.dart). Kullanıcı testi daha önce hiç tamamlamadıysa
/// ("hasTakenPlacementExam" — bkz. storage_service.dart) daha davetkâr bir
/// metin/başlık gösterir; bir kez tamamladıktan sonra kart kaybolmaz (her
/// zaman ulaşılabilir kalması gerekiyor) ama daha sakin bir "Tekrar Sına"
/// tonuna geçer — böylece kullanıcı agresif biçimde tekrar tekrar davet
/// edilmiş gibi hissetmez.
class _BeniSinaCard extends StatelessWidget {
  final bool alreadyTaken;
  final List<Subject> subjects;
  const _BeniSinaCard({required this.alreadyTaken, required this.subjects});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsBannerCard(
      emoji: '🎯',
      accent: c.mint,
      title: 'Beni Sına',
      subtitle: alreadyTaken
          ? 'Güncel seviyeni görmek için kısa teşhis testini tekrar çöz.'
          : 'Her dersten birkaç soruyla nerede güçlü, nerede eksik olduğunu 5 dakikada öğren!',
      actionLabel: alreadyTaken ? 'Tekrar Sına →' : 'Beni Sına →',
      filledAction: false,
      onAction: () {
        context.read<SoundService>().click();
        // Tam Deneme Sınavı/"yarıda kalan test" ile AYNI desen: quiz
        // akışı (ve bu akışın kısa yükleme ekranı) alt navigasyon
        // çubuğunun üstünde, KÖK Navigator'da açılır (bkz.
        // main_shell.dart üstteki açıklama) — bu yüzden burada da
        // pushReplacement DEĞİL, kök navigator'a push kullanılıyor;
        // PlacementExamScreen kendi içinde quiz'e geçerken zaten
        // AYNI kök navigator üzerinde pushReplacement yapıyor (bkz.
        // placement_exam_screen.dart).
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (_) => PlacementExamScreen(subjects: subjects)));
      },
    );
  }
}

/// Sunucudaki soru içeriği güncellendiğinde (bkz. _checkContentUpdate)
/// gösterilen bildirim kartı — Ayarlar'a yönlendirip "Tüm Soruları İndir"i
/// hatırlatır.
class _ContentUpdateBanner extends StatelessWidget {
  final KpssColors colors;
  final DateTime updatedAt;
  const _ContentUpdateBanner({required this.colors, required this.updatedAt});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: colors.gold.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('🆕', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Yeni sorular eklendi!', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text('Çevrimdışı da güncel kalman için Ayarlar\'dan tekrar indir.',
                      style: TextStyle(fontSize: 11.5, color: colors.text.withValues(alpha: 0.75))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anasayfa kartı — yarıda kalmış (bitirilmemiş) bir test varsa gösterilir.
/// QuizEngine._saveDraft() her cevapta otomatik güncellendiği için, kullanıcı
/// bir testi bitirmeden çıkarsa taslak burada yakalanıp devam ettirilebilir.
class _DraftResumeCard extends StatelessWidget {
  final String draftKey;
  final Map<String, dynamic> draft;
  final KpssColors colors;
  const _DraftResumeCard({required this.draftKey, required this.draft, required this.colors});

  @override
  Widget build(BuildContext context) {
    final topicBaslik = draft['topicBaslik'] as String? ?? 'Test';
    final questions = draft['questions'] as List? ?? const [];
    final answers = draft['answers'] as List? ?? const [];
    final answeredCount = answers.where((a) => a != null).length;

    return Card(
      color: colors.warn.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⏸️ Yarıda kalan testin var: $topicBaslik',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 4),
            Text('$answeredCount / ${questions.length} soru cevaplanmış.',
                style: TextStyle(fontSize: 12, color: colors.textFaint)),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {
                    context.read<SoundService>().click();
                    context.read<QuizEngine>().restoreFromDraft(draft);
                    Navigator.of(context, rootNavigator: true)
                        .push(MaterialPageRoute(builder: (_) => const QuizScreen.resume()));
                  },
                  child: const Text('Devam Et →'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    context.read<SoundService>().click();
                    context.read<StorageService>().clearDraft(draftKey);
                  },
                  child: const Text('Sil'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sağ üstteki profil butonu — kullanıcının baş harfini gradyan bir dairede
/// gösteren şık, yuvarlak bir avatar.
class _ProfileAvatarButton extends StatelessWidget {
  final String name;
  final VoidCallback onTap;
  const _ProfileAvatarButton({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final trimmed = name.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '\u{1F642}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.violet, c.rose],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: c.violet.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Saniyeyi "1sa 20dk" / "45dk" gibi kısa okunur bir süreye çevirir.
String _fmtStudyShort(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 1) return '0dk';
  final h = minutes ~/ 60, m = minutes % 60;
  return h > 0 ? '${h}sa ${m}dk' : '${m}dk';
}

class _SubjectCard extends StatelessWidget {
  final Subject subject;
  final int completedCount;
  final int studySeconds;
  final VoidCallback onTap;
  const _SubjectCard({
    required this.subject,
    required this.completedCount,
    required this.studySeconds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final palette = subjectPaletteFor(subject.id);
    final toplam = subject.konular.length;
    return Container(
      decoration: subjectCardDecoration(
        palette: palette,
        isLight: c.isLight,
        radius: kDsRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kDsRadius),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.icon, style: const TextStyle(fontSize: 24)),
                    const Spacer(),
                    // Süre çipi yalnızca gerçekten çalışma süresi varsa.
                    if (studySeconds > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: c.glass2,
                          border: Border.all(color: c.border),
                        ),
                        child: Text(
                          '⏱ ${_fmtStudyShort(studySeconds)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w700, color: c.textDim),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Text(
                    subject.ad,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14.5, color: c.text),
                  ),
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DsProgressBar(
                            value: toplam == 0 ? 0 : completedCount / toplam,
                            color: palette.b,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$completedCount/$toplam konu',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: c.textDim),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.glass2,
                        border: Border.all(color: palette.a.withValues(alpha: 0.55)),
                      ),
                      child: Icon(Icons.arrow_forward, size: 15, color: c.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Anasayfadaki yan yana hızlı erişim kartı (Akılda Kalıcı Kodlama /
/// Mentörlük). Dokununca ilgili sayfayı açar.
class _HizliErisimKarti extends StatelessWidget {
  final String emoji;
  final String baslik;
  final Color renk;
  final VoidCallback onTap;
  const _HizliErisimKarti({
    required this.emoji,
    required this.baslik,
    required this.renk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      accent: renk,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          DsIconBadge(emoji: emoji, color: renk, size: 40, glow: false),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              baslik,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: c.textFaint),
        ],
      ),
    );
  }
}
