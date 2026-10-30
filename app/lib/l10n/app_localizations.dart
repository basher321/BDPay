import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
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
  static const List<Locale> supportedLocales = <Locale>[Locale('bn')];

  /// No description provided for @appTitle.
  ///
  /// In bn, this message translates to:
  /// **'BDPay SMS Verifier'**
  String get appTitle;

  /// No description provided for @headerBrand.
  ///
  /// In bn, this message translates to:
  /// **'BDPay'**
  String get headerBrand;

  /// No description provided for @headerProduct.
  ///
  /// In bn, this message translates to:
  /// **'SMS Verifier'**
  String get headerProduct;

  /// No description provided for @headerSubtitle.
  ///
  /// In bn, this message translates to:
  /// **'পেমেন্ট যাচাই অ্যাপ'**
  String get headerSubtitle;

  /// No description provided for @online.
  ///
  /// In bn, this message translates to:
  /// **'অনলাইন'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In bn, this message translates to:
  /// **'অফলাইন'**
  String get offline;

  /// No description provided for @tabHome.
  ///
  /// In bn, this message translates to:
  /// **'হোম'**
  String get tabHome;

  /// No description provided for @tabTransactions.
  ///
  /// In bn, this message translates to:
  /// **'লেনদেন'**
  String get tabTransactions;

  /// No description provided for @tabQueue.
  ///
  /// In bn, this message translates to:
  /// **'পাঠানো বাকি'**
  String get tabQueue;

  /// No description provided for @tabDevLab.
  ///
  /// In bn, this message translates to:
  /// **'পরীক্ষা'**
  String get tabDevLab;

  /// No description provided for @tabSettings.
  ///
  /// In bn, this message translates to:
  /// **'সেটিংস'**
  String get tabSettings;

  /// No description provided for @opBkash.
  ///
  /// In bn, this message translates to:
  /// **'bKash'**
  String get opBkash;

  /// No description provided for @opNagad.
  ///
  /// In bn, this message translates to:
  /// **'Nagad'**
  String get opNagad;

  /// No description provided for @opRocket.
  ///
  /// In bn, this message translates to:
  /// **'Rocket'**
  String get opRocket;

  /// No description provided for @opUpay.
  ///
  /// In bn, this message translates to:
  /// **'Upay'**
  String get opUpay;

  /// No description provided for @verifyPending.
  ///
  /// In bn, this message translates to:
  /// **'যাচাই বাকি'**
  String get verifyPending;

  /// No description provided for @verifyVerified.
  ///
  /// In bn, this message translates to:
  /// **'পেমেন্ট নিশ্চিত ✓'**
  String get verifyVerified;

  /// No description provided for @verifyMismatch.
  ///
  /// In bn, this message translates to:
  /// **'টাকা মেলেনি'**
  String get verifyMismatch;

  /// No description provided for @verifyRejected.
  ///
  /// In bn, this message translates to:
  /// **'বাতিল'**
  String get verifyRejected;

  /// No description provided for @syncQueued.
  ///
  /// In bn, this message translates to:
  /// **'পাঠানো বাকি'**
  String get syncQueued;

  /// No description provided for @syncSending.
  ///
  /// In bn, this message translates to:
  /// **'পাঠানো হচ্ছে…'**
  String get syncSending;

  /// No description provided for @syncSent.
  ///
  /// In bn, this message translates to:
  /// **'পাঠানো হয়েছে'**
  String get syncSent;

  /// No description provided for @syncFailed.
  ///
  /// In bn, this message translates to:
  /// **'আবার চেষ্টা হবে'**
  String get syncFailed;

  /// No description provided for @kindPayment.
  ///
  /// In bn, this message translates to:
  /// **'পেমেন্ট'**
  String get kindPayment;

  /// No description provided for @kindReceived.
  ///
  /// In bn, this message translates to:
  /// **'টাকা গ্রহণ'**
  String get kindReceived;

  /// No description provided for @justNow.
  ///
  /// In bn, this message translates to:
  /// **'এইমাত্র'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In bn, this message translates to:
  /// **'{n} মিনিট আগে'**
  String minutesAgo(int n);

  /// No description provided for @hoursAgo.
  ///
  /// In bn, this message translates to:
  /// **'{n} ঘণ্টা আগে'**
  String hoursAgo(int n);

  /// No description provided for @daysAgo.
  ///
  /// In bn, this message translates to:
  /// **'{n} দিন আগে'**
  String daysAgo(int n);

  /// No description provided for @noValue.
  ///
  /// In bn, this message translates to:
  /// **'—'**
  String get noValue;

  /// No description provided for @trxLabel.
  ///
  /// In bn, this message translates to:
  /// **'Trx: {trxId}'**
  String trxLabel(String trxId);

  /// No description provided for @payerLine.
  ///
  /// In bn, this message translates to:
  /// **'প্রেরক: {payer} • {kind}'**
  String payerLine(String payer, String kind);

  /// No description provided for @monitoringOnSubtitle.
  ///
  /// In bn, this message translates to:
  /// **'এসএমএস দেখা হচ্ছে'**
  String get monitoringOnSubtitle;

  /// No description provided for @monitoringOffSubtitle.
  ///
  /// In bn, this message translates to:
  /// **'মনিটরিং বন্ধ — নতুন পেমেন্ট ধরা হবে না'**
  String get monitoringOffSubtitle;

  /// No description provided for @serverConnected.
  ///
  /// In bn, this message translates to:
  /// **'সার্ভার সংযুক্ত'**
  String get serverConnected;

  /// No description provided for @serverDisconnected.
  ///
  /// In bn, this message translates to:
  /// **'সার্ভারে সংযোগ নেই'**
  String get serverDisconnected;

  /// No description provided for @lastContact.
  ///
  /// In bn, this message translates to:
  /// **' • শেষ সংযোগ {time}'**
  String lastContact(String time);

  /// No description provided for @pingOk.
  ///
  /// In bn, this message translates to:
  /// **'সার্ভার সংযুক্ত আছে'**
  String get pingOk;

  /// No description provided for @healthTitle.
  ///
  /// In bn, this message translates to:
  /// **'ডিভাইস স্বাস্থ্য'**
  String get healthTitle;

  /// No description provided for @healthAllOk.
  ///
  /// In bn, this message translates to:
  /// **'সব ঠিক আছে ✓'**
  String get healthAllOk;

  /// No description provided for @healthProblems.
  ///
  /// In bn, this message translates to:
  /// **'{n} টি সমস্যা'**
  String healthProblems(int n);

  /// No description provided for @fix.
  ///
  /// In bn, this message translates to:
  /// **'ঠিক করুন'**
  String get fix;

  /// No description provided for @healthSmsTitle.
  ///
  /// In bn, this message translates to:
  /// **'এসএমএস পড়ার অনুমতি'**
  String get healthSmsTitle;

  /// No description provided for @healthSmsOk.
  ///
  /// In bn, this message translates to:
  /// **'দেওয়া আছে'**
  String get healthSmsOk;

  /// No description provided for @healthSmsProblem.
  ///
  /// In bn, this message translates to:
  /// **'অনুমতি দিন — না দিলে অ্যাপ কাজ করবে না'**
  String get healthSmsProblem;

  /// No description provided for @healthBatteryTitle.
  ///
  /// In bn, this message translates to:
  /// **'ব্যাটারি সেভার থেকে বাদ'**
  String get healthBatteryTitle;

  /// No description provided for @healthBatteryOk.
  ///
  /// In bn, this message translates to:
  /// **'ঠিক আছে'**
  String get healthBatteryOk;

  /// No description provided for @healthBatteryProblem.
  ///
  /// In bn, this message translates to:
  /// **'চালু থাকলে ফোন অ্যাপটি বন্ধ করে দিতে পারে'**
  String get healthBatteryProblem;

  /// No description provided for @healthInternetTitle.
  ///
  /// In bn, this message translates to:
  /// **'ইন্টারনেট'**
  String get healthInternetTitle;

  /// No description provided for @healthInternetOk.
  ///
  /// In bn, this message translates to:
  /// **'সংযুক্ত'**
  String get healthInternetOk;

  /// No description provided for @healthInternetProblem.
  ///
  /// In bn, this message translates to:
  /// **'নেই — এসএমএস ফোনে জমা থাকবে'**
  String get healthInternetProblem;

  /// No description provided for @healthMonitoringTitle.
  ///
  /// In bn, this message translates to:
  /// **'এসএমএস মনিটরিং'**
  String get healthMonitoringTitle;

  /// No description provided for @healthMonitoringOk.
  ///
  /// In bn, this message translates to:
  /// **'চালু'**
  String get healthMonitoringOk;

  /// No description provided for @healthMonitoringProblem.
  ///
  /// In bn, this message translates to:
  /// **'বন্ধ আছে'**
  String get healthMonitoringProblem;

  /// No description provided for @healthLastSmsTitle.
  ///
  /// In bn, this message translates to:
  /// **'সর্বশেষ এসএমএস'**
  String get healthLastSmsTitle;

  /// No description provided for @healthLastSmsNone.
  ///
  /// In bn, this message translates to:
  /// **'এখনো আসেনি'**
  String get healthLastSmsNone;

  /// No description provided for @todayTotalLabel.
  ///
  /// In bn, this message translates to:
  /// **'আজ নিশ্চিত হওয়া মোট টাকা'**
  String get todayTotalLabel;

  /// No description provided for @todayTotalCaption.
  ///
  /// In bn, this message translates to:
  /// **'শুধু সার্ভার যেগুলো নিশ্চিত করেছে'**
  String get todayTotalCaption;

  /// No description provided for @countVerified.
  ///
  /// In bn, this message translates to:
  /// **'নিশ্চিত'**
  String get countVerified;

  /// No description provided for @countPending.
  ///
  /// In bn, this message translates to:
  /// **'যাচাই বাকি'**
  String get countPending;

  /// No description provided for @countMismatchRejected.
  ///
  /// In bn, this message translates to:
  /// **'মেলেনি / বাতিল'**
  String get countMismatchRejected;

  /// No description provided for @sendPendingNow.
  ///
  /// In bn, this message translates to:
  /// **'⟳ বাকি {n} টি এখনই পাঠান'**
  String sendPendingNow(int n);

  /// No description provided for @allSent.
  ///
  /// In bn, this message translates to:
  /// **'সব পাঠানো হয়েছে'**
  String get allSent;

  /// No description provided for @someFailed.
  ///
  /// In bn, this message translates to:
  /// **'{f} টি পাঠানো যায়নি — পরে আবার চেষ্টা হবে'**
  String someFailed(int f);

  /// No description provided for @devLabButton.
  ///
  /// In bn, this message translates to:
  /// **'⚗ এসএমএস পরীক্ষা (ডেভেলপার)'**
  String get devLabButton;

  /// No description provided for @operatorsTitle.
  ///
  /// In bn, this message translates to:
  /// **'অপারেটর'**
  String get operatorsTitle;

  /// No description provided for @operatorCount.
  ///
  /// In bn, this message translates to:
  /// **'{count} টি'**
  String operatorCount(int count);

  /// No description provided for @operatorOff.
  ///
  /// In bn, this message translates to:
  /// **'বন্ধ'**
  String get operatorOff;

  /// No description provided for @latestTitle.
  ///
  /// In bn, this message translates to:
  /// **'সর্বশেষ লেনদেন'**
  String get latestTitle;

  /// No description provided for @seeAll.
  ///
  /// In bn, this message translates to:
  /// **'সব দেখুন ({total})'**
  String seeAll(int total);

  /// No description provided for @latestEmpty.
  ///
  /// In bn, this message translates to:
  /// **'এখনো কোনো লেনদেন নেই'**
  String get latestEmpty;

  /// No description provided for @differenceLess.
  ///
  /// In bn, this message translates to:
  /// **'{amount} কম'**
  String differenceLess(String amount);

  /// No description provided for @differenceMore.
  ///
  /// In bn, this message translates to:
  /// **'{amount} বেশি'**
  String differenceMore(String amount);

  /// No description provided for @searchHint.
  ///
  /// In bn, this message translates to:
  /// **'🔍 TrxID বা প্রেরকের নম্বর'**
  String get searchHint;

  /// No description provided for @allOperators.
  ///
  /// In bn, this message translates to:
  /// **'সব অপারেটর'**
  String get allOperators;

  /// No description provided for @statusAll.
  ///
  /// In bn, this message translates to:
  /// **'সব'**
  String get statusAll;

  /// No description provided for @statusVerified.
  ///
  /// In bn, this message translates to:
  /// **'নিশ্চিত'**
  String get statusVerified;

  /// No description provided for @statusPending.
  ///
  /// In bn, this message translates to:
  /// **'যাচাই বাকি'**
  String get statusPending;

  /// No description provided for @statusMismatch.
  ///
  /// In bn, this message translates to:
  /// **'মেলেনি'**
  String get statusMismatch;

  /// No description provided for @statusRejected.
  ///
  /// In bn, this message translates to:
  /// **'বাতিল'**
  String get statusRejected;

  /// No description provided for @reviewBanner.
  ///
  /// In bn, this message translates to:
  /// **'{n} টি পেমেন্টে টাকা মেলেনি — দেখুন'**
  String reviewBanner(int n);

  /// No description provided for @resultCount.
  ///
  /// In bn, this message translates to:
  /// **'{n} টি লেনদেন'**
  String resultCount(int n);

  /// No description provided for @noResultsTitle.
  ///
  /// In bn, this message translates to:
  /// **'কিছু পাওয়া যায়নি'**
  String get noResultsTitle;

  /// No description provided for @noResultsHint.
  ///
  /// In bn, this message translates to:
  /// **'ফিল্টার বদলে আবার চেষ্টা করুন'**
  String get noResultsHint;

  /// No description provided for @detailTrxId.
  ///
  /// In bn, this message translates to:
  /// **'TrxID'**
  String get detailTrxId;

  /// No description provided for @detailPayer.
  ///
  /// In bn, this message translates to:
  /// **'প্রেরকের নম্বর'**
  String get detailPayer;

  /// No description provided for @detailKind.
  ///
  /// In bn, this message translates to:
  /// **'ধরন'**
  String get detailKind;

  /// No description provided for @detailReference.
  ///
  /// In bn, this message translates to:
  /// **'রেফারেন্স'**
  String get detailReference;

  /// No description provided for @detailBalance.
  ///
  /// In bn, this message translates to:
  /// **'নতুন ব্যালেন্স'**
  String get detailBalance;

  /// No description provided for @detailTime.
  ///
  /// In bn, this message translates to:
  /// **'সময়'**
  String get detailTime;

  /// No description provided for @copied.
  ///
  /// In bn, this message translates to:
  /// **'কপি হয়েছে'**
  String get copied;

  /// No description provided for @serverReplyTitle.
  ///
  /// In bn, this message translates to:
  /// **'সার্ভারের উত্তর'**
  String get serverReplyTitle;

  /// No description provided for @serverReplyState.
  ///
  /// In bn, this message translates to:
  /// **'অবস্থা'**
  String get serverReplyState;

  /// No description provided for @serverReplyCode.
  ///
  /// In bn, this message translates to:
  /// **'কোড'**
  String get serverReplyCode;

  /// No description provided for @serverReplyNone.
  ///
  /// In bn, this message translates to:
  /// **'এখনো উত্তর আসেনি'**
  String get serverReplyNone;

  /// No description provided for @rawSmsTitle.
  ///
  /// In bn, this message translates to:
  /// **'মূল এসএমএস'**
  String get rawSmsTitle;

  /// No description provided for @close.
  ///
  /// In bn, this message translates to:
  /// **'বন্ধ করুন'**
  String get close;

  /// No description provided for @sendNow.
  ///
  /// In bn, this message translates to:
  /// **'⟳ এখনই পাঠান'**
  String get sendNow;

  /// No description provided for @reviewNeeded.
  ///
  /// In bn, this message translates to:
  /// **'রিভিউ দরকার'**
  String get reviewNeeded;

  /// No description provided for @reviewOrder.
  ///
  /// In bn, this message translates to:
  /// **'অর্ডার {orderRef}'**
  String reviewOrder(String orderRef);

  /// No description provided for @reviewExpected.
  ///
  /// In bn, this message translates to:
  /// **'অর্ডারের টাকা'**
  String get reviewExpected;

  /// No description provided for @reviewSmsAmount.
  ///
  /// In bn, this message translates to:
  /// **'এসএমএস-এ টাকা'**
  String get reviewSmsAmount;

  /// No description provided for @reviewDifference.
  ///
  /// In bn, this message translates to:
  /// **'পার্থক্য'**
  String get reviewDifference;

  /// No description provided for @reviewNoOrder.
  ///
  /// In bn, this message translates to:
  /// **'কোনো অর্ডারের সাথে যুক্ত নয়'**
  String get reviewNoOrder;

  /// No description provided for @approve.
  ///
  /// In bn, this message translates to:
  /// **'অনুমোদন দিন'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In bn, this message translates to:
  /// **'বাতিল করুন'**
  String get reject;

  /// No description provided for @note.
  ///
  /// In bn, this message translates to:
  /// **'নোট (ঐচ্ছিক)'**
  String get note;

  /// No description provided for @no.
  ///
  /// In bn, this message translates to:
  /// **'না'**
  String get no;

  /// No description provided for @yesConfirm.
  ///
  /// In bn, this message translates to:
  /// **'হ্যাঁ, নিশ্চিত'**
  String get yesConfirm;

  /// No description provided for @approvedToast.
  ///
  /// In bn, this message translates to:
  /// **'অনুমোদন দেওয়া হয়েছে'**
  String get approvedToast;

  /// No description provided for @rejectedToast.
  ///
  /// In bn, this message translates to:
  /// **'বাতিল করা হয়েছে'**
  String get rejectedToast;

  /// No description provided for @reviewOffline.
  ///
  /// In bn, this message translates to:
  /// **'ইন্টারনেট নেই — পরে চেষ্টা করুন'**
  String get reviewOffline;

  /// No description provided for @reviewNotAllowed.
  ///
  /// In bn, this message translates to:
  /// **'এটি আর রিভিউ করা যাবে না'**
  String get reviewNotAllowed;

  /// No description provided for @queueInfoSafe.
  ///
  /// In bn, this message translates to:
  /// **'ইন্টারনেট না থাকলেও এসএমএস ফোনে নিরাপদে জমা থাকে।'**
  String get queueInfoSafe;

  /// No description provided for @queueInfoAuto.
  ///
  /// In bn, this message translates to:
  /// **'সংযোগ ফিরলে নিজে থেকেই পাঠানো হবে।'**
  String get queueInfoAuto;

  /// No description provided for @queueInfoManual.
  ///
  /// In bn, this message translates to:
  /// **'অটো পাঠানো বন্ধ আছে — নিচের বোতাম চাপুন।'**
  String get queueInfoManual;

  /// No description provided for @queueInfoNoDuplicate.
  ///
  /// In bn, this message translates to:
  /// **'একই লেনদেন দুবার গণনা হবে না।'**
  String get queueInfoNoDuplicate;

  /// No description provided for @queueTitle.
  ///
  /// In bn, this message translates to:
  /// **'পাঠানো বাকি ({n})'**
  String queueTitle(int n);

  /// No description provided for @internetYes.
  ///
  /// In bn, this message translates to:
  /// **'ইন্টারনেট আছে'**
  String get internetYes;

  /// No description provided for @internetNo.
  ///
  /// In bn, this message translates to:
  /// **'ইন্টারনেট নেই'**
  String get internetNo;

  /// No description provided for @sendAll.
  ///
  /// In bn, this message translates to:
  /// **'☁ সব পাঠান'**
  String get sendAll;

  /// No description provided for @queuePayerLine.
  ///
  /// In bn, this message translates to:
  /// **'প্রেরক: {payer} • {time}'**
  String queuePayerLine(String payer, String time);

  /// No description provided for @retryFailedLine.
  ///
  /// In bn, this message translates to:
  /// **'{retryCount} বার চেষ্টা ব্যর্থ • {message}'**
  String retryFailedLine(int retryCount, String message);

  /// No description provided for @stuckWarning.
  ///
  /// In bn, this message translates to:
  /// **'বারবার ব্যর্থ — ইন্টারনেট বা সার্ভার চেক করুন'**
  String get stuckWarning;

  /// No description provided for @staleWarning.
  ///
  /// In bn, this message translates to:
  /// **'২৪ ঘণ্টার বেশি পুরনো — গ্রাহকের অর্ডার বাতিল হয়ে যেতে পারে'**
  String get staleWarning;

  /// No description provided for @details.
  ///
  /// In bn, this message translates to:
  /// **'বিস্তারিত'**
  String get details;

  /// No description provided for @sendOne.
  ///
  /// In bn, this message translates to:
  /// **'⟳ পাঠান'**
  String get sendOne;

  /// No description provided for @autoSent.
  ///
  /// In bn, this message translates to:
  /// **'ইন্টারনেট ফিরেছে — {k} টি পাঠানো হয়েছে'**
  String autoSent(int k);

  /// No description provided for @queueEmptyTitle.
  ///
  /// In bn, this message translates to:
  /// **'সব পাঠানো হয়েছে!'**
  String get queueEmptyTitle;

  /// No description provided for @queueEmptyHint.
  ///
  /// In bn, this message translates to:
  /// **'কোনো এসএমএস বাকি নেই।'**
  String get queueEmptyHint;

  /// No description provided for @accountMerchant.
  ///
  /// In bn, this message translates to:
  /// **'মার্চেন্ট'**
  String get accountMerchant;

  /// No description provided for @accountAgent.
  ///
  /// In bn, this message translates to:
  /// **'এজেন্ট'**
  String get accountAgent;

  /// No description provided for @simSlot1.
  ///
  /// In bn, this message translates to:
  /// **'সিম ১'**
  String get simSlot1;

  /// No description provided for @simSlot2.
  ///
  /// In bn, this message translates to:
  /// **'সিম ২'**
  String get simSlot2;

  /// No description provided for @simUnknown.
  ///
  /// In bn, this message translates to:
  /// **'জানি না'**
  String get simUnknown;

  /// No description provided for @yes.
  ///
  /// In bn, this message translates to:
  /// **'হ্যাঁ'**
  String get yes;

  /// No description provided for @loginEmailPrompt.
  ///
  /// In bn, this message translates to:
  /// **'আপনার ইমেইল দিন'**
  String get loginEmailPrompt;

  /// No description provided for @sendCode.
  ///
  /// In bn, this message translates to:
  /// **'কোড পাঠান'**
  String get sendCode;

  /// No description provided for @errInvalidEmail.
  ///
  /// In bn, this message translates to:
  /// **'সঠিক ইমেইল দিন'**
  String get errInvalidEmail;

  /// No description provided for @errTooSoon.
  ///
  /// In bn, this message translates to:
  /// **'একটু পরে আবার চেষ্টা করুন'**
  String get errTooSoon;

  /// No description provided for @codeSentTo.
  ///
  /// In bn, this message translates to:
  /// **'{email} -এ ৬ সংখ্যার কোড পাঠানো হয়েছে'**
  String codeSentTo(String email);

  /// No description provided for @verifyCode.
  ///
  /// In bn, this message translates to:
  /// **'যাচাই করুন'**
  String get verifyCode;

  /// No description provided for @errWrongCode.
  ///
  /// In bn, this message translates to:
  /// **'কোড ভুল — আবার দেখুন'**
  String get errWrongCode;

  /// No description provided for @resendCode.
  ///
  /// In bn, this message translates to:
  /// **'আবার কোড পাঠান'**
  String get resendCode;

  /// No description provided for @resendIn.
  ///
  /// In bn, this message translates to:
  /// **'{s} সেকেন্ড পরে আবার পাঠানো যাবে'**
  String resendIn(int s);

  /// No description provided for @changeEmail.
  ///
  /// In bn, this message translates to:
  /// **'ইমেইল বদলান'**
  String get changeEmail;

  /// No description provided for @businessNamePrompt.
  ///
  /// In bn, this message translates to:
  /// **'আপনার ব্যবসার নাম'**
  String get businessNamePrompt;

  /// No description provided for @startButton.
  ///
  /// In bn, this message translates to:
  /// **'শুরু করুন'**
  String get startButton;

  /// No description provided for @setupTitle.
  ///
  /// In bn, this message translates to:
  /// **'সেটআপ বাকি'**
  String get setupTitle;

  /// No description provided for @addWalletTitle.
  ///
  /// In bn, this message translates to:
  /// **'ওয়ালেট যোগ করুন'**
  String get addWalletTitle;

  /// No description provided for @connectShopify.
  ///
  /// In bn, this message translates to:
  /// **'Shopify যুক্ত করুন'**
  String get connectShopify;

  /// No description provided for @shopifyTitle.
  ///
  /// In bn, this message translates to:
  /// **'Shopify স্টোর'**
  String get shopifyTitle;

  /// No description provided for @shopifyPrompt.
  ///
  /// In bn, this message translates to:
  /// **'আপনার Shopify স্টোরের ঠিকানা দিন'**
  String get shopifyPrompt;

  /// No description provided for @shopifyHint.
  ///
  /// In bn, this message translates to:
  /// **'yourstore.myshopify.com'**
  String get shopifyHint;

  /// No description provided for @errShopDomain.
  ///
  /// In bn, this message translates to:
  /// **'শুধু .myshopify.com ঠিকানা দিন'**
  String get errShopDomain;

  /// No description provided for @shopifyConnecting.
  ///
  /// In bn, this message translates to:
  /// **'যুক্ত হচ্ছে…'**
  String get shopifyConnecting;

  /// No description provided for @shopifyConnectedAgo.
  ///
  /// In bn, this message translates to:
  /// **'যুক্ত হয়েছে {time}'**
  String shopifyConnectedAgo(String time);

  /// No description provided for @shopifyTest.
  ///
  /// In bn, this message translates to:
  /// **'সংযোগ পরীক্ষা'**
  String get shopifyTest;

  /// No description provided for @shopifyTestOk.
  ///
  /// In bn, this message translates to:
  /// **'Shopify সংযুক্ত আছে'**
  String get shopifyTestOk;

  /// No description provided for @shopifyTestFail.
  ///
  /// In bn, this message translates to:
  /// **'সংযোগ পাওয়া যায়নি'**
  String get shopifyTestFail;

  /// No description provided for @shopifyDisconnect.
  ///
  /// In bn, this message translates to:
  /// **'বিচ্ছিন্ন করুন'**
  String get shopifyDisconnect;

  /// No description provided for @walletsTitle.
  ///
  /// In bn, this message translates to:
  /// **'ওয়ালেট'**
  String get walletsTitle;

  /// No description provided for @walletMeta.
  ///
  /// In bn, this message translates to:
  /// **'{type} • {sim}'**
  String walletMeta(String type, String sim);

  /// No description provided for @addWalletButton.
  ///
  /// In bn, this message translates to:
  /// **'+ ওয়ালেট যোগ করুন'**
  String get addWalletButton;

  /// No description provided for @lastWalletConfirm.
  ///
  /// In bn, this message translates to:
  /// **'কোনো সক্রিয় ওয়ালেট থাকবে না — পেমেন্ট যাচাই বন্ধ হয়ে যাবে। নিশ্চিত?'**
  String get lastWalletConfirm;

  /// No description provided for @walletNumberLabel.
  ///
  /// In bn, this message translates to:
  /// **'ওয়ালেট নম্বর'**
  String get walletNumberLabel;

  /// No description provided for @accountTypeLabel.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাকাউন্ট টাইপ'**
  String get accountTypeLabel;

  /// No description provided for @simLabel.
  ///
  /// In bn, this message translates to:
  /// **'সিম'**
  String get simLabel;

  /// No description provided for @walletLabelLabel.
  ///
  /// In bn, this message translates to:
  /// **'লেবেল (ঐচ্ছিক)'**
  String get walletLabelLabel;

  /// No description provided for @accountTypeNote.
  ///
  /// In bn, this message translates to:
  /// **'ব্যবসার পেমেন্ট নিতে মার্চেন্ট অ্যাকাউন্ট ব্যবহার করুন। ব্যক্তিগত অ্যাকাউন্ট সমর্থিত নয়।'**
  String get accountTypeNote;

  /// No description provided for @save.
  ///
  /// In bn, this message translates to:
  /// **'সংরক্ষণ করুন'**
  String get save;

  /// No description provided for @errWalletNumber.
  ///
  /// In bn, this message translates to:
  /// **'সঠিক নম্বর দিন (01XXXXXXXXX)'**
  String get errWalletNumber;

  /// No description provided for @errWalletDuplicate.
  ///
  /// In bn, this message translates to:
  /// **'এই নম্বর আগেই যোগ করা আছে'**
  String get errWalletDuplicate;

  /// No description provided for @errSimTaken.
  ///
  /// In bn, this message translates to:
  /// **'এই সিমে এই অপারেটরের আরেকটি ওয়ালেট আছে'**
  String get errSimTaken;

  /// No description provided for @deviceSectionTitle.
  ///
  /// In bn, this message translates to:
  /// **'এই ডিভাইস'**
  String get deviceSectionTitle;

  /// No description provided for @deviceNameLabel.
  ///
  /// In bn, this message translates to:
  /// **'ডিভাইস নাম'**
  String get deviceNameLabel;

  /// No description provided for @deviceIdLabel.
  ///
  /// In bn, this message translates to:
  /// **'ডিভাইস আইডি'**
  String get deviceIdLabel;

  /// No description provided for @autoSendTitle.
  ///
  /// In bn, this message translates to:
  /// **'সাথে সাথে পাঠান'**
  String get autoSendTitle;

  /// No description provided for @autoSendHint.
  ///
  /// In bn, this message translates to:
  /// **'এসএমএস আসামাত্র সার্ভারে যাবে'**
  String get autoSendHint;

  /// No description provided for @saveSettings.
  ///
  /// In bn, this message translates to:
  /// **'💾 সংরক্ষণ করুন'**
  String get saveSettings;

  /// No description provided for @settingsSaved.
  ///
  /// In bn, this message translates to:
  /// **'সেটিংস সংরক্ষিত হয়েছে'**
  String get settingsSaved;

  /// No description provided for @smsOperatorsTitle.
  ///
  /// In bn, this message translates to:
  /// **'কোন অপারেটরের এসএমএস দেখবে'**
  String get smsOperatorsTitle;

  /// No description provided for @developerTitle.
  ///
  /// In bn, this message translates to:
  /// **'ডেভেলপার মোড'**
  String get developerTitle;

  /// No description provided for @developerHint.
  ///
  /// In bn, this message translates to:
  /// **'পরীক্ষার টুল দেখাবে'**
  String get developerHint;

  /// No description provided for @simulateOffline.
  ///
  /// In bn, this message translates to:
  /// **'অফলাইন সিমুলেট'**
  String get simulateOffline;

  /// No description provided for @accountTitle.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাকাউন্ট'**
  String get accountTitle;

  /// No description provided for @businessNameLabel.
  ///
  /// In bn, this message translates to:
  /// **'ব্যবসার নাম'**
  String get businessNameLabel;

  /// No description provided for @emailLabel.
  ///
  /// In bn, this message translates to:
  /// **'ইমেইল'**
  String get emailLabel;

  /// No description provided for @logout.
  ///
  /// In bn, this message translates to:
  /// **'লগ আউট'**
  String get logout;

  /// No description provided for @logoutBlocked.
  ///
  /// In bn, this message translates to:
  /// **'আগে বাকি {n} টি এসএমএস পাঠান'**
  String logoutBlocked(int n);

  /// No description provided for @logoutConfirm.
  ///
  /// In bn, this message translates to:
  /// **'লগ আউট করবেন? এই ফোনে পেমেন্ট যাচাই বন্ধ হবে।'**
  String get logoutConfirm;

  /// No description provided for @privacyNote.
  ///
  /// In bn, this message translates to:
  /// **'এই অ্যাপ শুধু bKash, Nagad, Rocket ও Upay-এর এসএমএস পড়ে। ব্যক্তিগত মেসেজ পড়া বা পাঠানো হয় না।'**
  String get privacyNote;

  /// No description provided for @appVersionLine.
  ///
  /// In bn, this message translates to:
  /// **'ভার্সন {version}'**
  String appVersionLine(String version);

  /// No description provided for @keepStored.
  ///
  /// In bn, this message translates to:
  /// **'নেওয়া হয়েছে'**
  String get keepStored;

  /// No description provided for @keepDuplicate.
  ///
  /// In bn, this message translates to:
  /// **'আগেই নেওয়া হয়েছে (ডুপ্লিকেট)'**
  String get keepDuplicate;

  /// No description provided for @keepMonitoringOff.
  ///
  /// In bn, this message translates to:
  /// **'মনিটরিং বন্ধ'**
  String get keepMonitoringOff;

  /// No description provided for @keepSenderNotTrusted.
  ///
  /// In bn, this message translates to:
  /// **'প্রেরক বিশ্বস্ত নয় — নেওয়া হয়নি'**
  String get keepSenderNotTrusted;

  /// No description provided for @keepOperatorOff.
  ///
  /// In bn, this message translates to:
  /// **'এই অপারেটর বন্ধ'**
  String get keepOperatorOff;

  /// No description provided for @keepBlocked.
  ///
  /// In bn, this message translates to:
  /// **'OTP/অফার — নেওয়া হয়নি'**
  String get keepBlocked;

  /// No description provided for @keepNotIncoming.
  ///
  /// In bn, this message translates to:
  /// **'টাকা গ্রহণের এসএমএস নয় — নেওয়া হয়নি'**
  String get keepNotIncoming;

  /// No description provided for @unknownFormat.
  ///
  /// In bn, this message translates to:
  /// **'অজানা ফরম্যাট'**
  String get unknownFormat;

  /// No description provided for @autoStartTitle.
  ///
  /// In bn, this message translates to:
  /// **'অটোস্টার্ট চালু করুন'**
  String get autoStartTitle;

  /// No description provided for @autoStartHint.
  ///
  /// In bn, this message translates to:
  /// **'ফোনের সেটিং-এ BDPay-এর অটোস্টার্ট ও ব্যাকগ্রাউন্ড চালু রাখুন'**
  String get autoStartHint;

  /// No description provided for @autoStartForceStop.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাপ জোর করে বন্ধ করবেন না'**
  String get autoStartForceStop;

  /// No description provided for @openSettings.
  ///
  /// In bn, this message translates to:
  /// **'সেটিং খুলুন'**
  String get openSettings;

  /// No description provided for @autoStartDone.
  ///
  /// In bn, this message translates to:
  /// **'করেছি'**
  String get autoStartDone;

  /// No description provided for @labTitle.
  ///
  /// In bn, this message translates to:
  /// **'এসএমএস পরীক্ষা (ডেভেলপার)'**
  String get labTitle;

  /// No description provided for @labInfo.
  ///
  /// In bn, this message translates to:
  /// **'আসল টাকা ছাড়াই পার্সিং, ভুয়া এসএমএস ঠেকানো ও ডুপ্লিকেট চেক পরীক্ষা করুন।'**
  String get labInfo;

  /// No description provided for @labTemplates.
  ///
  /// In bn, this message translates to:
  /// **'নমুনা টেমপ্লেট নির্বাচন করুন:'**
  String get labTemplates;

  /// No description provided for @tplBkash.
  ///
  /// In bn, this message translates to:
  /// **'bKash পেমেন্ট প্রাপ্তি'**
  String get tplBkash;

  /// No description provided for @tplNagad.
  ///
  /// In bn, this message translates to:
  /// **'Nagad টাকা প্রাপ্তি'**
  String get tplNagad;

  /// No description provided for @tplRocket.
  ///
  /// In bn, this message translates to:
  /// **'Rocket টাকা প্রাপ্তি'**
  String get tplRocket;

  /// No description provided for @tplUpay.
  ///
  /// In bn, this message translates to:
  /// **'Upay পেমেন্ট'**
  String get tplUpay;

  /// No description provided for @tplBanglaBkash.
  ///
  /// In bn, this message translates to:
  /// **'বাংলা bKash মেসেজ'**
  String get tplBanglaBkash;

  /// No description provided for @tplFake.
  ///
  /// In bn, this message translates to:
  /// **'⚠ ভুয়া এসএমএস'**
  String get tplFake;

  /// No description provided for @tplOtp.
  ///
  /// In bn, this message translates to:
  /// **'⚠ OTP'**
  String get tplOtp;

  /// No description provided for @tplOutgoing.
  ///
  /// In bn, this message translates to:
  /// **'⚠ টাকা পাঠানো (outgoing)'**
  String get tplOutgoing;

  /// No description provided for @tplHtml.
  ///
  /// In bn, this message translates to:
  /// **'⚠ HTML ইনজেকশন'**
  String get tplHtml;

  /// No description provided for @labSenderLabel.
  ///
  /// In bn, this message translates to:
  /// **'এসএমএস প্রেরক হেডার (যেমন: bKash, 16247, NAGAD)'**
  String get labSenderLabel;

  /// No description provided for @labBodyLabel.
  ///
  /// In bn, this message translates to:
  /// **'ইনকামিং এসএমএস টেক্সট'**
  String get labBodyLabel;

  /// No description provided for @labParse.
  ///
  /// In bn, this message translates to:
  /// **'পার্স করে দেখুন'**
  String get labParse;

  /// No description provided for @labInject.
  ///
  /// In bn, this message translates to:
  /// **'⚡ অ্যাপে পাঠান'**
  String get labInject;

  /// No description provided for @labResultTitle.
  ///
  /// In bn, this message translates to:
  /// **'পার্সিং ফলাফল'**
  String get labResultTitle;

  /// No description provided for @labValid.
  ///
  /// In bn, this message translates to:
  /// **'ভ্যালিড এমএফএস'**
  String get labValid;

  /// No description provided for @labInvalid.
  ///
  /// In bn, this message translates to:
  /// **'অকার্যকর'**
  String get labInvalid;

  /// No description provided for @labOperator.
  ///
  /// In bn, this message translates to:
  /// **'চিহ্নিত অপারেটর'**
  String get labOperator;

  /// No description provided for @labTrxId.
  ///
  /// In bn, this message translates to:
  /// **'Transaction ID (TrxID)'**
  String get labTrxId;

  /// No description provided for @labAmount.
  ///
  /// In bn, this message translates to:
  /// **'টাকার পরিমাণ'**
  String get labAmount;

  /// No description provided for @labPayer.
  ///
  /// In bn, this message translates to:
  /// **'প্রেরক মোবাইল'**
  String get labPayer;

  /// No description provided for @labNotFound.
  ///
  /// In bn, this message translates to:
  /// **'পাওয়া যায়নি'**
  String get labNotFound;

  /// No description provided for @labErrors.
  ///
  /// In bn, this message translates to:
  /// **'ত্রুটি'**
  String get labErrors;

  /// No description provided for @parseErrUnknownSender.
  ///
  /// In bn, this message translates to:
  /// **'প্রেরক চেনা নয়'**
  String get parseErrUnknownSender;

  /// No description provided for @parseErrNoTrxId.
  ///
  /// In bn, this message translates to:
  /// **'TrxID পাওয়া যায়নি'**
  String get parseErrNoTrxId;

  /// No description provided for @parseErrNoAmount.
  ///
  /// In bn, this message translates to:
  /// **'টাকার পরিমাণ পাওয়া যায়নি'**
  String get parseErrNoAmount;

  /// No description provided for @appNotConfigured.
  ///
  /// In bn, this message translates to:
  /// **'অ্যাপ কনফিগার করা হয়নি'**
  String get appNotConfigured;

  /// No description provided for @errShopTaken.
  ///
  /// In bn, this message translates to:
  /// **'এই স্টোর অন্য একটি BDPay অ্যাকাউন্টে যুক্ত'**
  String get errShopTaken;

  /// No description provided for @shopifyNotYet.
  ///
  /// In bn, this message translates to:
  /// **'এখনো যুক্ত হয়নি — আবার চেষ্টা করুন'**
  String get shopifyNotYet;

  /// No description provided for @shopifyReconnectNeeded.
  ///
  /// In bn, this message translates to:
  /// **'Shopify-এর সংযোগ শেষ হয়ে গেছে'**
  String get shopifyReconnectNeeded;

  /// No description provided for @shopifyReconnect.
  ///
  /// In bn, this message translates to:
  /// **'আবার যুক্ত করুন'**
  String get shopifyReconnect;

  /// No description provided for @shopifyDisconnectHow.
  ///
  /// In bn, this message translates to:
  /// **'Shopify বিচ্ছিন্ন করতে: Shopify অ্যাডমিন > Apps > BDPay > Uninstall. এরপর নতুন অর্ডার আর যাচাই হবে না।'**
  String get shopifyDisconnectHow;

  /// No description provided for @okButton.
  ///
  /// In bn, this message translates to:
  /// **'ঠিক আছে'**
  String get okButton;

  /// No description provided for @shopifyGuideTitle.
  ///
  /// In bn, this message translates to:
  /// **'সেটআপ গাইড'**
  String get shopifyGuideTitle;

  /// No description provided for @shopifyGuideStep1.
  ///
  /// In bn, this message translates to:
  /// **'BDPay অ্যাপে Shopify যুক্ত করুন (সেটিংস > Shopify স্টোর).'**
  String get shopifyGuideStep1;

  /// No description provided for @shopifyGuideStep2.
  ///
  /// In bn, this message translates to:
  /// **'Shopify অ্যাডমিন > Settings > Payments > Manual payment methods > Create custom payment method. নামে অবশ্যই \"BDPay\" শব্দটি রাখুন, যেমন: \"bKash / Nagad (BDPay)\".'**
  String get shopifyGuideStep2;

  /// No description provided for @shopifyGuideStep3.
  ///
  /// In bn, this message translates to:
  /// **'Shopify অ্যাডমিন > Settings > Checkout > Customize: Thank you পেজে এবং Order status পেজে \"BDPay pay box\" ব্লক যোগ করে Save করুন.'**
  String get shopifyGuideStep3;

  /// No description provided for @shopifyGuideStep4.
  ///
  /// In bn, this message translates to:
  /// **'স্টোরের মুদ্রা BDT রাখুন.'**
  String get shopifyGuideStep4;

  /// No description provided for @shopifyGuideStep5.
  ///
  /// In bn, this message translates to:
  /// **'একটি পরীক্ষামূলক অর্ডার দিয়ে দেখুন \"এখনই পেমেন্ট করুন\" বোতাম দেখা যাচ্ছে কিনা.'**
  String get shopifyGuideStep5;

  /// No description provided for @deviceLimitTitle.
  ///
  /// In bn, this message translates to:
  /// **'এই অ্যাকাউন্টে ৩টি ফোন যুক্ত আছে'**
  String get deviceLimitTitle;

  /// No description provided for @deviceLimitHint.
  ///
  /// In bn, this message translates to:
  /// **'অন্য একটি ফোন থেকে লগ আউট করে আবার চেষ্টা করুন'**
  String get deviceLimitHint;

  /// No description provided for @deviceLimitRetry.
  ///
  /// In bn, this message translates to:
  /// **'আবার চেষ্টা করুন'**
  String get deviceLimitRetry;

  /// No description provided for @deviceDisconnected.
  ///
  /// In bn, this message translates to:
  /// **'এই ফোন BDPay থেকে বিচ্ছিন্ন — আবার লগইন করুন'**
  String get deviceDisconnected;

  /// No description provided for @logoutNeedsInternet.
  ///
  /// In bn, this message translates to:
  /// **'লগ আউট করতে ইন্টারনেট দরকার'**
  String get logoutNeedsInternet;

  /// No description provided for @rulesVersion.
  ///
  /// In bn, this message translates to:
  /// **'নিয়ম সংস্করণ: {version}'**
  String rulesVersion(int version);

  /// No description provided for @updateAvailable.
  ///
  /// In bn, this message translates to:
  /// **'নতুন ভার্সন {version} এসেছে'**
  String updateAvailable(String version);

  /// No description provided for @updateDownload.
  ///
  /// In bn, this message translates to:
  /// **'ডাউনলোড করুন'**
  String get updateDownload;

  /// No description provided for @privacyPolicyLink.
  ///
  /// In bn, this message translates to:
  /// **'গোপনীয়তা নীতি'**
  String get privacyPolicyLink;

  /// No description provided for @termsLink.
  ///
  /// In bn, this message translates to:
  /// **'শর্তাবলি'**
  String get termsLink;
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
      <String>['bn'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
