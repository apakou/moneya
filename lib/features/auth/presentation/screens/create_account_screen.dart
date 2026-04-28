import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/supported_country.dart';
import 'verify_phone_screen.dart';

/// Phone-number registration screen.
///
/// One-field signup: country code chip + national-number input. The Create
/// Account button stays disabled until the entered number is a valid E.164
/// phone for the chosen country.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  static const String routePath = '/auth/create-account';
  static const String routeName = 'create_account';

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocus = FocusNode();
  SupportedCountry _country = SupportedCountry.togo;
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_revalidate);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_revalidate);
    _phoneController.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  void _revalidate() {
    final next = _validate(_phoneController.text, _country);
    if (next != _isValid) setState(() => _isValid = next);
  }

  static bool _validate(String raw, SupportedCountry country) {
    if (raw.trim().isEmpty) return false;
    try {
      final parsed = PhoneNumber.parse(raw, callerCountry: _isoOf(country));
      return parsed.isValid();
    } catch (_) {
      return false;
    }
  }

  static IsoCode _isoOf(SupportedCountry country) =>
      IsoCode.values.firstWhere(
        (c) => c.name.toUpperCase() == country.isoCode,
      );

  /// Returns the entered phone formatted as international `+228 90 89 75 36`.
  /// Falls back to `+[dial] [raw]` if parsing fails.
  static String _formatInternational(String raw, SupportedCountry country) {
    try {
      final parsed = PhoneNumber.parse(raw, callerCountry: _isoOf(country));
      final nsn = parsed.formatNsn();
      return '+${country.dialCode} $nsn';
    } catch (_) {
      return '+${country.dialCode} ${raw.trim()}';
    }
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<SupportedCountry>(
      context: context,
      backgroundColor: AppColors.brandPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _CountryPickerSheet(selected: _country),
    );
    if (picked != null && picked != _country) {
      setState(() => _country = picked);
      _revalidate();
    }
  }

  Future<void> _submit() async {
    if (!_isValid) return;
    FocusScope.of(context).unfocus();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      barrierColor: Colors.black.withValues(alpha: 0.55),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _ConfirmNumberSheet(
        country: _country,
        formattedNumber: _formatInternational(
          _phoneController.text,
          _country,
        ),
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VerifyPhoneScreen(
            dialCode: _country.dialCode,
            nationalNumber: _phoneController.text,
          ),
        ),
      );
    }
  }

  void _goToLogin() {
    // TODO: replace with LoginScreen once it exists.
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
        resizeToAvoidBottomInset: true,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 4),

                  // --- Header ---
                  const Text(
                    'Create New Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.onBrand,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Just enter your phone number and we're set.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.onBrandMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // --- Country chip + phone input ---
                  Row(
                    children: [
                      _CountryChip(
                        country: _country,
                        onTap: _pickCountry,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PhoneField(
                          controller: _phoneController,
                          focusNode: _phoneFocus,
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // --- "Already have an account ? Login" inline link ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const Text(
                        'Already have an account ? ',
                        style: TextStyle(
                          color: AppColors.onBrandMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      _InlineLink(label: 'Login', onTap: _goToLogin),
                    ],
                  ),

                  const Spacer(flex: 2),

                  // --- Primary CTA ---
                  _PrimaryPillButton(
                    label: 'Create Account',
                    enabled: _isValid,
                    onPressed: _submit,
                  ),

                  const Spacer(flex: 5),
                ],
              ),
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

/// Pill-shaped country chip displaying flag + dial code, opens a bottom sheet
/// picker on tap.
class _CountryChip extends StatelessWidget {
  const _CountryChip({required this.country, required this.onTap});

  final SupportedCountry country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountryFlag.fromCountryCode(
                country.isoCode,
                theme: const ImageTheme(
                  width: 28,
                  height: 28,
                  shape: Circle(),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '+${country.dialCode}',
                style: const TextStyle(
                  color: AppColors.onBrand,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone-number text field with a translucent dark fill, white text, muted
/// placeholder, and a translucent border that brightens on focus.
class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      cursorColor: AppColors.onBrand,
      style: const TextStyle(
        color: AppColors.onBrand,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9 \-]')),
        LengthLimitingTextInputFormatter(20),
      ],
      decoration: InputDecoration(
        hintText: 'Enter your phone number',
        hintStyle: const TextStyle(
          color: AppColors.onBrandMuted,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: AppColors.surfaceDark,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              tooltip: 'Clear',
              splashRadius: 18,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.70),
              ),
              onPressed: () {
                controller.clear();
                focusNode.requestFocus();
              },
            );
          },
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.32)),
        ),
      ),
    );
  }
}

/// Inline tappable link rendered as a `Text` with the action color.
class _InlineLink extends StatelessWidget {
  const _InlineLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.actionPurple,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Full-width pill primary button with a disabled state.
class _PrimaryPillButton extends StatelessWidget {
  const _PrimaryPillButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bg = enabled
        ? AppColors.actionPurple
        : AppColors.actionPurple.withValues(alpha: 0.35);
    final fg = enabled
        ? AppColors.onBrand
        : AppColors.onBrand.withValues(alpha: 0.60);

    return SizedBox(
      height: 56,
      child: Material(
        color: bg,
        shape: const StadiumBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet country picker: simple list of [SupportedCountry] entries.
class _CountryPickerSheet extends StatelessWidget {
  const _CountryPickerSheet({required this.selected});

  final SupportedCountry selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle.
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select country',
                  style: TextStyle(
                    color: AppColors.onBrand,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: SupportedCountry.values.length,
                itemBuilder: (context, i) {
                  final c = SupportedCountry.values[i];
                  final isSelected = c == selected;
                  return ListTile(
                    leading: CountryFlag.fromCountryCode(
                      c.isoCode,
                      theme: const ImageTheme(
                        width: 36,
                        height: 36,
                        shape: Circle(),
                      ),
                    ),
                    title: Text(
                      c.label,
                      style: const TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Text(
                      '+${c.dialCode}',
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.actionPurple
                            : AppColors.onBrandMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet confirming the entered phone number before triggering OTP.
///
/// Pops `true` if the user taps "Confirm", `false` (or `null` on dismiss) if
/// they tap "Go back".
class _ConfirmNumberSheet extends StatelessWidget {
  const _ConfirmNumberSheet({
    required this.country,
    required this.formattedNumber,
  });

  final SupportedCountry country;
  final String formattedNumber;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle.
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Confirm the phone number',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onBrand,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "We'll send a verification code to this number.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onBrandMuted,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 24),

            // Number row: round flag + formatted E.164.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                children: [
                  CountryFlag.fromCountryCode(
                    country.isoCode,
                    theme: const ImageTheme(
                      width: 28,
                      height: 28,
                      shape: Circle(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      formattedNumber,
                      style: const TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            _PrimaryPillButton(
              label: 'Confirm',
              enabled: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 12),

            // "Go back" outlined / ghost button.
            SizedBox(
              height: 56,
              child: Material(
                color: Colors.transparent,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => Navigator.of(context).pop(false),
                  child: const Center(
                    child: Text(
                      'Go back',
                      style: TextStyle(
                        color: AppColors.onBrand,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
