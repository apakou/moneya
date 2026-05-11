import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import '../../../../core/format/money_format.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/back_chevron_button.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../auth/domain/supported_country.dart';
import '../../../home/domain/supported_currency.dart';
import '../../data/recipient_lookup_service.dart';
import '../../domain/funding_provider.dart';
import '../../domain/recipient_lookup.dart';
import '../../domain/transfer_recipient_prefill.dart';
import '../widgets/amount_keypad_sheet.dart';
import '../widgets/country_picker_sheet.dart';
import '../widgets/funding_provider_picker_sheet.dart';
import 'payment_confirm_screen.dart';

/// Send Money / Transfer Money screen.
///
/// Two phone fields:
/// * **From** — the sender's *own* mobile-money number on the chosen
///   funding provider (e.g., the Moov number being debited). Typed
///   manually; validated against the chosen sender country with
///   [PhoneNumber] from `phone_numbers_parser`. No directory lookup.
/// * **To** — the recipient's number. Can be typed or picked from the
///   device contact book (`flutter_contacts`, TODO). On every keystroke
///   we look the number up in MoneyA's directory:
///   * [RecipientFound] → name auto-fills (read-only); funds route to
///     their wallet.
///   * [RecipientNotFound] → name is editable so the sender can type a
///     name for the SMS-invite flow (escrow funds, send invite, release
///     on signup + phone verification).
///
/// Today this screen is purely UI + a stub [RecipientLookupService] —
/// no real lookup, no SMS, no balance debit. Confirm just `debugPrint`s
/// the structured intent and pops.
class TransferMoneyScreen extends StatefulWidget {
  const TransferMoneyScreen({
    required this.currency,
    this.prefill,
    super.key,
  });

  /// Currency the sender is debited in. Driven by the home screen's
  /// currency pill for now; will move to a Riverpod provider later.
  final SupportedCurrency currency;

  /// Optional recipient prefill — set when the transfer is opened from
  /// a deep entry point that already knows the recipient (e.g. tapping
  /// a favorite avatar on Home). When non-null, the recipient country,
  /// phone, and display name are populated and the directory lookup
  /// runs immediately so the "Found" badge appears without typing.
  final TransferRecipientPrefill? prefill;

  static const String routePath = '/transfer';

  @override
  State<TransferMoneyScreen> createState() => _TransferMoneyScreenState();
}

class _TransferMoneyScreenState extends State<TransferMoneyScreen> {
  // -- Stub configuration -----------------------------------------------------
  /// Flat fee rate. Replace with backend-driven pricing once available.
  static const double _feeRate = 0.01;

  // -- State ------------------------------------------------------------------
  // From (sender-side).
  SupportedCountry _senderCountry = SupportedCountry.ivoryCoast;
  FundingProvider _provider = FundingProvider.moovAfrica;
  final _senderPhoneController = TextEditingController();
  bool _senderPhoneValid = false;

  // To (recipient-side). Default to the same corridor as the sender so
  // the prefix doesn't surprise the user; they can switch it.
  SupportedCountry _recipientCountry = SupportedCountry.ivoryCoast;
  final _recipientPhoneController = TextEditingController();
  final _recipientNameController = TextEditingController();
  bool _recipientPhoneValid = false;

  // Amount + purpose.
  String _amount = '2000'; // matches the mock; numeric string.
  final _purposeController = TextEditingController();

  // Recipient directory lookup.
  final _lookupService = const RecipientLookupService();
  RecipientLookupResult? _lookupResult;
  bool _lookingUp = false;
  // Debounce token: incremented on every change so stale callbacks
  // don't overwrite a newer state.
  int _lookupRequestId = 0;

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    if (prefill != null) {
      _recipientCountry = prefill.country;
      _recipientPhoneController.text = prefill.nationalPhone;
      _recipientNameController.text = prefill.displayName;
      _recipientPhoneValid = _validatePhone(
        prefill.nationalPhone,
        prefill.country,
      );
      // Kick off the directory lookup right away so the user sees the
      // "Found" badge resolve without typing. If the number is in the
      // directory, the canonical name overwrites the favorite's name.
      if (prefill.nationalPhone.isNotEmpty) {
        // Defer until after first frame so setState inside the lookup
        // doesn't fire during build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _runRecipientLookup(prefill.nationalPhone);
        });
      }
    }
  }

  @override
  void dispose() {
    _senderPhoneController.dispose();
    _recipientPhoneController.dispose();
    _recipientNameController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  // -- Phone validation -------------------------------------------------------
  static IsoCode _isoOf(SupportedCountry country) =>
      IsoCode.values.firstWhere((c) => c.name.toUpperCase() == country.isoCode);

  static bool _validatePhone(String raw, SupportedCountry country) {
    if (raw.trim().isEmpty) return false;
    try {
      final parsed = PhoneNumber.parse(raw, callerCountry: _isoOf(country));
      return parsed.isValid();
    } catch (_) {
      return false;
    }
  }

  // -- Derived values ---------------------------------------------------------
  double get _amountValue => double.tryParse(_amount) ?? 0;
  double get _feeValue => _amountValue * _feeRate;
  double get _payoutValue => _amountValue - _feeValue;

  bool get _canConfirm =>
      _amountValue > 0 &&
      _senderPhoneValid &&
      _recipientPhoneValid &&
      _recipientNameController.text.trim().isNotEmpty &&
      !_lookingUp;

  // -- Actions: amount / sender chips ----------------------------------------
  Future<void> _onAmountTap() async {
    final result = await showAmountKeypadSheet(
      context: context,
      currencyCode: widget.currency.code,
      initialAmount: _amount,
    );
    if (!mounted || result == null) return;
    setState(() => _amount = result);
  }

  Future<void> _onSenderCountryTap() async {
    final picked = await showTransferCountryPickerSheet(
      context: context,
      selected: _senderCountry,
    );
    if (!mounted || picked == null || picked == _senderCountry) return;
    setState(() {
      _senderCountry = picked;
      _senderPhoneValid = _validatePhone(
        _senderPhoneController.text,
        _senderCountry,
      );
    });
  }

  Future<void> _onProviderTap() async {
    final picked = await showFundingProviderPickerSheet(
      context: context,
      selected: _provider,
    );
    if (!mounted || picked == null || picked == _provider) return;
    setState(() => _provider = picked);
  }

  void _onSenderPhoneChanged(String value) {
    final next = _validatePhone(value, _senderCountry);
    if (next != _senderPhoneValid) {
      setState(() => _senderPhoneValid = next);
    }
  }

  // -- Actions: recipient -----------------------------------------------------
  Future<void> _onRecipientCountryTap() async {
    final picked = await showTransferCountryPickerSheet(
      context: context,
      selected: _recipientCountry,
    );
    if (!mounted || picked == null || picked == _recipientCountry) return;
    setState(() {
      _recipientCountry = picked;
      // Same digits + new prefix == different E.164. Re-validate and
      // re-run the directory lookup.
      _recipientPhoneValid = _validatePhone(
        _recipientPhoneController.text,
        _recipientCountry,
      );
      _lookupResult = null;
    });
    if (_recipientPhoneController.text.trim().isNotEmpty) {
      _runRecipientLookup(_recipientPhoneController.text);
    }
  }

  void _onRecipientPhoneChanged(String value) {
    final isValid = _validatePhone(value, _recipientCountry);
    setState(() => _recipientPhoneValid = isValid);

    final id = ++_lookupRequestId;
    if (value.trim().isEmpty) {
      setState(() {
        _lookupResult = null;
        _lookingUp = false;
        _recipientNameController.text = '';
      });
      return;
    }
    setState(() => _lookingUp = true);
    _lookupAsync(value, id);
  }

  Future<void> _runRecipientLookup(String value) async {
    final id = ++_lookupRequestId;
    setState(() => _lookingUp = true);
    await _lookupAsync(value, id);
  }

  Future<void> _lookupAsync(String rawPhone, int requestId) async {
    final result = await _lookupService.lookup(
      '${_recipientCountry.dialCode}$rawPhone',
    );
    if (!mounted || requestId != _lookupRequestId) return;
    setState(() {
      _lookupResult = result;
      _lookingUp = false;
      if (result is RecipientFound) {
        _recipientNameController.text = result.displayName;
      }
      // On NotFound: leave the name field as-is so the user can type
      // (or keep what they typed before the lookup completed).
    });
  }

  Future<void> _onPickFromContacts() async {
    // Ask for READ_CONTACTS up front. Android's system picker
    // (ACTION_PICK) technically does not require it — the OS handles
    // selection — but `flutter_contacts` reads the picked contact's
    // properties via the ContentResolver on return, which DOES need
    // the runtime permission on API 23+. Without it some OEMs
    // SIGKILL the activity instead of throwing a SecurityException.
    final granted = await _ensureContactsPermission();
    if (!mounted || !granted) return;

    Contact? picked;
    try {
      picked = await FlutterContacts.openExternalPick();
    } catch (e, st) {
      debugPrint('openExternalPick threw: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).transferContactPickerError,
          ),
        ),
      );
      return;
    }
    if (!mounted || picked == null) return;

    // Defer to the next frame so the picker activity is fully torn
    // down before we re-fetch the contact. Touching ContentResolver
    // while the activity is still resuming has been observed to
    // SIGKILL the process on some OEMs.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    // `openExternalPick()` returns a *light* Contact (id + display
    // name + the single phone the user tapped on iOS; on Android the
    // returned object can be missing phones entirely). Re-fetch the
    // full record by id with properties so we always have phones.
    Contact? full;
    try {
      full = await FlutterContacts.getContact(
        picked.id,
        withProperties: true,
        withThumbnail: false,
        withPhoto: false,
      );
    } catch (e, st) {
      debugPrint('getContact threw: $e\n$st');
    }
    final contact = full ?? picked;

    final phones = contact.phones;
    if (phones.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).transferContactNoPhone,
          ),
        ),
      );
      return;
    }
    final rawPhone = phones.first.number.trim();
    if (rawPhone.isEmpty) return;

    final displayName = contact.displayName.trim();
    _applyPickedContact(rawPhone: rawPhone, displayName: displayName);
  }

  Future<bool> _ensureContactsPermission() async {
    final status = await Permission.contacts.request();
    if (status.isGranted) return true;
    if (!mounted) return false;
    await _handleContactsPermissionDenied();
    return false;
  }

  /// Normalize a phone string returned by the OS contact book and push
  /// it into the recipient fields.
  ///
  /// Strategy (per user-confirmed plan):
  /// * If the number parses with a country prefix, switch
  ///   [_recipientCountry] to match (when the country is one of our
  ///   [SupportedCountry] values) and store the national-significant
  ///   number in the controller.
  /// * Otherwise treat it as already in the currently selected
  ///   recipient corridor — strip non-digits and any leading zero
  ///   (West-African MoMo numbers are dialed locally as `07xxxxxxxx`
  ///   but stored as `7xxxxxxxx` once the dial code is prepended).
  void _applyPickedContact({
    required String rawPhone,
    required String displayName,
  }) {
    String nationalDigits;
    SupportedCountry country = _recipientCountry;

    final hasIntlPrefix = rawPhone.startsWith('+') || rawPhone.startsWith('00');
    if (hasIntlPrefix) {
      try {
        final parsed = PhoneNumber.parse(
          rawPhone.startsWith('00') ? '+${rawPhone.substring(2)}' : rawPhone,
        );
        nationalDigits = parsed.nsn;
        final matched = _supportedCountryForIso(parsed.isoCode.name);
        if (matched != null && matched != _recipientCountry) {
          debugPrint(
            'Contact prefix switched recipient country: '
            '${_recipientCountry.isoCode} → ${matched.isoCode}',
          );
          country = matched;
        }
      } catch (_) {
        nationalDigits = _digitsOnly(rawPhone);
      }
    } else {
      // Local format — strip non-digits and a single leading zero.
      var digits = _digitsOnly(rawPhone);
      if (digits.startsWith('0')) digits = digits.substring(1);
      nationalDigits = digits;
    }

    setState(() {
      _recipientCountry = country;
      _recipientPhoneController.text = nationalDigits;
      _recipientPhoneValid = _validatePhone(nationalDigits, country);
      // Pre-fill the name with the contact's display name. If the
      // directory lookup later resolves to a MoneyA user it will
      // overwrite this with the canonical account name.
      if (displayName.isNotEmpty) {
        _recipientNameController.text = displayName;
      }
      _lookupResult = null;
    });

    if (nationalDigits.isNotEmpty) {
      _runRecipientLookup(nationalDigits);
    }
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Map a `phone_numbers_parser` ISO code (e.g. `ci`, `gh`) back to
  /// our [SupportedCountry] enum, or `null` if the prefix belongs to a
  /// country we don't yet ship.
  SupportedCountry? _supportedCountryForIso(String iso) {
    final upper = iso.toUpperCase();
    for (final c in SupportedCountry.values) {
      if (c.isoCode == upper) return c;
    }
    return null;
  }

  Future<void> _handleContactsPermissionDenied() async {
    final status = await Permission.contacts.status;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (status.isPermanentlyDenied) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.transferContactPermissionDeniedPermanent),
          action: SnackBarAction(
            label: l10n.transferContactPermissionDeniedAction,
            onPressed: openAppSettings,
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.transferContactPermissionNeeded),
        ),
      );
    }
  }

  void _onConfirm() {
    if (!_canConfirm) return;
    final isInvite = _lookupResult is RecipientNotFound;
    debugPrint(
      'Transfer confirm: ${widget.currency.code} $_amount '
      'from +${_senderCountry.dialCode}${_senderPhoneController.text} '
      '(${_provider.label}) → '
      '+${_recipientCountry.dialCode}${_recipientPhoneController.text} '
      '(${_recipientNameController.text.trim()}) '
      '${isInvite ? "[SMS invite + escrow]" : "[direct]"}',
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaymentConfirmScreen(
          amount: _amount,
          currency: widget.currency,
          feeAmount: _feeValue,
          netAmount: _payoutValue,
          provider: _provider,
          senderCountry: _senderCountry,
          senderPhoneLocal: _senderPhoneController.text.trim(),
          recipientCountry: _recipientCountry,
          recipientPhoneLocal: _recipientPhoneController.text.trim(),
          recipientName: _recipientNameController.text.trim(),
          lookupResult: _lookupResult,
          purpose: _purposeController.text.trim(),
        ),
      ),
    );
  }

  // -- Build ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.black,
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: SafeArea(
            child: Column(
              children: [
                _Header(onBack: () => Navigator.of(context).maybePop()),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Text(
                            l10n.transferTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _AmountCard(
                          currencyCode: widget.currency.code,
                          amount: _amount,
                          onTap: _onAmountTap,
                        ),
                        const SizedBox(height: 28),
                        // From ------------------------------------------------
                        _SectionLabel(l10n.transferSectionFrom),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _CountryChip(
                                country: _senderCountry,
                                onTap: _onSenderCountryTap,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _ProviderChip(
                                provider: _provider,
                                onTap: _onProviderTap,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _PhoneInputRow(
                          country: _senderCountry,
                          controller: _senderPhoneController,
                          hint: l10n.transferSenderPhoneHint,
                          onChanged: _onSenderPhoneChanged,
                          onClear: () {
                            _senderPhoneController.clear();
                            _onSenderPhoneChanged('');
                          },
                        ),
                        const SizedBox(height: 28),
                        // To --------------------------------------------------
                        _SectionLabel(l10n.transferSectionTo),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _CountryChip(
                                country: _recipientCountry,
                                onTap: _onRecipientCountryTap,
                              ),
                            ),
                            // Reserve balance with the From row so the
                            // To phone field aligns under the sender phone.
                            const SizedBox(width: 12),
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _PhoneInputRow(
                          country: _recipientCountry,
                          controller: _recipientPhoneController,
                          hint: l10n.transferRecipientPhoneHint,
                          onChanged: _onRecipientPhoneChanged,
                          onClear: () {
                            _recipientPhoneController.clear();
                            _onRecipientPhoneChanged('');
                          },
                          // Show the contacts launcher only when the
                          // field is empty — otherwise the clear button
                          // (×) lives in that slot.
                          trailingWhenEmpty: _ContactsLauncherButton(
                            onTap: _onPickFromContacts,
                          ),
                        ),
                        if (_lookingUp || _lookupResult != null) ...[
                          const SizedBox(height: 8),
                          _LookupStatus(
                            looking: _lookingUp,
                            result: _lookupResult,
                          ),
                        ],
                        const SizedBox(height: 12),
                        _NameField(
                          controller: _recipientNameController,
                          // Lock the name when MoneyA already knows the
                          // recipient — it's the source of truth.
                          enabled: _lookupResult is! RecipientFound,
                          onChanged: (_) => setState(() {}),
                          onClear: () {
                            _recipientNameController.clear();
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 12),
                        _PurposeField(controller: _purposeController),
                        const SizedBox(height: 24),
                        _FeeRow(
                          label: l10n.transferFeeLabel,
                          value:
                              '${widget.currency.code} ${_formatAmount(_feeValue)}',
                        ),
                        const SizedBox(height: 8),
                        _FeeRow(
                          label: l10n.transferRecipientReceivesLabel,
                          value:
                              '${widget.currency.code} ${_formatAmount(_payoutValue)}',
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _canConfirm ? _onConfirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white.withValues(
                          alpha: 0.35,
                        ),
                        foregroundColor: AppColors.actionPurple,
                        disabledForegroundColor: AppColors.actionPurple
                            .withValues(alpha: 0.65),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        l10n.transferConfirmCta,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
// Subcomponents
// ---------------------------------------------------------------------------

String _formatAmount(double value) => MoneyFormat.fromNum(value);

/// Render-time resolver for [FundingProvider] display names. The enum's
/// `label` field is kept for debug logs (per the `directionLabel`
/// precedent on [Transaction]); user-visible strings come through here.
String fundingProviderLabel(FundingProvider provider, AppLocalizations l10n) {
  return switch (provider) {
    FundingProvider.moneyaWallet => l10n.fundingProviderMoneyaWallet,
    FundingProvider.moovAfrica => l10n.fundingProviderMoovAfrica,
    FundingProvider.orangeMoney => l10n.fundingProviderOrangeMoney,
    FundingProvider.mtnMomo => l10n.fundingProviderMtnMomo,
    FundingProvider.wave => l10n.fundingProviderWave,
  };
}

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
            l10n.transferHeaderTitle,
            style: AppTextStyles.screenTitle,
          ),
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.currencyCode,
    required this.amount,
    required this.onTap,
  });

  final String currencyCode;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, right: 8),
                  child: Text(
                    currencyCode,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                HeroTextScaleClamp(
                  child: Text(
                    amount,
                    style: AppTextStyles.heroAmount,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.65),
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Reusable rounded "pill" container for the chips and inputs. Fixed
/// 56dp height to match the iOS HIG / Material 3 input/CTA size we use
/// across the app.
class _PillContainer extends StatelessWidget {
  const _PillContainer({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _CountryChip extends StatelessWidget {
  const _CountryChip({required this.country, required this.onTap});

  final SupportedCountry country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: _PillContainer(
          child: Row(
            children: [
              CountryFlag.fromCountryCode(
                country.isoCode,
                theme: const ImageTheme(width: 24, height: 24, shape: Circle()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  country.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                color: Colors.white.withValues(alpha: 0.65),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({required this.provider, required this.onTap});

  final FundingProvider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: _PillContainer(
          child: Row(
            children: [
              _ProviderInlineGlyph(provider: provider),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fundingProviderLabel(provider, l10n),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                color: Colors.white.withValues(alpha: 0.65),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderInlineGlyph extends StatelessWidget {
  const _ProviderInlineGlyph({required this.provider});

  final FundingProvider provider;

  @override
  Widget build(BuildContext context) {
    final asset = provider.iconAsset;
    if (asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          asset,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          errorBuilder: (ctx, _, _) => _initialFallback(ctx),
        ),
      );
    }
    return _initialFallback(context);
  }

  Widget _initialFallback(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: AppColors.actionPurple.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        fundingProviderLabel(provider, l10n).characters.first.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Generic phone input row used for both From (sender) and To
/// (recipient). Renders a dial-code chip + a TextField. Optionally
/// shows a custom trailing widget when the field is empty (used to
/// host the contacts launcher on the recipient row).
class _PhoneInputRow extends StatelessWidget {
  const _PhoneInputRow({
    required this.country,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    this.trailingWhenEmpty,
  });

  final SupportedCountry country;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Widget? trailingWhenEmpty;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Dial-code chip — non-tappable; the country chip above drives it.
        _PillContainer(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountryFlag.fromCountryCode(
                country.isoCode,
                theme: const ImageTheme(width: 22, height: 22, shape: Circle()),
              ),
              const SizedBox(width: 8),
              Text(
                '(${country.dialCode})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PillContainer(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                    ],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      hintText: hint,
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.40),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  _CircleClearButton(onTap: onClear)
                else
                  ?trailingWhenEmpty,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _PillContainer(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                hintText: 'Recipient name',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40),
                  fontSize: 15,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          if (enabled && controller.text.isNotEmpty)
            _CircleClearButton(onTap: onClear),
        ],
      ),
    );
  }
}

class _PurposeField extends StatelessWidget {
  const _PurposeField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        maxLines: 4,
        minLines: 4,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        decoration: InputDecoration(
          isCollapsed: true,
          hintText: 'Purpose (Optional)',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.40),
            fontSize: 15,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _CircleClearButton extends StatelessWidget {
  const _CircleClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
      ),
    );
  }
}

class _ContactsLauncherButton extends StatelessWidget {
  const _ContactsLauncherButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.actionPurple.withValues(alpha: 0.20),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.contacts_rounded,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }
}

class _LookupStatus extends StatelessWidget {
  const _LookupStatus({required this.looking, required this.result});

  final bool looking;
  final RecipientLookupResult? result;

  @override
  Widget build(BuildContext context) {
    if (looking) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Checking MoneyA directory…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
            ),
          ),
        ],
      );
    }
    final r = result;
    if (r is RecipientFound) {
      return Row(
        children: [
          const Icon(
            Icons.verified_rounded,
            color: Color(0xFF22C55E),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'MoneyA user found — ${r.displayName}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF22C55E),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }
    if (r is RecipientNotFound) {
      return Row(
        children: [
          const Icon(Icons.sms_rounded, color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Not on MoneyA yet. They\'ll get an SMS invite to claim this transfer.',
              style: TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label : ',
          style: AppTextStyles.bodyMuted,
        ),
        Text(
          value,
          style: AppTextStyles.numeric(AppTextStyles.pillLabel),
        ),
      ],
    );
  }
}
