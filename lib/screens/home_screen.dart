import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/subject.dart';
import '../models/question.dart';
import '../models/badge.dart';
import '../services/auth_service.dart';
import '../services/quiz_engine.dart';
import '../services/storage_service.dart';
import '../services/sound_service.dart';
import '../services/remote_question_service.dart';
import '../theme/app_theme.dart';
import '../theme/subject_colors.dart';
import '../theme/theme_provider.dart';
import '../utils/exam_dates.dart';
import 'subject_screen.dart';
import 'quiz_screen.dart';
import 'profile_screen.dart';
import 'premium_screen.dart';
import 'score_distribution_screen.dart';
import 'account_login_screen.dart';
import 'duel/duel_lobby_screen.dart';
import 'settings_screen.dart';
import 'placement_exam_screen.dart';

const int kFreeMaxFullTestAttempts = 3;

/// Cinsiyete göre hitap eden anasayfa karşılama mesajı.
/// JS karşılığı: src/js/app.js içindeki _heroGreeting(gender, name).
String _heroGreetingFor(String gender, String name) {
  if (gender == 'k') return 'Merhaba Prensesim $name! Hazır mısın? 👸';
  if (gender == 'e') return 'Merhaba Aslanım $name! Hazır mısın? 🦁';
  return 'Merhaba, $name! Hazır mısın? 🌸';
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
    for (final b in newlyUnlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🏅 Yeni rozet: ${b.name}!'), duration: const Duration(seconds: 4)),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎁 Günlük giriş ödülün: +${StorageService.kDailyLoginRewardXp} XP!'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _startFullTest(BuildContext context) async {
    final storage = context.read<StorageService>();
    final premium = storage.isPremiumUser();
    if (!premium) {
      final done = storage.getAttempts().where((a) => a.topicId == 'full-test').length;
      if (done >= kFreeMaxFullTestAttempts) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Ücretsiz pakette $kFreeMaxFullTestAttempts deneme hakkın var. "
              "Sınırsız deneme için Premium'a geç."),
        ));
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
        return;
      }
    }

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
    // getActiveUser() sadece profil oluşturulurken bir kere set edilen ham
    // kullanıcı kaydı adı ("Misafir") — Google/Apple girişinden sonra
    // güncellenen GERÇEK isim getUserName()'de tutulur (bkz. profile_screen.dart
    // ile aynı öncelik: profil_screen.dart'ın kullandığı desenin AYNISI).
    final name = storage.getUserName().isNotEmpty ? storage.getUserName() : storage.getActiveUser();
    final gender = storage.getUserGender();
    final premium = storage.isPremiumUser();
    final overall = storage.computeOverall();
    final completed = storage.getCompletedTopics();
    final totalTopics = subjects.fold(0, (s, x) => s + x.konular.length);
    final totalQuestions = subjects.fold<int>(
        0, (s, x) => s + x.konular.fold<int>(0, (s2, t) => s2 + t.sorular.length));
    final doneTopics = subjects.fold(0, (s, x) => s + x.konular.where((t) => completed[t.id] == true).length);
    final fullTestDone = storage.getAttempts().where((a) => a.topicId == 'full-test').length;
    final examInfo = examInfoFor(storage.getExamType());
    final auth = context.watch<AuthService>();
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
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              DrawerHeader(
                child: Text('🌙 KPSS Hazırlık',
                    style: GoogleFonts.baloo2(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              ListTile(
                leading: const Text('💎'),
                title: const Text('Premium'),
                onTap: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                },
              ),
              ListTile(
                leading: const Text('📊'),
                title: const Text('Soru Dağılımı'),
                onTap: () {
                  context.read<SoundService>().click();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScoreDistributionScreen()));
                },
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (examInfo != null) _ExamCountdownBar(examInfo: examInfo),
            if (examInfo != null) const SizedBox(height: 12),
            if (!auth.isSignedIn) ...[
              _LoginBanner(colors: c),
              const SizedBox(height: 12),
            ],
            if (_newContentAvailableAt != null) ...[
              _ContentUpdateBanner(colors: c, updatedAt: _newContentAvailableAt!),
              const SizedBox(height: 12),
            ],
            for (final entry in drafts.entries) ...[
              _DraftResumeCard(draftKey: entry.key, draft: entry.value, colors: c),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_heroGreetingFor(gender, name),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('2026 KPSS hazırlığında bugün ne çalışmak istersin?'),
                    const SizedBox(height: 10),
                    Chip(label: Text(premium ? 'Premium' : 'Ücretsiz')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatCard(icon: '🎯', value: '${overall.rate}%', label: 'Genel Başarı')),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(icon: '📝', value: '${overall.solved}', label: 'Çözülen Soru')),
                const SizedBox(width: 10),
                Expanded(child: _StatCard(icon: '✅', value: '$doneTopics/$totalTopics', label: 'Konu')),
              ],
            ),
            const SizedBox(height: 16),
            _BeniSinaCard(
              colors: c,
              alreadyTaken: storage.hasTakenPlacementExam,
              subjects: subjects,
            ),
            if (!premium) ...[
              const SizedBox(height: 16),
              Card(
                color: c.violet.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💎 Ek ayrıcalıklar ve daha fazla soru için Premium\'a geç!',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                      const SizedBox(height: 6),
                      Text('$totalQuestions soruluk tam soru bankası, sınırsız test, oyunlar ve daha fazlası.',
                          style: TextStyle(fontSize: 12, color: c.textFaint)),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () {
                          context.read<SoundService>().click();
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
                        },
                        child: const Text("Premium'a Geç →"),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              color: c.gold.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🎯 Tam Deneme Sınavı', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text('Gerçek KPSS formatında 120 soru', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      premium
                          ? '✨ Sınırsız deneme hakkın var'
                          : '${(kFreeMaxFullTestAttempts - fullTestDone).clamp(0, kFreeMaxFullTestAttempts)} / $kFreeMaxFullTestAttempts deneme hakkın kaldı',
                      style: TextStyle(fontSize: 12, color: c.warn),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _startingFullTest
                          ? null
                          : () {
                              context.read<SoundService>().click();
                              _startFullTest(context);
                            },
                      child: _startingFullTest
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sınava Gir ➜'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: c.rose.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('⚔️ KPSS Düello',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.rose.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('POPÜLER',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: c.rose)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Rakiplerinle canlı yarış: 1v1 Düello veya çok kişilik Royale',
                        style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        context.read<SoundService>().click();
                        Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => const DuelLobbyScreen()));
                      },
                      child: const Text('Düelloya Gir ➜'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Dersler', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.3,
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

/// Ay/Gün/Saat/Dakika hassasiyetinde canlı geri sayım — dakika değiştikçe
/// (ekranın geri kalanı yeniden çizilmeden) kendi kendine güncellenir.
class _ExamCountdownBar extends StatefulWidget {
  final ExamInfo examInfo;
  const _ExamCountdownBar({required this.examInfo});

  @override
  State<_ExamCountdownBar> createState() => _ExamCountdownBarState();
}

class _ExamCountdownBarState extends State<_ExamCountdownBar> {
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14)],
        ),
      ),
      child: Column(
        children: [
          Text('📅 ${examInfo.label} KPSS — $dateStr', style: TextStyle(fontSize: 12, color: c.textDim)),
          const SizedBox(height: 2),
          Text('Sınava kalan süre: $countdown',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
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
  final KpssColors colors;
  const _LoginBanner({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: colors.violet.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('🔐', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Giriş yap, kaybolma!', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text('Sohbette gerçek adınla mesajlaş, ilerlemen hesabına bağlansın.',
                      style: TextStyle(fontSize: 11.5, color: colors.textFaint)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                context.read<SoundService>().click();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountLoginScreen()));
              },
              child: const Text('Giriş Yap'),
            ),
          ],
        ),
      ),
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
  final KpssColors colors;
  final bool alreadyTaken;
  final List<Subject> subjects;
  const _BeniSinaCard({required this.colors, required this.alreadyTaken, required this.subjects});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: colors.mint.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(alreadyTaken ? '🎯 Beni Sına' : '🎯 Beni Sına',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                if (!alreadyTaken) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.mint.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('YENİ',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: colors.mint)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              alreadyTaken
                  ? 'Güncel seviyeni görmek için kısa teşhis testini tekrar çöz.'
                  : 'Her dersten birkaç soruyla nerede güçlü, nerede eksik olduğunu 5 dakikada öğren!',
              style: TextStyle(fontSize: 12, color: colors.textFaint),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
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
              child: Text(alreadyTaken ? 'Tekrar Sına →' : 'Beni Sına →'),
            ),
          ],
        ),
      ),
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

class _StatCard extends StatelessWidget {
  final String icon, value, label;
  const _StatCard({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
          ],
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
    return Container(
      decoration: subjectCardDecoration(palette: palette, isLight: c.isLight),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(subject.icon, style: const TextStyle(fontSize: 22)),
                    const Spacer(),
                    if (studySeconds > 0)
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, size: 12, color: c.textFaint),
                          const SizedBox(width: 2),
                          Text(_fmtStudyShort(studySeconds), style: TextStyle(fontSize: 10.5, color: c.textFaint)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(subject.ad, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const Spacer(),
                LinearProgressIndicator(
                  value: subject.konular.isEmpty ? 0 : completedCount / subject.konular.length,
                  backgroundColor: palette.a.withValues(alpha: c.isLight ? 0.14 : 0.20),
                  valueColor: AlwaysStoppedAnimation(palette.b),
                ),
                const SizedBox(height: 4),
                Text('$completedCount/${subject.konular.length} konu', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
