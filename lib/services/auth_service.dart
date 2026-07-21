import 'dart:io' show Platform;

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

  /// E-posta + şifre ile YENİ hesap oluşturur. [displayName] verilirse
  /// oluşturulan kullanıcının görünen adı da güncellenir.
  Future<AuthResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (!isConfigured) return const AuthResult.failure(kFirebaseNotConfiguredMessage);
    try {
      final userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final ad = displayName?.trim();
      if (ad != null && ad.isNotEmpty) {
        await userCred.user?.updateDisplayName(ad);
        // updateDisplayName sonrası yerel User nesnesi eski adı taşır;
        // tazeleyip güncel hâlini döndürüyoruz.
        await userCred.user?.reload();
      }
      notifyListeners();
      return AuthResult.success(FirebaseAuth.instance.currentUser ?? userCred.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_turkceHataMesaji(e));
    } catch (e) {
      return AuthResult.failure('Kayıt başarısız: $e');
    }
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
