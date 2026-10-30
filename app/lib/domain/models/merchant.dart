import 'package:flutter/foundation.dart';

@immutable
class Merchant {
  const Merchant({required this.id, required this.businessName});

  final String id;
  final String businessName;

  Merchant copyWith({String? id, String? businessName}) {
    return Merchant(id: id ?? this.id, businessName: businessName ?? this.businessName);
  }
}
