import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/document_side.dart';
import '../../domain/kyc_document_type.dart';
import 'capture_document_screen.dart';

/// Choose KYC document screen.
///
/// First step of KYC after biometric enrollment. Lets the user pick the
/// identity document they intend to capture in the next step (camera). Only
/// National ID and Passport are accepted at MVP — see [KycDocumentType] for
/// rationale.
class ChooseKycDocumentScreen extends StatefulWidget {
  const ChooseKycDocumentScreen({super.key});

  static const String routePath = '/auth/kyc/choose-document';

  @override
  State<ChooseKycDocumentScreen> createState() =>
      _ChooseKycDocumentScreenState();
}

class _ChooseKycDocumentScreenState extends State<ChooseKycDocumentScreen> {
  // Mock pre-selects National ID; mirror that.
  KycDocumentType _selected = KycDocumentType.nationalId;

  void _onContinue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaptureDocumentScreen(
          documentType: _selected,
          side: DocumentSide.front,
        ),
      ),
    );
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
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.onBrand,
                      size: 20,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(flex: 4),
                      Text(
                        'Pick a document to verify\nyour identity',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.heroOnboarding.copyWith(
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "We don't accept scans or copies.",
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyOnboardingMuted,
                      ),
                      const SizedBox(height: 28),
                      _DocumentChoiceCard(
                        selected: _selected,
                        onChanged: (v) => setState(() => _selected = v),
                      ),
                      const Spacer(flex: 5),
                      _ContinueButton(onPressed: _onContinue),
                      const Spacer(flex: 1),
                    ],
                  ),
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
// Pieces
// ---------------------------------------------------------------------------

/// Translucent rounded card grouping the two document options.
class _DocumentChoiceCard extends StatelessWidget {
  const _DocumentChoiceCard({
    required this.selected,
    required this.onChanged,
  });

  final KycDocumentType selected;
  final ValueChanged<KycDocumentType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          _DocumentOptionTile(
            type: KycDocumentType.nationalId,
            icon: Icons.badge_outlined,
            isSelected: selected == KycDocumentType.nationalId,
            onTap: () => onChanged(KycDocumentType.nationalId),
          ),
          _DocumentOptionTile(
            type: KycDocumentType.passport,
            icon: Icons.book_outlined,
            isSelected: selected == KycDocumentType.passport,
            onTap: () => onChanged(KycDocumentType.passport),
          ),
        ],
      ),
    );
  }
}

/// A single radio + circular icon + label row.
class _DocumentOptionTile extends StatelessWidget {
  const _DocumentOptionTile({
    required this.type,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final KycDocumentType type;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: type.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              _RadioDot(selected: isSelected),
              const SizedBox(width: 16),
              _IconBadge(icon: icon),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  type.label,
                  style: AppTextStyles.inputText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom radio dot. Outer ring + inner filled disc when selected.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: selected ? 0.95 : 0.55),
                width: 2,
              ),
            ),
          ),
          if (selected)
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

/// Translucent purple circular icon badge.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.actionPurple.withValues(alpha: 0.28),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: AppColors.onBrand),
    );
  }
}

/// White pill primary CTA with purple label. Always enabled here since the
/// mock pre-selects an option.
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.white,
        shape: const StadiumBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Center(
            child: Text(
              'Continue',
              style: AppTextStyles.subsectionTitle.copyWith(
                color: AppColors.actionPurple,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
