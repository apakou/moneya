import 'package:uuid/uuid.dart';

import '../storage/secure_storage.dart';
import 'auth_session.dart';

/// Persistence boundary for the auth session.
///
/// - [readSession] / [writeSession] / [clearSession] manage the session
///   blob under [SecureStorageKeys.session].
/// - [readOrCreateDeviceId] returns a stable UUIDv4 for this install,
///   persisted under [SecureStorageKeys.deviceId]. The device id survives
///   logout intentionally — a logged-out device is still the same device.
class SessionStore {
  SessionStore(this._storage, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final SecureStorage _storage;
  final Uuid _uuid;

  Future<AuthSession?> readSession() async {
    final raw = await _storage.read(SecureStorageKeys.session);
    if (raw == null) return null;
    try {
      return AuthSession.decode(raw);
    } catch (_) {
      // Corrupt blob — drop it so the next boot starts clean.
      await _storage.delete(SecureStorageKeys.session);
      return null;
    }
  }

  Future<void> writeSession(AuthSession session) async {
    await _storage.write(SecureStorageKeys.session, session.encode());
  }

  Future<void> clearSession() async {
    await _storage.delete(SecureStorageKeys.session);
  }

  Future<String> readOrCreateDeviceId() async {
    final existing = await _storage.read(SecureStorageKeys.deviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = _uuid.v4();
    await _storage.write(SecureStorageKeys.deviceId, fresh);
    return fresh;
  }
}
