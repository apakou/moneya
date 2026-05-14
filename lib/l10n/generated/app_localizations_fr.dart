// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'MoneyA';

  @override
  String get languageTooltip => 'Langue';

  @override
  String get notificationsTooltip => 'Notifications';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get homeTotalBalance => 'Solde total';

  @override
  String get homeBalanceShow => 'Afficher le solde';

  @override
  String get homeBalanceHide => 'Masquer le solde';

  @override
  String get homeActionSend => 'Envoyer';

  @override
  String get homeActionReceive => 'Recevoir';

  @override
  String get homeActionLoad => 'Recharger';

  @override
  String get homeActionWithdraw => 'Retirer';

  @override
  String get homeSectionAiInsights => 'Insights IA';

  @override
  String get homeSectionFavorites => 'Vos favoris';

  @override
  String get homeSectionRecentTransactions => 'Transactions récentes';

  @override
  String get homeViewAll => 'Tout voir';

  @override
  String get insightSmartRateTitle => 'Taux intelligent';

  @override
  String get insightSmartRateBody =>
      'Économisez sur votre prochain transfert international.';

  @override
  String get insightTrustScoreTitle => 'Score de confiance';

  @override
  String insightTrustScoreBody(String currency, String limit) {
    return 'Débloquez des micro-prêts jusqu’à $currency $limit.';
  }

  @override
  String get insightSpendingPulseTitle => 'Pouls des dépenses';

  @override
  String get insightSpendingPulseBody =>
      'Vous avez dépensé 18 % de moins que la semaine dernière.';

  @override
  String get txnLabelReceived => 'Reçu';

  @override
  String get txnLabelSent => 'Envoyé';

  @override
  String get txnLabelPayed => 'Payé';

  @override
  String get txnStatusSuccess => 'Réussi';

  @override
  String get txnStatusFailed => 'Échoué';

  @override
  String get transactionsTitle => 'Vos transactions';

  @override
  String get transactionsExportTooltip => 'Exporter';

  @override
  String get transactionsEmpty =>
      'Aucune transaction ne correspond à ce filtre.';

  @override
  String get txnFilterSent => 'Envoyés';

  @override
  String get txnFilterReceived => 'Reçus';

  @override
  String get txnFilterSucceeded => 'Réussis';

  @override
  String get txnFilterPending => 'En attente';

  @override
  String get txnFilterFailed => 'Échoués';

  @override
  String get txnStatusPending => 'En attente';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get navHome => 'Accueil';

  @override
  String get navTransactions => 'Transactions';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get commonBack => 'Retour';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get settingsSectionSecurity => 'Sécurité et confidentialité';

  @override
  String get settingsSectionTransactions => 'Transactions';

  @override
  String get settingsSectionActions => 'Actions';

  @override
  String get settingsRowChangePassword => 'Changer le mot de passe';

  @override
  String get settingsRowLoginOptions => 'Options de connexion';

  @override
  String get settingsRowBiometricsLabel => 'Biométrie pour les transactions';

  @override
  String get settingsRowBiometricsSubtitle =>
      'Authentifier les transactions par biométrie';

  @override
  String get settingsRowPhoneNumberAccount => 'Compte par numéro de téléphone';

  @override
  String get settingsRowUssdBanking => 'Banque USSD';

  @override
  String get settingsRowDeleteAccount => 'Supprimer le compte';

  @override
  String get deleteAccountDialogTitle => 'Supprimer le compte ?';

  @override
  String get deleteAccountDialogBody =>
      'Cela supprime définitivement votre compte MoneyA, vos soldes et votre historique de transactions. Cette action est irréversible.';

  @override
  String get profileTitle => 'Détails du profil';

  @override
  String get profileSectionPersonal => 'Informations personnelles';

  @override
  String get profileSectionActions => 'Actions';

  @override
  String get profileFieldPhone => 'Numéro de téléphone';

  @override
  String get profileFieldEmail => 'E-mail';

  @override
  String get profileFieldAddress => 'Adresse';

  @override
  String get profileFieldDateOfBirth => 'Date de naissance';

  @override
  String get profileVerifiedBadge => 'Vérifié';

  @override
  String get profileActionReferAndEarn => 'Parrainer et gagner';

  @override
  String get profileActionSettings => 'Paramètres';

  @override
  String get profileActionLogout => 'Déconnexion';

  @override
  String get txnDetailTitle => 'Détails de la transaction';

  @override
  String get txnDetailStatusSuccess => 'Réussie';

  @override
  String get txnDetailStatusPending => 'En attente';

  @override
  String get txnDetailStatusFailed => 'Échouée';

  @override
  String get txnDetailDirectionSent => 'Envoyé';

  @override
  String get txnDetailDirectionReceived => 'Reçu';

  @override
  String get txnDetailRowFee => 'Frais';

  @override
  String get txnDetailRowTotal => 'Total';

  @override
  String get txnDetailRowPhone => 'Téléphone';

  @override
  String get txnDetailRowMethod => 'Méthode';

  @override
  String get txnDetailRowReference => 'Référence';

  @override
  String txnDetailCopiedSnack(String label) {
    return '$label copié';
  }

  @override
  String get txnDetailActionShare => 'Partager';

  @override
  String get txnDetailActionDownloadPdf => 'Télécharger en PDF';

  @override
  String txnDetailShareSubject(String reference) {
    return 'Reçu MoneyA — $reference';
  }

  @override
  String get txnDetailShareHeader => 'Reçu MoneyA';

  @override
  String txnDetailShareLineStatus(String status) {
    return 'Statut : $status';
  }

  @override
  String txnDetailShareLineDirection(String direction) {
    return 'Sens : $direction';
  }

  @override
  String txnDetailShareLineCounterparty(String label, String name) {
    return '$label : $name';
  }

  @override
  String txnDetailShareLineWhen(String timestamp) {
    return 'Date : $timestamp';
  }

  @override
  String txnDetailShareLineAmount(String amount) {
    return 'Montant : $amount';
  }

  @override
  String txnDetailShareLineFee(String fee) {
    return 'Frais : $fee';
  }

  @override
  String txnDetailShareLineTotal(String total) {
    return 'Total : $total';
  }

  @override
  String txnDetailShareLineMethod(String method) {
    return 'Méthode : $method';
  }

  @override
  String txnDetailShareLinePhone(String phone) {
    return 'Téléphone : $phone';
  }

  @override
  String txnDetailShareLineReference(String reference) {
    return 'Référence : $reference';
  }

  @override
  String get txnDetailShareFooter => 'Propulsé par MoneyA';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsMarkAllRead => 'Tout marquer comme lu';

  @override
  String get notificationsGroupToday => 'Aujourd\'hui';

  @override
  String get notificationsGroupYesterday => 'Hier';

  @override
  String get notificationsGroupEarlierWeek => 'Plus tôt cette semaine';

  @override
  String get notificationsGroupOlder => 'Plus anciennes';

  @override
  String get notificationsTimeJustNow => 'à l\'instant';

  @override
  String notificationsTimeMinutes(int n) {
    return '$n min';
  }

  @override
  String notificationsTimeHours(int n) {
    return '$n h';
  }

  @override
  String get notificationsTimeYesterday => 'Hier';

  @override
  String notificationsTimeDays(int n) {
    return '$n j';
  }

  @override
  String get receiveTitle => 'Recevoir';

  @override
  String get receiveTabAccount => 'Compte';

  @override
  String get receiveTabQrCode => 'Code QR';

  @override
  String get receiveTabRequest => 'Demande';

  @override
  String receiveTabSemanticLabel(String label) {
    return 'Onglet $label';
  }

  @override
  String get receiveTabSemanticHint => 'Appuyer deux fois pour changer';

  @override
  String get receiveAccountVerifiedMember => 'Membre MoneyA vérifié';

  @override
  String get receiveAccountHelpText =>
      'Toute personne sur MoneyA peut vous envoyer de l\'argent instantanément avec ce numéro.';

  @override
  String get receiveAccountCardLabel => 'Numéro de compte MoneyA';

  @override
  String get receiveAccountCopyLabel => 'Copier le numéro';

  @override
  String get receiveAccountShareLabel => 'Partager';

  @override
  String receiveAccountCopySemantic(String number) {
    return 'Copier le numéro de compte $number';
  }

  @override
  String get receiveAccountShareSemantic => 'Partager le numéro de compte';

  @override
  String get receiveAccountCopyAnnouncement =>
      'Numéro de compte copié dans le presse-papiers';

  @override
  String get receiveAccountCopySnack => 'Numéro de compte copié';

  @override
  String get receiveAccountShareSubject => 'Mon numéro de compte MoneyA';

  @override
  String receiveAccountShareBody(String number) {
    return 'Envoyez-moi de l\'argent sur MoneyA. Mon numéro de compte est $number.';
  }

  @override
  String get authLandingTagline => 'Dites-le. Nous l\'envoyons.';

  @override
  String get authLandingLogin => 'Se connecter';

  @override
  String get authLandingCreateAccount => 'Créer un compte';

  @override
  String get createAccountTitle => 'Créer un nouveau compte';

  @override
  String get createAccountSubtitle =>
      'Entrez simplement votre numéro de téléphone, c\'est tout.';

  @override
  String get createAccountPhoneHint => 'Entrez votre numéro de téléphone';

  @override
  String get createAccountClearTooltip => 'Effacer';

  @override
  String get createAccountAlreadyHaveAccount => 'Vous avez déjà un compte ? ';

  @override
  String get createAccountLoginLink => 'Se connecter';

  @override
  String get createAccountCta => 'Créer un compte';

  @override
  String get createAccountPickCountryTitle => 'Sélectionner un pays';

  @override
  String get createAccountConfirmSheetTitle =>
      'Confirmer le numéro de téléphone';

  @override
  String get createAccountConfirmSheetBody =>
      'Nous enverrons un code de vérification à ce numéro.';

  @override
  String get createAccountConfirmCta => 'Confirmer';

  @override
  String get createAccountGoBack => 'Retour';

  @override
  String get countryTogo => 'Togo';

  @override
  String get countrySenegal => 'Sénégal';

  @override
  String get countryIvoryCoast => 'Côte d\'Ivoire';

  @override
  String get countryMali => 'Mali';

  @override
  String get countryBurkinaFaso => 'Burkina Faso';

  @override
  String get countryBenin => 'Bénin';

  @override
  String get countryNigeria => 'Nigéria';

  @override
  String get countryGhana => 'Ghana';

  @override
  String get verifyPhoneTitle => 'Saisir le code';

  @override
  String verifyPhoneSubtitle(int length, String dialCode, String tail) {
    return 'Nous avons envoyé un code à $length chiffres à votre numéro de téléphone (+$dialCode) … $tail';
  }

  @override
  String get verifyPhoneResendPrompt => 'Vous n\'avez pas reçu le code ?';

  @override
  String get verifyPhoneResendLink => 'Renvoyer le code';

  @override
  String get verifyPhoneIncorrectTitle => 'Code incorrect';

  @override
  String get verifyPhoneIncorrectBody =>
      'Veuillez vérifier le code et réessayer.';

  @override
  String get verifyPhoneGotIt => 'Compris';

  @override
  String get passcodeSetTitle => 'Définir un code d\'accès';

  @override
  String get passcodeConfirmTitle => 'Confirmer le code d\'accès';

  @override
  String passcodeSetSubtitle(int length) {
    return 'créez un code d\'accès à $length chiffres';
  }

  @override
  String passcodeConfirmSubtitle(int length) {
    return 'Répétez le code d\'accès à $length chiffres';
  }

  @override
  String get passcodeNextCta => 'Suivant';

  @override
  String get passcodeSaveCta => 'Enregistrer';

  @override
  String get passcodeMismatchError => 'Les codes ne correspondent pas.';

  @override
  String passcodeErrorWrongLength(int length) {
    return 'Utilisez $length chiffres.';
  }

  @override
  String get passcodeErrorDigitsOnly => 'Chiffres uniquement.';

  @override
  String get passcodeErrorRepeating => 'Évitez les chiffres répétés.';

  @override
  String get passcodeErrorSequential => 'Évitez les chiffres consécutifs.';

  @override
  String get passcodeBiometricReason => 'Activer la connexion biométrique';

  @override
  String get kycChooseTitle =>
      'Choisissez une pièce pour\nvérifier votre identité';

  @override
  String get kycChooseSubtitle => 'Nous n\'acceptons ni scans ni copies.';

  @override
  String get kycDocumentNationalId => 'Carte d\'identité nationale';

  @override
  String get kycDocumentPassport => 'Passeport';

  @override
  String get kycChooseContinue => 'Continuer';

  @override
  String get kycCaptureFrontInstruction =>
      'Placez le recto de votre pièce dans le cadre';

  @override
  String get kycCaptureBackInstruction =>
      'Placez le verso de votre pièce dans le cadre';

  @override
  String get kycCaptureProcessing => 'Traitement…';

  @override
  String get kycCameraDeniedMessage =>
      'L\'accès à la caméra est nécessaire pour vérifier votre identité.';

  @override
  String get kycCameraOpenSettings => 'Ouvrir les paramètres';

  @override
  String get kycCameraUnavailableMessage =>
      'La caméra n\'est pas disponible sur cet appareil.';

  @override
  String get kycCameraTryAgain => 'Réessayer';

  @override
  String get kycSelfieInstruction => 'Gardez votre visage dans l\'ovale';

  @override
  String get cameraShutterLabel => 'Prendre une photo';

  @override
  String get transferHeaderTitle => 'Transfert';

  @override
  String get transferTitle => 'Envoyer de l\'argent';

  @override
  String get transferSectionFrom => 'De';

  @override
  String get transferSectionTo => 'À';

  @override
  String get transferSenderPhoneHint => 'Votre numéro mobile money';

  @override
  String get transferRecipientPhoneHint => 'Numéro du destinataire';

  @override
  String get transferRecipientNameHint => 'Nom du destinataire';

  @override
  String get transferPurposeHint => 'Motif (Facultatif)';

  @override
  String get transferFeeLabel => 'Frais de transaction';

  @override
  String get transferRecipientReceivesLabel => 'Le destinataire recevra';

  @override
  String get transferConfirmCta => 'Confirmer';

  @override
  String get transferLookupChecking => 'Recherche dans l\'annuaire MoneyA…';

  @override
  String transferLookupFound(String name) {
    return 'Utilisateur MoneyA trouvé — $name';
  }

  @override
  String get transferLookupNotFound =>
      'Pas encore sur MoneyA. Cette personne recevra une invitation par SMS pour réclamer ce transfert.';

  @override
  String get transferContactPickerError =>
      'Impossible d\'ouvrir le sélecteur de contacts.';

  @override
  String get transferContactNoPhone =>
      'Ce contact n\'a pas de numéro de téléphone.';

  @override
  String get transferContactPermissionDeniedPermanent =>
      'L\'accès aux contacts est désactivé. Activez-le dans les Réglages pour choisir un destinataire dans votre carnet d\'adresses.';

  @override
  String get transferContactPermissionDeniedAction => 'Réglages';

  @override
  String get transferContactPermissionNeeded =>
      'L\'autorisation Contacts est nécessaire pour choisir un destinataire.';

  @override
  String get confirmPaymentHeaderTitle => 'Confirmer';

  @override
  String get confirmPaymentTitle => 'Confirmer votre paiement';

  @override
  String get confirmPaymentDetailsHeading => 'Détails du paiement';

  @override
  String get confirmPaymentDetailsSubtitle =>
      'Vérifiez les détails et glissez pour payer !';

  @override
  String get confirmPaymentAmountLabel => 'Montant';

  @override
  String get confirmPaymentFromYourPrefix => 'Depuis votre ';

  @override
  String get confirmPaymentToRecipientPrefix => 'À ';

  @override
  String get confirmPaymentRecipientFallback => 'Destinataire';

  @override
  String get confirmPaymentSwipeLabel => 'Glisser pour payer';

  @override
  String get confirmPaymentAuthFailedSnack =>
      'Trop de tentatives erronées. Réessayez.';

  @override
  String get amountKeypadDoneCta => 'Terminé';

  @override
  String get fundingProviderPickerTitle => 'Choisir la source de financement';

  @override
  String get transferCountryPickerTitle => 'Choisir le pays d\'envoi';

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
      'Code QR MoneyA. Demandez à quelqu\'un de le scanner avec son application MoneyA pour vous envoyer de l\'argent. Pour entendre votre numéro de compte, passez à l\'onglet Compte.';

  @override
  String get receiveQrHelpText =>
      'Présentez ce code QR à toute personne ayant l\'application MoneyA pour recevoir de l\'argent en personne.';

  @override
  String get receiveQrShareLabel => 'Partager le QR';

  @override
  String get receiveQrSaveLabel => 'Enregistrer l\'image';

  @override
  String get receiveQrShareSemantic => 'Partager le code QR';

  @override
  String get receiveQrSaveSemantic => 'Enregistrer le code QR dans les photos';

  @override
  String get receiveQrShareSubject => 'Mon code QR MoneyA';

  @override
  String receiveQrShareBody(String number) {
    return 'Envoyez-moi de l\'argent sur MoneyA. Mon numéro de compte est $number.';
  }

  @override
  String get receiveQrSavedSnack => 'Code QR enregistré dans vos photos';

  @override
  String get receiveQrSavedAnnouncement => 'Code QR enregistré dans vos photos';

  @override
  String receiveQrSaveErrorSnack(String reason) {
    return 'Impossible d\'enregistrer le QR : $reason';
  }

  @override
  String receiveQrSaveErrorAnnouncement(String reason) {
    return 'Impossible d\'enregistrer le code QR. $reason';
  }

  @override
  String get receiveRequestSectionFrom => 'De';

  @override
  String get receiveRequestSectionAmount => 'Montant';

  @override
  String get receiveRequestClearPhoneSemantic =>
      'Effacer le numéro de téléphone';

  @override
  String get receiveRequestNotOnMoneyA =>
      'Ce numéro n\'est pas sur MoneyA. Vous ne pouvez demander qu\'à des utilisateurs MoneyA existants.';

  @override
  String get receiveRequestCurrencyHint =>
      'Appuyer deux fois pour changer de devise';

  @override
  String get receiveRequestBusyHint => 'Chargement';

  @override
  String get receiveRequestSwipeLabel => 'Glisser pour demander';

  @override
  String get receiveRequestSwipeSemanticLabel =>
      'Glissez pour envoyer la demande de paiement';

  @override
  String get receiveRequestSwipeHintReady =>
      'Glissez vers la droite pour confirmer';

  @override
  String get receiveRequestSwipeHintDisabled =>
      'Saisissez un destinataire et un montant pour activer';

  @override
  String get receiveRequestOutcomeTitle => 'Demande envoyée';

  @override
  String get receiveRequestOutcomeBodyPrefix => 'Nous avons notifié ';

  @override
  String get receiveRequestOutcomeBodyMiddle => ' de votre demande de ';

  @override
  String get receiveRequestOutcomeBodySuffix =>
      '. Nous vous préviendrons dès qu\'ils paient.';

  @override
  String get receiveRequestOutcomePrimary => 'Terminé';

  @override
  String get receiveRequestOutcomeSecondary => 'Partager la demande';

  @override
  String get receiveRequestShareSubject => 'Demande de paiement MoneyA';

  @override
  String get receiveRequestNoteLabel => 'Note (facultatif)';

  @override
  String get receiveRequestNoteHint =>
      'Objet de la demande ? (ex. déjeuner, loyer, billets)';

  @override
  String receiveRequestShareBody(String name, String currency, String amount) {
    return 'Bonjour $name — je viens de vous envoyer une demande de paiement de $currency $amount sur MoneyA. Ouvrez l\'application pour payer.';
  }

  @override
  String get onboardingLanguageHeadline => 'Quelle langue parlez-vous ?';

  @override
  String get onboardingSendMoneyHeadline =>
      'Envoyez de l\'argent plus vite et moins cher';

  @override
  String get onboardingCrossCorridorHeadline =>
      'Entre pays africains francophones\net anglophones';

  @override
  String get onboardingNext => 'Suivant';

  @override
  String get onboardingSkip => 'Passer';

  @override
  String get onboardingBack => 'Retour';

  @override
  String get loadProviderHeaderTitle => 'Charger de l\'argent';

  @override
  String get loadProviderSubtitle =>
      'Choisissez le compte mobile money à débiter.';

  @override
  String get loadProviderCountryLabel => 'Pays';

  @override
  String get loadProviderListLabel => 'Opérateurs mobile money';

  @override
  String get loadProviderEmptyMessage =>
      'Aucun opérateur mobile money n\'est encore disponible dans ce pays.';

  @override
  String get loadAmountHeaderTitle => 'Charger de l\'argent';

  @override
  String get loadAmountTitle => 'Combien voulez-vous charger ?';

  @override
  String get loadAmountFromLabel => 'Depuis';

  @override
  String get loadAmountSourcePhoneHint => 'Numéro mobile money';

  @override
  String get loadAmountSwipeLabel => 'Glissez pour charger';

  @override
  String loadAmountOverLimit(String currency, String max, String tier) {
    return 'Le montant dépasse votre limite $tier de $currency $max. Mettez à niveau votre compte pour charger plus.';
  }

  @override
  String loadAmountLimitHint(String currency, String max) {
    return 'Limite quotidienne : $currency $max';
  }

  @override
  String get loadSuccessTitle => 'Demande de chargement envoyée';

  @override
  String get loadSuccessBodyPrefix => 'Vous recevrez ';

  @override
  String loadSuccessBodySuffix(String provider) {
    return ' sur votre solde MoneyA après avoir autorisé le débit sur $provider.';
  }

  @override
  String get loadSuccessPrimaryCta => 'Retour à l\'accueil';

  @override
  String get loadSuccessSecondaryCta => 'Terminé';

  @override
  String get withdrawProviderHeaderTitle => 'Retirer';

  @override
  String get withdrawProviderSubtitle =>
      'Choisissez le compte mobile money à créditer.';

  @override
  String get withdrawProviderCountryLabel => 'Pays';

  @override
  String get withdrawProviderListLabel => 'Opérateurs mobile money';

  @override
  String get withdrawProviderEmptyMessage =>
      'Aucun opérateur mobile money n\'est encore disponible dans ce pays.';

  @override
  String get withdrawAmountHeaderTitle => 'Retirer';

  @override
  String get withdrawAmountTitle => 'Combien voulez-vous retirer ?';

  @override
  String get withdrawAmountToLabel => 'Vers';

  @override
  String get withdrawAmountDestinationPhoneHint => 'Numéro mobile money';

  @override
  String get withdrawAmountSwipeLabel => 'Glissez pour retirer';

  @override
  String withdrawAmountOverLimit(String currency, String max, String tier) {
    return 'Le montant dépasse votre limite $tier de $currency $max. Mettez à niveau votre compte pour retirer plus.';
  }

  @override
  String withdrawAmountInsufficientBalance(String currency, String balance) {
    return 'Vous disposez seulement de $currency $balance. Réduisez le montant ou chargez de l\'argent d\'abord.';
  }

  @override
  String withdrawAmountLimitHint(String currency, String balance) {
    return 'Solde disponible : $currency $balance';
  }

  @override
  String get withdrawSuccessTitle => 'Retrait envoyé';

  @override
  String get withdrawSuccessBodyPrefix => 'Nous envoyons ';

  @override
  String withdrawSuccessBodySuffix(String provider) {
    return ' sur votre compte $provider. L\'argent arrive généralement en quelques minutes.';
  }

  @override
  String get withdrawSuccessPrimaryCta => 'Retour à l\'accueil';

  @override
  String get withdrawSuccessSecondaryCta => 'Terminé';

  @override
  String get withdrawPendingTitle => 'Retrait en attente';

  @override
  String get withdrawPendingBodyPrefix => 'Votre retrait de ';

  @override
  String withdrawPendingBodySuffix(String provider) {
    return ' vers $provider est en cours de traitement. Nous vous informerons dès qu\'il sera finalisé.';
  }

  @override
  String get withdrawPendingPrimaryCta => 'Retour à l\'accueil';

  @override
  String get withdrawPendingSecondaryCta => 'Voir la transaction';

  @override
  String get withdrawFailedTitle => 'Échec du retrait';

  @override
  String get withdrawFailedBodyPrefix => 'Impossible d\'envoyer ';

  @override
  String withdrawFailedBodySuffix(String provider) {
    return ' vers votre compte $provider. Aucun montant n\'a été débité — veuillez réessayer.';
  }

  @override
  String get withdrawFailedPrimaryCta => 'Réessayer';

  @override
  String get withdrawFailedSecondaryCta => 'Retour à l\'accueil';

  @override
  String get discardChangesTitle => 'Annuler les modifications ?';

  @override
  String get discardChangesBody =>
      'Vos saisies sur cet écran ne seront pas enregistrées.';

  @override
  String get discardChangesConfirm => 'Annuler';

  @override
  String get discardChangesCancel => 'Continuer la saisie';
}
