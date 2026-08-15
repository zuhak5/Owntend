import 'package:owntend/l10n/app_localizations.dart';

import 'user_facing_errors.dart';

enum AppFailureCode {
  general('general'),
  localDatabaseBusy('local_database_busy'),
  signIn('sign_in'),
  themeUpdate('theme_update'),
  locationUpdate('location_update'),
  notificationSetup('notification_setup'),
  testReminder('test_reminder'),
  photoSave('photo_save'),
  taskUpdate('task_update'),
  backup('backup'),
  undo('undo'),
  cloudInitialization('cloud_initialization'),
  accountDeletion('account_deletion');

  const AppFailureCode(this.wireValue);

  final String wireValue;
}

AppFailureCode appFailureCodeFor(
  Object error, {
  AppFailureCode fallback = AppFailureCode.general,
}) {
  return isLocalDatabaseBusyError(error)
      ? AppFailureCode.localDatabaseBusy
      : fallback;
}

String localizedFailureMessage(AppLocalizations l10n, AppFailureCode code) {
  return switch (code) {
    AppFailureCode.general => l10n.somethingWentWrongPleaseTryAgain,
    AppFailureCode.localDatabaseBusy =>
      l10n.owntendIsFinishingAnotherLocalOperationPleaseTryAgainInAMoment,
    AppFailureCode.signIn => l10n.signInFailedPleaseTryAgain,
    AppFailureCode.themeUpdate => l10n.themeUpdateFailedPleaseTryAgain,
    AppFailureCode.locationUpdate => l10n.locationUpdateFailedPleaseTryAgain,
    AppFailureCode.notificationSetup =>
      l10n.notificationSetupFailedPleaseTryAgain,
    AppFailureCode.testReminder =>
      l10n.theTestReminderCouldNotBeSentPleaseTryAgain,
    AppFailureCode.photoSave => l10n.thePhotoCouldNotBeSavedPleaseTryAgain,
    AppFailureCode.taskUpdate => l10n.theTaskCouldNotBeUpdatedPleaseTryAgain,
    AppFailureCode.backup => l10n.backupFailedPleaseTryAgain,
    AppFailureCode.undo => l10n.undoFailedPleaseTryAgain,
    AppFailureCode.cloudInitialization =>
      l10n.cloudServicesAreUnavailablePleaseTryAgainLater,
    AppFailureCode.accountDeletion => l10n.accountDeletionFailed,
  };
}
