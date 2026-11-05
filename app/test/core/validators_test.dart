import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/validators.dart';
import 'package:verifier/domain/enums.dart';

void main() {
  group('username (spec 16)', () {
    test('normalize, rules and the internal address', () {
      expect(normalizeUsername(' Rahim_1 '), 'rahim_1');
      expect(isValidUsername('rahim_1'), isTrue);
      expect(isValidUsername('abc'), isTrue);
      expect(isValidUsername('a' * 20), isTrue);
      expect(isValidUsername('ab'), isFalse);
      expect(isValidUsername('a' * 21), isFalse);
      expect(isValidUsername('Rahim'), isFalse);
      expect(isValidUsername('ra him'), isFalse);
      expect(isValidUsername('rahim@x'), isFalse);
      expect(isValidUsername('রহিম'), isFalse);
      expect(usernameToEmail('rahim'), 'rahim@users.bdpay.app');
      expect(usernameOf('rahim@users.bdpay.app'), 'rahim');
      expect(usernameOf('old@gmail.com'), 'old@gmail.com');
    });
  });

  group('email', () {
    test('" Basher@Example.COM " is sent as "basher@example.com"', () {
      expect(normalizeEmail(' Basher@Example.COM '), 'basher@example.com');
    });

    test('simple text@text.text check', () {
      expect(isValidEmail('basher@example.com'), isTrue);
      expect(isValidEmail('demo@bdpay.test'), isTrue);
      expect(isValidEmail('abc'), isFalse);
      expect(isValidEmail('a@b'), isFalse);
      expect(isValidEmail('a b@c.d'), isFalse);
      expect(isValidEmail(''), isFalse);
    });
  });

  group('wallet number', () {
    test('"০১৭১১-২২২ ৩৩৩" becomes "01711222333"', () {
      expect(normalizeWalletNumber('০১৭১১-২২২ ৩৩৩'), '01711222333');
    });

    test('"+8801711222333" and "8801711222333" become "01711222333"', () {
      expect(normalizeWalletNumber('+8801711222333'), '01711222333');
      expect(normalizeWalletNumber('8801711222333'), '01711222333');
    });

    test('11 digits are valid for every operator', () {
      for (final op in MfsOperator.values) {
        expect(isValidWalletNumber(op, '01711222333'), isTrue, reason: op.name);
      }
    });

    test('12 digits are valid for Rocket only', () {
      expect(isValidWalletNumber(MfsOperator.rocket, '017112223331'), isTrue);
      expect(isValidWalletNumber(MfsOperator.bkash, '017112223331'), isFalse);
      expect(isValidWalletNumber(MfsOperator.nagad, '017112223331'), isFalse);
      expect(isValidWalletNumber(MfsOperator.upay, '017112223331'), isFalse);
    });

    test('bkash "01211222333" is invalid (02-prefix not allowed)', () {
      expect(isValidWalletNumber(MfsOperator.bkash, '01211222333'), isFalse);
    });

    test('too short, too long and non-digits are invalid', () {
      expect(isValidWalletNumber(MfsOperator.bkash, '0171122233'), isFalse);
      expect(isValidWalletNumber(MfsOperator.rocket, '0171122233312'), isFalse);
      expect(isValidWalletNumber(MfsOperator.bkash, '0171122233a'), isFalse);
    });
  });

  group('shop domain', () {
    test('three inputs all become "myshop.myshopify.com"', () {
      for (final input in ['MyShop', 'https://myshop.myshopify.com/admin/orders', 'myshop.myshopify.com']) {
        final d = normalizeShopDomain(input);
        expect(d, 'myshop.myshopify.com', reason: input);
        expect(isValidShopDomain(d), isTrue);
      }
    });

    test('http:// is removed too', () {
      expect(normalizeShopDomain(' http://MyShop.myshopify.com/ '), 'myshop.myshopify.com');
    });

    test('"myshop.com" is invalid', () {
      expect(isValidShopDomain(normalizeShopDomain('myshop.com')), isFalse);
    });

    test('"-shop.myshopify.com" is invalid', () {
      expect(isValidShopDomain('-shop.myshopify.com'), isFalse);
    });
  });

  group('lengths and code', () {
    test('business name 2 to 60', () {
      expect(isValidBusinessName('a'), isFalse);
      expect(isValidBusinessName(' ab '), isTrue);
      expect(isValidBusinessName('a' * 60), isTrue);
      expect(isValidBusinessName('a' * 61), isFalse);
    });

    test('device name 1 to 30', () {
      expect(isValidDeviceName('  '), isFalse);
      expect(isValidDeviceName('a'), isTrue);
      expect(isValidDeviceName('a' * 30), isTrue);
      expect(isValidDeviceName('a' * 31), isFalse);
    });

    test('wallet label at most 30', () {
      expect(isValidWalletLabel(''), isTrue);
      expect(isValidWalletLabel('a' * 30), isTrue);
      expect(isValidWalletLabel('a' * 31), isFalse);
    });

    test('code: 6 digits, Bangla digits accepted', () {
      expect(isCompleteCode('123456'), isTrue);
      expect(isCompleteCode('১২৩৪৫৬'), isTrue);
      expect(isCompleteCode('12345'), isFalse);
      expect(isCompleteCode('12345a'), isFalse);
      expect(toEnglishDigits('১২৩৪৫৬'), '123456');
    });
  });
}
