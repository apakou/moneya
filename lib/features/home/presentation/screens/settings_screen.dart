import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// App settings — reached from the Profile screen's Actions list.
///
/// Three sections, each rendered as a single rounded translucent card
/// over the brand gradient → black backdrop:
///
///   • Security & Privacy: Change Password / Login Options /
///     Biometrics-for-transactions toggle.
///   • Transactions: Phone Number Account / USSD Banking.
///   • Actions: Delete Account (destructive — opens an AlertDialog
///     confirm before firing).
///
/// All row destinations are stubbed with `debugPrint`s; the only live
/// behaviors are the biometrics switch (in-memory until we wire
/// `flutter_secure_storage` under the
/// `biometrics_for_transactions_enabled` key) and the delete-account
/// confirmation dialog.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.showBackButton = true});

  static const String routePath = '/settings';

  /// When `true` (default — pushed as a route from Profile) the header
  /// renders a chevron-left back button. When `false` (hosted as a
  /// bottom-nav tab inside [HomeShell]) the chevron is hidden so the
  /// screen reads as a top-level destination.
  final bool showBackButton;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricsEnabled = true;

  void _onChangePassword() => AppLogger.i('settings.change_password.tap', const {});
  void _onLoginOptions() => AppLogger.i('settings.login_options.tap', const {});
  void _onPhoneNumberAccount() =>
      AppLogger.i('settings.phone_account.tap', const {});
  void _onUssdBanking() => AppLogger.i('settings.ussd_banking.tap', const {});

  Future<void> _onDeleteAccount() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F23),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          l10n.deleteAccountDialogTitle,
          style: AppTextStyles.screenTitle,
        ),
        content: Text(
          l10n.deleteAccountDialogBody,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: Text(
              l10n.commonCancel,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Get.back<bool>(result: true),
            child: Text(
              l10n.commonDelete,
              style: const TextStyle(
                color: Color(0xFFFF4D2E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // TODO: call DELETE /users/me, clear flutter_secure_storage,
      // navigate back to splash + onboarding entry.
      AppLogger.i('settings.delete_account.confirmed', const {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                _Header(
                  onBack: widget.showBackButton ? Get.back : null,
                ),
                const SizedBox(height: 28),
                _SectionLabel(l10n.settingsSectionSecurity),
                _SectionCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.lock_outline_rounded,
                      label: l10n.settingsRowChangePassword,
                      onTap: _onChangePassword,
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.tune_rounded,
                      label: l10n.settingsRowLoginOptions,
                      onTap: _onLoginOptions,
                    ),
                    const _RowDivider(),
                    _SettingsToggleRow(
                      icon: Icons.fingerprint_rounded,
                      label: l10n.settingsRowBiometricsLabel,
                      subtitle: l10n.settingsRowBiometricsSubtitle,
                      value: _biometricsEnabled,
                      onChanged: (v) =>
                          setState(() => _biometricsEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _SectionLabel(l10n.settingsSectionTransactions),
                _SectionCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.smartphone_rounded,
                      label: l10n.settingsRowPhoneNumberAccount,
                      onTap: _onPhoneNumberAccount,
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.tag_rounded,
                      label: l10n.settingsRowUssdBanking,
                      onTap: _onUssdBanking,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _SectionLabel(l10n.settingsSectionActions),
                _SectionCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.delete_outline_rounded,
                      iconColor: const Color(0xFFFF4D2E),
                      labelColor: const Color(0xFFFF4D2E),
                      label: l10n.settingsRowDeleteAccount,
                      onTap: _onDeleteAccount,
                      showChevron: false,
                    ),
                  ],
                ),
                SizedBox(
                  height: widget.showBackButton
                      ? 32
                      // Hosted inside HomeShell which uses extendBody:true,
                      // so we must clear the 64dp bottom nav + system inset.
                      : 32 + 64 + MediaQuery.paddingOf(context).bottom,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Standard left-aligned chevron + title header.
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  /// When `null`, the back chevron is omitted (used when Settings is
  /// hosted as a bottom-nav tab). When non-null, renders the standard
  /// chevron-left button.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasBack = onBack != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(hasBack ? 8 : 24, 4, 24, 0),
      child: Row(
        children: [
          if (hasBack) ...[
            BackChevronButton(onTap: onBack!, tooltip: l10n.commonBack),
          ] else
            // Match the vertical rhythm of the chevron variant so the
            // title sits at the same baseline regardless of mode.
            const SizedBox(height: 48),
          Text(
            l10n.settingsTitle,
            style: AppTextStyles.screenTitle,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withValues(alpha: 0.06),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? Colors.white,
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: labelColor != null
                    ? AppTextStyles.label.copyWith(color: labelColor)
                    : AppTextStyles.label,
              ),
            ),
            if (showChevron)
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.40),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.label,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.actionPurple,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.20),
          ),
        ],
      ),
    );
  }
}
