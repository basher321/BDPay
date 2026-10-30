import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import 'transaction_detail_sheet.dart';

/// Opens the detail bottom sheet for one transaction. Used by লেনদেন, হোম and the queue.
Future<void> showTransactionDetail(BuildContext context, String id) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.sf,
    barrierColor: AppColors.scrim,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => TransactionDetailSheet(id: id),
  );
}
