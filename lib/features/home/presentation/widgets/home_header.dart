import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// UI languages exposed in the top-right pill across the home shell
/// tabs. Lives at module scope (not inside [HomeHeader]) because both
/// `HomeScreen` and `TransactionsScreen` hold their own language state
/// today; once we wire real l10n + a locale provider, both call sites
/// should read from that instead.
enum UiLanguage {
  en('assets/images/Great Britain.png'),
  fr('assets/images/France.png');

  const UiLanguage(this.flagAssetPath);

  final String flagAssetPath;
}

/// Shared top-row used by every tab inside `HomeShell`:
/// avatar + user name on the left, language flag pill + notification
/// pill on the right.
///
/// Why this exists: the home tab and the transactions tab both render
/// the exact same chrome. Before extraction, the transactions screen
/// hardcoded the GB flag, which would silently drift from the home
/// tab once the user toggled language on home. With both tabs going
/// through this widget we keep the visual contract in one place; the
/// per-tab state objects stay independent until a real locale
/// provider lands.
///
/// All taps are passed through as callbacks — the widget owns no
/// state of its own, which keeps it cheap to embed inside any
/// scrollable.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.userName,
    required this.language,
    required this.onProfileTap,
    required this.onLanguageTap,
    required this.onNotificationsTap,
  });

  final String userName;
  final UiLanguage language;
  final VoidCallback onProfileTap;
  final VoidCallback onLanguageTap;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkResponse(
          onTap: onProfileTap,
          radius: 32,
          child: const CircleAvatar(
            radius: 26,
            backgroundColor: Color(0xFF3D2817),
            child: Icon(Icons.person_rounded, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            userName,
            style: const TextStyle(
              color: AppColors.onBrand,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        HomeIconButton(
          tooltip: 'Language',
          onTap: onLanguageTap,
          // Round flag PNG for the active language. Clipped to a
          // circle so the rectangular asset reads as a flag chip.
          child: ClipOval(
            child: Image.asset(
              language.flagAssetPath,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 10),
        HomeIconButton(
          tooltip: 'Notifications',
          onTap: onNotificationsTap,
          child: Image.asset(
            'assets/images/Notification.png',
            width: 22,
            height: 22,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }
}

/// 40dp rounded-square icon button used on the home shell:
/// language pill, notifications pill, transactions export pill, etc.
///
/// Public so screens that compose [HomeHeader] alongside their own
/// trailing buttons (e.g. the transactions export pill) can match
/// the chrome without redefining the surface treatment.
class HomeIconButton extends StatelessWidget {
  const HomeIconButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
