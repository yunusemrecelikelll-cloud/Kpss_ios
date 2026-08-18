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
import '../widgets/davet_kazan_karti.dart';
import '../widgets/hak_kazan_sheet.dart';
import '../services/storage_service.dart';
import '../services/sound_service.dart';
import '../services/league_service.dart';
import '../services/remote_question_service.dart';
import '../theme/design_system.dart';
import '../theme/subject_colors.dart';
import '../theme/theme_provider.dart';
import '../utils/exam_dates.dart';
import '../utils/ust_bildirim.dart';
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
import 'hak_satin_al_screen.dart';
import 'ders_bildirim_screen.dart';
import 'notlar_screen.dart';
import '../services/karalama_not_service.dart';
import 'mentor_screen.dart';
import 'mnemonics_screen.dart';
import 'predictor_screen.dart';
import 'score_calculator_screen.dart';
import 'league_screen.dart';
import 'detailed_stats_screen.dart';

/// Ücretsiz pakette 120 soruluk TAM DENEME sınavı hakkı (toplam, günlük değil).
/// Deneme sınavı uygulamanın en ağır içeriği olduğu için ücretsiz tarafta
/// tek denemeyle sınırlı.
const int kFreeMaxFullTestAttempts = 1;

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
      ustBildirim('Yeterli soru yüklenemedi.', tur: UstBildirimTuru.hata);
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
            : (epostaOnEki.isNotEmpty ? epostaOnEki : 'Aday'));
    final premium = storage.isPremiumUser();
    final overall = storage.computeOverall();
    final completed = storage.getCompletedTopics();
    final totalTopics = subjects.fold(0, (s, x) => s + x.konular.length);
    final doneTopics = subjects.fold(0, (s, x) => s + x.konular.where((t) => completed[t.id] == true).length);
    final attempts = storage.getAttempts();
    final fullTestDone = attempts.where((a) => a.topicId == 'full-test').length;
    final examInfo = examInfoFor(storage.getExamType());
    final drafts = storage.getAllDrafts();

    return Scaffold(
      appBar: AppBar(
        // Renkli gradyan başlık (kullanıcı isteği): okul rozeti + "KPSS Hazırlık"
        // mor→gül→altın gradyanıyla boyanır (ShaderMask, srcIn).
        title: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [c.violet, c.roseL, c.gold],
          ).createShader(rect),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school_rounded, size: 23, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                'KPSS Hazırlık',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: 0.2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Üstte hak sayısı + "＋" (Hak Satın Al'a yönlendirir). Premium'da
          // hak sistemi tümüyle gizli (sınırsız) — bu çip de gösterilmez.
          if (!premium)
            _HakChip(
              haklar: storage.getHaklar(),
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const HakSatinAlScreen()));
              },
            ),
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
      // Kullanıcı isteği: anasayfa RENGARENK, her bölüm farklı premium renk
      // üstünde dursun. Dikey çok renkli (mor→gül→altın→nane) düşük saydamlıklı
      // gradyan zemin — kaydırdıkça her bölüm ayrı renk bandında görünür.
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                  c.violet.withValues(alpha: c.isLight ? 0.11 : 0.18), c.bg),
              Color.alphaBlend(
                  c.rose.withValues(alpha: c.isLight ? 0.10 : 0.16), c.bg),
              Color.alphaBlend(
                  c.gold.withValues(alpha: c.isLight ? 0.10 : 0.15), c.bg),
              Color.alphaBlend(
                  c.mint.withValues(alpha: c.isLight ? 0.09 : 0.14), c.bg),
              c.bg,
            ],
            stops: const [0.0, 0.28, 0.52, 0.76, 1.0],
          ),
        ),
        child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1) ÜST ŞERİT — "Kalan süre" + "Merhaba" yan yana, kompakt.
            // NOT: IntrinsicHeight yerine SABİT (metin ölçeğiyle ölçeklenen)
            // yükseklik kullanılıyor — IntrinsicHeight, alt piksel yuvarlama
            // yüzünden "BOTTOM OVERFLOWED BY 1.0 px" hatasına yol açıyordu.
            // Sabit yükseklik + stretch: iki kart tam eşit boyda ve taşmasız.
            SizedBox(
              height: 128 *
                  (MediaQuery.textScalerOf(context).scale(14) / 14)
                      .clamp(1.0, 1.7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (examInfo != null) ...[
                    Expanded(child: _KalanSureMini(examInfo: examInfo)),
                    const SizedBox(width: kDsGap),
                  ],
                  Expanded(child: _MerhabaMini(name: name, premium: premium)),
                ],
              ),
            ),
            const SizedBox(height: kDsGap),
            // 2) Giriş banner'ı — anonim oturum "girişli" SAYILMAZ; gerçek
            // hesabı olmayan herkese giriş daveti gösterilmeye devam eder.
            if (!auth.isRealSignedIn) ...[
              const _LoginBanner(),
              const SizedBox(height: kDsGap),
            ],
            if (_newContentAvailableAt != null) ...[
              _ContentUpdateBanner(updatedAt: _newContentAvailableAt!),
              const SizedBox(height: kDsGap),
            ],
            for (final entry in drafts.entries) ...[
              _DraftResumeCard(draftKey: entry.key, draft: entry.value),
              const SizedBox(height: kDsGap),
            ],
            // 3) Premium özet / "geç" widget'ı (kullanıcı isteği): premium'da
            // durum özeti, ücretsizde yükseltme daveti. Tek kompakt kart.
            _PremiumOzetKarti(premium: premium),
            const SizedBox(height: kDsGap),
            // 3b) Davet Et & Kazan (kullanıcı isteği): davet kodu + kazanımlar +
            // kalan bonus premium süresi.
            const DavetKazanKarti(),
            const SizedBox(height: kDsGap),
            // 4) Günlük Çalışma Planı kartı.
            const StudyPlanCard(),
            const SizedBox(height: kDsGap),
            // Ders Bildirimleri (kullanıcı isteği: ana sayfaya taşındı, Premium'a
            // özel). Ücretsiz kullanıcı kartı soluk + "premium" rozetli görür;
            // dokununca DersBildirimScreen kilitli vitrini açar.
            wrapPremiumKart(
              context,
              DsCard(
                accent: c.violet,
                onTap: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DersBildirimScreen()));
                },
                child: Row(
                  children: [
                    DsIconBadge(
                        icon: Icons.notifications_active_rounded,
                        color: c.violet,
                        size: 44,
                        glow: false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Ders Bildirimleri',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                  color: c.text)),
                          const SizedBox(height: 2),
                          Text(
                            'İstediğin dersten, istediğin saatte akılda kalıcı '
                            'kodlama, motivasyon ve "bunu biliyor musun?" bildirimi al.',
                            style: TextStyle(fontSize: 12, color: c.textDim),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.textFaint),
                  ],
                ),
              ),
              true,
            ),
            const SizedBox(height: kDsGap),
            // 5) Hızlı erişim: Akılda Kalıcı Kodlama + Mentörlük.
            Row(
              children: [
                Expanded(
                  child: _HizliErisimKarti(
                    emoji: '🧠',
                    baslik: 'Akılda Kalıcı\nKodlama',
                    renk: c.mint,
                    premiumOzellik: true,
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
                    premiumOzellik: true,
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
            // 6) Kompakt aksiyon kartları — Akılda Kalıcı Kodlama kartlarıyla
            // AYNI boy/stil, yazı ORTALI (kullanıcı isteği: "Durumun" başlığı
            // yok; yazılar yan yana, ortalı, aynı boyutta). 2 satır × 2.
            Row(
              children: [
                Expanded(
                  child: _MiniAksiyonKarti(
                    emoji: '🎯',
                    baslik: 'Bugün Girsen Kaç Alırsın',
                    renk: c.violet,
                    premiumOzellik: true,
                    onTap: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const PredictorScreen()));
                    },
                  ),
                ),
                const SizedBox(width: kDsGap),
                Expanded(
                  child: _MiniAksiyonKarti(
                    emoji: '🧮',
                    baslik: 'Puan Hesaplama',
                    // Kullanıcı isteği: Akılda Kalıcı Kodlama (mint) ile AYNI
                    // renk olmasın; her kart farklı renk.
                    renk: c.rose,
                    onTap: () {
                      context.read<SoundService>().click();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ScoreCalculatorScreen()));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: kDsGap),
            // Geniş Lig widget'ı (kullanıcı isteği: çalışma planı kadar geniş;
            // üzerinde KAÇINCI SIRADA + HANGİ LİGDE olduğu yazar; dokununca lig
            // sayfasına gider).
            const _LigWidget(),
            const SizedBox(height: kDsGap),
            _MiniAksiyonKarti(
              emoji: '📈',
              baslik: 'İstatistik',
              renk: c.success,
              onTap: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const DetailedStatsScreen()));
              },
            ),
            const SizedBox(height: kDsGap),
            // 7) En iyi / en zayıf ders özeti (kullanıcı isteği).
            _EnIyiZayifDersKarti(subjects: subjects),
            const SizedBox(height: kDsGap),
            // 8) İstatistik şeridi (genel başarı / çözülen / konu).
            _HomeStatsStrip(
              rate: overall.rate,
              solved: overall.solved,
              doneTopics: doneTopics,
              totalTopics: totalTopics,
            ),
            const SizedBox(height: kDsGap),
            // 9) "Beni Sına" banner'ı.
            _BeniSinaCard(
              alreadyTaken: storage.hasTakenPlacementExam,
              subjects: subjects,
            ),
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
                // Dersler ızgarasında Türkçe'nin YANINA "Notlar" kartı
                // (kullanıcı isteği): önizlemesi son kaydedilen not.
                _NotlarKarti(
                  onTap: () async {
                    context.read<SoundService>().click();
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const NotlarScreen()));
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// KOMPAKT canlı geri sayım kartı (üst şeritte "Merhaba" ile yan yana durur).
/// Ay+Gün hassasiyetinde (bkz. formatCountdown — kullanıcı isteğiyle saat/dk
/// kaldırıldı); dakika değiştikçe kendi kendine tazelenir. Yarım genişlikte
/// olduğu için illüstrasyon yok, sayı büyük/birim küçük tek sütun.
class _KalanSureMini extends StatefulWidget {
  final ExamInfo examInfo;
  const _KalanSureMini({required this.examInfo});

  @override
  State<_KalanSureMini> createState() => _KalanSureMiniState();
}

class _KalanSureMiniState extends State<_KalanSureMini> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Ay+Gün gösterildiği için sık tazelemeye gerek yok; gün dönümünü
    // yakalamak adına dakikada bir yeterli.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
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
      padding: const EdgeInsets.all(14),
      // spaceBetween + max: sabit yükseklikte taşmasız (bkz. _MerhabaMini notu).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text('📅', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('SINAVA KALAN',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: c.textFaint)),
              ),
            ],
          ),
          if (parts.isEmpty)
            Text(countdown,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: c.text))
          else
            Wrap(
              spacing: 8,
              runSpacing: 0,
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
                              fontSize: 30,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              color: c.text)),
                      const SizedBox(width: 2),
                      Text(p.$2,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: c.textFaint)),
                    ],
                  ),
              ],
            ),
          Text('${examInfo.label} • $dateStr',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c.textFaint)),
        ],
      ),
    );
  }

  /// `formatCountdown` çıktısını ("2 Ay 5 Gün") (değer, birim) ikililerine
  /// böler. Beklenmedik bir biçim gelirse boş liste döner ve metin olduğu gibi
  /// gösterilir.
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

/// KOMPAKT karşılama kartı — üst şeritte "Kalan süre" ile yan yana durur.
/// Adıyla selamlar ve plan rozetini (PREMIUM/ÜCRETSİZ) gösterir.
class _MerhabaMini extends StatelessWidget {
  final String name;
  final bool premium;
  const _MerhabaMini({required this.name, required this.premium});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      accent: premium ? c.gold : c.mint,
      padding: const EdgeInsets.all(14),
      // spaceBetween + max: içerik sabit yüksekliğe göre dağıtılır; çocukların
      // toplam yüksekliği alandan küçük olduğu için ASLA taşmaz (IntrinsicHeight
      // 1px taşma hatasının kalıcı çözümü).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text('👋', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('MERHABA',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: c.textFaint)),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                      fontSize: 21, fontWeight: FontWeight.w700, color: c.text)),
              Text('Hazır mısın? ✨',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.textDim)),
            ],
          ),
          DsChip(
            label: premium ? '👑 PREMIUM' : 'ÜCRETSİZ',
            color: premium ? c.gold : c.violetL,
          ),
        ],
      ),
    );
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
  final DateTime updatedAt;
  const _ContentUpdateBanner({required this.updatedAt});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return DsCard(
      accent: c.gold,
      onTap: () {
        context.read<SoundService>().click();
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      },
      child: Row(
        children: [
          DsIconBadge(emoji: '🆕', color: c.gold, size: 42, glow: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Yeni sorular eklendi!',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14, color: c.text)),
                const SizedBox(height: 3),
                Text('Çevrimdışı da güncel kalman için Ayarlar\'dan tekrar indir.',
                    style: TextStyle(fontSize: 11.5, height: 1.3, color: c.textDim)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DsChip(label: 'Güncelle', color: c.gold),
        ],
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
  const _DraftResumeCard({required this.draftKey, required this.draft});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final topicBaslik = draft['topicBaslik'] as String? ?? 'Test';
    final questions = draft['questions'] as List? ?? const [];
    final answers = draft['answers'] as List? ?? const [];
    final answeredCount = answers.where((a) => a != null).length;
    final oran = questions.isEmpty ? 0.0 : answeredCount / questions.length;

    // Kullanıcı isteği: göz alıcı parlak sarı YERİNE daha LOŞ ama özellikle
    // Gece Yarısı (koyu) temasında OKUNUR bir ton. Griye harmanlamak yerine
    // uyarı renginin hue'sü korunur, parlaklık/doygunluk düşürülerek koyu
    // zeminde net okunan dinlendirici bir altın elde edilir.
    final bool koyuTema = !c.isLight;
    final Color los = HSLColor.fromColor(c.warn)
        .withSaturation(koyuTema ? 0.60 : 0.64)
        .withLightness(koyuTema ? 0.52 : 0.44)
        .toColor();

    return DsCard(
      accent: los,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DsIconBadge(emoji: '⏸️', color: los, size: 44, glow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Yarıda kalan testin var',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: c.text)),
                    const SizedBox(height: 2),
                    Text(topicBaslik,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textDim)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DsProgressBar(value: oran.clamp(0.0, 1.0), color: los),
          const SizedBox(height: 6),
          Text('$answeredCount / ${questions.length} soru cevaplanmış',
              style: TextStyle(fontSize: 11.5, color: c.textFaint)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DsPillButton(
                  label: 'Devam Et',
                  color: los,
                  trailingIcon: Icons.arrow_forward,
                  onPressed: () {
                    context.read<SoundService>().click();
                    context.read<QuizEngine>().restoreFromDraft(draft);
                    Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(builder: (_) => const QuizScreen.resume()));
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Kullanıcı isteği: Sil butonu arkaplanı KIRMIZI (dolgulu).
              DsPillButton(
                label: 'Sil',
                color: c.danger,
                onPressed: () {
                  context.read<SoundService>().click();
                  context.read<StorageService>().clearDraft(draftKey);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Üst bardaki HAK göstergesi: mevcut hak sayısı + "＋" düğmesi. Dokununca
/// Hak Satın Al ekranına gider. YALNIZCA ücretsiz kullanıcıda gösterilir
/// (premium'da hak sistemi tümüyle gizlidir — çağıran yer `if (!premium)` ile
/// sarar).
class _HakChip extends StatelessWidget {
  final int haklar;
  final VoidCallback onTap;
  const _HakChip({required this.haklar, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: c.violet.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎟️', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text('$haklar',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 14, color: c.text)),
                const SizedBox(width: 5),
                Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.violet, shape: BoxShape.circle),
                  child: const Icon(Icons.add, size: 14, color: Colors.white),
                ),
              ],
            ),
          ),
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
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Kullanıcı isteği: DAHA CANLI logo. Üç renkli (mor→gül→altın)
              // köşegen sweep gradyan + belirgin çift renkli parıltı.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.violet, c.rose, c.gold],
                stops: const [0.0, 0.55, 1.0],
              ),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85), width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: c.rose.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: c.violet.withValues(alpha: 0.30),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            alignment: Alignment.center,
            // "Farklı fontta kalın yazı tipi": başlık (Baloo2) ve gövdeden
            // (Nunito) ayrışan güçlü display fontu Righteous.
            child: Text(
              initial,
              style: GoogleFonts.righteous(
                color: Colors.white,
                fontSize: 19,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
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

/// Dersler ızgarasında Türkçe'nin yanındaki "Notlar" kartı — _SubjectCard ile
/// AYNI boyutta (ızgara hücresi). Önizlemesi son kaydedilen notun içeriğidir
/// (çizim ya da yazı).
class _NotlarKarti extends StatelessWidget {
  final Future<void> Function() onTap;
  const _NotlarKarti({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final notlar = KaralamaNotService().getir(storage);
    final sonNot = notlar.isNotEmpty ? notlar.first : null;
    const palette = SubjectPalette(Color(0xFFF59E0B), Color(0xFFB45309));
    return Container(
      decoration: subjectCardDecoration(
          palette: palette, isLight: c.isLight, radius: kDsRadius),
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
                    const Text('📝', style: TextStyle(fontSize: 24)),
                    const Spacer(),
                    if (notlar.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: c.glass2,
                          border: Border.all(color: c.border),
                        ),
                        child: Text('${notlar.length} not',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: c.textDim)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Notlar',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: c.text)),
                const SizedBox(height: 6),
                Expanded(
                  child: sonNot == null
                      ? Text(
                          'Testlerde yaz/çiz ve "Kaydet" de; notların burada.',
                          style: TextStyle(fontSize: 11, color: c.textFaint),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: c.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: KaralamaMiniOnizleme(not: sonNot),
                        ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(sonNot == null ? 'Boş' : 'Son not',
                        style: TextStyle(fontSize: 11, color: c.textDim)),
                    const Spacer(),
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.glass2,
                        border: Border.all(
                            color: palette.a.withValues(alpha: 0.55)),
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
/// Premium'a ÖZEL bir özellik kartına eklenen görsel işaretler. Kullanıcı
/// isteği (GÜNCEL): "premium" rozeti YALNIZCA ücretsiz kullanıcıda gösterilir;
/// kart ayrıca soluk (yarı saydam) çizilir. Premium açıldığında kart normale
/// döner ve "premium" yazısı KALKAR.
///
/// [kart]'ı sarıp döndürür. [premiumOzellik] false ise kartı aynen döndürür.
Widget wrapPremiumKart(BuildContext context, Widget kart, bool premiumOzellik) {
  if (!premiumOzellik) return kart;
  final c = context.watch<ThemeProvider>().colors;
  final premium = context.watch<StorageService>().isPremiumUser();
  // Premium kullanıcıda kart normale döner ve rozet HİÇ gösterilmez.
  if (premium) return kart;
  return Stack(
    children: [
      Opacity(opacity: 0.55, child: kart),
      Positioned(
        top: 4,
        right: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.gold, c.gold.withValues(alpha: 0.72)],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(color: c.gold.withValues(alpha: 0.40), blurRadius: 6),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium, size: 10, color: Colors.white),
              SizedBox(width: 3),
              Text('premium',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Hızlı erişim / mini aksiyon kartlarının RENKLİ zemin gradyanı. Kullanıcı
/// isteği: kartların arkaplan tasarımı değişsin ve renkleri BİRBİRİNDEN belirgin
/// biçimde farklı görünsün. Kartın kendi rengi + hafif hue kaydırılmış ikinci
/// tonla çift renkli yumuşak bir yıkama üretilir (metin okunaklı kalır).
Gradient _kartZeminGradyani(Color renk, bool isLight) {
  final hsl = HSLColor.fromColor(renk);
  final renk2 = hsl.withHue((hsl.hue + 26) % 360.0).toColor();
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      renk.withValues(alpha: isLight ? 0.22 : 0.34),
      renk2.withValues(alpha: isLight ? 0.09 : 0.15),
    ],
  );
}

class _HizliErisimKarti extends StatelessWidget {
  final String emoji;
  final String baslik;
  final Color renk;
  final VoidCallback onTap;
  final bool premiumOzellik;
  const _HizliErisimKarti({
    required this.emoji,
    required this.baslik,
    required this.renk,
    required this.onTap,
    this.premiumOzellik = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return wrapPremiumKart(
      context,
      DsCard(
        accent: renk,
        gradient: _kartZeminGradyani(renk, c.isLight),
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
      ),
      premiumOzellik,
    );
  }
}

/// Premium özet / "Premium'a geç" widget'ı (kullanıcı isteği). Tek kart iki
/// durumu da kapsar:
///  • Premium'da → altın vurgulu "Premium aktif" özeti (aboneliği yönet),
///  • Ücretsizde → mor vurgulu yükseltme daveti.
/// Her ikisinde de dokununca Premium ekranı açılır.
class _PremiumOzetKarti extends StatelessWidget {
  final bool premium;
  const _PremiumOzetKarti({required this.premium});

  @override
  Widget build(BuildContext context) {
    // Kullanıcı isteği: Premium banner ALTIN renginde ve ÖNE ÇIKAN olsun.
    // Koyu altın degrade zemin + ışıma + altın kenarlık; her temada belirgin.
    const altin1 = Color(0xFFE8C766);
    const altin2 = Color(0xFFC9962E);
    const altin3 = Color(0xFF8A6B1E);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kDsRadius),
        onTap: () {
          context.read<SoundService>().click();
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [altin1, altin2, altin3],
            ),
            borderRadius: BorderRadius.circular(kDsRadius),
            border: Border.all(color: const Color(0xFFFFE9A8), width: 1.2),
            boxShadow: [
              BoxShadow(
                  color: altin2.withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                ),
                child: Text(premium ? '👑' : '💎',
                    style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(premium ? '👑 Premium Aktif' : "Premium'a Geç",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF3A2B00),
                            letterSpacing: 0.2)),
                    const SizedBox(height: 3),
                    Text(
                        premium
                            ? 'Sınırsız erişim açık. Aboneliğini yönet.'
                            : 'Reklamsız, sınırsız soru, oyun ve gelişmiş analiz.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF3A2B00).withValues(alpha: 0.8))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  size: 22, color: Color(0xFF3A2B00)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kompakt aksiyon kartı — Akılda Kalıcı Kodlama kartlarıyla AYNI boy/stil
/// (emoji rozeti + başlık yan yana), yazı ORTALI. Dokununca ilgili ekrana gider.
/// Anasayfadaki GENİŞ Lig widget'ı (kullanıcı isteği). Kullanıcının bu haftaki
/// SIRA numarasını ve LİG kademesini gösterir; dokununca Lig ekranına gider.
/// Çevrimiçi karşılaştırma (giriş + internet) varsa gerçek sıra gelir; yoksa
/// yerel haftalık puandan kademe gösterilir, sıra "—" olur.
class _LigWidget extends StatefulWidget {
  const _LigWidget();

  @override
  State<_LigWidget> createState() => _LigWidgetState();
}

class _LigWidgetState extends State<_LigWidget> {
  Future<LeagueResult?>? _future;

  @override
  void initState() {
    super.initState();
    _future = LeagueService().computeMyLeagueTier(context.read<StorageService>());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final weekly = storage.getWeeklyPoints();
    final renk = c.gold;

    return FutureBuilder<LeagueResult?>(
      future: _future,
      builder: (context, snap) {
        final result = snap.data;
        final loading = snap.connectionState == ConnectionState.waiting;
        // Kademe: çevrimiçi sonuç varsa ondan, yoksa yerel puandan (aynı eşikler).
        final tier = result?.tier ?? tierForPoints(weekly);
        final rank = result?.myRank;

        final String altSatir;
        if (rank != null) {
          altSatir = '$rank. sıra • $weekly puan';
        } else if (loading) {
          altSatir = 'Sıralama yükleniyor…';
        } else {
          altSatir = '$weekly puan';
        }

        return DsCard(
          accent: renk,
          gradient: _kartZeminGradyani(renk, c.isLight),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          onTap: () {
            context.read<SoundService>().click();
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LeagueScreen()));
          },
          child: Row(
            children: [
              // Kademe rozeti (emoji)
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: renk.withValues(alpha: c.isLight ? 0.14 : 0.18),
                  border: Border.all(color: renk.withValues(alpha: 0.5), width: 1.4),
                ),
                child: Text(tier.icon, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🏆 HAFTALIK LİG',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: renk)),
                    const SizedBox(height: 2),
                    Text('${tier.label} Lig',
                        style: TextStyle(
                            fontSize: 16.5, fontWeight: FontWeight.w900, color: c.text)),
                    const SizedBox(height: 2),
                    Text(altSatir,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textDim)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Sıra numarası büyük (varsa) + ok
              if (rank != null) ...[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$rank.',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900, color: renk, height: 1.0)),
                    Text('sıra',
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700, color: c.textFaint)),
                  ],
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right_rounded, color: c.violetL),
            ],
          ),
        );
      },
    );
  }
}

class _MiniAksiyonKarti extends StatelessWidget {
  final String emoji;
  final String baslik;
  final Color renk;
  final VoidCallback onTap;
  final bool premiumOzellik;
  const _MiniAksiyonKarti({
    required this.emoji,
    required this.baslik,
    required this.renk,
    required this.onTap,
    this.premiumOzellik = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return wrapPremiumKart(
      context,
      DsCard(
        accent: renk,
        gradient: _kartZeminGradyani(renk, c.isLight),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DsIconBadge(emoji: emoji, color: renk, size: 40, glow: false),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                baslik,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: c.text,
                ),
              ),
            ),
          ],
        ),
      ),
      premiumOzellik,
    );
  }
}

/// En güçlü ve en zayıf ders özeti. Ders ortalaması (Attempt.skor)
/// [StorageService.computeSubjectAvg] ile bulunur; en az bir derste veri varsa
/// gösterilir. Hiç veri yoksa test çözmeye davet eder. Dokununca detaylı
/// istatistik ekranına gider.
class _EnIyiZayifDersKarti extends StatelessWidget {
  final List<Subject> subjects;
  const _EnIyiZayifDersKarti({required this.subjects});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();

    final veriler = <({String ad, String icon, int avg})>[];
    for (final s in subjects) {
      final avg = storage.computeSubjectAvg(s.id);
      if (avg != null) veriler.add((ad: s.ad, icon: s.icon, avg: avg));
    }
    veriler.sort((a, b) => b.avg.compareTo(a.avg));

    if (veriler.isEmpty) {
      return DsCard(
        accent: c.mint,
        child: Row(
          children: [
            DsIconBadge(emoji: '📚', color: c.mint, size: 44, glow: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Güçlü ve zayıf derslerin',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w900, color: c.text)),
                  const SizedBox(height: 2),
                  Text('Birkaç test çöz, en iyi ve en zayıf dersini burada göstereyim.',
                      style: TextStyle(fontSize: 11.5, height: 1.3, color: c.textDim)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final enIyi = veriler.first;
    final enZayif = veriler.last;
    final tekDers = veriler.length < 2;

    return DsCard(
      accent: c.success,
      onTap: () {
        context.read<SoundService>().click();
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const DetailedStatsScreen()));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Güçlü & Zayıf Ders',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w900, color: c.text)),
              const Spacer(),
              Icon(Icons.chevron_right, size: 18, color: c.textFaint),
            ],
          ),
          const SizedBox(height: 10),
          _DersSatiri(
            renk: c.success,
            etiket: 'En güçlü',
            icon: enIyi.icon,
            ad: enIyi.ad,
            avg: enIyi.avg,
          ),
          if (!tekDers) ...[
            const SizedBox(height: 8),
            _DersSatiri(
              renk: c.warn,
              etiket: 'En zayıf',
              icon: enZayif.icon,
              ad: enZayif.ad,
              avg: enZayif.avg,
            ),
          ],
        ],
      ),
    );
  }
}

/// _EnIyiZayifDersKarti içindeki tek ders satırı.
class _DersSatiri extends StatelessWidget {
  final Color renk;
  final String etiket;
  final String icon;
  final String ad;
  final int avg;
  const _DersSatiri({
    required this.renk,
    required this.etiket,
    required this.icon,
    required this.ad,
    required this.avg,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(etiket,
                  style: TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w800, color: renk)),
              Text(ad,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: renk.withValues(alpha: 0.16),
            border: Border.all(color: renk.withValues(alpha: 0.4)),
          ),
          child: Text('$avg puan',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900, color: c.text)),
        ),
      ],
    );
  }
}
