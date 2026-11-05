import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:verifier/data/account_providers.dart';
import 'package:verifier/data/mock/mock_account_data.dart';
import 'package:verifier/data/providers.dart';

/// The shared helper that starts the app signed in (spec 05): the demo merchant with its
/// 4 wallets and a connected store, so the setup card is hidden and earlier screens look as before.
List<Override> signedInOverrides() => [
      mockAccountDataProvider.overrideWith(
        (ref) => MockAccountData.demoSignedIn(
          health: ref.watch(deviceHealthRepositoryProvider),
          clock: () => ref.read(clockProvider),
          storeConnected: true,
        ),
      ),
    ];
