import 'package:url_launcher/url_launcher.dart';

/// Opens a link in the phone's browser. The link is never logged (the Shopify one carries a one-time state).
abstract interface class UrlOpener {
  /// false when no app could open it.
  Future<bool> open(Uri url);
}

class UrlLauncherOpener implements UrlOpener {
  const UrlLauncherOpener();

  /// External-application mode only, without canLaunchUrl, so no manifest `<queries>` entry is needed.
  @override
  Future<bool> open(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
