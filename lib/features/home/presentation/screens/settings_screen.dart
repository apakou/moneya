import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

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
  const SettingsScreen({super.key});

  static const String routePath = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricsEnabled = true;

  void _onChangePassword() => debugPrint('TODO: open change-password flow');
  void _onLoginOptions() => debugPrint('TODO: open login options');
  void _onPhoneNumberAccount() =>
      debugPrint('TODO: open phone-number-account settings');
  void _onUssdBanking() => debugPrint('TODO: open USSD banking settings');

  Future<void> _onDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F23),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete account?',
          style: AppTextStyles.screenTitle,
        ),
        content: Text(
          'This permanently removes your MoneyA account, balances, and '
          'transaction history. This action cannot be undone.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(
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
      debugPrint('TODO: delete account confirmed');
    }
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
                _Header(onBack: () => Navigator.of(context).maybePop()),
                const SizedBox(height: 28),
                const _SectionLabel('Security & Privacy'),
                _SectionCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.lock_outline_rounded,
                      label: 'Change Password',
                      onTap: _onChangePassword,
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.tune_rounded,
                      label: 'Login Options',
                      onTap: _onLoginOptions,
                    ),
                    const _RowDivider(),
                    _SettingsToggleRow(
                      icon: Icons.fingerprint_rounded,
                      label: 'Biometrics for transactions',
                      subtitle: 'Authenticate transactions with biometrics',
                      value: _biometricsEnabled,
                      onChanged: (v) =>
                          setState(() => _biometricsEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionLabel('Transactions'),
                _SectionCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.smartphone_rounded,
                      label: 'Phone Number Account',
                      onTap: _onPhoneNumberAccount,
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.tag_rounded,
                      label: 'USSD Banking',
                      onTap: _onUssdBanking,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SectionLabel('Actions'),
                _SectionCard(
                  children: [
                    _SettingsRow(
                      icon: Icons.delete_outline_rounded,
                      iconColor: const Color(0xFFFF4D2E),
                      labelColor: const Color(0xFFFF4D2E),
                      label: 'Delete Account',
                      onTap: _onDeleteAccount,
                      showChevron: false,
                    ),
                  ],
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
// Standard left-aligned chevron + title header.
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 24, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
              size: 28,
            ),
            splashRadius: 24,
          ),
          const Text(
            'Settings',
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
