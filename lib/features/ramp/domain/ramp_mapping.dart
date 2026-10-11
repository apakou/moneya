import '../../home/domain/supported_currency.dart';
import '../../load_money/domain/momo_provider.dart';

/// App ↔ API vocabulary bridges. The API follows ISO 4217 and `openapi.yaml`'s
/// `payment_method` enum; the app has legacy display codes.
class RampMapping {
  const RampMapping._();

  /// Ghana's cedi is shown as `GHC` in the app (legacy branding, see
  /// [SupportedCurrency.ghs]) but the API speaks ISO `GHS`.
  static String wireCurrency(SupportedCurrency c) => c == SupportedCurrency.ghs ? 'GHS' : c.code;

  /// `openapi.yaml` `OnrampOrderRequest.payment_method`. `null` = the provider
  /// is not in the contract yet (T-Money, OPay): the UI must say so instead of
  /// sending a request the server will reject.
  static String? paymentMethod(MomoProvider p) => switch (p) {
        MomoProvider.wave => 'WAVE',
        MomoProvider.orangeMoney => 'ORANGE_MONEY',
        MomoProvider.mtnMomo => 'MTN_MOMO',
        MomoProvider.moovAfrica => 'MOOV_MONEY',
        MomoProvider.tMoney => null,
        MomoProvider.opay => null,
      };
}
