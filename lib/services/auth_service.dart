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
  Future<AuthResult> reauthenticate() async {
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
