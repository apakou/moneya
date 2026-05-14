import 'package:flutter_test/flutter_test.dart';
import 'package:moneya/core/logging/pii.dart';

void main() {
  group('maskPhone', () {
    test('masks an E.164 number keeping prefix and tail', () {
      expect(maskPhone('+221770123456'), '+221 ** ** ** 56');
    });

    test('returns *** for short or null input', () {
      expect(maskPhone(null), '***');
      expect(maskPhone(''), '***');
      expect(maskPhone('+1234'), '***');
    });
  });

  group('maskToken', () {
    test('shows first and last four chars when long enough', () {
      expect(maskToken('eyJhbGciOiJSUzI1NiJ9.payload.sig'), 'eyJh….sig');
    });

    test('returns *** when too short', () {
      expect(maskToken('short'), '***');
      expect(maskToken(null), '***');
    });
  });

  test('maskSecret always returns ***', () {
    expect(maskSecret('123456'), '***');
    expect(maskSecret(null), '***');
    expect(maskSecret(42), '***');
  });

  group('maskEmail', () {
    test('keeps first char and domain', () {
      expect(maskEmail('jane@example.com'), 'j***@example.com');
    });

    test('returns *** on malformed input', () {
      expect(maskEmail('@x.com'), '***');
      expect(maskEmail('jane@'), '***');
      expect(maskEmail(null), '***');
    });
  });

  group('redactMap', () {
    test('redacts known PII keys', () {
      final out = redactMap({
        'passcode': '123456',
        'otp': '999000',
        'access_token': 'eyJhbGciOiJSUzI1NiJ9.payload.sig',
        'refresh_token': 'rfr-very-long-secret-value',
        'amount': '100.00',
      });
      expect(out['passcode'], '***');
      expect(out['otp'], '***');
      expect(out['access_token'], '***');
      expect(out['refresh_token'], '***');
      expect(out['amount'], '100.00');
    });

    test('masks phone-like keys', () {
      final out = redactMap({'phone': '+221770123456', 'name': 'Aminata'});
      expect(out['phone'], '+221 ** ** ** 56');
      expect(out['name'], 'Aminata');
    });

    test('recurses into nested maps and lists', () {
      final out = redactMap({
        'user': {'passcode': 'x', 'phone': '+221770000099'},
        'history': [
          {'otp': '123'},
          'plain',
        ],
      });
      final user = out['user']! as Map<String, Object?>;
      expect(user['passcode'], '***');
      expect(user['phone'], startsWith('+221'));

      final history = out['history']! as List;
      expect((history[0] as Map)['otp'], '***');
      expect(history[1], 'plain');
    });

    test('does not mutate input', () {
      final input = {'passcode': '1'};
      redactMap(input);
      expect(input['passcode'], '1');
    });
  });

  group('redactHeaders', () {
    test('drops authorization and txn-token', () {
      final out = redactHeaders({
        'Authorization': 'Bearer eyJh.payload.sig',
        'X-Txn-Token': 'short-lived',
        'Idempotency-Key': 'uuid-here',
        'X-App-Version': '1.0.0+1',
      });
      expect(out['Authorization'], '***');
      expect(out['X-Txn-Token'], '***');
      expect(out['Idempotency-Key'], '***');
      expect(out['X-App-Version'], '1.0.0+1');
    });

    test('case-insensitive matching', () {
      final out = redactHeaders({'authorization': 'Bearer x', 'COOKIE': 'a=b'});
      expect(out['authorization'], '***');
      expect(out['COOKIE'], '***');
    });
  });
}
