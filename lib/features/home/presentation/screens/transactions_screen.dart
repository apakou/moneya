import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Placeholder Transactions tab. The real list will be wired up once the
/// transactions feature lands.
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Transactions',
                style: TextStyle(
                  color: AppColors.onBrand,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: Text(
                    'Your transaction history will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.onBrandMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
