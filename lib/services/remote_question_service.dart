import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

import '../firebase_bootstrap.dart';
import '../models/question.dart';

/// Soru havuzlarını Firestore'dan (`question_banks/{topicId}` dokümanları)
/// indirip cihazda dosya olarak önbellekleyen servis.
///
/// TASARIM: Firestore bir konunun TÜM sorularını (~100-250 adet) TEK bir
/// dokümanda tutar — "önce 3 tanesini indir, sonra kalanını arka planda"
/// şeklinde parça parça indirme Firestore'un doğasında yoktur (belge tek
/// parça gelir). Bunun yerine kullanıcı deneyimini şöyle sağlıyoruz:
///
/// 1. Kullanıcı bir KONU ekranını açtığında [prefetch] çağrılır — o konunun
///    tüm havuzu SESSİZCE arka planda indirilip cihaza yazılır (genelde
///    birkaç saniye sürer, kullanıcı konu anlatımını okurken tamamlanır).
/// 2. "Teste Başla" dendiğinde [getPool] ANINDA (network beklemeden) döner:
///    - Önbellek zaten varsa (önceki bir prefetch/indirme tamamlanmışsa) o
///      TAM havuzu döner.
///    - Önbellek henüz yoksa, uygulamayla birlikte gömülü olan KÜÇÜK yedek
///      soru setini (topic.sorular, ~15 soru) anında döner VE arka planda
///      indirmeyi başlatır — bir sonraki sefer tam havuz hazır olur.
/// 3. Kullanılmış soru takibi (tekrar etmeme, havuz bitince karışık tekrar)
///    zaten StorageService.getUsedQuestions/addUsedQuestions + QuestionPicker
///    içinde var — bu servis sadece HAVUZUN KAYNAĞINI değiştirir, o mantığa
///    dokunmaz.
/// Tüm soru bankasının (69 konu) ölçülmüş gerçek toplam boyutu — Ayarlar >
/// "Tüm Soruları İndir" yanında kullanıcıya "yaklaşık ne kadar yer kaplar"
/// fikri vermek için kullanılır. İçerik büyüdükçe (yeni sorular eklendikçe)
/// bu sabit gerçek değerden biraz sapabilir, kritik değildir — sadece bir
/// tahmin göstergesidir.
const int kQuestionBankEstimatedBytes = 7700000; // ~7,3 MB (69 konu, ölçüldü)

String formatEstimatedSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '~${mb.toStringAsFixed(1)} MB';
}

class RemoteQuestionService {
  static const String _collection = "question_banks";

  Future<Directory> _cacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final qdir = Directory("${dir.path}/qcache");
    if (!await qdir.exists()) {
      await qdir.create(recursive: true);
    }
    return qdir;
  }

  /// null dönerse (path_provider kanalı henüz kayıtlı değil, platform
  /// desteklemiyor, disk hatası vb.) önbellekleme tamamen devre dışı kalır —
  /// çağıran taraflar HER ZAMAN gömülü yedek soruları kullanmaya devam eder,
  /// asla askıda kalmaz veya istisna fırlatmaz.
  Future<File?> _cacheFileFor(String topicId) async {
    try {
      final dir = await _cacheDir();
      return File("${dir.path}/$topicId.json");
    } catch (_) {
      return null;
    }
  }

  /// Bir konu için önbellek zaten var mı (daha önce başarıyla indirilmiş mi).
  Future<bool> isCached(String topicId) async {
    try {
      final file = await _cacheFileFor(topicId);
      if (file == null) return false;
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Konu ekranı açıldığında çağrılır — önbellek yoksa sessizce indirir.
  /// Hata olursa (internet yok, Firestore yapılandırılmamış, dosya sistemi
  /// erişilemez vb.) sessizce başarısız olur, hiçbir zaman istisna fırlatmaz
  /// ya da askıda kalmaz.
  Future<void> prefetch(String topicId) async {
    try {
      if (await isCached(topicId)) return;
      await _fetchAndCache(topicId);
    } catch (_) {
      // Sessizce basarisiz ol.
    }
  }

  Future<bool> _fetchAndCache(String topicId) async {
    if (!isFirebaseConfigured) return false;
    try {
      final doc = await FirebaseFirestore.instance.collection(_collection).doc(topicId).get();
      final data = doc.data();
      if (data == null) return false;
      final sorular = data["sorular"] as List? ?? const [];
      final file = await _cacheFileFor(topicId);
      if (file == null) return false;
      await file.writeAsString(jsonEncode(sorular));
      return true;
    } catch (_) {
      // Sessizce basarisiz ol - fallback kullanilmaya devam eder.
      return false;
    }
  }

  /// Bir konu için o an kullanılabilecek soru havuzunu döner:
  /// önbellek varsa önbellekten, yoksa [fallback]'ten (gömülü yedek sorular)
  /// — ve önbellek yoksa arka planda indirmeyi (bir dahaki sefere hazır
  /// olması için) tetikler. HİÇBİR ZAMAN network beklemez ya da istisna
  /// fırlatmaz (aksi halde çağıran ekranlarda "yükleniyor" göstergesi
  /// sonsuza dek asılı kalır) — herhangi bir hata durumunda anında
  /// [fallback] ile döner.
  Future<List<Question>> getPool(String topicId, List<Question> fallback) async {
    try {
      final file = await _cacheFileFor(topicId);
      if (file != null && await file.exists()) {
        try {
          final raw = jsonDecode(await file.readAsString()) as List;
          final qs = raw.map((q) => Question.fromJson(Map<String, dynamic>.from(q as Map))).toList();
          if (qs.isNotEmpty) return qs;
        } catch (_) {
          // Bozuk onbellek - yeniden indirmeyi dene, simdilik fallback don.
        }
      }
      // Onbellek yok/bozuk: arka planda indirmeyi baslat (await ETME), simdilik
      // gomulu yedek sorulari dondur.
      // ignore: unawaited_futures
      _fetchAndCache(topicId);
    } catch (_) {
      // Herhangi bir beklenmeyen hata (ör. path_provider kanalı henüz kayıtlı
      // değil) - sessizce yedek soru listesine düş.
    }
    return fallback;
  }

  /// Ayarlar > "Tüm Soruları İndir" — verilen tüm konu id'lerini sırayla
  /// indirip önbellekler, ilerlemeyi [onProgress] ile bildirir. Tam offline
  /// kullanım için. Kaç konunun GERÇEKTEN başarıyla indirildiğini (ör.
  /// internet yoksa ya da Firestore erişilemezse 0 olabilir) döner — çağıran
  /// taraf bunu `topicIds.length` ile karşılaştırıp kullanıcıya DÜRÜST bir
  /// sonuç göstermelidir (körlemesine "tamamlandı" demek yerine).
  Future<int> downloadAll(List<String> topicIds, {void Function(int done, int total)? onProgress}) async {
    var done = 0;
    var succeeded = 0;
    for (final topicId in topicIds) {
      // HER ZAMAN sunucudan yeniden çeker (önbellekte olsa bile) — ileride
      // içerik güncellendiğinde (ör. yeni/düzeltilmiş sorular yüklendiğinde)
      // "Tüm Soruları İndir" gerçekten en güncel veriyi getirsin diye.
      if (await _fetchAndCache(topicId)) succeeded++;
      done++;
      onProgress?.call(done, topicIds.length);
    }
    return succeeded;
  }

  /// Tüm konuların önbelleğe alınıp alınmadığını (tam offline hazır mı) kontrol eder.
  Future<int> countCached(List<String> topicIds) async {
    var count = 0;
    for (final topicId in topicIds) {
      if (await isCached(topicId)) count++;
    }
    return count;
  }

  /// Firestore'daki `app_meta/content_version` dokümanından, soru içeriğinin
  /// (geliştirici yeni/düzeltilmiş sorular yükledikçe) en son ne zaman
  /// güncellendiğini okur — "Yeni sorular eklendi" bildirimi için kullanılır.
  /// Firebase yapılandırılmamışsa, doküman yoksa ya da bir ağ hatası olursa
  /// sessizce `null` döner (bildirim gösterilmez, asla istisna fırlatmaz).
  Future<DateTime?> getServerContentUpdatedAt() async {
    if (!isFirebaseConfigured) return null;
    try {
      final doc = await FirebaseFirestore.instance.collection('app_meta').doc('content_version').get();
      final ts = doc.data()?['updatedAt'];
      return ts is Timestamp ? ts.toDate() : null;
    } catch (_) {
      return null;
    }
  }
}
