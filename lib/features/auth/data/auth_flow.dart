import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../core/network/api_result.dart';
import '../../../core/session/session_controller.dart';
import 'auth_dtos.dart';
import 'auth_repository.dart';

/// Orchestrates sign-in: request a code, verify it (and persist the session),
/// set the passcode. Screens talk to this, not to the repository, so the
/// "verify succeeded → session stored" invariant lives in one tested place.
class AuthFlow extends GetxService {
  AuthFlow({AuthRepository? repository, SessionController? session})
      : _repo = repository ?? AuthRepository(),
        _session = session;

  final AuthRepository _repo;
  final SessionController? _session;
  SessionController get _sessions => _session ?? Get.find<SessionController>();

  /// Sends a one-time code to [phoneE164] (`+` and digits).
  Future<ApiResult<OtpRequested>> requestCode(String phoneE164) {
    return _repo.requestOtp(
      phoneE164: phoneE164,
      deviceId: _sessions.deviceId,
      deviceKind: switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'IOS',
        TargetPlatform.android => 'ANDROID',
        _ => null,
      },
    );
  }

  /// Verifies the code. On success the session is stored BEFORE this returns,
  /// so the caller can immediately make authenticated calls (set passcode).
  Future<ApiResult<LoginResult>> verifyCode(String phoneE164, String code) async {
    final result = await _repo.verifyOtp(
      phoneE164: phoneE164,
      code: code,
      deviceId: _sessions.deviceId,
    );
    if (result case Success(:final value)) {
      await _sessions.setSession(value.session);
    }
    return result;
  }

  Future<ApiResult<void>> savePasscode(String passcode, {String? currentPasscode}) {
    return _repo.setPasscode(passcode: passcode, currentPasscode: currentPasscode);
  }
}
