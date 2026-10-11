import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// Brand name shown in the OS task switcher and the splash screen.
  ///
  /// In en, this message translates to:
  /// **'MoneyA'**
  String get appName;

  /// Tooltip on the language flag pill in the home header.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTooltip;

  /// Tooltip on the bell pill in the home header.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTooltip;

  /// Display name of the English locale, used in the language picker.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Display name of the French locale, used in the language picker.
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// Caption above the big balance figure on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Total Balance'**
  String get homeTotalBalance;

  /// Accessibility/tooltip for the eye icon when the balance is hidden.
  ///
  /// In en, this message translates to:
  /// **'Show balance'**
  String get homeBalanceShow;

  /// Accessibility/tooltip for the eye icon when the balance is visible.
  ///
  /// In en, this message translates to:
  /// **'Hide balance'**
  String get homeBalanceHide;

  /// Primary action button label for the outbound transfer flow.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get homeActionSend;

  /// Primary action button label for the receive flow.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get homeActionReceive;

  /// Primary action button label that opens the onramp (top up the MoneyA balance with mobile money) flow.
  ///
  /// In en, this message translates to:
  /// **'Load Money'**
  String get homeActionLoad;

  /// Primary action button label that opens the offramp (cash out to mobile money or bank account) flow.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get homeActionWithdraw;

  /// Section header above the AI insights card carousel.
  ///
  /// In en, this message translates to:
  /// **'AI Insights'**
  String get homeSectionAiInsights;

  /// Section header above the favorite contacts strip.
  ///
  /// In en, this message translates to:
  /// **'Your Favorites'**
  String get homeSectionFavorites;

  /// Section header above the recent transactions list.
  ///
  /// In en, this message translates to:
  /// **'Recent transactions'**
  String get homeSectionRecentTransactions;

  /// Trailing button in section headers; navigates to the full list.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get homeViewAll;

  /// Title of the FX-savings insight card.
  ///
  /// In en, this message translates to:
  /// **'Smart Rate'**
  String get insightSmartRateTitle;

  /// Body copy of the Smart Rate insight card.
  ///
  /// In en, this message translates to:
  /// **'Save on your next cross-border transfer.'**
  String get insightSmartRateBody;

  /// Title of the trust-score insight card.
  ///
  /// In en, this message translates to:
  /// **'Trust Score'**
  String get insightTrustScoreTitle;

  /// Body of the trust-score insight card. Includes the active currency code and a formatted credit limit.
  ///
  /// In en, this message translates to:
  /// **'Unlock micro-loans up to {currency} {limit}.'**
  String insightTrustScoreBody(String currency, String limit);

  /// Title of the spending-trend insight card.
  ///
  /// In en, this message translates to:
  /// **'Spending pulse'**
  String get insightSpendingPulseTitle;

  /// Body copy of the Spending pulse insight card. Hardcoded percentage in v1; will be backend-driven.
  ///
  /// In en, this message translates to:
  /// **'You spent 18% less than last week.'**
  String get insightSpendingPulseBody;

  /// Label on a transaction tile when funds were credited to the user.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get txnLabelReceived;

  /// Label on a transaction tile for an outbound transfer.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get txnLabelSent;

  /// Label on a transaction tile for a merchant payment. Note: 'Payed' (not 'Paid') matches the design mock and the legacy backend tag.
  ///
  /// In en, this message translates to:
  /// **'Payed'**
  String get txnLabelPayed;

  /// Status pill on a transaction tile when the transaction completed.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get txnStatusSuccess;

  /// Status pill on a transaction tile when the transaction failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get txnStatusFailed;

  /// Title at the top of the Transactions tab.
  ///
  /// In en, this message translates to:
  /// **'Your Transactions'**
  String get transactionsTitle;

  /// Tooltip on the download/export pill on the Transactions tab.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get transactionsExportTooltip;

  /// Empty-state copy shown when an active filter excludes every transaction.
  ///
  /// In en, this message translates to:
  /// **'No transactions match this filter.'**
  String get transactionsEmpty;

  /// Filter chip label — outbound transfers.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get txnFilterSent;

  /// Filter chip label — inbound transfers.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get txnFilterReceived;

  /// Filter chip label — completed transactions.
  ///
  /// In en, this message translates to:
  /// **'Succeeded'**
  String get txnFilterSucceeded;

  /// Filter chip label — in-flight transactions.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get txnFilterPending;

  /// Filter chip label — failed transactions.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get txnFilterFailed;

  /// Status pill on a transaction tile when the transaction is still in flight.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get txnStatusPending;

  /// Screen title for the Settings screen (also used in nav).
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Bottom-nav label for the Home tab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom-nav label for the Transactions tab.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get navTransactions;

  /// Bottom-nav label for the Settings tab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Tooltip on the chevron-left back button across screens.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Cancel button label in confirmation dialogs.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Destructive confirm button in confirmation dialogs.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Header above the security/privacy settings card.
  ///
  /// In en, this message translates to:
  /// **'Security & Privacy'**
  String get settingsSectionSecurity;

  /// Header above the transactions settings card.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get settingsSectionTransactions;

  /// Header above the destructive-actions settings card.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get settingsSectionActions;

  /// Settings row that opens the change-password flow.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get settingsRowChangePassword;

  /// Settings row that opens login-method preferences.
  ///
  /// In en, this message translates to:
  /// **'Login Options'**
  String get settingsRowLoginOptions;

  /// Toggle row label for biometric transaction approval.
  ///
  /// In en, this message translates to:
  /// **'Biometrics for transactions'**
  String get settingsRowBiometricsLabel;

  /// Helper copy under the biometrics toggle.
  ///
  /// In en, this message translates to:
  /// **'Authenticate transactions with biometrics'**
  String get settingsRowBiometricsSubtitle;

  /// Settings row showing the user's phone-number-based account number.
  ///
  /// In en, this message translates to:
  /// **'Phone Number Account'**
  String get settingsRowPhoneNumberAccount;

  /// Settings row that opens USSD short-code banking preferences.
  ///
  /// In en, this message translates to:
  /// **'USSD Banking'**
  String get settingsRowUssdBanking;

  /// Destructive settings row that initiates account deletion.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get settingsRowDeleteAccount;

  /// Title of the delete-account confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get deleteAccountDialogTitle;

  /// Body copy of the delete-account confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes your MoneyA account, balances, and transaction history. This action cannot be undone.'**
  String get deleteAccountDialogBody;

  /// Title of the logout confirmation dialog opened from Profile → Logout.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logoutDialogTitle;

  /// Body copy of the logout confirmation dialog. Reassures the user that logging out is reversible and non-destructive.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need to sign in again to send or receive money. Your account and balances stay safe.'**
  String get logoutDialogBody;

  /// Destructive CTA of the logout confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logoutDialogConfirm;

  /// Screen title at the top of the Profile screen.
  ///
  /// In en, this message translates to:
  /// **'Profile Details'**
  String get profileTitle;

  /// Header above the personal information card on Profile. Note: 'Informations' (plural) matches the legacy mock copy and the French source.
  ///
  /// In en, this message translates to:
  /// **'Personal Informations'**
  String get profileSectionPersonal;

  /// Header above the actions card on Profile.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get profileSectionActions;

  /// Label for the phone-number row on Profile.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get profileFieldPhone;

  /// Label for the email row on Profile.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get profileFieldEmail;

  /// Label for the address row on Profile.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get profileFieldAddress;

  /// Label for the date-of-birth row on Profile. Note: 'Date of Birthday' is intentional — matches the design mock; will be revisited in the plain-language pass.
  ///
  /// In en, this message translates to:
  /// **'Date of Birthday'**
  String get profileFieldDateOfBirth;

  /// Badge shown next to a verified field on Profile.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get profileVerifiedBadge;

  /// Action row label that opens the referral flow. Note: 'Refere' typo matches the design mock; will be fixed in the plain-language pass.
  ///
  /// In en, this message translates to:
  /// **'Refere and earn'**
  String get profileActionReferAndEarn;

  /// Action row label on Profile that opens the saved-recipients (favourites) list.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get profileActionFavorites;

  /// Action row label on Profile that opens the Settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profileActionSettings;

  /// Destructive action row label on Profile.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get profileActionLogout;

  /// Screen title for the transaction-detail receipt screen.
  ///
  /// In en, this message translates to:
  /// **'Transaction Details'**
  String get txnDetailTitle;

  /// Status badge on the receipt when the transaction succeeded.
  ///
  /// In en, this message translates to:
  /// **'Successful'**
  String get txnDetailStatusSuccess;

  /// Status badge on the receipt when the transaction is pending settlement.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get txnDetailStatusPending;

  /// Status badge on the receipt when the transaction failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get txnDetailStatusFailed;

  /// Tracked-uppercase direction label rendered above the counterparty name on outgoing receipts.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get txnDetailDirectionSent;

  /// Tracked-uppercase direction label rendered above the counterparty name on incoming receipts.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get txnDetailDirectionReceived;

  /// Receipt row label for the network/processing fee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get txnDetailRowFee;

  /// Receipt row label for the total amount (amount + fee).
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get txnDetailRowTotal;

  /// Receipt row label for the counterparty phone number; row is tap-to-copy.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get txnDetailRowPhone;

  /// Receipt row label for the funding/payout method (e.g. mobile money, bank).
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get txnDetailRowMethod;

  /// Receipt row label for the unique transaction reference id; row is tap-to-copy.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get txnDetailRowReference;

  /// SnackBar shown after a tap-to-copy receipt row succeeds.
  ///
  /// In en, this message translates to:
  /// **'{label} copied'**
  String txnDetailCopiedSnack(String label);

  /// Outline pill CTA at the bottom of the receipt — shares the receipt as text/image.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get txnDetailActionShare;

  /// Filled pill CTA at the bottom of the receipt — exports the receipt as a PDF.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get txnDetailActionDownloadPdf;

  /// Subject line used when sharing a transaction receipt via email/share-sheet.
  ///
  /// In en, this message translates to:
  /// **'MoneyA receipt — {reference}'**
  String txnDetailShareSubject(String reference);

  /// First line of the shared receipt body — branded heading.
  ///
  /// In en, this message translates to:
  /// **'MoneyA receipt'**
  String get txnDetailShareHeader;

  /// Status line in shared receipt body.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String txnDetailShareLineStatus(String status);

  /// Direction line (Sent/Received) in shared receipt body.
  ///
  /// In en, this message translates to:
  /// **'Direction: {direction}'**
  String txnDetailShareLineDirection(String direction);

  /// Counterparty line — {label} is From/To, {name} is the person.
  ///
  /// In en, this message translates to:
  /// **'{label}: {name}'**
  String txnDetailShareLineCounterparty(String label, String name);

  /// Timestamp line in shared receipt body.
  ///
  /// In en, this message translates to:
  /// **'When: {timestamp}'**
  String txnDetailShareLineWhen(String timestamp);

  /// Amount line in shared receipt body — value already includes currency code and sign.
  ///
  /// In en, this message translates to:
  /// **'Amount: {amount}'**
  String txnDetailShareLineAmount(String amount);

  /// Fee line in shared receipt body.
  ///
  /// In en, this message translates to:
  /// **'Fee: {fee}'**
  String txnDetailShareLineFee(String fee);

  /// Total line in shared receipt body.
  ///
  /// In en, this message translates to:
  /// **'Total: {total}'**
  String txnDetailShareLineTotal(String total);

  /// Payment method line in shared receipt body.
  ///
  /// In en, this message translates to:
  /// **'Method: {method}'**
  String txnDetailShareLineMethod(String method);

  /// Counterparty phone line in shared receipt body.
  ///
  /// In en, this message translates to:
  /// **'Phone: {phone}'**
  String txnDetailShareLinePhone(String phone);

  /// Reference line in shared receipt body.
  ///
  /// In en, this message translates to:
  /// **'Reference: {reference}'**
  String txnDetailShareLineReference(String reference);

  /// Last line of shared receipt body — brand footer.
  ///
  /// In en, this message translates to:
  /// **'Powered by MoneyA'**
  String get txnDetailShareFooter;

  /// Title of the notifications bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// Text-button label that marks every unread notification as read.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get notificationsMarkAllRead;

  /// Section header for notifications received today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get notificationsGroupToday;

  /// Section header for notifications received yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get notificationsGroupYesterday;

  /// Section header for notifications received between 2 and 7 days ago.
  ///
  /// In en, this message translates to:
  /// **'Earlier this week'**
  String get notificationsGroupEarlierWeek;

  /// Section header for notifications older than the rolling 7-day window.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get notificationsGroupOlder;

  /// Compact relative-time label rendered on a notification tile when the event happened less than 1 minute ago.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get notificationsTimeJustNow;

  /// Compact relative-time label for events 1–59 minutes ago. Translators: 'm' is short for 'minutes'.
  ///
  /// In en, this message translates to:
  /// **'{n}m'**
  String notificationsTimeMinutes(int n);

  /// Compact relative-time label for events 1–23 hours ago. Translators: 'h' is short for 'hours'.
  ///
  /// In en, this message translates to:
  /// **'{n}h'**
  String notificationsTimeHours(int n);

  /// Compact relative-time label rendered on a notification tile when the event happened yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get notificationsTimeYesterday;

  /// Compact relative-time label for events 2–6 days ago. Translators: 'd' is short for 'days'.
  ///
  /// In en, this message translates to:
  /// **'{n}d'**
  String notificationsTimeDays(int n);

  /// Screen title for the Receive screen — landing surface for getting paid via account number, QR, or payment request.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receiveTitle;

  /// Tab label for the Account tab (shows the user's MoneyA account number).
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get receiveTabAccount;

  /// Tab label for the QR code tab (shows a scannable code that resolves to the user's account).
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get receiveTabQrCode;

  /// Tab label for the Request tab (sends a payment request to a phone number).
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get receiveTabRequest;

  /// Screen-reader label for a tab segment, e.g. 'Account tab'. Wraps the visible tab label so VoiceOver/TalkBack announce the role.
  ///
  /// In en, this message translates to:
  /// **'{label} tab'**
  String receiveTabSemanticLabel(String label);

  /// Screen-reader hint announced on inactive tabs. Tells the user the gesture required to activate the tab.
  ///
  /// In en, this message translates to:
  /// **'Double tap to switch'**
  String get receiveTabSemanticHint;

  /// Status caption rendered under the user's name on the Account tab. Indicates the account has completed KYC.
  ///
  /// In en, this message translates to:
  /// **'Verified MoneyA member'**
  String get receiveAccountVerifiedMember;

  /// Help paragraph below the account-number card explaining what the account number does.
  ///
  /// In en, this message translates to:
  /// **'Anyone on MoneyA can send you money instantly using this number.'**
  String get receiveAccountHelpText;

  /// Tracked-uppercase header inside the account-number card; also used as the field's screen-reader label.
  ///
  /// In en, this message translates to:
  /// **'MoneyA account number'**
  String get receiveAccountCardLabel;

  /// Filled action-pill label that copies the account number to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy number'**
  String get receiveAccountCopyLabel;

  /// Outline action-pill label that opens the native share sheet to share the account number.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get receiveAccountShareLabel;

  /// Screen-reader label for the Copy pill, with the formatted account number spelled into the announcement.
  ///
  /// In en, this message translates to:
  /// **'Copy account number {number}'**
  String receiveAccountCopySemantic(String number);

  /// Screen-reader label for the Share pill on the Account tab.
  ///
  /// In en, this message translates to:
  /// **'Share account number'**
  String get receiveAccountShareSemantic;

  /// SemanticsService announcement spoken to assistive tech when the account number is copied.
  ///
  /// In en, this message translates to:
  /// **'Account number copied to clipboard'**
  String get receiveAccountCopyAnnouncement;

  /// Visual SnackBar message shown after the user copies the account number.
  ///
  /// In en, this message translates to:
  /// **'Account number copied'**
  String get receiveAccountCopySnack;

  /// Subject line passed to the native share sheet (used by email clients, etc.).
  ///
  /// In en, this message translates to:
  /// **'My MoneyA account number'**
  String get receiveAccountShareSubject;

  /// First line of the share-sheet body. The body is followed by a blank line and a moneya:// deep link rendered separately so the deep link is not translated.
  ///
  /// In en, this message translates to:
  /// **'Send me money on MoneyA. My account number is {number}.'**
  String receiveAccountShareBody(String number);

  /// Brand tagline shown under the wordmark on the auth landing screen.
  ///
  /// In en, this message translates to:
  /// **'Say it. We send it.'**
  String get authLandingTagline;

  /// Primary CTA on the auth landing screen for existing users to sign in.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authLandingLogin;

  /// Secondary CTA on the auth landing screen for new users to start signup.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get authLandingCreateAccount;

  /// Hero title at the top of the phone-number signup screen.
  ///
  /// In en, this message translates to:
  /// **'Create New Account'**
  String get createAccountTitle;

  /// Subtitle under the create-account hero title; explains the one-field signup.
  ///
  /// In en, this message translates to:
  /// **'Just enter your phone number and we\'re set.'**
  String get createAccountSubtitle;

  /// Placeholder text inside the national-number input field.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get createAccountPhoneHint;

  /// Tooltip on the X icon that clears the phone-number field.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get createAccountClearTooltip;

  /// Inline prompt before the Login link on the create-account screen. The trailing space is intentional — preserves spacing before the inline link.
  ///
  /// In en, this message translates to:
  /// **'Already have an account ? '**
  String get createAccountAlreadyHaveAccount;

  /// Inline link label that takes existing users to the login screen.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get createAccountLoginLink;

  /// Primary CTA pill on the create-account screen.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccountCta;

  /// Header inside the country-picker bottom sheet on the create-account screen.
  ///
  /// In en, this message translates to:
  /// **'Select country'**
  String get createAccountPickCountryTitle;

  /// Title of the bottom sheet shown after the user submits the phone number, asking them to confirm before OTP send.
  ///
  /// In en, this message translates to:
  /// **'Confirm the phone number'**
  String get createAccountConfirmSheetTitle;

  /// Body copy inside the confirm-number bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a verification code to this number.'**
  String get createAccountConfirmSheetBody;

  /// Primary CTA in the confirm-number bottom sheet — proceeds to OTP.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get createAccountConfirmCta;

  /// Ghost CTA in the confirm-number bottom sheet — dismisses without sending the OTP.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get createAccountGoBack;

  /// Display name of Togo in the country-picker.
  ///
  /// In en, this message translates to:
  /// **'Togo'**
  String get countryTogo;

  /// Display name of Senegal in the country-picker.
  ///
  /// In en, this message translates to:
  /// **'Senegal'**
  String get countrySenegal;

  /// Display name of Côte d'Ivoire in the country-picker.
  ///
  /// In en, this message translates to:
  /// **'Côte d\'Ivoire'**
  String get countryIvoryCoast;

  /// Display name of Mali in the country-picker.
  ///
  /// In en, this message translates to:
  /// **'Mali'**
  String get countryMali;

  /// Display name of Burkina Faso in the country-picker.
  ///
  /// In en, this message translates to:
  /// **'Burkina Faso'**
  String get countryBurkinaFaso;

  /// Display name of Benin in the country-picker.
  ///
  /// In en, this message translates to:
  /// **'Benin'**
  String get countryBenin;

  /// Display name of Nigeria in the country-picker.
  ///
  /// In en, this message translates to:
  /// **'Nigeria'**
  String get countryNigeria;

  /// Display name of Ghana in the country-picker.
  ///
  /// In en, this message translates to:
  /// **'Ghana'**
  String get countryGhana;

  /// Hero title of the OTP verification screen.
  ///
  /// In en, this message translates to:
  /// **'Enter The Code'**
  String get verifyPhoneTitle;

  /// Subtitle on the OTP screen. Includes the code length, the dial code (without +), and the masked last digits of the phone number.
  ///
  /// In en, this message translates to:
  /// **'We sent an {length} digit code to your phone number (+{dialCode}) … {tail}'**
  String verifyPhoneSubtitle(int length, String dialCode, String tail);

  /// Muted prompt above the resend link. Note: 'Didn't received' is intentional — matches the design mock; will be revisited in the plain-language pass.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t received the code ?'**
  String get verifyPhoneResendPrompt;

  /// Tappable link label that re-sends the OTP. Disabled while the resend countdown is running.
  ///
  /// In en, this message translates to:
  /// **'Resend the code'**
  String get verifyPhoneResendLink;

  /// Title of the bottom sheet shown when the entered OTP is wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect code entered'**
  String get verifyPhoneIncorrectTitle;

  /// Body of the incorrect-OTP bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Please, check the code and try again.'**
  String get verifyPhoneIncorrectBody;

  /// Acknowledgement CTA in the incorrect-OTP bottom sheet — dismisses the sheet.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get verifyPhoneGotIt;

  /// Hero title when the user is choosing their MoneyA passcode for the first time.
  ///
  /// In en, this message translates to:
  /// **'Set a passcode'**
  String get passcodeSetTitle;

  /// Hero title when the user is repeating the passcode they just chose.
  ///
  /// In en, this message translates to:
  /// **'Confirm the passcode'**
  String get passcodeConfirmTitle;

  /// Subtitle on the set-passcode screen. Note: lowercase 'create' is intentional — matches the design mock.
  ///
  /// In en, this message translates to:
  /// **'create a {length} digit passcode'**
  String passcodeSetSubtitle(int length);

  /// Subtitle on the confirm-passcode screen.
  ///
  /// In en, this message translates to:
  /// **'Repeat the {length} digit passcode'**
  String passcodeConfirmSubtitle(int length);

  /// CTA label on the set-passcode screen — advances to the confirm step.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get passcodeNextCta;

  /// CTA label on the confirm-passcode screen — saves the passcode.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get passcodeSaveCta;

  /// Inline error shown on the confirm screen when the repeated passcode does not match the original.
  ///
  /// In en, this message translates to:
  /// **'Passcodes don\'t match.'**
  String get passcodeMismatchError;

  /// Inline error when the entered passcode is shorter or longer than required.
  ///
  /// In en, this message translates to:
  /// **'Use {length} digits.'**
  String passcodeErrorWrongLength(int length);

  /// Inline error when the passcode contains a non-digit character.
  ///
  /// In en, this message translates to:
  /// **'Digits only.'**
  String get passcodeErrorDigitsOnly;

  /// Inline error when the passcode is all the same digit, e.g. 000000.
  ///
  /// In en, this message translates to:
  /// **'Avoid repeating digits.'**
  String get passcodeErrorRepeating;

  /// Inline error when the passcode is a strictly ascending or descending sequence, e.g. 123456.
  ///
  /// In en, this message translates to:
  /// **'Avoid sequential digits.'**
  String get passcodeErrorSequential;

  /// Reason string shown by the OS biometric prompt when offering to enroll biometric login after passcode setup.
  ///
  /// In en, this message translates to:
  /// **'Enable login with biometric'**
  String get passcodeBiometricReason;

  /// Hero title on the choose-KYC-document screen. Contains a hard newline matching the mock layout.
  ///
  /// In en, this message translates to:
  /// **'Pick a document to verify\nyour identity'**
  String get kycChooseTitle;

  /// Subtitle warning users that only originals are accepted for KYC.
  ///
  /// In en, this message translates to:
  /// **'We don\'t accept scans or copies.'**
  String get kycChooseSubtitle;

  /// Label for the National ID option in the KYC document picker.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get kycDocumentNationalId;

  /// Label for the Passport option in the KYC document picker.
  ///
  /// In en, this message translates to:
  /// **'Passport'**
  String get kycDocumentPassport;

  /// Primary CTA on the choose-KYC-document screen — advances to the camera screen.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get kycChooseContinue;

  /// Instruction shown under the document-camera viewfinder when capturing the front side.
  ///
  /// In en, this message translates to:
  /// **'Position the front of your document in the frame'**
  String get kycCaptureFrontInstruction;

  /// Instruction shown under the document-camera viewfinder when capturing the back side.
  ///
  /// In en, this message translates to:
  /// **'Position the back of your document in the frame'**
  String get kycCaptureBackInstruction;

  /// Status text shown while the captured document image is being uploaded/processed.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get kycCaptureProcessing;

  /// Message shown inside the camera viewfinder when the user has denied the camera permission.
  ///
  /// In en, this message translates to:
  /// **'Camera access is required to verify your identity.'**
  String get kycCameraDeniedMessage;

  /// Action button under the camera-permission-denied message; opens the OS app settings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get kycCameraOpenSettings;

  /// Message shown inside the camera viewfinder when no camera hardware is available.
  ///
  /// In en, this message translates to:
  /// **'Camera is not available on this device.'**
  String get kycCameraUnavailableMessage;

  /// Action button under the camera-unavailable message; retries camera initialization.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get kycCameraTryAgain;

  /// Instruction shown below the oval mask on the selfie capture screen.
  ///
  /// In en, this message translates to:
  /// **'Keep your face within the oval'**
  String get kycSelfieInstruction;

  /// Screen-reader label for the camera shutter button used on the document and selfie capture screens.
  ///
  /// In en, this message translates to:
  /// **'Take picture'**
  String get cameraShutterLabel;

  /// Top-bar title next to the back chevron on the Send Money screen.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transferHeaderTitle;

  /// Centered headline at the top of the Send Money screen body.
  ///
  /// In en, this message translates to:
  /// **'Transfer Money'**
  String get transferTitle;

  /// Section label above the sender country / funding-provider / phone row on the Send Money screen.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get transferSectionFrom;

  /// Section label above the recipient country / phone / name fields on the Send Money screen.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get transferSectionTo;

  /// Placeholder text in the sender phone-number field on the Send Money screen.
  ///
  /// In en, this message translates to:
  /// **'Your mobile money number'**
  String get transferSenderPhoneHint;

  /// Placeholder text in the recipient phone-number field on the Send Money screen.
  ///
  /// In en, this message translates to:
  /// **'Recipient phone number'**
  String get transferRecipientPhoneHint;

  /// Placeholder text in the recipient name field on the Send Money screen.
  ///
  /// In en, this message translates to:
  /// **'Recipient name'**
  String get transferRecipientNameHint;

  /// Placeholder text in the multi-line purpose / note field on the Send Money screen.
  ///
  /// In en, this message translates to:
  /// **'Purpose (Optional)'**
  String get transferPurposeHint;

  /// Row label for the transaction fee on the Send Money and Confirm Payment screens.
  ///
  /// In en, this message translates to:
  /// **'Transaction fee'**
  String get transferFeeLabel;

  /// Row label for the net amount the recipient receives on the Send Money and Confirm Payment screens.
  ///
  /// In en, this message translates to:
  /// **'Recipient will receive'**
  String get transferRecipientReceivesLabel;

  /// Primary CTA at the bottom of the Send Money screen — opens the Confirm Payment screen.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get transferConfirmCta;

  /// Inline status text shown while the recipient phone number is being looked up in the MoneyA directory.
  ///
  /// In en, this message translates to:
  /// **'Checking MoneyA directory…'**
  String get transferLookupChecking;

  /// Inline success status shown when the recipient phone number resolves to an existing MoneyA user. Includes the matched display name.
  ///
  /// In en, this message translates to:
  /// **'MoneyA user found — {name}'**
  String transferLookupFound(String name);

  /// Inline warning status shown when the recipient is not on MoneyA — funds will be escrowed and an SMS invite sent.
  ///
  /// In en, this message translates to:
  /// **'Not on MoneyA yet. They\'ll get an SMS invite to claim this transfer.'**
  String get transferLookupNotFound;

  /// SnackBar shown when the OS contact picker fails to open.
  ///
  /// In en, this message translates to:
  /// **'Could not open the contact picker.'**
  String get transferContactPickerError;

  /// SnackBar shown when the picked contact has no associated phone number.
  ///
  /// In en, this message translates to:
  /// **'That contact has no phone number.'**
  String get transferContactNoPhone;

  /// SnackBar shown when the user has permanently denied the Contacts permission. Paired with a Settings action.
  ///
  /// In en, this message translates to:
  /// **'Contacts access is disabled. Enable it in Settings to pick a recipient from your contact book.'**
  String get transferContactPermissionDeniedPermanent;

  /// SnackBar action label that opens the OS app-settings screen so the user can grant Contacts permission.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get transferContactPermissionDeniedAction;

  /// SnackBar shown when the Contacts permission is denied (non-permanent) and the user tries to pick a contact.
  ///
  /// In en, this message translates to:
  /// **'Contacts permission is needed to pick a recipient.'**
  String get transferContactPermissionNeeded;

  /// Top-bar title next to the back chevron on the Confirm Payment screen.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmPaymentHeaderTitle;

  /// Centered headline at the top of the Confirm Payment screen body.
  ///
  /// In en, this message translates to:
  /// **'Confirm Your Payment'**
  String get confirmPaymentTitle;

  /// Subsection heading above the amount + From/To card on the Confirm Payment screen.
  ///
  /// In en, this message translates to:
  /// **'Payment Details'**
  String get confirmPaymentDetailsHeading;

  /// Helper sentence under the Payment Details heading on the Confirm Payment screen.
  ///
  /// In en, this message translates to:
  /// **'Check payment details and swipe to pay!'**
  String get confirmPaymentDetailsSubtitle;

  /// Caption above the editable amount card on the Confirm Payment screen.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get confirmPaymentAmountLabel;

  /// Leading muted span before the bolded provider name in the From card on the Confirm Payment screen. Trailing space is intentional so the bolded provider name reads inline.
  ///
  /// In en, this message translates to:
  /// **'From your '**
  String get confirmPaymentFromYourPrefix;

  /// Leading muted span before the bolded recipient name in the To card on the Confirm Payment screen. Trailing space is intentional so the bolded name reads inline.
  ///
  /// In en, this message translates to:
  /// **'To '**
  String get confirmPaymentToRecipientPrefix;

  /// Fallback bolded label used in the To card when no recipient name was provided.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get confirmPaymentRecipientFallback;

  /// Centered label on the slide-to-confirm pill at the bottom of the Confirm Payment screen.
  ///
  /// In en, this message translates to:
  /// **'Swipe to pay'**
  String get confirmPaymentSwipeLabel;

  /// SnackBar shown on the Confirm Payment screen after too many failed step-up authentication attempts.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong attempts. Try again.'**
  String get confirmPaymentAuthFailedSnack;

  /// Confirm CTA at the bottom of the numeric keypad bottom sheet for entering a transfer amount.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get amountKeypadDoneCta;

  /// Title at the top of the funding-provider picker bottom sheet (Send Money).
  ///
  /// In en, this message translates to:
  /// **'Select funding source'**
  String get fundingProviderPickerTitle;

  /// Title at the top of the country picker bottom sheet on the Send Money screen.
  ///
  /// In en, this message translates to:
  /// **'Select sending country'**
  String get transferCountryPickerTitle;

  /// Display name of the in-app MoneyA balance funding source.
  ///
  /// In en, this message translates to:
  /// **'MoneyA balance'**
  String get fundingProviderMoneyaBalance;

  /// Display name of the Moov Africa mobile-money funding source. Brand name; kept as-is across locales.
  ///
  /// In en, this message translates to:
  /// **'Moov Africa'**
  String get fundingProviderMoovAfrica;

  /// Display name of the Orange Money mobile-money funding source. Brand name; kept as-is across locales.
  ///
  /// In en, this message translates to:
  /// **'Orange Money'**
  String get fundingProviderOrangeMoney;

  /// Display name of the MTN MoMo mobile-money funding source. Brand name; kept as-is across locales.
  ///
  /// In en, this message translates to:
  /// **'MTN MoMo'**
  String get fundingProviderMtnMomo;

  /// Display name of the Wave mobile-money funding source. Brand name; kept as-is across locales.
  ///
  /// In en, this message translates to:
  /// **'Wave'**
  String get fundingProviderWave;

  /// Screen-reader description of the QR card image on the QR tab. Explains the purpose of the code and points to the Account tab for the readable account number.
  ///
  /// In en, this message translates to:
  /// **'MoneyA QR code. Have someone scan this with their MoneyA app to send you money. To read your account number out loud, switch to the Account tab.'**
  String get receiveQrCardSemantic;

  /// Help paragraph below the QR card on the QR tab. Explains how the QR is used.
  ///
  /// In en, this message translates to:
  /// **'Show this QR code to anyone with the MoneyA app to receive money in person.'**
  String get receiveQrHelpText;

  /// Filled action-pill label on the QR tab that opens the native share sheet to share the QR image.
  ///
  /// In en, this message translates to:
  /// **'Share QR'**
  String get receiveQrShareLabel;

  /// Outline action-pill label on the QR tab that saves the QR image to the user's photo library.
  ///
  /// In en, this message translates to:
  /// **'Save image'**
  String get receiveQrSaveLabel;

  /// Screen-reader label for the Share QR pill on the QR tab.
  ///
  /// In en, this message translates to:
  /// **'Share QR code'**
  String get receiveQrShareSemantic;

  /// Screen-reader label for the Save image pill on the QR tab.
  ///
  /// In en, this message translates to:
  /// **'Save QR code to photos'**
  String get receiveQrSaveSemantic;

  /// Subject line passed to the native share sheet when sharing the QR image.
  ///
  /// In en, this message translates to:
  /// **'My MoneyA QR code'**
  String get receiveQrShareSubject;

  /// First line of the share-sheet body when sharing the QR image. Followed by a blank line and a moneya:// deep link rendered separately so the deep link is not translated.
  ///
  /// In en, this message translates to:
  /// **'Send me money on MoneyA. My account number is {number}.'**
  String receiveQrShareBody(String number);

  /// Visual SnackBar message shown after the user successfully saves the QR image to their photo library.
  ///
  /// In en, this message translates to:
  /// **'QR code saved to your photos'**
  String get receiveQrSavedSnack;

  /// SemanticsService announcement spoken to assistive tech when the QR image has been saved to the photo library.
  ///
  /// In en, this message translates to:
  /// **'QR code saved to your photos'**
  String get receiveQrSavedAnnouncement;

  /// Visual SnackBar message shown when saving the QR image to the photo library fails. The reason is platform-supplied (e.g. permission denied) and is not translated by us.
  ///
  /// In en, this message translates to:
  /// **'Could not save QR: {reason}'**
  String receiveQrSaveErrorSnack(String reason);

  /// SemanticsService announcement spoken to assistive tech when saving the QR image fails. The reason is platform-supplied and is not translated by us.
  ///
  /// In en, this message translates to:
  /// **'Could not save QR code. {reason}'**
  String receiveQrSaveErrorAnnouncement(String reason);

  /// Tracked-uppercase section label above the recipient phone-number field on the Request tab.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get receiveRequestSectionFrom;

  /// Tracked-uppercase section label above the amount input on the Request tab.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get receiveRequestSectionAmount;

  /// Screen-reader label for the trailing 'x' button on the phone-number field that clears the input.
  ///
  /// In en, this message translates to:
  /// **'Clear phone number'**
  String get receiveRequestClearPhoneSemantic;

  /// Screen-reader description (Semantics label) shown below the phone field when the entered number does not belong to a MoneyA user. The visible inline copy uses a different, friendlier phrasing rendered separately.
  ///
  /// In en, this message translates to:
  /// **'This number is not on MoneyA. You can only request from existing MoneyA users.'**
  String get receiveRequestNotOnMoneyA;

  /// Screen-reader hint on the currency-picker pill in the amount row.
  ///
  /// In en, this message translates to:
  /// **'Double tap to change currency'**
  String get receiveRequestCurrencyHint;

  /// Screen-reader hint announced on action pills (Share/Save) while an async operation is in flight.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get receiveRequestBusyHint;

  /// Visible label on the swipe-to-pay button on the Request tab. The user drags right to submit the payment request.
  ///
  /// In en, this message translates to:
  /// **'Swipe to request'**
  String get receiveRequestSwipeLabel;

  /// Screen-reader label for the swipe-to-pay button on the Request tab. Replaces the visible label for assistive tech with a fuller description.
  ///
  /// In en, this message translates to:
  /// **'Swipe to send payment request'**
  String get receiveRequestSwipeSemanticLabel;

  /// Screen-reader hint on the swipe-to-pay button when the form is valid and the request can be submitted.
  ///
  /// In en, this message translates to:
  /// **'Swipe right to confirm'**
  String get receiveRequestSwipeHintReady;

  /// Screen-reader hint on the swipe-to-pay button when the form is incomplete; explains why the control is disabled.
  ///
  /// In en, this message translates to:
  /// **'Enter a recipient and amount to enable'**
  String get receiveRequestSwipeHintDisabled;

  /// Title shown on the success screen after submitting a payment request.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get receiveRequestOutcomeTitle;

  /// First muted segment of the request-sent body, shown before the bolded recipient name. Trailing space is intentional — the recipient name is appended directly.
  ///
  /// In en, this message translates to:
  /// **'We notified '**
  String get receiveRequestOutcomeBodyPrefix;

  /// Muted middle segment of the request-sent body, shown between the recipient name and the bolded amount. Leading and trailing spaces are intentional.
  ///
  /// In en, this message translates to:
  /// **' about your request for '**
  String get receiveRequestOutcomeBodyMiddle;

  /// Final muted segment of the request-sent body, shown after the bolded amount.
  ///
  /// In en, this message translates to:
  /// **'. We’ll let you know the moment they pay.'**
  String get receiveRequestOutcomeBodySuffix;

  /// Primary CTA on the request-sent success screen. Pops back to the home screen.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get receiveRequestOutcomePrimary;

  /// Secondary CTA on the request-sent success screen. Opens the native share sheet so the user can also nudge the recipient outside MoneyA.
  ///
  /// In en, this message translates to:
  /// **'Share request'**
  String get receiveRequestOutcomeSecondary;

  /// Subject line passed to the native share sheet when sharing a payment request.
  ///
  /// In en, this message translates to:
  /// **'MoneyA payment request'**
  String get receiveRequestShareSubject;

  /// Section label above the optional free-text note field on the Request tab of the Receive screen.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get receiveRequestNoteLabel;

  /// Placeholder hint shown inside the optional note field on the Request tab. Examples in parentheses help the user understand the kind of short context to type (e.g. lunch, rent, tickets).
  ///
  /// In en, this message translates to:
  /// **'What is this for? (e.g. Lunch, rent, tickets)'**
  String get receiveRequestNoteHint;

  /// Body text passed to the native share sheet when sharing a payment request. Includes the recipient name, currency code, and amount.
  ///
  /// In en, this message translates to:
  /// **'Hi {name} — I just sent you a payment request for {currency} {amount} on MoneyA. Open the app to pay.'**
  String receiveRequestShareBody(String name, String currency, String amount);

  /// Hero question on onboarding step 1, where the user picks the app language.
  ///
  /// In en, this message translates to:
  /// **'Which language are you speaking?'**
  String get onboardingLanguageHeadline;

  /// Hero headline on onboarding step 2 (value-prop: speed + low cost).
  ///
  /// In en, this message translates to:
  /// **'Send money faster and cheaper'**
  String get onboardingSendMoneyHeadline;

  /// Hero headline on onboarding step 3. The newline is intentional and reproduces the design's two-line break; translators may move or remove the newline if their rendering needs it.
  ///
  /// In en, this message translates to:
  /// **'Between African francophone\nand anglophone countries'**
  String get onboardingCrossCorridorHeadline;

  /// Primary CTA pill at the bottom-right of every onboarding step. Advances to the next step or, on the last step, finishes onboarding.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Top-right text shortcut that bypasses the remaining onboarding steps and goes straight to the auth landing screen.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// Bottom-left pill on onboarding steps 2 and 3 that returns to the previous step.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// Header title on step 1 of the Load Money flow (provider selection).
  ///
  /// In en, this message translates to:
  /// **'Load money'**
  String get loadProviderHeaderTitle;

  /// Sub-header explaining what the user does on the provider-selection step.
  ///
  /// In en, this message translates to:
  /// **'Pick the mobile money account you want to load from.'**
  String get loadProviderSubtitle;

  /// Section label above the country picker on the load-provider step.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get loadProviderCountryLabel;

  /// Section label above the list of available mobile-money rails.
  ///
  /// In en, this message translates to:
  /// **'Mobile money providers'**
  String get loadProviderListLabel;

  /// Empty-state message shown when the selected country has no rails wired up yet.
  ///
  /// In en, this message translates to:
  /// **'No mobile money providers are available in this country yet.'**
  String get loadProviderEmptyMessage;

  /// Header title on step 2 of the Load Money flow (amount entry).
  ///
  /// In en, this message translates to:
  /// **'Load money'**
  String get loadAmountHeaderTitle;

  /// Centered question above the tappable amount card.
  ///
  /// In en, this message translates to:
  /// **'How much do you want to load?'**
  String get loadAmountTitle;

  /// Section label above the locked provider summary and source-phone field.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get loadAmountFromLabel;

  /// Placeholder for the source-phone input — the user's own mobile-money number being debited.
  ///
  /// In en, this message translates to:
  /// **'Mobile money number'**
  String get loadAmountSourcePhoneHint;

  /// Label on the swipe-to-confirm control at the bottom of the amount step.
  ///
  /// In en, this message translates to:
  /// **'Swipe to load'**
  String get loadAmountSwipeLabel;

  /// Inline error shown when the entered amount is above the client-side KYC tier cap. Backend will revalidate.
  ///
  /// In en, this message translates to:
  /// **'Amount exceeds your {tier} limit of {currency} {max}. Upgrade your account to load more.'**
  String loadAmountOverLimit(String currency, String max, String tier);

  /// Helper text under the form summarising the daily cap.
  ///
  /// In en, this message translates to:
  /// **'Daily limit: {currency} {max}'**
  String loadAmountLimitHint(String currency, String max);

  /// Title of the success outcome screen after a load request is submitted. The funds are pending until the provider authorizes — the copy intentionally avoids the word 'success'.
  ///
  /// In en, this message translates to:
  /// **'Load request sent'**
  String get loadSuccessTitle;

  /// First inline span on the success body, before the bold amount.
  ///
  /// In en, this message translates to:
  /// **'You\'ll receive '**
  String get loadSuccessBodyPrefix;

  /// Trailing inline span on the success body explaining the provider USSD/app authorization step.
  ///
  /// In en, this message translates to:
  /// **' in your MoneyA balance after you authorize the debit on {provider}.'**
  String loadSuccessBodySuffix(String provider);

  /// Primary CTA on the load success screen — returns to the home shell.
  ///
  /// In en, this message translates to:
  /// **'Go back home'**
  String get loadSuccessPrimaryCta;

  /// Secondary CTA on the load success screen — same destination as the primary for now; kept for visual parity with the transfer outcome screens.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get loadSuccessSecondaryCta;

  /// Header title on step 1 of the Withdraw flow (destination provider selection).
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get withdrawProviderHeaderTitle;

  /// Sub-header explaining what the user does on the withdraw destination-provider step.
  ///
  /// In en, this message translates to:
  /// **'Pick the mobile money account you want to send your funds to.'**
  String get withdrawProviderSubtitle;

  /// Section label above the country picker on the withdraw-provider step.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get withdrawProviderCountryLabel;

  /// Section label above the list of available mobile-money rails on the withdraw step.
  ///
  /// In en, this message translates to:
  /// **'Mobile money providers'**
  String get withdrawProviderListLabel;

  /// Empty-state message shown when the selected destination country has no rails wired up yet.
  ///
  /// In en, this message translates to:
  /// **'No mobile money providers are available in this country yet.'**
  String get withdrawProviderEmptyMessage;

  /// Header title on step 2 of the Withdraw flow (amount entry).
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get withdrawAmountHeaderTitle;

  /// Centered question above the tappable amount card on the withdraw step.
  ///
  /// In en, this message translates to:
  /// **'How much do you want to withdraw?'**
  String get withdrawAmountTitle;

  /// Section label above the locked destination provider summary and recipient-phone field.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get withdrawAmountToLabel;

  /// Placeholder for the destination-phone input — the account being credited.
  ///
  /// In en, this message translates to:
  /// **'Mobile money number'**
  String get withdrawAmountDestinationPhoneHint;

  /// Label on the swipe-to-confirm control at the bottom of the withdraw amount step.
  ///
  /// In en, this message translates to:
  /// **'Swipe to withdraw'**
  String get withdrawAmountSwipeLabel;

  /// Inline error shown when the entered withdraw amount is above the client-side KYC tier cap.
  ///
  /// In en, this message translates to:
  /// **'Amount exceeds your {tier} limit of {currency} {max}. Upgrade your account to withdraw more.'**
  String withdrawAmountOverLimit(String currency, String max, String tier);

  /// Inline error shown when the entered amount is higher than the user's current MoneyA balance. Blocks the swipe-to-pay control.
  ///
  /// In en, this message translates to:
  /// **'You only have {currency} {balance} available. Lower the amount or load more money first.'**
  String withdrawAmountInsufficientBalance(String currency, String balance);

  /// Helper text under the form summarising the user's current available balance.
  ///
  /// In en, this message translates to:
  /// **'Available balance: {currency} {balance}'**
  String withdrawAmountLimitHint(String currency, String balance);

  /// Title of the success outcome screen after a withdraw request is accepted. Wording avoids 'completed' because settlement is asynchronous on most rails.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal sent'**
  String get withdrawSuccessTitle;

  /// First inline span on the withdraw success body, before the bold amount.
  ///
  /// In en, this message translates to:
  /// **'We\'re sending '**
  String get withdrawSuccessBodyPrefix;

  /// Trailing inline span on the withdraw success body naming the destination provider.
  ///
  /// In en, this message translates to:
  /// **' to your {provider} account. It usually arrives within a few minutes.'**
  String withdrawSuccessBodySuffix(String provider);

  /// Primary CTA on the withdraw success screen — returns to the home shell.
  ///
  /// In en, this message translates to:
  /// **'Go back home'**
  String get withdrawSuccessPrimaryCta;

  /// Secondary CTA on the withdraw success screen — same destination as primary; kept for visual parity.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get withdrawSuccessSecondaryCta;

  /// Title of the pending outcome screen when the backend has accepted the withdraw but settlement hasn't confirmed yet.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal pending'**
  String get withdrawPendingTitle;

  /// First inline span on the pending withdraw body.
  ///
  /// In en, this message translates to:
  /// **'Your withdrawal of '**
  String get withdrawPendingBodyPrefix;

  /// Trailing inline span on the pending withdraw body.
  ///
  /// In en, this message translates to:
  /// **' to {provider} is being processed. We\'ll notify you once it settles.'**
  String withdrawPendingBodySuffix(String provider);

  /// Primary CTA on the pending withdraw outcome screen.
  ///
  /// In en, this message translates to:
  /// **'Go back home'**
  String get withdrawPendingPrimaryCta;

  /// Secondary CTA on the pending withdraw outcome — opens the transaction detail once that route is wired.
  ///
  /// In en, this message translates to:
  /// **'View transaction'**
  String get withdrawPendingSecondaryCta;

  /// Title of the failed outcome screen when the backend rejected the withdraw.
  ///
  /// In en, this message translates to:
  /// **'Withdrawal failed'**
  String get withdrawFailedTitle;

  /// First inline span on the failed withdraw body.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send '**
  String get withdrawFailedBodyPrefix;

  /// Trailing inline span on the failed withdraw body — reassures the user no debit happened.
  ///
  /// In en, this message translates to:
  /// **' to your {provider} account. No funds were taken from your balance — please try again.'**
  String withdrawFailedBodySuffix(String provider);

  /// Primary CTA on the failed withdraw outcome — pops back to the amount form so the user can retry with the same idempotency key.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get withdrawFailedPrimaryCta;

  /// Secondary CTA on the failed withdraw outcome — pops to home shell.
  ///
  /// In en, this message translates to:
  /// **'Go back home'**
  String get withdrawFailedSecondaryCta;

  /// Title of the adaptive dialog shown when the user attempts to leave a dirty form screen via back gesture or chevron.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesTitle;

  /// Body of the discard-changes dialog — neutral language; do not enumerate field names.
  ///
  /// In en, this message translates to:
  /// **'Your entries on this screen won\'t be saved.'**
  String get discardChangesBody;

  /// Destructive CTA of the discard-changes dialog — confirms abandoning the form.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardChangesConfirm;

  /// Cancel CTA of the discard-changes dialog — returns the user to the form.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get discardChangesCancel;

  /// Screen title for the saved-recipients list (Profile > Favorites).
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favoritesTitle;

  /// Empty-state title on the Favorites screen when the user has not saved any recipients.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get favoritesEmptyTitle;

  /// Empty-state body on the Favorites screen explaining the add-favorite rule: favorites are added from the success screen after a transfer.
  ///
  /// In en, this message translates to:
  /// **'Send money to someone first, then you can save them here for quick access next time.'**
  String get favoritesEmptyBody;

  /// Empty-state CTA on the Favorites screen that opens the Transfer flow.
  ///
  /// In en, this message translates to:
  /// **'Send money'**
  String get favoritesEmptyCta;

  /// Snackbar shown after the user swipes to delete a favorite. {name} is the favorite's display name.
  ///
  /// In en, this message translates to:
  /// **'Removed {name}'**
  String favoritesRemoved(String name);

  /// Snackbar action label that restores the just-removed favorite.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get favoritesUndo;

  /// Screen-reader hint on each favorite row describing the swipe-to-delete affordance.
  ///
  /// In en, this message translates to:
  /// **'Swipe left to remove'**
  String get favoritesSwipeHint;

  /// Title of the add-to-favorites card shown on the Send Money success screen. {name} is the recipient's display name.
  ///
  /// In en, this message translates to:
  /// **'Save {name} as a favorite?'**
  String favoritesAddPromptTitle(String name);

  /// Body of the add-to-favorites card on the Send Money success screen.
  ///
  /// In en, this message translates to:
  /// **'Saved recipients appear on your home screen so you can send money to them in one tap.'**
  String get favoritesAddPromptBody;

  /// CTA on the add-to-favorites card that saves the recipient.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get favoritesAddCta;

  /// Inline confirmation shown in place of the add-to-favorites card after the user taps the CTA.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get favoritesAddedConfirmation;

  /// Shown when a sign-in request cannot reach the server.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your network and try again.'**
  String get authErrorNetwork;

  /// Rate limit on requesting a sign-in code.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Try again in {minutes} min.'**
  String authErrorTooManyRequests(int minutes);

  /// Sign-in locked after repeated wrong codes.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong codes. Try again in {minutes} min.'**
  String authErrorOtpLocked(int minutes);

  /// The SMS provider is temporarily unavailable.
  ///
  /// In en, this message translates to:
  /// **'We could not send the code. Please try again in a moment.'**
  String get authErrorSmsUnavailable;

  /// The server rejected the phone number.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number.'**
  String get authErrorInvalidPhone;

  /// Fallback for unexpected sign-in errors.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get authErrorGeneric;

  /// The server rejected the passcode as too easy to guess.
  ///
  /// In en, this message translates to:
  /// **'Choose a less predictable passcode.'**
  String get passcodeErrorWeak;

  /// Label of the fee row in the price card.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get rampQuoteFeeLabel;

  /// Label for the amount credited to the balance.
  ///
  /// In en, this message translates to:
  /// **'You\'ll receive'**
  String get rampQuoteTopUpReceiveLabel;

  /// Label for the amount paid out to the recipient.
  ///
  /// In en, this message translates to:
  /// **'Recipient gets'**
  String get rampQuotePayoutReceiveLabel;

  /// Countdown while the price is locked.
  ///
  /// In en, this message translates to:
  /// **'Price valid for {seconds}s'**
  String rampQuoteValidFor(int seconds);

  /// Shown when the locked price ran out.
  ///
  /// In en, this message translates to:
  /// **'Price expired'**
  String get rampQuoteExpired;

  /// Action to fetch a new price.
  ///
  /// In en, this message translates to:
  /// **'Refresh price'**
  String get rampQuoteRefresh;

  /// Price could not be fetched.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t get a price. Check the amount and try again.'**
  String get rampQuoteError;

  /// Dialog title when a new price replaces the one shown.
  ///
  /// In en, this message translates to:
  /// **'The price changed'**
  String get rampRequoteTitle;

  /// Top-up price changed.
  ///
  /// In en, this message translates to:
  /// **'You\'ll now receive {amount} (fee {fee}). Continue?'**
  String rampRequoteBody(String amount, String fee);

  /// Cash-out price changed.
  ///
  /// In en, this message translates to:
  /// **'The recipient will now get {amount} (fee {fee}). Continue?'**
  String rampRequoteBodyPayout(String amount, String fee);

  /// Confirm the new price.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get rampRequoteContinue;

  /// Cash-out larger than the balance.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have enough balance for this.'**
  String get rampErrorInsufficientFunds;

  /// Provider unavailable.
  ///
  /// In en, this message translates to:
  /// **'Payments are temporarily unavailable. Please try again in a moment.'**
  String get rampErrorUnavailable;

  /// Provider not supported by the server yet.
  ///
  /// In en, this message translates to:
  /// **'This mobile money provider isn\'t available yet.'**
  String get rampErrorProviderNotSupported;

  /// Network error while placing an order.
  ///
  /// In en, this message translates to:
  /// **'Connection lost. Try again — you won\'t be charged twice.'**
  String get rampErrorNetwork;

  /// Fallback.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get rampErrorGeneric;

  /// Top-up waiting for the user.
  ///
  /// In en, this message translates to:
  /// **'Approve on your phone'**
  String get rampTopUpPendingTitle;

  /// Top-up pending body.
  ///
  /// In en, this message translates to:
  /// **'Check your phone and approve the payment of {amount}. This screen updates by itself.'**
  String rampTopUpPendingBody(String amount);

  /// Top-up success.
  ///
  /// In en, this message translates to:
  /// **'Top-up complete'**
  String get rampTopUpSuccessTitle;

  /// Top-up success body.
  ///
  /// In en, this message translates to:
  /// **'{amount} was added to your MoneyA balance.'**
  String rampTopUpSuccessBody(String amount);

  /// Top-up failed.
  ///
  /// In en, this message translates to:
  /// **'Payment not completed'**
  String get rampTopUpFailedTitle;

  /// Top-up declined.
  ///
  /// In en, this message translates to:
  /// **'The payment was declined or cancelled. You were not charged.'**
  String get rampTopUpFailedBody;

  /// Top-up timed out.
  ///
  /// In en, this message translates to:
  /// **'Your provider didn\'t respond in time. You were not charged.'**
  String get rampTopUpFailedTimeoutBody;

  /// Cash-out in progress.
  ///
  /// In en, this message translates to:
  /// **'Sending your money'**
  String get rampCashOutPendingTitle;

  /// Cash-out pending body.
  ///
  /// In en, this message translates to:
  /// **'We\'re sending {amount} to {phone}. This usually takes a few minutes.'**
  String rampCashOutPendingBody(String amount, String phone);

  /// Cash-out success.
  ///
  /// In en, this message translates to:
  /// **'Money sent'**
  String get rampCashOutSuccessTitle;

  /// Cash-out success body.
  ///
  /// In en, this message translates to:
  /// **'{amount} was sent to {phone}.'**
  String rampCashOutSuccessBody(String amount, String phone);

  /// Cash-out failed.
  ///
  /// In en, this message translates to:
  /// **'Cash-out failed'**
  String get rampCashOutFailedTitle;

  /// Cash-out refunded.
  ///
  /// In en, this message translates to:
  /// **'The money is back in your MoneyA balance.'**
  String get rampCashOutFailedBody;

  /// Shown when the order is slow.
  ///
  /// In en, this message translates to:
  /// **'This is taking longer than usual. You can leave this screen — we\'ll notify you when it\'s done.'**
  String get rampSlowNote;

  /// Close the status screen.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get rampDoneCta;

  /// Return home.
  ///
  /// In en, this message translates to:
  /// **'Go back home'**
  String get rampBackHomeCta;

  /// Retry after a failure.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get rampTryAgainCta;

  /// Hero title on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginTitle;

  /// Subtitle under the login hero title; explains passwordless sign-in.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number and we\'ll send you a code.'**
  String get loginSubtitle;

  /// Primary CTA pill on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginCta;

  /// Inline prompt before the Create link on the login screen. The trailing space is intentional.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account ? '**
  String get loginNoAccount;

  /// Inline link label that takes new users from login to account creation.
  ///
  /// In en, this message translates to:
  /// **'Create one'**
  String get loginCreateLink;

  /// Generic retry button after a failed load.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// Shown under the balance card when the balance request fails; tapping retries.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your balance. Tap to retry.'**
  String get homeBalanceLoadError;

  /// Shown in the recent-transactions section when the request fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your transactions.'**
  String get homeTransactionsLoadError;

  /// Empty state of the recent-transactions section for a user with no activity.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet.'**
  String get homeNoTransactions;

  /// Shown on the Transactions tab when the request fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your transactions.'**
  String get transactionsLoadError;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
