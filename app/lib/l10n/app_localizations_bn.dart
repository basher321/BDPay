// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class AppLocalizationsBn extends AppLocalizations {
  AppLocalizationsBn([String locale = 'bn']) : super(locale);

  @override
  String get appTitle => 'BDPay';

  @override
  String get headerBrand => 'BDPay';

  @override
  String get online => 'অনলাইন';

  @override
  String get offline => 'অফলাইন';

  @override
  String get tabHome => 'হোম';

  @override
  String get tabTransactions => 'লেনদেন';

  @override
  String get tabQueue => 'পাঠানো বাকি';

  @override
  String get tabDevLab => 'পরীক্ষা';

  @override
  String get tabSettings => 'সেটিংস';

  @override
  String get opBkash => 'bKash';

  @override
  String get opNagad => 'Nagad';

  @override
  String get opRocket => 'Rocket';

  @override
  String get opUpay => 'Upay';

  @override
  String get verifyPending => 'যাচাই বাকি';

  @override
  String get verifyVerified => 'পেমেন্ট নিশ্চিত ✓';

  @override
  String get verifyMismatch => 'টাকা মেলেনি';

  @override
  String get verifyRejected => 'বাতিল';

  @override
  String get syncQueued => 'পাঠানো বাকি';

  @override
  String get syncSending => 'পাঠানো হচ্ছে…';

  @override
  String get syncSent => 'পাঠানো হয়েছে';

  @override
  String get syncFailed => 'আবার চেষ্টা হবে';

  @override
  String get kindPayment => 'পেমেন্ট';

  @override
  String get kindReceived => 'টাকা গ্রহণ';

  @override
  String get justNow => 'এইমাত্র';

  @override
  String minutesAgo(int n) {
    return '$n মিনিট আগে';
  }

  @override
  String hoursAgo(int n) {
    return '$n ঘণ্টা আগে';
  }

  @override
  String daysAgo(int n) {
    return '$n দিন আগে';
  }

  @override
  String get noValue => '—';

  @override
  String trxLabel(String trxId) {
    return 'Trx: $trxId';
  }

  @override
  String payerLine(String payer, String kind) {
    return 'প্রেরক: $payer • $kind';
  }

  @override
  String get monitoringOnSubtitle => 'এসএমএস দেখা হচ্ছে';

  @override
  String get monitoringOffSubtitle => 'মনিটরিং বন্ধ — নতুন পেমেন্ট ধরা হবে না';

  @override
  String get serverConnected => 'সার্ভার সংযুক্ত';

  @override
  String get serverDisconnected => 'সার্ভারে সংযোগ নেই';

  @override
  String lastContact(String time) {
    return ' • শেষ সংযোগ $time';
  }

  @override
  String get pingOk => 'সার্ভার সংযুক্ত আছে';

  @override
  String get healthTitle => 'ডিভাইস স্বাস্থ্য';

  @override
  String get healthAllOk => 'সব ঠিক আছে ✓';

  @override
  String healthProblems(int n) {
    return '$n টি সমস্যা';
  }

  @override
  String get fix => 'ঠিক করুন';

  @override
  String get healthSmsTitle => 'এসএমএস পড়ার অনুমতি';

  @override
  String get healthSmsOk => 'দেওয়া আছে';

  @override
  String get healthSmsProblem => 'অনুমতি দিন — না দিলে অ্যাপ কাজ করবে না';

  @override
  String get healthBatteryTitle => 'ব্যাটারি সেভার থেকে বাদ';

  @override
  String get healthBatteryOk => 'ঠিক আছে';

  @override
  String get healthBatteryProblem =>
      'চালু থাকলে ফোন অ্যাপটি বন্ধ করে দিতে পারে';

  @override
  String get healthInternetTitle => 'ইন্টারনেট';

  @override
  String get healthInternetOk => 'সংযুক্ত';

  @override
  String get healthInternetProblem => 'নেই — এসএমএস ফোনে জমা থাকবে';

  @override
  String get healthMonitoringTitle => 'এসএমএস মনিটরিং';

  @override
  String get healthMonitoringOk => 'চালু';

  @override
  String get healthMonitoringProblem => 'বন্ধ আছে';

  @override
  String get healthLastSmsTitle => 'সর্বশেষ এসএমএস';

  @override
  String get healthLastSmsNone => 'এখনো আসেনি';

  @override
  String get todayTotalLabel => 'আজ নিশ্চিত হওয়া মোট টাকা';

  @override
  String get todayTotalCaption => 'শুধু সার্ভার যেগুলো নিশ্চিত করেছে';

  @override
  String get countVerified => 'নিশ্চিত';

  @override
  String get countPending => 'যাচাই বাকি';

  @override
  String get countMismatchRejected => 'মেলেনি / বাতিল';

  @override
  String sendPendingNow(int n) {
    return '⟳ বাকি $n টি এখনই পাঠান';
  }

  @override
  String get allSent => 'সব পাঠানো হয়েছে';

  @override
  String someFailed(int f) {
    return '$f টি পাঠানো যায়নি — পরে আবার চেষ্টা হবে';
  }

  @override
  String get devLabButton => '⚗ এসএমএস পরীক্ষা (ডেভেলপার)';

  @override
  String get operatorsTitle => 'অপারেটর';

  @override
  String operatorCount(int count) {
    return '$count টি';
  }

  @override
  String get operatorOff => 'বন্ধ';

  @override
  String get latestTitle => 'সর্বশেষ লেনদেন';

  @override
  String seeAll(int total) {
    return 'সব দেখুন ($total)';
  }

  @override
  String get latestEmpty => 'এখনো কোনো লেনদেন নেই';

  @override
  String differenceLess(String amount) {
    return '$amount কম';
  }

  @override
  String differenceMore(String amount) {
    return '$amount বেশি';
  }

  @override
  String get searchHint => '🔍 TrxID বা প্রেরকের নম্বর';

  @override
  String get allOperators => 'সব অপারেটর';

  @override
  String get statusAll => 'সব';

  @override
  String get statusVerified => 'নিশ্চিত';

  @override
  String get statusPending => 'যাচাই বাকি';

  @override
  String get statusMismatch => 'মেলেনি';

  @override
  String get statusRejected => 'বাতিল';

  @override
  String reviewBanner(int n) {
    return '$n টি পেমেন্টে টাকা মেলেনি — দেখুন';
  }

  @override
  String resultCount(int n) {
    return '$n টি লেনদেন';
  }

  @override
  String get noResultsTitle => 'কিছু পাওয়া যায়নি';

  @override
  String get noResultsHint => 'ফিল্টার বদলে আবার চেষ্টা করুন';

  @override
  String get detailTrxId => 'TrxID';

  @override
  String get detailPayer => 'প্রেরকের নম্বর';

  @override
  String get detailKind => 'ধরন';

  @override
  String get detailReference => 'রেফারেন্স';

  @override
  String get detailBalance => 'নতুন ব্যালেন্স';

  @override
  String get detailTime => 'সময়';

  @override
  String get copied => 'কপি হয়েছে';

  @override
  String get serverReplyTitle => 'সার্ভারের উত্তর';

  @override
  String get serverReplyState => 'অবস্থা';

  @override
  String get serverReplyCode => 'কোড';

  @override
  String get serverReplyNone => 'এখনো উত্তর আসেনি';

  @override
  String get rawSmsTitle => 'মূল এসএমএস';

  @override
  String get close => 'বন্ধ করুন';

  @override
  String get sendNow => '⟳ এখনই পাঠান';

  @override
  String get reviewNeeded => 'রিভিউ দরকার';

  @override
  String reviewOrder(String orderRef) {
    return 'অর্ডার $orderRef';
  }

  @override
  String get reviewExpected => 'অর্ডারের টাকা';

  @override
  String get reviewSmsAmount => 'এসএমএস-এ টাকা';

  @override
  String get reviewDifference => 'পার্থক্য';

  @override
  String get reviewNoOrder => 'কোনো অর্ডারের সাথে যুক্ত নয়';

  @override
  String get approve => 'অনুমোদন দিন';

  @override
  String get reject => 'বাতিল করুন';

  @override
  String get note => 'নোট (ঐচ্ছিক)';

  @override
  String get no => 'না';

  @override
  String get yesConfirm => 'হ্যাঁ, নিশ্চিত';

  @override
  String get approvedToast => 'অনুমোদন দেওয়া হয়েছে';

  @override
  String get rejectedToast => 'বাতিল করা হয়েছে';

  @override
  String get reviewOffline => 'ইন্টারনেট নেই — পরে চেষ্টা করুন';

  @override
  String get reviewNotAllowed => 'এটি আর রিভিউ করা যাবে না';

  @override
  String get queueInfoSafe =>
      'ইন্টারনেট না থাকলেও এসএমএস ফোনে নিরাপদে জমা থাকে।';

  @override
  String get queueInfoAuto => 'সংযোগ ফিরলে নিজে থেকেই পাঠানো হবে।';

  @override
  String get queueInfoManual => 'অটো পাঠানো বন্ধ আছে — নিচের বোতাম চাপুন।';

  @override
  String get queueInfoNoDuplicate => 'একই লেনদেন দুবার গণনা হবে না।';

  @override
  String queueTitle(int n) {
    return 'পাঠানো বাকি ($n)';
  }

  @override
  String get internetYes => 'ইন্টারনেট আছে';

  @override
  String get internetNo => 'ইন্টারনেট নেই';

  @override
  String get sendAll => '☁ সব পাঠান';

  @override
  String queuePayerLine(String payer, String time) {
    return 'প্রেরক: $payer • $time';
  }

  @override
  String retryFailedLine(int retryCount, String message) {
    return '$retryCount বার চেষ্টা ব্যর্থ • $message';
  }

  @override
  String get stuckWarning => 'বারবার ব্যর্থ — ইন্টারনেট বা সার্ভার চেক করুন';

  @override
  String get staleWarning =>
      '২৪ ঘণ্টার বেশি পুরনো — গ্রাহকের অর্ডার বাতিল হয়ে যেতে পারে';

  @override
  String get details => 'বিস্তারিত';

  @override
  String get sendOne => '⟳ পাঠান';

  @override
  String autoSent(int k) {
    return 'ইন্টারনেট ফিরেছে — $k টি পাঠানো হয়েছে';
  }

  @override
  String get queueEmptyTitle => 'সব পাঠানো হয়েছে!';

  @override
  String get queueEmptyHint => 'কোনো এসএমএস বাকি নেই।';

  @override
  String get accountMerchant => 'মার্চেন্ট';

  @override
  String get accountAgent => 'এজেন্ট';

  @override
  String get simSlot1 => 'সিম ১';

  @override
  String get simSlot2 => 'সিম ২';

  @override
  String get simUnknown => 'জানি না';

  @override
  String get yes => 'হ্যাঁ';

  @override
  String get loginTitle => 'লগইন করুন';

  @override
  String get signupTitle => 'নতুন অ্যাকাউন্ট খুলুন';

  @override
  String get usernameLabel => 'ইউজারনেম';

  @override
  String get passwordLabel => 'পাসওয়ার্ড';

  @override
  String get showPassword => 'পাসওয়ার্ড দেখুন';

  @override
  String get hidePassword => 'পাসওয়ার্ড লুকান';

  @override
  String get loginButton => 'লগইন';

  @override
  String get signupButton => 'অ্যাকাউন্ট খুলুন';

  @override
  String get toSignup => 'নতুন অ্যাকাউন্ট খুলুন';

  @override
  String get toLogin => 'অ্যাকাউন্ট আছে? লগইন করুন';

  @override
  String get forgotPassword => 'পাসওয়ার্ড ভুলে গেছেন?';

  @override
  String get forgotPasswordHelp =>
      'BDPay সাপোর্টে যোগাযোগ করুন। তারা আপনার ইউজারনেমে নতুন পাসওয়ার্ড সেট করে দেবে।';

  @override
  String get usernameRule => 'ইংরেজি ছোট অক্ষর, সংখ্যা বা _ — ৩ থেকে ২০টি';

  @override
  String get errInvalidUsername =>
      'ইউজারনেম: ইংরেজি ছোট অক্ষর, সংখ্যা বা _ — ৩ থেকে ২০টি';

  @override
  String get errWeakPassword => 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের দিন';

  @override
  String get errWrongPassword => 'ইউজারনেম বা পাসওয়ার্ড ভুল';

  @override
  String get errUsernameTaken => 'এই ইউজারনেম আগেই নেওয়া হয়েছে';

  @override
  String get errNotConfirmed =>
      'অ্যাকাউন্ট এখনো চালু হয়নি — সাপোর্টে যোগাযোগ করুন';

  @override
  String get errTooSoon => 'একটু পরে আবার চেষ্টা করুন';

  @override
  String get businessNamePrompt => 'আপনার ব্যবসার নাম';

  @override
  String get startButton => 'শুরু করুন';

  @override
  String get setupTitle => 'সেটআপ বাকি';

  @override
  String get addWalletTitle => 'ওয়ালেট যোগ করুন';

  @override
  String get connectShopify => 'Shopify যুক্ত করুন';

  @override
  String get shopifyTitle => 'Shopify স্টোর';

  @override
  String get shopifyPrompt => 'আপনার Shopify স্টোরের ঠিকানা দিন';

  @override
  String get shopifyHint => 'yourstore.myshopify.com';

  @override
  String get errShopDomain => 'শুধু .myshopify.com ঠিকানা দিন';

  @override
  String get shopifyConnecting => 'যুক্ত হচ্ছে…';

  @override
  String shopifyConnectedAgo(String time) {
    return 'যুক্ত হয়েছে $time';
  }

  @override
  String get shopifyTest => 'সংযোগ পরীক্ষা';

  @override
  String get shopifyTestOk => 'Shopify সংযুক্ত আছে';

  @override
  String get shopifyTestFail => 'সংযোগ পাওয়া যায়নি';

  @override
  String get shopifyDisconnect => 'বিচ্ছিন্ন করুন';

  @override
  String get walletsTitle => 'ওয়ালেট';

  @override
  String walletMeta(String type, String sim) {
    return '$type • $sim';
  }

  @override
  String get addWalletButton => '+ ওয়ালেট যোগ করুন';

  @override
  String get lastWalletConfirm =>
      'কোনো সক্রিয় ওয়ালেট থাকবে না — পেমেন্ট যাচাই বন্ধ হয়ে যাবে। নিশ্চিত?';

  @override
  String get walletNumberLabel => 'ওয়ালেট নম্বর';

  @override
  String get accountTypeLabel => 'অ্যাকাউন্ট টাইপ';

  @override
  String get simLabel => 'সিম';

  @override
  String get walletLabelLabel => 'লেবেল (ঐচ্ছিক)';

  @override
  String get accountTypeNote =>
      'ব্যবসার পেমেন্ট নিতে মার্চেন্ট অ্যাকাউন্ট ব্যবহার করুন। ব্যক্তিগত অ্যাকাউন্ট সমর্থিত নয়।';

  @override
  String get save => 'সংরক্ষণ করুন';

  @override
  String get errWalletNumber => 'সঠিক নম্বর দিন (01XXXXXXXXX)';

  @override
  String get errWalletDuplicate => 'এই নম্বর আগেই যোগ করা আছে';

  @override
  String get errSimTaken => 'এই সিমে এই অপারেটরের আরেকটি ওয়ালেট আছে';

  @override
  String get deviceSectionTitle => 'এই ডিভাইস';

  @override
  String get deviceNameLabel => 'ডিভাইস নাম';

  @override
  String get deviceIdLabel => 'ডিভাইস আইডি';

  @override
  String get autoSendTitle => 'সাথে সাথে পাঠান';

  @override
  String get autoSendHint => 'এসএমএস আসামাত্র সার্ভারে যাবে';

  @override
  String get saveSettings => '💾 সংরক্ষণ করুন';

  @override
  String get settingsSaved => 'সেটিংস সংরক্ষিত হয়েছে';

  @override
  String get smsOperatorsTitle => 'কোন অপারেটরের এসএমএস দেখবে';

  @override
  String get developerTitle => 'ডেভেলপার মোড';

  @override
  String get developerHint => 'পরীক্ষার টুল দেখাবে';

  @override
  String get simulateOffline => 'অফলাইন সিমুলেট';

  @override
  String get accountTitle => 'অ্যাকাউন্ট';

  @override
  String get businessNameLabel => 'ব্যবসার নাম';

  @override
  String get logout => 'লগ আউট';

  @override
  String logoutBlocked(int n) {
    return 'আগে বাকি $n টি এসএমএস পাঠান';
  }

  @override
  String get logoutConfirm => 'লগ আউট করবেন? এই ফোনে পেমেন্ট যাচাই বন্ধ হবে।';

  @override
  String get privacyNote =>
      'এই অ্যাপ শুধু bKash, Nagad, Rocket ও Upay-এর এসএমএস পড়ে। ব্যক্তিগত মেসেজ পড়া বা পাঠানো হয় না।';

  @override
  String appVersionLine(String version) {
    return 'ভার্সন $version';
  }

  @override
  String get keepStored => 'নেওয়া হয়েছে';

  @override
  String get keepDuplicate => 'আগেই নেওয়া হয়েছে (ডুপ্লিকেট)';

  @override
  String get keepMonitoringOff => 'মনিটরিং বন্ধ';

  @override
  String get keepSenderNotTrusted => 'প্রেরক বিশ্বস্ত নয় — নেওয়া হয়নি';

  @override
  String get keepOperatorOff => 'এই অপারেটর বন্ধ';

  @override
  String get keepBlocked => 'OTP/অফার — নেওয়া হয়নি';

  @override
  String get keepNotIncoming => 'টাকা গ্রহণের এসএমএস নয় — নেওয়া হয়নি';

  @override
  String get unknownFormat => 'অজানা ফরম্যাট';

  @override
  String get autoStartTitle => 'অটোস্টার্ট চালু করুন';

  @override
  String get autoStartHint =>
      'ফোনের সেটিং-এ BDPay-এর অটোস্টার্ট ও ব্যাকগ্রাউন্ড চালু রাখুন';

  @override
  String get autoStartForceStop => 'অ্যাপ জোর করে বন্ধ করবেন না';

  @override
  String get openSettings => 'সেটিং খুলুন';

  @override
  String get autoStartDone => 'করেছি';

  @override
  String get labTitle => 'এসএমএস পরীক্ষা (ডেভেলপার)';

  @override
  String get labInfo =>
      'আসল টাকা ছাড়াই পার্সিং, ভুয়া এসএমএস ঠেকানো ও ডুপ্লিকেট চেক পরীক্ষা করুন।';

  @override
  String get labTemplates => 'নমুনা টেমপ্লেট নির্বাচন করুন:';

  @override
  String get tplBkash => 'bKash পেমেন্ট প্রাপ্তি';

  @override
  String get tplNagad => 'Nagad টাকা প্রাপ্তি';

  @override
  String get tplRocket => 'Rocket টাকা প্রাপ্তি';

  @override
  String get tplUpay => 'Upay পেমেন্ট';

  @override
  String get tplBanglaBkash => 'বাংলা bKash মেসেজ';

  @override
  String get tplFake => '⚠ ভুয়া এসএমএস';

  @override
  String get tplOtp => '⚠ OTP';

  @override
  String get tplOutgoing => '⚠ টাকা পাঠানো (outgoing)';

  @override
  String get tplHtml => '⚠ HTML ইনজেকশন';

  @override
  String get labSenderLabel =>
      'এসএমএস প্রেরক হেডার (যেমন: bKash, 16247, NAGAD)';

  @override
  String get labBodyLabel => 'ইনকামিং এসএমএস টেক্সট';

  @override
  String get labParse => 'পার্স করে দেখুন';

  @override
  String get labInject => '⚡ অ্যাপে পাঠান';

  @override
  String get labResultTitle => 'পার্সিং ফলাফল';

  @override
  String get labValid => 'ভ্যালিড এমএফএস';

  @override
  String get labInvalid => 'অকার্যকর';

  @override
  String get labOperator => 'চিহ্নিত অপারেটর';

  @override
  String get labTrxId => 'Transaction ID (TrxID)';

  @override
  String get labAmount => 'টাকার পরিমাণ';

  @override
  String get labPayer => 'প্রেরক মোবাইল';

  @override
  String get labNotFound => 'পাওয়া যায়নি';

  @override
  String get labErrors => 'ত্রুটি';

  @override
  String get parseErrUnknownSender => 'প্রেরক চেনা নয়';

  @override
  String get parseErrNoTrxId => 'TrxID পাওয়া যায়নি';

  @override
  String get parseErrNoAmount => 'টাকার পরিমাণ পাওয়া যায়নি';

  @override
  String get appNotConfigured => 'অ্যাপ কনফিগার করা হয়নি';

  @override
  String get errShopTaken => 'এই স্টোর অন্য একটি BDPay অ্যাকাউন্টে যুক্ত';

  @override
  String get shopifyNotYet => 'এখনো যুক্ত হয়নি — আবার চেষ্টা করুন';

  @override
  String get shopifyReconnectNeeded => 'Shopify-এর সংযোগ শেষ হয়ে গেছে';

  @override
  String get shopifyReconnect => 'আবার যুক্ত করুন';

  @override
  String get shopifyDisconnectHow =>
      'Shopify বিচ্ছিন্ন করতে: Shopify অ্যাডমিন > Apps > BDPay > Uninstall. এরপর নতুন অর্ডার আর যাচাই হবে না।';

  @override
  String get okButton => 'ঠিক আছে';

  @override
  String get shopifyGuideTitle => 'সেটআপ গাইড';

  @override
  String get shopifyGuideStep1 =>
      'BDPay অ্যাপে Shopify যুক্ত করুন (সেটিংস > Shopify স্টোর).';

  @override
  String get shopifyGuideStep2 =>
      'Shopify অ্যাডমিন > Settings > Payments > Manual payment methods > Create custom payment method. নামে অবশ্যই \"BDPay\" শব্দটি রাখুন, যেমন: \"bKash / Nagad (BDPay)\".';

  @override
  String get shopifyGuideStep3 =>
      'Shopify অ্যাডমিন > Settings > Checkout > Customize: Thank you পেজে এবং Order status পেজে \"BDPay pay box\" ব্লক যোগ করে Save করুন.';

  @override
  String get shopifyGuideStep4 => 'স্টোরের মুদ্রা BDT রাখুন.';

  @override
  String get shopifyGuideStep5 =>
      'একটি পরীক্ষামূলক অর্ডার দিয়ে দেখুন \"এখনই পেমেন্ট করুন\" বোতাম দেখা যাচ্ছে কিনা.';

  @override
  String get deviceLimitTitle => 'এই অ্যাকাউন্টে ৩টি ফোন যুক্ত আছে';

  @override
  String get deviceLimitHint =>
      'অন্য একটি ফোন থেকে লগ আউট করে আবার চেষ্টা করুন';

  @override
  String get deviceLimitRetry => 'আবার চেষ্টা করুন';

  @override
  String get deviceDisconnected =>
      'এই ফোন BDPay থেকে বিচ্ছিন্ন — আবার লগইন করুন';

  @override
  String get logoutNeedsInternet => 'লগ আউট করতে ইন্টারনেট দরকার';

  @override
  String rulesVersion(int version) {
    return 'নিয়ম সংস্করণ: $version';
  }

  @override
  String updateAvailable(String version) {
    return 'নতুন ভার্সন $version এসেছে';
  }

  @override
  String get updateDownload => 'ডাউনলোড করুন';

  @override
  String get privacyPolicyLink => 'গোপনীয়তা নীতি';

  @override
  String get termsLink => 'শর্তাবলি';

  @override
  String get connectionsTitle => 'স্টোর / ওয়েবসাইট';

  @override
  String get connectionsEmpty => 'এখনো কোনো ওয়েবসাইট যুক্ত হয়নি';

  @override
  String get addStoreButton => '+ স্টোর যোগ করুন';

  @override
  String get choosePlatformTitle => 'প্ল্যাটফর্ম বেছে নিন';

  @override
  String get platformSearchHint => 'প্ল্যাটফর্ম খুঁজুন';

  @override
  String get platformOther => 'অন্য প্ল্যাটফর্ম';

  @override
  String get platformNoMatch =>
      'কিছু পাওয়া যায়নি — \"অন্য প্ল্যাটফর্ম\" বেছে নিন';

  @override
  String get shopifyUseSection =>
      'Shopify স্টোর নিচের \"Shopify স্টোর\" অংশ থেকে যুক্ত করুন';

  @override
  String get siteNameLabel => 'ওয়েবসাইটের নাম';

  @override
  String get siteUrlLabel => 'ওয়েবসাইটের ঠিকানা';

  @override
  String get siteUrlHint => 'https://yourshop.com';

  @override
  String get connectSiteButton => 'যুক্ত করুন';

  @override
  String get errSiteName => 'নাম ২ থেকে ৬০ অক্ষরের দিন';

  @override
  String get errSiteUrl => 'https:// দিয়ে শুরু হওয়া সঠিক ঠিকানা দিন';

  @override
  String get errSiteDuplicate => 'এই ওয়েবসাইট এই প্ল্যাটফর্মে আগেই যুক্ত আছে';

  @override
  String get siteConnectedTitle => 'যুক্ত হয়েছে';

  @override
  String get apiKeyLabel => 'API কী';

  @override
  String get webhookSecretLabel => 'ওয়েবহুক সিক্রেট';

  @override
  String get keyShownOnce =>
      'এই কী আর দেখানো হবে না — এখনই কপি করে নিরাপদে রাখুন';

  @override
  String get copyButton => 'কপি করুন';

  @override
  String get copiedToast => 'কপি হয়েছে';

  @override
  String get doneButton => 'হয়ে গেছে';

  @override
  String get connStatusActive => 'চালু';

  @override
  String get connStatusDisabled => 'বন্ধ';

  @override
  String get connStatusUninstalled => 'আনইনস্টল';

  @override
  String get keyPrefixLabel => 'কী-এর শুরু';

  @override
  String connConnectedAgo(String time) {
    return 'যুক্ত হয়েছে $time';
  }

  @override
  String get webhookUrlLabel => 'ওয়েবহুক ঠিকানা (ঐচ্ছিক)';

  @override
  String get webhookUrlHint => 'https://yourshop.com/bdpay-webhook';

  @override
  String get saveWebhookButton => 'ওয়েবহুক সংরক্ষণ করুন';

  @override
  String get webhookSaved => 'ওয়েবহুক সংরক্ষিত হয়েছে';

  @override
  String get rotateKeyButton => 'নতুন কী তৈরি করুন';

  @override
  String get rotateKeyConfirm =>
      'নতুন কী তৈরি করলে পুরোনো কী সাথে সাথে বন্ধ হয়ে যাবে। চালিয়ে যাবেন?';

  @override
  String get newKeyTitle => 'নতুন API কী';

  @override
  String get disableConnButton => 'সংযোগ বন্ধ করুন';

  @override
  String get disableConnConfirm =>
      'সংযোগ বন্ধ করলে এই ওয়েবসাইট থেকে নতুন অর্ডার আর আসবে না। আগের লেনদেন থাকবে। চালিয়ে যাবেন?';

  @override
  String get apiAddressLabel => 'API ঠিকানা';

  @override
  String get guideApiStep1 =>
      'API কী আপনার ওয়েবসাইটের সার্ভারে গোপন সেটিং হিসেবে রাখুন। কখনো ব্রাউজারের কোডে বা পাবলিক পেজে রাখবেন না।';

  @override
  String get guideApiStep2 =>
      'অর্ডার হলে সার্ভার থেকে API ঠিকানায় POST পাঠান: orderId, orderRef, amountPoisha (১ টাকা = ১০০ পয়সা, যেমন ৳ 1,250.00 = 125000), currency \"BDT\", returnUrl। হেডার: Authorization: Bearer <API কী>।';

  @override
  String get guideApiStep3 =>
      'উত্তরের payUrl-এ গ্রাহককে পাঠান। সেখানে গ্রাহক bKash / Nagad / Rocket / Upay-এর TrxID দেবে।';

  @override
  String get guideApiStep4 =>
      'পেমেন্ট যাচাই হলে BDPay আপনার ওয়েবহুক ঠিকানায় payment.verified পাঠাবে। X-BDPay-Signature ওয়েবহুক সিক্রেট দিয়ে মিলিয়ে নিন। ওয়েবহুক না থাকলে GET API ঠিকানা/<orderId> দিয়ে অবস্থা দেখুন।';

  @override
  String guideServerPlatform(String platform) {
    return '$platform: কলটি আপনার সার্ভারের কোড থেকে করুন (যেমন প্লাগিন, মডিউল, কন্ট্রোলার বা API রুট)।';
  }

  @override
  String guideBuilderPlatform(String platform) {
    return '$platform: কলটি সাইটের ব্যাকএন্ড বা অটোমেশন ফিচার থেকে করুন (যেমন Wix Velo, Bubble API Connector, HubSpot serverless function, অথবা Zapier / Make)।';
  }

  @override
  String guideBrowserPlatform(String platform) {
    return '$platform ব্রাউজারে চলে — API কী সেখানে রাখবেন না। একটি ছোট সার্ভার (যেমন Node.js বা serverless function) থেকে কল করুন।';
  }
}
