import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/subject.dart';
import '../../services/data_service.dart';
import '../../services/duel_service.dart';
import '../../services/remote_question_service.dart';
import '../../services/sound_service.dart';
import '../../services/storage_service.dart';
import '../../theme/theme_provider.dart';
import '../premium_screen.dart';
import '../tools_hub_screen.dart' show HowToPlayButton, formatPlayDuration, kFreeGameDailyLimit;
import 'duel_play_screen.dart';
import 'duel_waiting_room_screen.dart';

/// Düello/Royale günlük ücretsiz maç sayacı için oyun kimliği
/// (StorageService.getGamePlayState/useGamePlay).
const String kDuelloGameId = 'duello';

/// KPSS Düello & Royale giriş/lobi ekranı — oyuncu adı, mod seçimi, oda kur /
/// özel odaya katıl / tek başına yarış butonları ve canlı açık odalar listesi.
class DuelLobbyScreen extends StatefulWidget {
  const DuelLobbyScreen({super.key});

  @override
  State<DuelLobbyScreen> createState() => _DuelLobbyScreenState();
}

class _DuelLobbyScreenState extends State<DuelLobbyScreen> {
  final DuelService _duel = DuelService();
  late final TextEditingController _nameCtrl;
  String _mode = DuelService.modeDuello;
  List<Subject> _subjects = const [];
  bool _loadingSubjects = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Kayıtlı kullanıcı adı varsa onu, yoksa rastgele bir oyuncu adı öner.
    final storage = context.read<StorageService>();
    final existing = storage.getUserName();
    _nameCtrl = TextEditingController(
      text: existing.isNotEmpty ? existing : _duel.generateRandomPlayerName(),
    );
    context.read<DataService>().loadAll().then((s) {
      if (!mounted) return;
      setState(() {
        _subjects = s.where((x) => x.konular.isNotEmpty).toList();
        _loadingSubjects = false;
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String get _playerName {
    final n = _nameCtrl.text.trim();
    return n.isEmpty ? 'Oyuncu' : n;
  }

  /// Ücretsiz kullanıcı için günlük hak kontrolü; hak yoksa Premium'a yönlendirir
  /// ve false döner. Hak varsa bir hak tüketir ve true döner.
  Future<bool> _consumePlayOrGate() async {
    final storage = context.read<StorageService>();
    if (storage.isPremiumUser()) return true;
    final state = storage.getGamePlayState(kDuelloGameId);
    final left = (kFreeGameDailyLimit - (state['plays'] as int)).clamp(0, kFreeGameDailyLimit);
    if (left <= 0) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Bugünkü ücretsiz Düello hakkın bitti '
            '($kFreeGameDailyLimit/gün). Sınırsız için Premium\'a geç.'),
      ));
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
      return false;
    }
    await storage.useGamePlay(kDuelloGameId);
    return true;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _createRoom() async {
    if (!_duel.isConfigured) {
      _snack('Çok oyunculu mod için internet bağlantısı gerekli. '
          '"Tek Başına Yarış"ı deneyebilirsin.');
      return;
    }
    final cfg = await showModalBottomSheet<_RoomConfig>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateRoomSheet(mode: _mode, subjects: _subjects),
    );
    if (cfg == null || !mounted) return;
    if (!await _consumePlayOrGate()) return;
    if (!mounted) return;
    final remote = context.read<RemoteQuestionService>();
    setState(() => _busy = true);
    try {
      final roomId = await _duel.createRoom(
        mode: _mode,
        hostName: _playerName,
        subjectFilter: cfg.subjectIds,
        topicId: cfg.topicId,
        maxPlayers: cfg.maxPlayers,
        isPublic: cfg.isPublic,
        subjects: _subjects,
        remote: remote,
        perQuestionSeconds: cfg.secondsPerQuestion,
        totalQuestions: cfg.questionCount,
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DuelWaitingRoomScreen(roomId: roomId),
      ));
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinByCode() async {
    if (!_duel.isConfigured) {
      _snack('Çok oyunculu mod için internet bağlantısı gerekli.');
      return;
    }
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinCodeDialog(),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    if (!await _consumePlayOrGate()) return;
    setState(() => _busy = true);
    try {
      final roomId = await _duel.joinRoomByCode(code, _playerName);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DuelWaitingRoomScreen(roomId: roomId),
      ));
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinRoom(RoomSummary room) async {
    if (!await _consumePlayOrGate()) return;
    setState(() => _busy = true);
    try {
      await _duel.joinRoomById(room.id, _playerName);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DuelWaitingRoomScreen(roomId: room.id),
      ));
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playSolo() async {
    if (_loadingSubjects) return;
    if (!await _consumePlayOrGate()) return;
    if (!mounted) return;
    // Solo tamamen yerel (Firestore GEREKTİRMEZ) — çevrimdışı da çalışır.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DuelPlayScreen.solo(subjects: _subjects),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final storage = context.watch<StorageService>();
    final premium = storage.isPremiumUser();
    final state = storage.getGamePlayState(kDuelloGameId);
    final left = (kFreeGameDailyLimit - (state['plays'] as int)).clamp(0, kFreeGameDailyLimit);
    final totalSeconds = storage.getGameTimeSpent(kDuelloGameId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('⚔️ KPSS Düello'),
        actions: const [
          HowToPlayButton(
            title: '⚔️ Nasıl Oynanır?',
            body: "Düello'da bir rakiple, Royale'de birden çok oyuncuyla aynı "
                'soruları aynı anda çözersün; hızlı ve doğru cevap veren daha çok '
                'puan kazanır. Oda kurabilir, kodla özel bir odaya katılabilir ya da '
                "hazır odalardan birine girebilirsin. İnternetin yoksa 'Tek Başına "
                "Yarış' ile pratik yapabilirsin.",
          ),
        ],
      ),
      body: _loadingSubjects
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  premium
                      ? 'Sınırsız maç hakkın var. Rakiplerinle aynı soruları çöz, hızlı+doğru cevap ver, kazan!'
                      : 'Bugün $left ücretsiz maç hakkın kaldı.',
                  style: TextStyle(fontSize: 13, color: c.textFaint),
                ),
                const SizedBox(height: 4),
                Text(
                  'Toplam: ${formatPlayDuration(totalSeconds)} oynadın',
                  style: TextStyle(fontSize: 11.5, color: c.textFaint),
                ),
                const SizedBox(height: 16),
                _ModeToggle(
                  mode: _mode,
                  onChanged: (m) {
                    context.read<SoundService>().click();
                    setState(() => _mode = m);
                  },
                ),
                const SizedBox(height: 16),
                // Oyuncu adı
                Text('Oyuncu adın', style: TextStyle(fontSize: 12.5, color: c.textDim, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        maxLength: 24,
                        decoration: const InputDecoration(
                          counterText: '',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Rastgele isim üret',
                      onPressed: () {
                        context.read<SoundService>().click();
                        setState(() => _nameCtrl.text = _duel.generateRandomPlayerName());
                      },
                      icon: const Icon(Icons.shuffle),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Aksiyon butonları
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _createRoom,
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('ODA KUR'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _joinByCode,
                        icon: const Icon(Icons.vpn_key_outlined, size: 18),
                        label: const Text('ÖZEL ODA'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _playSolo,
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('TEK BAŞINA YARIŞ (pratik)'),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Text('📋 Odalar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Açık odalara katıl ya da kendi odanı kur.',
                    style: TextStyle(fontSize: 11.5, color: c.textFaint)),
                const SizedBox(height: 10),
                if (!_duel.isConfigured)
                  _InfoCard(
                    color: c.warn,
                    text: 'Çevrimdışısın veya bağlantı yok — canlı odalar '
                        'görünmüyor. "Tek Başına Yarış" ile pratik yapabilirsin.',
                  )
                else
                  StreamBuilder<List<RoomSummary>>(
                    stream: _duel.listOpenRooms(mode: _mode),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final rooms = snap.data ?? const [];
                      if (rooms.isEmpty) {
                        return _InfoCard(
                          color: c.textFaint,
                          text: 'Şu an açık ${_mode == DuelService.modeRoyale ? "Royale" : "Düello"} '
                              'odası yok. İlk odayı sen kur!',
                        );
                      }
                      return Column(
                        children: [
                          for (final r in rooms)
                            _RoomCard(
                              room: r,
                              onJoin: _busy ? null : () => _joinRoom(r),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: DuelService.modeDuello, label: Text('⚔️ Düello'), icon: null),
        ButtonSegment(value: DuelService.modeRoyale, label: Text('👑 Royale'), icon: null),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Color color;
  final String text;
  const _InfoCard({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.5)),
      ),
    );
  }
}

/// Referans görseldeki oda kartı: oda adı, dersler, kod, doluluk çubuğu,
/// soru/süre bilgisi, KATIL butonu.
class _RoomCard extends StatelessWidget {
  final RoomSummary room;
  final VoidCallback? onJoin;
  const _RoomCard({required this.room, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final ratio = room.maxPlayers == 0 ? 0.0 : (room.playerCount / room.maxPlayers).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(room.mode == DuelService.modeRoyale ? '👑' : '⚔️', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(room.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.glass2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(room.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(room.configLabel,
                style: TextStyle(fontSize: 11.5, color: c.textFaint),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: ratio, minHeight: 6),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('${room.playerCount}/${room.maxPlayers} oyuncu',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                Text('${room.totalQuestions} soru', style: TextStyle(fontSize: 11.5, color: c.textFaint)),
                const SizedBox(width: 12),
                Text('${room.perQuestionSeconds} sn', style: TextStyle(fontSize: 11.5, color: c.textFaint)),
                const Spacer(),
                ElevatedButton(
                  onPressed: room.playerCount >= room.maxPlayers ? null : onJoin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(room.playerCount >= room.maxPlayers ? 'DOLU' : 'KATIL'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Oda kurma yapılandırması.
class _RoomConfig {
  final List<String> subjectIds;
  final String? topicId;
  final int maxPlayers;
  final bool isPublic;
  final int secondsPerQuestion;
  final int questionCount;
  const _RoomConfig({
    required this.subjectIds,
    required this.topicId,
    required this.maxPlayers,
    required this.isPublic,
    required this.secondsPerQuestion,
    required this.questionCount,
  });
}

/// Süre (saniye) seçenekleri — host'un soru başına verdiği süreyi seçtiği
/// sabit liste.
const List<int> kDuelSecondsOptions = [10, 15, 20, 30];

/// Soru sayısı seçenekleri — host'un maçın toplam soru sayısını seçtiği
/// sabit liste (Royale'in 5 soruda bir eleme mantığıyla uyumlu olsun diye
/// hepsi 5'in katı).
const List<int> kDuelQuestionCountOptions = [5, 10, 15, 20];

class _CreateRoomSheet extends StatefulWidget {
  final String mode;
  final List<Subject> subjects;
  const _CreateRoomSheet({required this.mode, required this.subjects});

  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  String? _selectedSubjectId; // null => Karışık (tüm dersler)
  String? _selectedTopicId; // null => Karışık (seçili ders içinde)
  late double _maxPlayers;
  bool _isPublic = true;
  late int _secondsPerQuestion;
  late int _questionCount;

  bool get _isRoyale => widget.mode == DuelService.modeRoyale;

  Subject? get _selectedSubject {
    if (_selectedSubjectId == null) return null;
    for (final s in widget.subjects) {
      if (s.id == _selectedSubjectId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _maxPlayers = _isRoyale ? 20 : 2;
    _secondsPerQuestion = 30;
    _questionCount = _isRoyale ? 15 : 10;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ThemeProvider>().colors;
    final minP = _isRoyale ? 10 : 2;
    final maxP = _isRoyale ? 50 : 10;
    final subject = _selectedSubject;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_isRoyale ? "👑 Royale" : "⚔️ Düello"} Odası Kur',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Ders seçmezsen tüm derslerden karışık sorular gelir.',
                style: TextStyle(fontSize: 12, color: c.textFaint)),
            const SizedBox(height: 10),
            Text('Ders', style: TextStyle(fontSize: 12.5, color: c.textDim, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('🔀 Karışık'),
                  selected: _selectedSubjectId == null,
                  onSelected: (_) => setState(() {
                    _selectedSubjectId = null;
                    _selectedTopicId = null;
                  }),
                ),
                for (final s in widget.subjects)
                  ChoiceChip(
                    label: Text('${s.icon} ${s.ad}'),
                    selected: _selectedSubjectId == s.id,
                    onSelected: (_) => setState(() {
                      _selectedSubjectId = s.id;
                      _selectedTopicId = null; // ders değişince konu sıfırlanır
                    }),
                  ),
              ],
            ),
            if (subject != null && subject.konular.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Konu', style: TextStyle(fontSize: 12.5, color: c.textDim, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('🔀 Karışık (bu ders)'),
                    selected: _selectedTopicId == null,
                    onSelected: (_) => setState(() => _selectedTopicId = null),
                  ),
                  for (final t in subject.konular)
                    ChoiceChip(
                      label: Text(t.baslik),
                      selected: _selectedTopicId == t.id,
                      onSelected: (_) => setState(() => _selectedTopicId = t.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('Süre (soru başına)', style: TextStyle(fontSize: 12.5, color: c.textDim, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sec in kDuelSecondsOptions)
                  ChoiceChip(
                    label: Text('$sec sn'),
                    selected: _secondsPerQuestion == sec,
                    onSelected: (_) => setState(() => _secondsPerQuestion = sec),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Soru sayısı', style: TextStyle(fontSize: 12.5, color: c.textDim, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in kDuelQuestionCountOptions)
                  ChoiceChip(
                    label: Text('$q soru'),
                    selected: _questionCount == q,
                    onSelected: (_) => setState(() => _questionCount = q),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Maksimum oyuncu: ${_maxPlayers.round()}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Slider(
              value: _maxPlayers.clamp(minP.toDouble(), maxP.toDouble()),
              min: minP.toDouble(),
              max: maxP.toDouble(),
              divisions: maxP - minP,
              label: '${_maxPlayers.round()}',
              onChanged: (v) => setState(() => _maxPlayers = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              title: const Text('Odalar listesinde herkese açık', style: TextStyle(fontSize: 13.5)),
              subtitle: Text('Kapalıysa sadece kodu bilenler katılabilir.',
                  style: TextStyle(fontSize: 11, color: c.textFaint)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_RoomConfig(
                  subjectIds: _selectedSubjectId == null ? const [] : [_selectedSubjectId!],
                  topicId: _selectedSubjectId == null ? null : _selectedTopicId,
                  maxPlayers: _maxPlayers.round(),
                  isPublic: _isPublic,
                  secondsPerQuestion: _secondsPerQuestion,
                  questionCount: _questionCount,
                )),
                child: const Text('Odayı Oluştur →'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinCodeDialog extends StatefulWidget {
  const _JoinCodeDialog();

  @override
  State<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<_JoinCodeDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Özel Odaya Katıl'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 6,
        inputFormatters: [
          UpperCaseTextFormatter(),
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
        ],
        decoration: const InputDecoration(
          labelText: 'Oda Kodu',
          hintText: 'Örn. 3YT9UY',
          counterText: '',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('İptal')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: const Text('Katıl'),
        ),
      ],
    );
  }
}

/// Oda kodu girişini büyük harfe zorlar.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(text: newValue.text.toUpperCase(), selection: newValue.selection);
  }
}
