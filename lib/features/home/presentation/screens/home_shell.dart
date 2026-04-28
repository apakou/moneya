import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../widgets/voice_fab.dart';
import 'home_screen.dart';
import 'transactions_screen.dart';

/// Top-level post-onboarding shell.
///
/// Hosts the bottom navigation bar (Home / Transactions) with a centered
/// floating voice mic button (the primary CTA of the app — "say it,
/// confirm it"). The voice button taps a stub for now; in a later
/// iteration it will open the voice intent capture sheet.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static const String routePath = '/home';

  /// Looks up the nearest enclosing [HomeShell] state so children
  /// (e.g. the Home tab's "View all" button) can switch tabs without
  /// pushing a new route.
  static HomeShellController? of(BuildContext context) =>
      context.findAncestorStateOfType<_HomeShellState>();

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// Public capability surface exposed by [HomeShell.of] so that callers
/// outside this library can switch tabs without depending on the
/// private `_HomeShellState` type.
abstract class HomeShellController {
  /// Switch the visible tab (0 = Home, 1 = Transactions).
  void selectTab(int index);
}

class _HomeShellState extends State<HomeShell>
    implements HomeShellController {
  int _index = 0;

  /// Programmatic tab switch — used by `View all` actions on the Home tab.
  @override
  void selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  static const List<Widget> _tabs = [
    HomeScreen(),
    TransactionsScreen(),
  ];

  void _onVoicePressed() {
    // TODO: open the voice intent capture sheet (see voice-intent-parsing
    // skill — STT + LLM function-calling to extract transfer intent).
    debugPrint('Voice FAB pressed.');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        extendBody: true,
        backgroundColor: AppColors.black,
        body: IndexedStack(index: _index, children: _tabs),
        floatingActionButton: VoiceFab(onPressed: _onVoicePressed),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: _BottomBar(
          index: _index,
          onTap: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: AppColors.black,
      elevation: 0,
      shape: const CircularNotchedRectangle(),
      notchMargin: 10,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Expanded(
              child: _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: index == 0,
                onTap: () => onTap(0),
              ),
            ),
            const SizedBox(width: 96), // notch gap for the oversized FAB
            Expanded(
              child: _NavItem(
                icon: Icons.receipt_long_rounded,
                label: 'Transactions',
                selected: index == 1,
                onTap: () => onTap(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppColors.actionPurple : AppColors.onBrandMuted;
    return InkResponse(
      onTap: onTap,
      radius: 36,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
