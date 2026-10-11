import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/preferences/app_prefs.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../favorites/presentation/screens/favorites_screen.dart';
import '../../../splash/presentation/screens/splash_screen.dart';
import '../../../wallet/data/wallet_controller.dart';
import '../../domain/user_profile.dart';
import 'settings_screen.dart';

/// Read-only user profile screen — entered by tapping the avatar on
/// the home / transactions header.
///
/// Visual structure:
///   ── brand gradient header band ──
///     • back chevron + "Profile Details" title (matches the standard
///       left-aligned header used elsewhere)
///     • centered avatar disc with a small camera-pill overlay (TODO:
///       wire image_picker once we persist photo uploads)
///     • full name caption
///   ── dark body ──
///     • KYC card (single tile with a green check on the right)
///     • "Personal Informations" section header
///     • Personal info card with labelled rows (read-only — KYC-bound
///       fields cannot be edited from the app; changes flow through
///       the dedicated re-verification paths)
///     • "Actions" section header
///     • Actions card (Refer & earn / Settings / Logout)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const String routePath = '/profile';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Local state retained for the avatar/photo flow only — personal
  // info itself is read-only and sourced from the mock until backend
  // lookup lands.
  // The signed-in user's real profile; the mock only backs the dev bypass (no session).
  late final UserProfile _user = Get.isRegistered<SessionController>() &&
          Get.find<SessionController>().sessionRx.value != null
      ? UserProfile.fromSession(Get.find<SessionController>().sessionRx.value!)
      : kMockUser;

  void _onChangePhoto() => AppLogger.i('profile.change_photo.tap', const {});
  void _onReferAndEarn() => AppLogger.i('profile.refer_and_earn.tap', const {});
  void _onFavorites() {
    Get.to<void>(() => const FavoritesScreen());
  }
  void _onSettings() {
    Get.to<void>(() => const SettingsScreen());
  }

  void _onLogout() {
    // Fire-and-forget the async confirmation flow. The
    // `unawaited`-equivalent pattern is fine here: the actual logout
    // work is gated behind the dialog's `confirmed` result and any
    // failure surfaces via AppLogger.
    _confirmAndLogout();
  }

  Future<void> _confirmAndLogout() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l10n.logoutDialogTitle),
        content: Text(l10n.logoutDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.logoutDialogConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    // Clear in the right order:
    //   1. SessionController.clear() — wipes access/refresh tokens
    //      and the persisted AuthSession blob.
    //   2. AppPrefs.clear()        — drops onboarding.complete and
    //      biometric.enabled so the next user on this device is
    //      walked through KYC again.
    // device.id is intentionally preserved (see SessionStore.clear)
    // so server-side device fingerprinting is stable across logouts.
    //
    // Server-side POST /v1/auth/logout is deferred to W2 once the
    // auth repository lands — the endpoint isn't strictly required
    // for correctness (refresh tokens self-expire) and we'd rather
    // not ship a half-wired call.
    AppLogger.i('logout.confirmed', const {});
    if (Get.isRegistered<WalletController>()) Get.find<WalletController>().clear();
    await Get.find<SessionController>().clear();
    await Get.find<AppPrefs>().clear();
    Get.offAll<void>(() => const SplashScreen());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      extendBodyBehindAppBar: true,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(onBack: Get.back),
                const SizedBox(height: 28),
                _AvatarBlock(
                  initials: _user.initials,
                  fullName: _user.fullName,
                  onChangePhoto: _onChangePhoto,
                ),
                const SizedBox(height: 36),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _KycCard(
                    label: _user.kycDocLabel,
                    verified: _user.kycVerified,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: _SectionLabel(AppLocalizations.of(context).profileSectionPersonal),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _PersonalInfoCard(user: _user),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: _SectionLabel(AppLocalizations.of(context).profileSectionActions),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _ActionsCard(
                    onReferAndEarn: _onReferAndEarn,
                    onFavorites: _onFavorites,
                    onSettings: _onSettings,
                    onLogout: _onLogout,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — matches the project's standard left-aligned chevron + title.
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 24, 0),
      child: Row(
        children: [
          BackChevronButton(onTap: onBack, tooltip: l10n.commonBack),
          Text(
            l10n.profileTitle,
            style: AppTextStyles.screenTitle,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar + name block. Initials placeholder until a real photo lands.
// ---------------------------------------------------------------------------

class _AvatarBlock extends StatelessWidget {
  const _AvatarBlock({
    required this.initials,
    required this.fullName,
    required this.onChangePhoto,
  });

  final String initials;
  final String fullName;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Avatar disc — initials placeholder. The mock shows a
              // photo; we'll swap to NetworkImage / FileImage once
              // upload + persistence are wired.
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.white.withValues(alpha: 0.06),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              // Camera pill overlapping the bottom-right edge.
              Positioned(
                right: -2,
                bottom: 0,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onChangePhoto,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.photo_camera_rounded,
                        color: AppColors.actionPurple,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          fullName,
          style: AppTextStyles.screenTitle.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// "Personal Informations" / "Actions" gray section captions.
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KYC tile (single rounded card, label + subtitle + green verified badge).
// ---------------------------------------------------------------------------

class _KycCard extends StatelessWidget {
  const _KycCard({required this.label, required this.verified});

  /// Document label, e.g. "Ghana Card".
  final String label;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KYC',
                  style: AppTextStyles.screenTitle.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (verified)
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0xFF16A34A),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Personal info card — labelled rows + bottom-right edit pencil.
// ---------------------------------------------------------------------------

class _PersonalInfoCard extends StatelessWidget {
  const _PersonalInfoCard({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow(
            label: l10n.profileFieldPhone,
            value: user.phone,
            verified: user.phoneVerified,
          ),
          const _InfoDivider(),
          _InfoRow(
            label: l10n.profileFieldEmail,
            value: user.email,
            verified: user.emailVerified,
          ),
          const _InfoDivider(),
          _InfoRow(
            label: l10n.profileFieldAddress,
            value: user.address,
            verified: user.addressVerified,
          ),
          const _InfoDivider(),
          _InfoRow(
            label: l10n.profileFieldDateOfBirth,
            value: user.dateOfBirth,
            verified: user.dobVerified,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.verified,
  });

  final String label;
  final String value;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.listTitleStrong,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (verified)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Text(
                AppLocalizations.of(context).profileVerifiedBadge,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoDivider extends StatelessWidget {
  const _InfoDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.white.withValues(alpha: 0.06),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions card — Refer & earn / Settings / Logout.
// ---------------------------------------------------------------------------

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.onReferAndEarn,
    required this.onFavorites,
    required this.onSettings,
    required this.onLogout,
  });

  final VoidCallback onReferAndEarn;
  final VoidCallback onFavorites;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.card_giftcard_rounded,
            iconColor: Colors.white,
            label: l10n.profileActionReferAndEarn,
            onTap: onReferAndEarn,
          ),
          _ActionRow(
            // Favourites lives between Refer & Earn and Settings —
            // it's a "people-related" action so it pairs naturally
            // with Refer & Earn, while still keeping Logout last.
            icon: Icons.favorite_rounded,
            iconColor: Colors.white,
            label: l10n.profileActionFavorites,
            onTap: onFavorites,
          ),
          _ActionRow(
            icon: Icons.settings_rounded,
            iconColor: Colors.white,
            label: l10n.profileActionSettings,
            onTap: onSettings,
          ),
          _ActionRow(
            icon: Icons.logout_rounded,
            iconColor: const Color(0xFFFF4D2E),
            labelColor: const Color(0xFFFF4D2E),
            label: l10n.profileActionLogout,
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.labelColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color? labelColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: labelColor != null
                  ? AppTextStyles.label.copyWith(color: labelColor)
                  : AppTextStyles.label,
            ),
          ],
        ),
      ),
    );
  }
}
