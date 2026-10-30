import 'package:flutter/foundation.dart';

import '../account_enums.dart';
import 'merchant.dart';

@immutable
class AuthState {
  const AuthState({required this.status, this.email, this.merchant, this.deviceId});

  static const signedOut = AuthState(status: AuthStatus.signedOut);

  final AuthStatus status;
  final String? email;
  final Merchant? merchant;
  final String? deviceId;

  AuthState copyWith({AuthStatus? status, String? email, Merchant? merchant, String? deviceId}) {
    return AuthState(
      status: status ?? this.status,
      email: email ?? this.email,
      merchant: merchant ?? this.merchant,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}
