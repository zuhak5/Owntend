library;

import '../monetization.dart';

import 'dart:math' as math;

import '../../../ui/components.dart' as hk_ui;
import '../../../ui/presentation_support.dart';
import 'daily_completion_reward_sheet.dart';
import 'earn_points_flow.dart';

part 'point_shortage_dialog.dart';
part 'wallet_sheet.dart';

String authoritativeRpcRejectionMessage(
  BuildContext context,
  AuthoritativeRpcRejectionException error,
) => switch (error.code) {
  AuthoritativeRpcRejectionCode.invalidPayload =>
    context.l10n.reviewInvalidFields,
  AuthoritativeRpcRejectionCode.unauthenticated =>
    context.l10n.serverSessionExpired,
  AuthoritativeRpcRejectionCode.entityNotFound =>
    context.l10n.authoritativeEntityNoLongerAvailable,
  AuthoritativeRpcRejectionCode.conflict =>
    context.l10n.authoritativeOperationConflict,
  AuthoritativeRpcRejectionCode.walletUnavailable =>
    context.l10n.pointRewardsUnavailable,
};
