// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'MoneyA';

  @override
  String get languageTooltip => 'Language';

  @override
  String get notificationsTooltip => 'Notifications';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get homeTotalBalance => 'Total Balance';

  @override
  String get homeBalanceShow => 'Show balance';

  @override
  String get homeBalanceHide => 'Hide balance';

  @override
  String get homeActionSend => 'Send';

  @override
  String get homeActionReceive => 'Receive';

  @override
  String get homeSectionAiInsights => 'AI Insights';

  @override
  String get homeSectionFavorites => 'Your Favorites';

  @override
  String get homeSectionRecentTransactions => 'Recent transactions';

  @override
  String get homeViewAll => 'View all';

  @override
  String get insightSmartRateTitle => 'Smart Rate';

  @override
  String get insightSmartRateBody => 'Save on your next cross-border transfer.';

  @override
  String get insightTrustScoreTitle => 'Trust Score';

  @override
  String insightTrustScoreBody(String currency, String limit) {
    return 'Unlock micro-loans up to $currency $limit.';
  }

  @override
  String get insightSpendingPulseTitle => 'Spending pulse';

  @override
  String get insightSpendingPulseBody => 'You spent 18% less than last week.';

  @override
  String get txnLabelReceived => 'Received';

  @override
  String get txnLabelSent => 'Sent';

  @override
  String get txnLabelPayed => 'Payed';

  @override
  String get txnStatusSuccess => 'Success';

  @override
  String get txnStatusFailed => 'Failed';

  @override
  String get transactionsTitle => 'Your Transactions';

  @override
  String get transactionsExportTooltip => 'Export';

  @override
  String get transactionsEmpty => 'No transactions match this filter.';

  @override
  String get txnFilterSent => 'Sent';

  @override
  String get txnFilterReceived => 'Received';

  @override
  String get txnFilterSucceeded => 'Succeeded';

  @override
  String get txnFilterPending => 'Pending';

  @override
  String get txnFilterFailed => 'Failed';

  @override
  String get txnStatusPending => 'Pending';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get navHome => 'Home';

  @override
  String get navTransactions => 'Transactions';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonBack => 'Back';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get settingsSectionSecurity => 'Security & Privacy';

  @override
  String get settingsSectionTransactions => 'Transactions';

  @override
  String get settingsSectionActions => 'Actions';

  @override
  String get settingsRowChangePassword => 'Change Password';

  @override
  String get settingsRowLoginOptions => 'Login Options';

  @override
  String get settingsRowBiometricsLabel => 'Biometrics for transactions';

  @override
  String get settingsRowBiometricsSubtitle =>
      'Authenticate transactions with biometrics';

  @override
  String get settingsRowPhoneNumberAccount => 'Phone Number Account';

  @override
  String get settingsRowUssdBanking => 'USSD Banking';

  @override
  String get settingsRowDeleteAccount => 'Delete Account';

  @override
  String get deleteAccountDialogTitle => 'Delete account?';

  @override
  String get deleteAccountDialogBody =>
      'This permanently removes your MoneyA account, balances, and transaction history. This action cannot be undone.';

  @override
  String get profileTitle => 'Profile Details';

  @override
  String get profileSectionPersonal => 'Personal Informations';

  @override
  String get profileSectionActions => 'Actions';

  @override
  String get profileFieldPhone => 'Phone Number';

  @override
  String get profileFieldEmail => 'Email';

  @override
  String get profileFieldAddress => 'Address';

  @override
  String get profileFieldDateOfBirth => 'Date of Birthday';

  @override
  String get profileVerifiedBadge => 'Verified';

  @override
  String get profileActionReferAndEarn => 'Refere and earn';

  @override
  String get profileActionSettings => 'Settings';

  @override
  String get profileActionLogout => 'Logout';

  @override
  String get txnDetailTitle => 'Transaction Details';

  @override
  String get txnDetailStatusSuccess => 'Successful';

  @override
  String get txnDetailStatusPending => 'Pending';

  @override
  String get txnDetailStatusFailed => 'Failed';

  @override
  String get txnDetailDirectionSent => 'Sent';

  @override
  String get txnDetailDirectionReceived => 'Received';

  @override
  String get txnDetailRowFee => 'Fee';

  @override
  String get txnDetailRowTotal => 'Total';

  @override
  String get txnDetailRowPhone => 'Phone';

  @override
  String get txnDetailRowMethod => 'Method';

  @override
  String get txnDetailRowReference => 'Reference';

  @override
  String txnDetailCopiedSnack(String label) {
    return '$label copied';
  }

  @override
  String get txnDetailActionShare => 'Share';

  @override
  String get txnDetailActionDownloadPdf => 'Download PDF';

  @override
  String txnDetailShareSubject(String reference) {
    return 'MoneyA receipt — $reference';
  }

  @override
  String get txnDetailShareHeader => 'MoneyA receipt';

  @override
  String txnDetailShareLineStatus(String status) {
    return 'Status: $status';
  }

  @override
  String txnDetailShareLineDirection(String direction) {
    return 'Direction: $direction';
  }

  @override
  String txnDetailShareLineCounterparty(String label, String name) {
    return '$label: $name';
  }

  @override
  String txnDetailShareLineWhen(String timestamp) {
    return 'When: $timestamp';
  }

  @override
  String txnDetailShareLineAmount(String amount) {
    return 'Amount: $amount';
  }

  @override
  String txnDetailShareLineFee(String fee) {
    return 'Fee: $fee';
  }

  @override
  String txnDetailShareLineTotal(String total) {
    return 'Total: $total';
  }

  @override
  String txnDetailShareLineMethod(String method) {
    return 'Method: $method';
  }

  @override
  String txnDetailShareLinePhone(String phone) {
    return 'Phone: $phone';
  }

  @override
  String txnDetailShareLineReference(String reference) {
    return 'Reference: $reference';
  }

  @override
  String get txnDetailShareFooter => 'Powered by MoneyA';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsMarkAllRead => 'Mark all as read';

  @override
  String get notificationsGroupToday => 'Today';

  @override
  String get notificationsGroupYesterday => 'Yesterday';

  @override
  String get notificationsGroupEarlierWeek => 'Earlier this week';

  @override
  String get notificationsGroupOlder => 'Older';

  @override
  String get notificationsTimeJustNow => 'just now';

  @override
  String notificationsTimeMinutes(int n) {
    return '${n}m';
  }

  @override
  String notificationsTimeHours(int n) {
    return '${n}h';
  }

  @override
  String get notificationsTimeYesterday => 'Yesterday';

  @override
  String notificationsTimeDays(int n) {
    return '${n}d';
  }

  @override
  String get receiveTitle => 'Receive';

  @override
  String get receiveTabAccount => 'Account';

  @override
  String get receiveTabQrCode => 'QR code';

  @override
  String get receiveTabRequest => 'Request';

  @override
  String receiveTabSemanticLabel(String label) {
    return '$label tab';
  }

  @override
  String get receiveTabSemanticHint => 'Double tap to switch';

  @override
  String get receiveAccountVerifiedMember => 'Verified MoneyA member';

  @override
  String get receiveAccountHelpText =>
      'Anyone on MoneyA can send you money instantly using this number.';

  @override
  String get receiveAccountCardLabel => 'MoneyA account number';

  @override
  String get receiveAccountCopyLabel => 'Copy number';

  @override
  String get receiveAccountShareLabel => 'Share';

  @override
  String receiveAccountCopySemantic(String number) {
    return 'Copy account number $number';
  }

  @override
  String get receiveAccountShareSemantic => 'Share account number';

  @override
  String get receiveAccountCopyAnnouncement =>
      'Account number copied to clipboard';

  @override
  String get receiveAccountCopySnack => 'Account number copied';

  @override
  String get receiveAccountShareSubject => 'My MoneyA account number';

  @override
  String receiveAccountShareBody(String number) {
    return 'Send me money on MoneyA. My account number is $number.';
  }

  @override
  String get authLandingTagline => 'Say it. We send it.';

  @override
  String get authLandingLogin => 'Login';

  @override
  String get authLandingCreateAccount => 'Create Account';

  @override
  String get createAccountTitle => 'Create New Account';

  @override
  String get createAccountSubtitle =>
      'Just enter your phone number and we\'re set.';

  @override
  String get createAccountPhoneHint => 'Enter your phone number';

  @override
  String get createAccountClearTooltip => 'Clear';

  @override
  String get createAccountAlreadyHaveAccount => 'Already have an account ? ';

  @override
  String get createAccountLoginLink => 'Login';

  @override
  String get createAccountCta => 'Create Account';

  @override
  String get createAccountPickCountryTitle => 'Select country';

  @override
  String get createAccountConfirmSheetTitle => 'Confirm the phone number';

  @override
  String get createAccountConfirmSheetBody =>
      'We\'ll send a verification code to this number.';

  @override
  String get createAccountConfirmCta => 'Confirm';

  @override
  String get createAccountGoBack => 'Go back';

  @override
  String get countryTogo => 'Togo';

  @override
  String get countrySenegal => 'Senegal';

  @override
  String get countryIvoryCoast => 'Côte d\'Ivoire';

  @override
  String get countryMali => 'Mali';

  @override
  String get countryBurkinaFaso => 'Burkina Faso';

  @override
  String get countryBenin => 'Benin';

  @override
  String get countryNigeria => 'Nigeria';

  @override
  String get countryGhana => 'Ghana';

  @override
  String get verifyPhoneTitle => 'Enter The Code';

  @override
  String verifyPhoneSubtitle(int length, String dialCode, String tail) {
    return 'We sent an $length digit code to your phone number (+$dialCode) … $tail';
  }

  @override
  String get verifyPhoneResendPrompt => 'Didn\'t received the code ?';

  @override
  String get verifyPhoneResendLink => 'Resend the code';

  @override
  String get verifyPhoneIncorrectTitle => 'Incorrect code entered';

  @override
  String get verifyPhoneIncorrectBody =>
      'Please, check the code and try again.';

  @override
  String get verifyPhoneGotIt => 'Got it';

  @override
  String get passcodeSetTitle => 'Set a passcode';

  @override
  String get passcodeConfirmTitle => 'Confirm the passcode';

  @override
  String passcodeSetSubtitle(int length) {
    return 'create a $length digit passcode';
  }

  @override
  String passcodeConfirmSubtitle(int length) {
    return 'Repeat the $length digit passcode';
  }

  @override
  String get passcodeNextCta => 'Next';

  @override
  String get passcodeSaveCta => 'Save';

  @override
  String get passcodeMismatchError => 'Passcodes don\'t match.';

  @override
  String passcodeErrorWrongLength(int length) {
    return 'Use $length digits.';
  }

  @override
  String get passcodeErrorDigitsOnly => 'Digits only.';

  @override
  String get passcodeErrorRepeating => 'Avoid repeating digits.';

  @override
  String get passcodeErrorSequential => 'Avoid sequential digits.';

  @override
  String get passcodeBiometricReason => 'Enable login with biometric';

  @override
  String get kycChooseTitle => 'Pick a document to verify\nyour identity';

  @override
  String get kycChooseSubtitle => 'We don\'t accept scans or copies.';

  @override
  String get kycDocumentNationalId => 'National ID';

  @override
  String get kycDocumentPassport => 'Passport';

  @override
  String get kycChooseContinue => 'Continue';

  @override
  String get kycCaptureFrontInstruction =>
      'Position the front of your document in the frame';

  @override
  String get kycCaptureBackInstruction =>
      'Position the back of your document in the frame';

  @override
  String get kycCaptureProcessing => 'Processing…';

  @override
  String get kycCameraDeniedMessage =>
      'Camera access is required to verify your identity.';

  @override
  String get kycCameraOpenSettings => 'Open settings';

  @override
  String get kycCameraUnavailableMessage =>
      'Camera is not available on this device.';

  @override
  String get kycCameraTryAgain => 'Try again';

  @override
  String get kycSelfieInstruction => 'Keep your face within the oval';

  @override
  String get cameraShutterLabel => 'Take picture';

  @override
  String get transferHeaderTitle => 'Transfer';

  @override
  String get transferTitle => 'Transfer Money';

  @override
  String get transferSectionFrom => 'From';

  @override
  String get transferSectionTo => 'To';

  @override
  String get transferSenderPhoneHint => 'Your mobile money number';

  @override
  String get transferRecipientPhoneHint => 'Recipient phone number';

  @override
  String get transferRecipientNameHint => 'Recipient name';

  @override
  String get transferPurposeHint => 'Purpose (Optional)';

  @override
  String get transferFeeLabel => 'Transaction fee';

  @override
  String get transferRecipientReceivesLabel => 'Recipient will receive';

  @override
  String get transferConfirmCta => 'Confirm';

  @override
  String get transferLookupChecking => 'Checking MoneyA directory…';

  @override
  String transferLookupFound(String name) {
    return 'MoneyA user found — $name';
  }

  @override
  String get transferLookupNotFound =>
      'Not on MoneyA yet. They\'ll get an SMS invite to claim this transfer.';

  @override
  String get transferContactPickerError => 'Could not open the contact picker.';

  @override
  String get transferContactNoPhone => 'That contact has no phone number.';

  @override
  String get transferContactPermissionDeniedPermanent =>
      'Contacts access is disabled. Enable it in Settings to pick a recipient from your contact book.';

  @override
  String get transferContactPermissionDeniedAction => 'Settings';

  @override
  String get transferContactPermissionNeeded =>
      'Contacts permission is needed to pick a recipient.';

  @override
  String get confirmPaymentHeaderTitle => 'Confirm';

  @override
  String get confirmPaymentTitle => 'Confirm Your Payment';

  @override
  String get confirmPaymentDetailsHeading => 'Payment Details';

  @override
  String get confirmPaymentDetailsSubtitle =>
      'Check payment details and swipe to pay!';

  @override
  String get confirmPaymentAmountLabel => 'Amount';

  @override
  String get confirmPaymentFromYourPrefix => 'From your ';

  @override
  String get confirmPaymentToRecipientPrefix => 'To ';

  @override
  String get confirmPaymentRecipientFallback => 'Recipient';

  @override
  String get confirmPaymentSwipeLabel => 'Swipe to pay';

  @override
  String get confirmPaymentAuthFailedSnack =>
      'Too many wrong attempts. Try again.';

  @override
  String get amountKeypadDoneCta => 'Done';

  @override
  String get fundingProviderPickerTitle => 'Select funding source';

  @override
  String get transferCountryPickerTitle => 'Select sending country';

  @override
  String get fundingProviderMoneyaWallet => 'MoneyA Wallet';

  @override
  String get fundingProviderMoovAfrica => 'Moov Africa';

  @override
  String get fundingProviderOrangeMoney => 'Orange Money';

  @override
  String get fundingProviderMtnMomo => 'MTN MoMo';

  @override
  String get fundingProviderWave => 'Wave';

  @override
  String get receiveQrCardSemantic =>
      'MoneyA QR code. Have someone scan this with their MoneyA app to send you money. To read your account number out loud, switch to the Account tab.';

  @override
  String get receiveQrHelpText =>
      'Show this QR code to anyone with the MoneyA app to receive money in person.';

  @override
  String get receiveQrShareLabel => 'Share QR';

  @override
  String get receiveQrSaveLabel => 'Save image';

  @override
  String get receiveQrShareSemantic => 'Share QR code';

  @override
  String get receiveQrSaveSemantic => 'Save QR code to photos';

  @override
  String get receiveQrShareSubject => 'My MoneyA QR code';

  @override
  String receiveQrShareBody(String number) {
    return 'Send me money on MoneyA. My account number is $number.';
  }

  @override
  String get receiveQrSavedSnack => 'QR code saved to your photos';

  @override
  String get receiveQrSavedAnnouncement => 'QR code saved to your photos';

  @override
  String receiveQrSaveErrorSnack(String reason) {
    return 'Could not save QR: $reason';
  }

  @override
  String receiveQrSaveErrorAnnouncement(String reason) {
    return 'Could not save QR code. $reason';
  }

  @override
  String get receiveRequestSectionFrom => 'From';

  @override
  String get receiveRequestSectionAmount => 'Amount';

  @override
  String get receiveRequestClearPhoneSemantic => 'Clear phone number';

  @override
  String get receiveRequestNotOnMoneyA =>
      'This number is not on MoneyA. You can only request from existing MoneyA users.';

  @override
  String get receiveRequestCurrencyHint => 'Double tap to change currency';

  @override
  String get receiveRequestBusyHint => 'Loading';

  @override
  String get receiveRequestSwipeLabel => 'Swipe to request';

  @override
  String get receiveRequestSwipeSemanticLabel =>
      'Swipe to send payment request';

  @override
  String get receiveRequestSwipeHintReady => 'Swipe right to confirm';

  @override
  String get receiveRequestSwipeHintDisabled =>
      'Enter a recipient and amount to enable';

  @override
  String get receiveRequestOutcomeTitle => 'Request sent';

  @override
  String get receiveRequestOutcomeBodyPrefix => 'We notified ';

  @override
  String get receiveRequestOutcomeBodyMiddle => ' about your request for ';

  @override
  String get receiveRequestOutcomeBodySuffix =>
      '. We’ll let you know the moment they pay.';

  @override
  String get receiveRequestOutcomePrimary => 'Done';

  @override
  String get receiveRequestOutcomeSecondary => 'Share request';

  @override
  String get receiveRequestShareSubject => 'MoneyA payment request';

  @override
  String get receiveRequestNoteLabel => 'Note (optional)';

  @override
  String get receiveRequestNoteHint =>
      'What is this for? (e.g. Lunch, rent, tickets)';

  @override
  String receiveRequestShareBody(String name, String currency, String amount) {
    return 'Hi $name — I just sent you a payment request for $currency $amount on MoneyA. Open the app to pay.';
  }
}
