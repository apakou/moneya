import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/domain/supported_country.dart';
import '../../data/favorites_service.dart';

/// Card shown on `PaymentSuccessScreen` that offers to save the
/// just-paid recipient as a favourite.
///
/// ## Visibility rules (enforced by the parent)
///
/// The parent screen decides whether to render this widget. It
/// should hide the card when:
/// 1. The transfer was an SMS invite + escrow ([isInvite] = true on
///    the success screen) — the recipient isn't on MoneyA yet and
///    we don't want to surface a favourite that can't currently
///    receive money in one tap.
/// 2. The recipient is already a favourite (per
///    `FavoritesService.contains`) — re-prompting would be noise.
///
/// ## States
///
/// Stateful because the user's tap flips the card to a confirmation
/// in place: the card body changes to "Added to favourites" and the
/// CTA disappears. We deliberately do NOT auto-dismiss the card or
/// navigate anywhere after the tap — the success screen is terminal,
/// and the user still wants to see the green check + amount confirmation.
class AddToFavoritesCard extends StatefulWidget {
  const AddToFavoritesCard({
    required this.country,
    required this.nationalPhone,
    required this.displayName,
    this.service,
    super.key,
  });

  final SupportedCountry country;
  final String nationalPhone;
  final String displayName;

  /// Override for tests. When `null`, defers to
  /// `FavoritesService.instance` at tap time.
  final FavoritesService? service;

  @override
  State<AddToFavoritesCard> createState() => _AddToFavoritesCardState();
}

class _AddToFavoritesCardState extends State<AddToFavoritesCard> {
  bool _added = false;

  void _onAdd() {
    final service = widget.service ?? FavoritesService.instance;
    service.add(
      country: widget.country,
      nationalPhone: widget.nationalPhone,
      displayName: widget.displayName,
    );
    setState(() => _added = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: _added ? _buildAddedState(l10n) : _buildPromptState(l10n),
    );
  }

  Widget _buildPromptState(AppLocalizations l10n) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.favorite_border_rounded,
            color: AppColors.onBrand,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.favoritesAddPromptTitle(widget.displayName),
                style: AppTextStyles.listTitle.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                l10n.favoritesAddPromptBody,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          // Tight padding so the CTA sits inside the card's vertical
          // bounds without enlarging the card height.
          style: TextButton.styleFrom(
            foregroundColor: AppColors.onBrand,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: _onAdd,
          child: Text(l10n.favoritesAddCta),
        ),
      ],
    );
  }

  Widget _buildAddedState(AppLocalizations l10n) {
    // Same visual chrome as the prompt state so the card doesn't
    // jump in size on the success screen — only the contents change.
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0x332BC46A), // 20% green
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF2BC46A),
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.favoritesAddedConfirmation,
            style: AppTextStyles.listTitle.copyWith(fontSize: 14),
          ),
        ),
      ],
    );
  }
}
