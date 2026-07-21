import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../firebase_bootstrap.dart';

const String kFirebaseNotConfiguredMessage =
    'Firebase henüz yapılandırılmadı. google-services.json / '
    'GoogleService-Info.plist eklenip initFirebaseIfConfigured() çağrıldıktan '
    'sonra bu özellik aktif olacak.';

/// Google/Apple ile giriş denemesinin sonucu. Firebase henüz kurulu değilse
/// (bkz. [isFirebaseConfigured]) her zaman `success: false` ve açıklayıcı bir
/// `errorMessage` ile döner — hiçbir zaman istisna fırlatıp uygulamayı
/// çökertmez.
class AuthResult {
  final bool success;
  final User? user;
  final String? errorMessage;

  const AuthResult.success(this.user)
      : success = true,
        errorMessage = null;

  const AuthResult.failure(this.errorMessage)
      : success = false,
        user = null;

  bool get isNotConfigured => errorMessage == kFirebaseNotConfiguredMessage;
}

/// Kullanıcı adı müsaitlik sorgusunun sonucu.
///
/// `bool` yerine bir enum kullanmamızın sebebi: "alınmış" ile "kontrol
/// edilemedi" (ağ yok / kural reddi) BİRBİRİNDEN ayrılabilmeli. İkisini de
/// `false` diye göstermek kullanıcıya yanlış bilgi verir ve emin olmadığımız
/// bir durumda kaydı sessizce engeller.
enum UsernameDurumu {
  /// Doküman yok → kullanıcı adı alınabilir.
  musait,

  /// `usernames/{kucukHarf}` dokümanı zaten var.
  alinmis,

  /// Biçim kurallarına uymuyor (bkz. [AuthService.usernameHatasi]).
  gecersiz,

  /// Sorgu başarısız oldu (ağ, izin, Firebase kurulu değil). Emin olamadığımız
  /// için kayıt AKIŞI DURDURULUR — yanlışlıkla ikinci bir kayıt açılmasın.
  kontrolEdilemedi,
}

/// `usernames` koleksiyonunun doküman kimliğinde kullanılan sabitler.
const String kUsernamesCollection = 'usernames';

/// Kullanıcı adı en az/en fazla uzunluk sınırları.
const int kUsernameMinUzunluk = 3;
const int kUsernameMaxUzunluk = 20;

/// Google / Apple ile giriş için ince bir servis katmanı.
///
/// Firebase henüz yapılandırılmamışsa (`Firebase.apps` boşsa) hiçbir metod
/// gerçek bir Firebase/Google/Apple SDK çağrısı yapmaz; hepsi anında
/// [AuthResult.failure] döner. Bu sayede ekranlar bu servisi güvenle
/// çağırabilir, config dosyaları gelmeden önce de sonra da davranış tutarlı
/// kalır.
class AuthService extends ChangeNotifier {
  GoogleSignIn? _googleSignIn;
  bool _googleInitialized = false;

  /// Firebase gerçekten başlatılmış mı (config dosyaları eklenip
  /// initFirebaseIfConfigured() başarıyla çalıştıysa true).
  bool get isConfigured => isFirebaseConfigured;

  /// Şu anki oturum açmış kullanıcı. Firebase yapılandırılmamışsa her zaman
  /// null döner.
  User? get currentUser => isConfigured ? FirebaseAuth.instance.currentUser : null;

  bool get isSignedIn => currentUser != null;

  /// Apple ile giriş sadece iOS'ta gösterilmeli (App Store kuralları gereği
  /// diğer platformlarda zorunlu değildir).
  bool get isAppleSignInAvailable => !kIsWeb && Platform.isIOS;

  Stream<User?> get authStateChanges {
    if (!isConfigured) return Stream<User?>.value(null);
    return FirebaseAuth.instance.authStateChanges();
  }

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleInitialized) return;
    _googleSignIn = GoogleSignIn.instance;
    await _googleSignIn!.initialize();
    _googleInitialized = true;
  }

  /// FirebaseAuthException kodlarını kullanıcıya gösterilebilir TÜRKÇE
  /// mesajlara çevirir. Bilinmeyen kodlarda genel bir mesaj + kod döner ki
  /// destek tarafında ne olduğu anlaşılabilsin.
  String _turkceHataMesaji(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Bu e-posta zaten kayıtlı. Giriş yapmayı dene.';
      case 'invalid-email':
        return 'Geçersiz e-posta adresi.';
      case 'weak-password':
        return 'Şifre çok zayıf. En az 6 karakter kullan.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'E-posta veya şifre hatalı.';
      case 'user-disabled':
        return 'Bu hesap devre dışı bırakılmış.';
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.';
      case 'network-request-failed':
        return 'İnternet bağlantısı yok.';
      case 'operation-not-allowed':
        return 'E-posta/şifre ile giriş bu projede kapalı görünüyor.';
      case 'requires-recent-login':
        return 'Güvenlik için tekrar giriş yapman gerekiyor.';
      default:
        return 'Bir hata oluştu, tekrar dene. (kod: ${e.code})';
    }
  }

  // ══ Kullanıcı adı desteği ═══════════════════════════════════════════════
  //
  // VERİ MODELİ: `usernames/{kullaniciAdiKucukHarf}`
  //   • Doküman kimliği = kullanıcı adının küçük harfe çevrilmiş hâli.
  //     Benzersizlik böyle GARANTİ EDİLİR: Firestore'da aynı kimlikte iki
  //     doküman olamaz, yani "ayşe" ve "Ayşe" aynı kaydı hedefler.
  //   • Alanlar: email (string), uid (string), username (string — kullanıcının
  //     yazdığı orijinal, büyük/küçük harfli hâli; ekranda bu gösterilir).

  /// Kullanıcı adını doküman kimliğine çevirir (küçük harf).
  ///
  /// TÜRKÇE NOTU: Dart'ın `toLowerCase()`'i Unicode varsayılanını uygular;
  /// 'İ' harfi orada "i + birleşen nokta" (iki kod noktası) hâline gelir ve
  /// doküman kimliği olarak görünmez biçimde bozulur. 'I' de 'i' olur, oysa
  /// Türkçede 'I' → 'ı' olmalıdır. Bu iki harfi ÖNCE elle çevirip sonra
  /// `toLowerCase()` çağırıyoruz; böylece "İREM", "İrem" ve "irem" hepsi aynı
  /// kimliğe düşer.
  static String usernameKey(String username) {
    return username
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase();
  }

  // Türkçe harfler dâhil izin verilen karakter kümesi.
  static final RegExp _usernameGecerliKarakterler =
      RegExp(r'^[A-Za-zÇĞİÖŞÜçğıöşü0-9._]+$');
  static final RegExp _usernameRakamlaBaslar = RegExp(r'^[0-9]');
  // Doküman kimliğinin ".", ".." ya da sadece noktalama olmasını engellemek
  // için en az bir harf/rakam şartı (Firestore "." ve ".." kimliklerini
  // reddeder, ayrıca "___" gibi adlar da anlamsızdır).
  static final RegExp _usernameHarfVeyaRakamIcerir =
      RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü0-9]');

  /// Kullanıcı adı biçim kurallarını uygular.
  /// Geçerliyse `null`, değilse TÜRKÇE bir hata mesajı döner.
  static String? usernameHatasi(String username) {
    final ad = username.trim();
    if (ad.isEmpty) return 'Kullanıcı adı boş bırakılamaz.';
    if (ad.contains('@')) {
      // ŞART: giriş alanında e-posta ile kullanıcı adını '@' varlığına bakarak
      // ayırıyoruz. Kullanıcı adında '@' olsaydı bu ayrım çökerdi.
      return 'Kullanıcı adı "@" içeremez.';
    }
    if (ad.contains(' ')) return 'Kullanıcı adı boşluk içeremez.';
    if (ad.length < kUsernameMinUzunluk) {
      return 'Kullanıcı adı en az $kUsernameMinUzunluk karakter olmalı.';
    }
    if (ad.length > kUsernameMaxUzunluk) {
      return 'Kullanıcı adı en fazla $kUsernameMaxUzunluk karakter olabilir.';
    }
    if (!_usernameGecerliKarakterler.hasMatch(ad)) {
      return 'Kullanıcı adı yalnızca harf, rakam, alt çizgi (_) ve nokta (.) '
          'içerebilir.';
    }
    if (_usernameRakamlaBaslar.hasMatch(ad)) {
      return 'Kullanıcı adı rakamla başlayamaz.';
    }
    if (!_usernameHarfVeyaRakamIcerir.hasMatch(ad)) {
      return 'Kullanıcı adı en az bir harf ya da rakam içermeli.';
    }
    return null;
  }

  /// Kullanıcı adının durumunu sorgular (müsait / alınmış / geçersiz /
  /// kontrol edilemedi). İstisna fırlatmaz.
  Future<UsernameDurumu> usernameDurumu(String username) async {
    if (usernameHatasi(username) != null) return UsernameDurumu.gecersiz;
    if (!isConfigured) return UsernameDurumu.kontrolEdilemedi;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(kUsernamesCollection)
          .doc(usernameKey(username))
          .get();
      return snap.exists ? UsernameDurumu.alinmis : UsernameDurumu.musait;
    } catch (_) {
      return UsernameDurumu.kontrolEdilemedi;
    }
  }

  /// Kullanıcı adı alınabilir mi?
  ///
  /// GÜVENLİ TARAF: sorgu başarısız olursa (ağ yok, kural reddi, Firebase
  /// kurulu değil) `false` döner. Emin olamadığımız bir durumda kaydın
  /// ilerlemesine izin VERMİYORUZ — yarım/çakışan kayıt oluşmasındansa
  /// kullanıcıya "kontrol edilemedi" demek daha doğru.
  Future<bool> usernameAvailable(String username) async {
    return await usernameDurumu(username) == UsernameDurumu.musait;
  }

  /// Kullanıcı adından e-posta çözer. Bulunamazsa ya da sorgu başarısız
  /// olursa `null` döner. İstisna fırlatmaz.
  Future<String?> emailForUsername(String username) async {
    if (!isConfigured) return null;
    final anahtar = usernameKey(username);
    if (anahtar.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(kUsernamesCollection)
          .doc(anahtar)
          .get();
      if (!snap.exists) return null;
      final eposta = snap.data()?['email'];
      if (eposta is String && eposta.trim().isNotEmpty) return eposta.trim();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// E-posta + şifre ile YENİ hesap oluşturur.
  ///
  /// [displayName] verilirse görünen ad güncellenir. [username] verilirse
  /// ayrıca `usernames/{kucukHarf}` eşleme dokümanı yazılır ve görünen ad
  /// kullanıcı adına ayarlanır. Her iki parametre de OPSİYONEL — kullanıcı
  /// adı olmadan yapılan mevcut çağrılar aynen çalışmaya devam eder.
  Future<AuthResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
    String? username,
  }) async {
    if (!isConfigured) return const AuthResult.failure(kFirebaseNotConfiguredMessage);

    final kullaniciAdi = username?.trim();
    final kullaniciAdiVar = kullaniciAdi != null && kullaniciAdi.isNotEmpty;

    // 1) Kullanıcı adı verildiyse Auth kullanıcısını OLUŞTURMADAN ÖNCE biçim
    //    ve müsaitlik kontrolü yap — böylece çoğu çakışmada hiç hesap
    //    açılmadan hata döneriz.
    if (kullaniciAdiVar) {
      final bicimHatasi = usernameHatasi(kullaniciAdi);
      if (bicimHatasi != null) return AuthResult.failure(bicimHatasi);

      final durum = await usernameDurumu(kullaniciAdi);
      switch (durum) {
        case UsernameDurumu.alinmis:
          return const AuthResult.failure(
            'Bu kullanıcı adı alınmış. Başka bir tane dene.',
          );
        case UsernameDurumu.kontrolEdilemedi:
          return const AuthResult.failure(
            'Kullanıcı adının uygunluğu kontrol edilemedi. İnternet '
            'bağlantını kontrol edip tekrar dene.',
          );
        case UsernameDurumu.gecersiz:
          return const AuthResult.failure('Kullanıcı adı geçersiz.');
        case UsernameDurumu.musait:
          break;
      }
    }

    User? olusturulanKullanici;
    try {
      final userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      olusturulanKullanici = userCred.user;

      if (kullaniciAdiVar) {
        final user = olusturulanKullanici;
        if (user == null) {
          return const AuthResult.failure(
            'Kayıt tamamlanamadı, tekrar dene.',
          );
        }
        // 2) Eşleme dokümanını yaz. Bu adım BAŞARISIZ olursa aşağıdaki catch
        //    bloğu oluşturulan Auth kullanıcısını geri alır.
        await FirebaseFirestore.instance
            .collection(kUsernamesCollection)
            .doc(usernameKey(kullaniciAdi))
            .set({
          'email': email.trim(),
          'uid': user.uid,
          'username': kullaniciAdi,
        });
      }

      // 3) Görünen ad: kullanıcı adı varsa o, yoksa displayName.
      //
      // Bu adım BİLEREK kendi try/catch'i içinde: hesap ve eşleme dokümanı
      // artık sağlam. Sırf görünen ad yazılamadı diye kaydı geri almak
      // kullanıcıya zarar verir — sessizce geçip başarı döneriz, ad bir
      // sonraki açılışta düzeltilebilir.
      final ad = kullaniciAdiVar ? kullaniciAdi : displayName?.trim();
      if (ad != null && ad.isNotEmpty) {
        try {
          await olusturulanKullanici?.updateDisplayName(ad);
          // updateDisplayName sonrası yerel User nesnesi eski adı taşır;
          // tazeleyip güncel hâlini döndürüyoruz.
          await olusturulanKullanici?.reload();
        } catch (_) {
          // Görünen ad güncellenemedi, kayıt yine de başarılı.
        }
      }
      notifyListeners();
      return AuthResult.success(
          FirebaseAuth.instance.currentUser ?? olusturulanKullanici);
    } on FirebaseAuthException catch (e) {
      await _yarimKaydiGeriAl(olusturulanKullanici);
      return AuthResult.failure(_turkceHataMesaji(e));
    } catch (e) {
      // YARIM KAYIT KORUMASI: Auth kullanıcısı açıldıysa ama eşleme dokümanı
      // yazılamadıysa, kullanıcı adı olmayan "hayalet" bir hesap kalırdı.
      // Oluşturulan hesabı geri alıyoruz ki kullanıcı baştan deneyebilsin.
      final geriAlindi = await _yarimKaydiGeriAl(olusturulanKullanici);
      if (olusturulanKullanici != null && kullaniciAdiVar) {
        return AuthResult.failure(
          geriAlindi
              ? 'Kullanıcı adı kaydedilemedi, kayıt geri alındı. Tekrar dene.'
              : 'Kullanıcı adı kaydedilemedi. Hesabın yarım kalmış olabilir, '
                  'giriş yapmayı dene ya da destekle iletişime geç.',
        );
      }
      return AuthResult.failure('Kayıt başarısız: $e');
    }
  }

  /// Yarım kalan kaydı temizler: oluşturulmuş Auth kullanıcısını siler.
  /// Silme de başarısız olursa `false` döner — çağıran buna göre mesaj verir.
  Future<bool> _yarimKaydiGeriAl(User? user) async {
    if (user == null) return false;
    try {
      await user.delete();
      notifyListeners();
      return true;
    } catch (_) {
      // Silinemedi (ör. ağ koptu). Oturumu en azından kapatmayı deneyelim ki
      // kullanıcı yarım bir oturumla devam etmesin.
      try {
        await FirebaseAuth.instance.signOut();
        notifyListeners();
      } catch (_) {}
      return false;
    }
  }

  /// E-posta VEYA kullanıcı adı + şifre ile giriş yapar.
  ///
  /// [kimlik] içinde '@' varsa doğrudan e-posta kabul edilir; yoksa
  /// `usernames` koleksiyonundan e-postaya çevrilir.
  Future<AuthResult> signInWithEmailOrUsername({
    required String kimlik,
    required String password,
  }) async {
    if (!isConfigured) return const AuthResult.failure(kFirebaseNotConfiguredMessage);

    final girdi = kimlik.trim();
    if (girdi.isEmpty) {
      return const AuthResult.failure('E-posta veya kullanıcı adı boş bırakılamaz.');
    }

    String eposta;
    if (girdi.contains('@')) {
      eposta = girdi;
    } else {
      final cozulen = await emailForUsername(girdi);
      if (cozulen == null) {
        // GİZLİLİK: "böyle bir kullanıcı adı yok" DEMİYORUZ. Aksi hâlde bu
        // ekran kullanıcı adı numaralandırma (enumeration) aracına dönerdi.
        return const AuthResult.failure('Kullanıcı adı veya şifre hatalı.');
      }
      eposta = cozulen;
    }

    return signInWithEmail(email: eposta, password: password);
  }

  /// E-posta + şifre ile giriş yapar.
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) return const AuthResult.failure(kFirebaseNotConfiguredMessage);
    try {
      final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      notifyListeners();
      return AuthResult.success(userCred.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_turkceHataMesaji(e));
    } catch (e) {
      return AuthResult.failure('Giriş başarısız: $e');
    }
  }

  /// "Şifremi unuttum" akışı: verilen adrese sıfırlama bağlantısı gönderir.
  /// Başarılıysa `user` null olan bir [AuthResult.success] döner.
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    if (!isConfigured) return const AuthResult.failure(kFirebaseNotConfiguredMessage);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      return const AuthResult.success(null);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_turkceHataMesaji(e));
    } catch (e) {
      return AuthResult.failure('Sıfırlama e-postası gönderilemedi: $e');
    }
  }

  Future<AuthResult> signInWithGoogle() async {
    if (!isConfigured) return const AuthResult.failure(kFirebaseNotConfiguredMessage);
    try {
      await _ensureGoogleSignInInitialized();
      final googleSignIn = _googleSignIn!;
      if (!googleSignIn.supportsAuthenticate()) {
        return const AuthResult.failure(
          'Bu platformda Google ile giriş desteklenmiyor.',
        );
      }
      final GoogleSignInAccount account = await googleSignIn.authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null) {
        return const AuthResult.failure('Google kimlik doğrulaması bir idToken döndürmedi.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      notifyListeners();
      return AuthResult.success(userCred.user);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const AuthResult.failure('Giriş iptal edildi.');
      }
      return AuthResult.failure('Google ile giriş başarısız: ${e.description ?? e.code}');
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure('Google ile giriş başarısız: ${e.message ?? e.code}');
    } catch (e) {
      return AuthResult.failure('Google ile giriş başarısız: $e');
    }
  }

  Future<AuthResult> signInWithApple() async {
    if (!isConfigured) return const AuthResult.failure(kFirebaseNotConfiguredMessage);
    if (!isAppleSignInAvailable) {
      return const AuthResult.failure('Apple ile giriş sadece iOS cihazlarda kullanılabilir.');
    }
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final userCred = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      notifyListeners();
      return AuthResult.success(userCred.user);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AuthResult.failure('Giriş iptal edildi.');
      }
      return AuthResult.failure('Apple ile giriş başarısız: ${e.message}');
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure('Apple ile giriş başarısız: ${e.message ?? e.code}');
    } catch (e) {
      return AuthResult.failure('Apple ile giriş başarısız: $e');
    }
  }

  /// Hesap silme gibi hassas işlemler için kimliği TAZELER.
  ///
  /// Firebase, `user.delete()` çağrısını yalnızca yakın zamanda giriş yapmış
  /// oturumlarda kabul eder; oturum eskiyse `requires-recent-login` döner. Bu
  /// metod kullanıcının HANGİ sağlayıcıyla giriş yaptığını `providerData`'dan
  /// okur ve aynı sağlayıcıyla yeniden doğrulama yapar.
  ///
  /// Anonim kullanıcılarda yeniden doğrulama diye bir şey yoktur — bu durumda
  /// başarılı sayılır (Auth kaydı zaten doğrudan silinebilir).
  /// E-posta/şifre ('password') sağlayıcısıyla girmiş kullanıcılarda yeniden
  /// doğrulama şifre gerektirir; bu durumda [password] verilmelidir. Parametre
  /// opsiyoneldir — Google/Apple hesaplarında eski çağrı biçimi aynen çalışır.
  Future<AuthResult> reauthenticate({String? password}) async {
    if (!isConfigured) return const AuthResult.failure(kFirebaseNotConfiguredMessage);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const AuthResult.failure('Oturum açık değil.');
    if (user.isAnonymous) return AuthResult.success(user);

    final saglayicilar = user.providerData.map((p) => p.providerId).toSet();
    try {
      if (saglayicilar.contains('apple.com')) {
        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: const [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
        final credential = OAuthProvider('apple.com').credential(
          idToken: appleCredential.identityToken,
          accessToken: appleCredential.authorizationCode,
        );
        await user.reauthenticateWithCredential(credential);
        return AuthResult.success(FirebaseAuth.instance.currentUser);
      }

      if (saglayicilar.contains('google.com')) {
        await _ensureGoogleSignInInitialized();
        final googleSignIn = _googleSignIn!;
        if (!googleSignIn.supportsAuthenticate()) {
          return const AuthResult.failure(
            'Bu platformda Google ile yeniden giriş desteklenmiyor.',
          );
        }
        final account = await googleSignIn.authenticate();
        final idToken = account.authentication.idToken;
        if (idToken == null) {
          return const AuthResult.failure(
            'Google kimlik doğrulaması bir idToken döndürmedi.',
          );
        }
        final credential = GoogleAuthProvider.credential(idToken: idToken);
        await user.reauthenticateWithCredential(credential);
        return AuthResult.success(FirebaseAuth.instance.currentUser);
      }

      if (saglayicilar.contains('password')) {
        final eposta = user.email;
        if (eposta == null || eposta.isEmpty) {
          return const AuthResult.failure(
            'Hesaba bağlı e-posta bulunamadı, yeniden doğrulama yapılamıyor.',
          );
        }
        if (password == null || password.isEmpty) {
          return const AuthResult.failure(
            'Devam etmek için hesabının şifresini girmen gerekiyor.',
          );
        }
        final credential = EmailAuthProvider.credential(
          email: eposta,
          password: password,
        );
        await user.reauthenticateWithCredential(credential);
        return AuthResult.success(FirebaseAuth.instance.currentUser);
      }

      return const AuthResult.failure(
        'Bu hesabın giriş yöntemi için yeniden doğrulama desteklenmiyor.',
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AuthResult.failure('Giriş iptal edildi.');
      }
      return AuthResult.failure('Yeniden giriş başarısız: ${e.message}');
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const AuthResult.failure('Giriş iptal edildi.');
      }
      return AuthResult.failure('Yeniden giriş başarısız: ${e.description ?? e.code}');
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure('Yeniden giriş başarısız: ${e.message ?? e.code}');
    } catch (e) {
      return AuthResult.failure('Yeniden giriş başarısız: $e');
    }
  }

  Future<void> signOut() async {
    if (!isConfigured) return;
    try {
      if (_googleInitialized) {
        await _googleSignIn?.signOut();
      }
    } catch (_) {
      // Google oturumu zaten kapalı olabilir, yok say.
    }
    await FirebaseAuth.instance.signOut();
    notifyListeners();
  }
}
