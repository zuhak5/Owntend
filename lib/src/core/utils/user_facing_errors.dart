bool isLocalDatabaseBusyError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('database is locked') ||
      message.contains('database table is locked') ||
      message.contains('sqlite_busy') ||
      message.contains('sqlite_locked');
}

bool looksLikeRawDatabaseError(Object error) {
  final message = error.toString().toLowerCase();
  return isLocalDatabaseBusyError(error) ||
      message.contains('sqliteexception') ||
      message.contains('sqlite error') ||
      message.contains('sql logic error') ||
      RegExp(r'\b(select|insert|update|delete|pragma)\b').hasMatch(message);
}

String userFacingErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (isLocalDatabaseBusyError(error)) {
    return 'Owntend is finishing another local database operation. '
        'Please try again in a moment.';
  }
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  if (message.isEmpty) return fallback;
  if (looksLikeRawDatabaseError(error)) return fallback;
  return message;
}

String syncDiagnosticMessage(Object error) {
  if (isLocalDatabaseBusyError(error)) {
    return 'Local database is busy; sync will retry automatically.';
  }
  if (looksLikeRawDatabaseError(error)) {
    return 'Local database operation failed; no record contents were exported.';
  }
  return userFacingErrorMessage(
    error,
    fallback: 'Sync failed. Please try again.',
  );
}
