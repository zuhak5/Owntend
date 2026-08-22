import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @owntend.
  ///
  /// In en, this message translates to:
  /// **'Owntend'**
  String get owntend;

  /// No description provided for @keepEveryHomeSystemUnderControl.
  ///
  /// In en, this message translates to:
  /// **'Keep every home system under control.'**
  String get keepEveryHomeSystemUnderControl;

  /// No description provided for @trackRoomsItemsRecurringCareRemindersAndBackupsFromAPrivateOfflineFirstCommandCe.
  ///
  /// In en, this message translates to:
  /// **'Track rooms, items, recurring care, reminders, and backups from a private offline-first command center.'**
  String
  get trackRoomsItemsRecurringCareRemindersAndBackupsFromAPrivateOfflineFirstCommandCe;

  /// No description provided for @startOwntend.
  ///
  /// In en, this message translates to:
  /// **'Start Owntend'**
  String get startOwntend;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @rooms.
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get rooms;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @tools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tools;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @backupAndRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get backupAndRestore;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @safety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get safety;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addTask.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get addTask;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItem;

  /// No description provided for @addArea.
  ///
  /// In en, this message translates to:
  /// **'Add area'**
  String get addArea;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get addPhoto;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createBackup.
  ///
  /// In en, this message translates to:
  /// **'Create backup'**
  String get createBackup;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @test.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get test;

  /// No description provided for @models.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get models;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @automaticByTimeOfDay.
  ///
  /// In en, this message translates to:
  /// **'Automatic by time of day'**
  String get automaticByTimeOfDay;

  /// No description provided for @manualTheme.
  ///
  /// In en, this message translates to:
  /// **'Manual theme'**
  String get manualTheme;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @shownOnHome.
  ///
  /// In en, this message translates to:
  /// **'Shown on Home'**
  String get shownOnHome;

  /// No description provided for @weatherLocation.
  ///
  /// In en, this message translates to:
  /// **'Weather location'**
  String get weatherLocation;

  /// No description provided for @setACityZipOrCurrentDeviceLocation.
  ///
  /// In en, this message translates to:
  /// **'Set a city, ZIP, or current device location.'**
  String get setACityZipOrCurrentDeviceLocation;

  /// No description provided for @changeAvatar.
  ///
  /// In en, this message translates to:
  /// **'Change avatar'**
  String get changeAvatar;

  /// No description provided for @searchLocation.
  ///
  /// In en, this message translates to:
  /// **'Search location'**
  String get searchLocation;

  /// No description provided for @useDeviceLocation.
  ///
  /// In en, this message translates to:
  /// **'Use device location'**
  String get useDeviceLocation;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @pushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get pushNotifications;

  /// No description provided for @alarmsAndReminders.
  ///
  /// In en, this message translates to:
  /// **'Alarms & reminders'**
  String get alarmsAndReminders;

  /// No description provided for @allowed.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get allowed;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @needsAccess.
  ///
  /// In en, this message translates to:
  /// **'Needs access'**
  String get needsAccess;

  /// No description provided for @limited.
  ///
  /// In en, this message translates to:
  /// **'Limited'**
  String get limited;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @configuredManually.
  ///
  /// In en, this message translates to:
  /// **'Configured manually'**
  String get configuredManually;

  /// No description provided for @approximateTiming.
  ///
  /// In en, this message translates to:
  /// **'Approximate timing'**
  String get approximateTiming;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @maintenanceWeatherAndDigestAlerts.
  ///
  /// In en, this message translates to:
  /// **'Maintenance, weather, and digest alerts'**
  String get maintenanceWeatherAndDigestAlerts;

  /// No description provided for @deviceReminders.
  ///
  /// In en, this message translates to:
  /// **'Device reminders'**
  String get deviceReminders;

  /// No description provided for @scheduledAndroidReminderDelivery.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Android reminder delivery'**
  String get scheduledAndroidReminderDelivery;

  /// No description provided for @preciseReminderAlarms.
  ///
  /// In en, this message translates to:
  /// **'Precise reminder alarms'**
  String get preciseReminderAlarms;

  /// No description provided for @askAndroidForAlarmsAndRemindersAccess.
  ///
  /// In en, this message translates to:
  /// **'Ask Android for Alarms & reminders access'**
  String get askAndroidForAlarmsAndRemindersAccess;

  /// No description provided for @inAppInbox.
  ///
  /// In en, this message translates to:
  /// **'In-app inbox'**
  String get inAppInbox;

  /// No description provided for @unreadTaskWeatherAndDigestUpdates.
  ///
  /// In en, this message translates to:
  /// **'Unread task, weather, and digest updates'**
  String get unreadTaskWeatherAndDigestUpdates;

  /// No description provided for @weatherAlerts.
  ///
  /// In en, this message translates to:
  /// **'Weather alerts'**
  String get weatherAlerts;

  /// No description provided for @outdoorTaskAlertsDuringSevereWeather.
  ///
  /// In en, this message translates to:
  /// **'Outdoor task alerts during severe weather'**
  String get outdoorTaskAlertsDuringSevereWeather;

  /// No description provided for @quietHours.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours'**
  String get quietHours;

  /// No description provided for @quietHoursStart.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours start'**
  String get quietHoursStart;

  /// No description provided for @quietHoursEnd.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours end'**
  String get quietHoursEnd;

  /// No description provided for @criticalRemindersBypass.
  ///
  /// In en, this message translates to:
  /// **'Critical reminders bypass'**
  String get criticalRemindersBypass;

  /// No description provided for @criticalTasksCanStillAlertDuringQuietHours.
  ///
  /// In en, this message translates to:
  /// **'Critical tasks can still alert during quiet hours'**
  String get criticalTasksCanStillAlertDuringQuietHours;

  /// No description provided for @hideLockScreenDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide lock-screen details'**
  String get hideLockScreenDetails;

  /// No description provided for @showGenericReminderTextOutsideTheApp.
  ///
  /// In en, this message translates to:
  /// **'Show generic reminder text outside the app'**
  String get showGenericReminderTextOutsideTheApp;

  /// No description provided for @dailyDigest.
  ///
  /// In en, this message translates to:
  /// **'Daily digest'**
  String get dailyDigest;

  /// No description provided for @groupedReminderSummary.
  ///
  /// In en, this message translates to:
  /// **'Grouped reminder summary'**
  String get groupedReminderSummary;

  /// No description provided for @defaultSnooze.
  ///
  /// In en, this message translates to:
  /// **'Default snooze'**
  String get defaultSnooze;

  /// No description provided for @maxRemindersPerDay.
  ///
  /// In en, this message translates to:
  /// **'Max reminders per day'**
  String get maxRemindersPerDay;

  /// No description provided for @reminderTime.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get reminderTime;

  /// No description provided for @digestTime.
  ///
  /// In en, this message translates to:
  /// **'Digest time'**
  String get digestTime;

  /// No description provided for @sendTest.
  ///
  /// In en, this message translates to:
  /// **'Send test'**
  String get sendTest;

  /// No description provided for @saveReminderSettings.
  ///
  /// In en, this message translates to:
  /// **'Save reminder settings'**
  String get saveReminderSettings;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @deviceLocationIsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Device location is unavailable.'**
  String get deviceLocationIsUnavailable;

  /// No description provided for @weatherLocationUpdated.
  ///
  /// In en, this message translates to:
  /// **'Weather location updated.'**
  String get weatherLocationUpdated;

  /// No description provided for @notificationSettingsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Notification settings updated.'**
  String get notificationSettingsUpdated;

  /// No description provided for @homeLocation.
  ///
  /// In en, this message translates to:
  /// **'Home Location'**
  String get homeLocation;

  /// No description provided for @searchForALocation.
  ///
  /// In en, this message translates to:
  /// **'Search for a location'**
  String get searchForALocation;

  /// No description provided for @todaySTasks.
  ///
  /// In en, this message translates to:
  /// **'Today\'\'s tasks'**
  String get todaySTasks;

  /// No description provided for @homeReadiness.
  ///
  /// In en, this message translates to:
  /// **'Home readiness'**
  String get homeReadiness;

  /// No description provided for @maintenancePlan.
  ///
  /// In en, this message translates to:
  /// **'Maintenance plan'**
  String get maintenancePlan;

  /// No description provided for @openAccount.
  ///
  /// In en, this message translates to:
  /// **'Open account'**
  String get openAccount;

  /// No description provided for @editAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get editAccount;

  /// No description provided for @sessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Session title'**
  String get sessionTitle;

  /// No description provided for @sessionNotes.
  ///
  /// In en, this message translates to:
  /// **'Session notes'**
  String get sessionNotes;

  /// No description provided for @archiveSession.
  ///
  /// In en, this message translates to:
  /// **'Archive session'**
  String get archiveSession;

  /// No description provided for @feels.
  ///
  /// In en, this message translates to:
  /// **'Feels'**
  String get feels;

  /// No description provided for @humidity.
  ///
  /// In en, this message translates to:
  /// **'Humidity'**
  String get humidity;

  /// No description provided for @wind.
  ///
  /// In en, this message translates to:
  /// **'Wind'**
  String get wind;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @next7.
  ///
  /// In en, this message translates to:
  /// **'Next 7'**
  String get next7;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcoming;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueToday;

  /// No description provided for @noAreasYet.
  ///
  /// In en, this message translates to:
  /// **'No areas yet'**
  String get noAreasYet;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// No description provided for @searchRooms.
  ///
  /// In en, this message translates to:
  /// **'Search rooms'**
  String get searchRooms;

  /// No description provided for @firstFloor.
  ///
  /// In en, this message translates to:
  /// **'First Floor'**
  String get firstFloor;

  /// No description provided for @secondFloor.
  ///
  /// In en, this message translates to:
  /// **'Second Floor'**
  String get secondFloor;

  /// No description provided for @outdoor.
  ///
  /// In en, this message translates to:
  /// **'Outdoor'**
  String get outdoor;

  /// No description provided for @indoor.
  ///
  /// In en, this message translates to:
  /// **'Indoor'**
  String get indoor;

  /// No description provided for @outdoorZone.
  ///
  /// In en, this message translates to:
  /// **'Outdoor zone'**
  String get outdoorZone;

  /// No description provided for @kitchen.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get kitchen;

  /// No description provided for @garden.
  ///
  /// In en, this message translates to:
  /// **'Garden'**
  String get garden;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @areaActions.
  ///
  /// In en, this message translates to:
  /// **'Area actions'**
  String get areaActions;

  /// No description provided for @editArea.
  ///
  /// In en, this message translates to:
  /// **'Edit area'**
  String get editArea;

  /// No description provided for @moveEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get moveEarlier;

  /// No description provided for @moveLater.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get moveLater;

  /// No description provided for @deleteArea.
  ///
  /// In en, this message translates to:
  /// **'Delete area'**
  String get deleteArea;

  /// No description provided for @roomActions.
  ///
  /// In en, this message translates to:
  /// **'Room actions'**
  String get roomActions;

  /// No description provided for @editRoom.
  ///
  /// In en, this message translates to:
  /// **'Edit room'**
  String get editRoom;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @deleteRoom.
  ///
  /// In en, this message translates to:
  /// **'Delete room'**
  String get deleteRoom;

  /// No description provided for @moveRoomToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move room to Trash'**
  String get moveRoomToTrash;

  /// No description provided for @room.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get room;

  /// No description provided for @noItemsInThisRoom.
  ///
  /// In en, this message translates to:
  /// **'No items in this room'**
  String get noItemsInThisRoom;

  /// No description provided for @item.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get item;

  /// No description provided for @task.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get task;

  /// No description provided for @taskNotFound.
  ///
  /// In en, this message translates to:
  /// **'Task not found.'**
  String get taskNotFound;

  /// No description provided for @itemNotFound.
  ///
  /// In en, this message translates to:
  /// **'Item not found.'**
  String get itemNotFound;

  /// No description provided for @roomNotFound.
  ///
  /// In en, this message translates to:
  /// **'Room not found.'**
  String get roomNotFound;

  /// No description provided for @discardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes?'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes that will be lost if you leave now.'**
  String get discardChangesMessage;

  /// No description provided for @discardChangesAction.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardChangesAction;

  /// No description provided for @keepEditingAction.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditingAction;

  /// No description provided for @completeTask.
  ///
  /// In en, this message translates to:
  /// **'Complete task'**
  String get completeTask;

  /// No description provided for @taskActions.
  ///
  /// In en, this message translates to:
  /// **'Task actions'**
  String get taskActions;

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTask;

  /// No description provided for @editPlan.
  ///
  /// In en, this message translates to:
  /// **'Edit plan'**
  String get editPlan;

  /// No description provided for @snooze.
  ///
  /// In en, this message translates to:
  /// **'Snooze'**
  String get snooze;

  /// No description provided for @deleteTask.
  ///
  /// In en, this message translates to:
  /// **'Delete task'**
  String get deleteTask;

  /// No description provided for @deleteItem.
  ///
  /// In en, this message translates to:
  /// **'Delete item'**
  String get deleteItem;

  /// No description provided for @moveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get moveToTrash;

  /// No description provided for @moveTaskToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move task to Trash'**
  String get moveTaskToTrash;

  /// No description provided for @moveItemToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move item to Trash'**
  String get moveItemToTrash;

  /// No description provided for @moveAreaToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move area to Trash'**
  String get moveAreaToTrash;

  /// No description provided for @nextDue.
  ///
  /// In en, this message translates to:
  /// **'Next due'**
  String get nextDue;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @instructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get instructions;

  /// No description provided for @openItem.
  ///
  /// In en, this message translates to:
  /// **'Open item'**
  String get openItem;

  /// No description provided for @timeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get timeline;

  /// No description provided for @completionHistoryForThisTask.
  ///
  /// In en, this message translates to:
  /// **'Completion history for this task'**
  String get completionHistoryForThisTask;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @placement.
  ///
  /// In en, this message translates to:
  /// **'Placement'**
  String get placement;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @purchased.
  ///
  /// In en, this message translates to:
  /// **'Purchased'**
  String get purchased;

  /// No description provided for @brand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get brand;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @consumable.
  ///
  /// In en, this message translates to:
  /// **'Consumable'**
  String get consumable;

  /// No description provided for @species.
  ///
  /// In en, this message translates to:
  /// **'Species'**
  String get species;

  /// No description provided for @feeding.
  ///
  /// In en, this message translates to:
  /// **'Feeding'**
  String get feeding;

  /// No description provided for @watering.
  ///
  /// In en, this message translates to:
  /// **'Watering'**
  String get watering;

  /// No description provided for @safetyType.
  ///
  /// In en, this message translates to:
  /// **'Safety type'**
  String get safetyType;

  /// No description provided for @testInterval.
  ///
  /// In en, this message translates to:
  /// **'Test interval'**
  String get testInterval;

  /// No description provided for @noTimelineYet.
  ///
  /// In en, this message translates to:
  /// **'No timeline yet'**
  String get noTimelineYet;

  /// No description provided for @photoActions.
  ///
  /// In en, this message translates to:
  /// **'Photo actions'**
  String get photoActions;

  /// No description provided for @setPrimary.
  ///
  /// In en, this message translates to:
  /// **'Set primary'**
  String get setPrimary;

  /// No description provided for @noTasksDueToday.
  ///
  /// In en, this message translates to:
  /// **'No tasks due today'**
  String get noTasksDueToday;

  /// No description provided for @noOverdueTasks.
  ///
  /// In en, this message translates to:
  /// **'No overdue tasks'**
  String get noOverdueTasks;

  /// No description provided for @noTasksInTheNext7Days.
  ///
  /// In en, this message translates to:
  /// **'No tasks in the next 7 days'**
  String get noTasksInTheNext7Days;

  /// No description provided for @noTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks'**
  String get noTasks;

  /// No description provided for @viewUpcomingTasks.
  ///
  /// In en, this message translates to:
  /// **'View upcoming tasks'**
  String get viewUpcomingTasks;

  /// No description provided for @viewNext7Days.
  ///
  /// In en, this message translates to:
  /// **'View next 7 days'**
  String get viewNext7Days;

  /// No description provided for @newTasks.
  ///
  /// In en, this message translates to:
  /// **'New tasks'**
  String get newTasks;

  /// No description provided for @alreadyExisting.
  ///
  /// In en, this message translates to:
  /// **'Already existing'**
  String get alreadyExisting;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newLabel;

  /// No description provided for @existingUpdated.
  ///
  /// In en, this message translates to:
  /// **'Existing - updated'**
  String get existingUpdated;

  /// No description provided for @noTasksOnThisDay.
  ///
  /// In en, this message translates to:
  /// **'No tasks on this day'**
  String get noTasksOnThisDay;

  /// No description provided for @localDataBackupsAndExportVisibility.
  ///
  /// In en, this message translates to:
  /// **'Local data, backups, and export visibility'**
  String get localDataBackupsAndExportVisibility;

  /// No description provided for @inventoryAndMaintenanceHistoryExports.
  ///
  /// In en, this message translates to:
  /// **'Inventory and maintenance history exports'**
  String get inventoryAndMaintenanceHistoryExports;

  /// No description provided for @completionTrendsAndTaskDistribution.
  ///
  /// In en, this message translates to:
  /// **'Completion trends and task distribution'**
  String get completionTrendsAndTaskDistribution;

  /// No description provided for @exportOrRestoreZipBackups.
  ///
  /// In en, this message translates to:
  /// **'Export or restore ZIP backups'**
  String get exportOrRestoreZipBackups;

  /// No description provided for @completeTaskTitleCase.
  ///
  /// In en, this message translates to:
  /// **'Complete Task'**
  String get completeTaskTitleCase;

  /// No description provided for @areaName.
  ///
  /// In en, this message translates to:
  /// **'Area name'**
  String get areaName;

  /// No description provided for @areaType.
  ///
  /// In en, this message translates to:
  /// **'Area type'**
  String get areaType;

  /// No description provided for @addRoom.
  ///
  /// In en, this message translates to:
  /// **'Add room'**
  String get addRoom;

  /// No description provided for @editItem.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get editItem;

  /// No description provided for @basic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get basic;

  /// No description provided for @itemName.
  ///
  /// In en, this message translates to:
  /// **'Item name *'**
  String get itemName;

  /// No description provided for @itemType.
  ///
  /// In en, this message translates to:
  /// **'Item type'**
  String get itemType;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @roomOrZone.
  ///
  /// In en, this message translates to:
  /// **'Room or zone'**
  String get roomOrZone;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @shelfCornerBalconyKennelArea.
  ///
  /// In en, this message translates to:
  /// **'Shelf, corner, balcony, kennel area...'**
  String get shelfCornerBalconyKennelArea;

  /// No description provided for @commaSeparated.
  ///
  /// In en, this message translates to:
  /// **'comma, separated'**
  String get commaSeparated;

  /// No description provided for @deviceDetails.
  ///
  /// In en, this message translates to:
  /// **'Device details'**
  String get deviceDetails;

  /// No description provided for @serialNumber.
  ///
  /// In en, this message translates to:
  /// **'Serial number'**
  String get serialNumber;

  /// No description provided for @powerSource.
  ///
  /// In en, this message translates to:
  /// **'Power source'**
  String get powerSource;

  /// No description provided for @manualUrl.
  ///
  /// In en, this message translates to:
  /// **'Manual URL'**
  String get manualUrl;

  /// No description provided for @filterBatteriesCartridges.
  ///
  /// In en, this message translates to:
  /// **'Filter, batteries, cartridges...'**
  String get filterBatteriesCartridges;

  /// No description provided for @petDetails.
  ///
  /// In en, this message translates to:
  /// **'Pet details'**
  String get petDetails;

  /// No description provided for @petType.
  ///
  /// In en, this message translates to:
  /// **'Pet Type'**
  String get petType;

  /// No description provided for @fishType.
  ///
  /// In en, this message translates to:
  /// **'Fish Type'**
  String get fishType;

  /// No description provided for @breed.
  ///
  /// In en, this message translates to:
  /// **'Breed'**
  String get breed;

  /// No description provided for @microchipId.
  ///
  /// In en, this message translates to:
  /// **'Microchip ID'**
  String get microchipId;

  /// No description provided for @vetName.
  ///
  /// In en, this message translates to:
  /// **'Vet name'**
  String get vetName;

  /// No description provided for @vetPhone.
  ///
  /// In en, this message translates to:
  /// **'Vet phone'**
  String get vetPhone;

  /// No description provided for @feedingNotes.
  ///
  /// In en, this message translates to:
  /// **'Feeding notes'**
  String get feedingNotes;

  /// No description provided for @medicalNotes.
  ///
  /// In en, this message translates to:
  /// **'Medical notes'**
  String get medicalNotes;

  /// No description provided for @plantDetails.
  ///
  /// In en, this message translates to:
  /// **'Plant details'**
  String get plantDetails;

  /// No description provided for @sunlight.
  ///
  /// In en, this message translates to:
  /// **'Sunlight'**
  String get sunlight;

  /// No description provided for @wateringInterval.
  ///
  /// In en, this message translates to:
  /// **'Watering interval'**
  String get wateringInterval;

  /// No description provided for @potSize.
  ///
  /// In en, this message translates to:
  /// **'Pot size'**
  String get potSize;

  /// No description provided for @toxicityNotes.
  ///
  /// In en, this message translates to:
  /// **'Toxicity notes'**
  String get toxicityNotes;

  /// No description provided for @safetyDetails.
  ///
  /// In en, this message translates to:
  /// **'Safety details'**
  String get safetyDetails;

  /// No description provided for @batteryType.
  ///
  /// In en, this message translates to:
  /// **'Battery type'**
  String get batteryType;

  /// No description provided for @changeItemType.
  ///
  /// In en, this message translates to:
  /// **'Change item type?'**
  String get changeItemType;

  /// No description provided for @createAnItemFirst.
  ///
  /// In en, this message translates to:
  /// **'Create an item first'**
  String get createAnItemFirst;

  /// No description provided for @taskTitle.
  ///
  /// In en, this message translates to:
  /// **'Task title'**
  String get taskTitle;

  /// No description provided for @every.
  ///
  /// In en, this message translates to:
  /// **'Every'**
  String get every;

  /// No description provided for @unit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unit;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @createAndAddAnother.
  ///
  /// In en, this message translates to:
  /// **'Create & add another'**
  String get createAndAddAnother;

  /// No description provided for @taskCreated.
  ///
  /// In en, this message translates to:
  /// **'Task created.'**
  String get taskCreated;

  /// No description provided for @deviceOrAppliance.
  ///
  /// In en, this message translates to:
  /// **'Device or appliance'**
  String get deviceOrAppliance;

  /// No description provided for @pet.
  ///
  /// In en, this message translates to:
  /// **'Pet'**
  String get pet;

  /// No description provided for @plant.
  ///
  /// In en, this message translates to:
  /// **'Plant'**
  String get plant;

  /// No description provided for @safetyItem.
  ///
  /// In en, this message translates to:
  /// **'Safety item'**
  String get safetyItem;

  /// No description provided for @generalItem.
  ///
  /// In en, this message translates to:
  /// **'General item'**
  String get generalItem;

  /// No description provided for @devicesAndAppliances.
  ///
  /// In en, this message translates to:
  /// **'Devices & Appliances'**
  String get devicesAndAppliances;

  /// No description provided for @pets.
  ///
  /// In en, this message translates to:
  /// **'Pets'**
  String get pets;

  /// No description provided for @plants.
  ///
  /// In en, this message translates to:
  /// **'Plants'**
  String get plants;

  /// No description provided for @safetyItems.
  ///
  /// In en, this message translates to:
  /// **'Safety Items'**
  String get safetyItems;

  /// No description provided for @generalItems.
  ///
  /// In en, this message translates to:
  /// **'General Items'**
  String get generalItems;

  /// No description provided for @mains.
  ///
  /// In en, this message translates to:
  /// **'Mains'**
  String get mains;

  /// No description provided for @battery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get battery;

  /// No description provided for @solar.
  ///
  /// In en, this message translates to:
  /// **'Solar'**
  String get solar;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @lowLight.
  ///
  /// In en, this message translates to:
  /// **'Low light'**
  String get lowLight;

  /// No description provided for @mediumLight.
  ///
  /// In en, this message translates to:
  /// **'Medium light'**
  String get mediumLight;

  /// No description provided for @brightIndirect.
  ///
  /// In en, this message translates to:
  /// **'Bright indirect'**
  String get brightIndirect;

  /// No description provided for @fullSun.
  ///
  /// In en, this message translates to:
  /// **'Full sun'**
  String get fullSun;

  /// No description provided for @routine.
  ///
  /// In en, this message translates to:
  /// **'Routine'**
  String get routine;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @critical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get critical;

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get hours;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get days;

  /// No description provided for @weeks.
  ///
  /// In en, this message translates to:
  /// **'Weeks'**
  String get weeks;

  /// No description provided for @months.
  ///
  /// In en, this message translates to:
  /// **'Months'**
  String get months;

  /// No description provided for @years.
  ///
  /// In en, this message translates to:
  /// **'Years'**
  String get years;

  /// No description provided for @dog.
  ///
  /// In en, this message translates to:
  /// **'Dog'**
  String get dog;

  /// No description provided for @cat.
  ///
  /// In en, this message translates to:
  /// **'Cat'**
  String get cat;

  /// No description provided for @fish.
  ///
  /// In en, this message translates to:
  /// **'Fish'**
  String get fish;

  /// No description provided for @bird.
  ///
  /// In en, this message translates to:
  /// **'Bird'**
  String get bird;

  /// No description provided for @rabbit.
  ///
  /// In en, this message translates to:
  /// **'Rabbit'**
  String get rabbit;

  /// No description provided for @reptile.
  ///
  /// In en, this message translates to:
  /// **'Reptile'**
  String get reptile;

  /// No description provided for @smallMammal.
  ///
  /// In en, this message translates to:
  /// **'Small mammal'**
  String get smallMammal;

  /// No description provided for @goldfish.
  ///
  /// In en, this message translates to:
  /// **'Goldfish'**
  String get goldfish;

  /// No description provided for @betta.
  ///
  /// In en, this message translates to:
  /// **'Betta'**
  String get betta;

  /// No description provided for @guppy.
  ///
  /// In en, this message translates to:
  /// **'Guppy'**
  String get guppy;

  /// No description provided for @tetra.
  ///
  /// In en, this message translates to:
  /// **'Tetra'**
  String get tetra;

  /// No description provided for @molly.
  ///
  /// In en, this message translates to:
  /// **'Molly'**
  String get molly;

  /// No description provided for @platy.
  ///
  /// In en, this message translates to:
  /// **'Platy'**
  String get platy;

  /// No description provided for @koi.
  ///
  /// In en, this message translates to:
  /// **'Koi'**
  String get koi;

  /// No description provided for @shareLatestBackup.
  ///
  /// In en, this message translates to:
  /// **'Share latest backup'**
  String get shareLatestBackup;

  /// No description provided for @automaticLocalBackups.
  ///
  /// In en, this message translates to:
  /// **'Automatic local backups'**
  String get automaticLocalBackups;

  /// No description provided for @chooseBackupZip.
  ///
  /// In en, this message translates to:
  /// **'Choose backup ZIP'**
  String get chooseBackupZip;

  /// No description provided for @restoreThisBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore this backup?'**
  String get restoreThisBackup;

  /// No description provided for @restoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get restoreBackup;

  /// No description provided for @restoreThisBackup2.
  ///
  /// In en, this message translates to:
  /// **'Restore this backup'**
  String get restoreThisBackup2;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @message30Minutes.
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get message30Minutes;

  /// No description provided for @message1Hour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get message1Hour;

  /// No description provided for @message3Hours.
  ///
  /// In en, this message translates to:
  /// **'3 hours'**
  String get message3Hours;

  /// No description provided for @customDateAndTime.
  ///
  /// In en, this message translates to:
  /// **'Custom date and time'**
  String get customDateAndTime;

  /// No description provided for @thisTaskWasAlreadyUpdated.
  ///
  /// In en, this message translates to:
  /// **'This task was already updated.'**
  String get thisTaskWasAlreadyUpdated;

  /// No description provided for @taskCompleted.
  ///
  /// In en, this message translates to:
  /// **'Task completed.'**
  String get taskCompleted;

  /// No description provided for @completionUndone.
  ///
  /// In en, this message translates to:
  /// **'Completion undone.'**
  String get completionUndone;

  /// No description provided for @deleteTask2.
  ///
  /// In en, this message translates to:
  /// **'Delete task?'**
  String get deleteTask2;

  /// No description provided for @deleteItem2.
  ///
  /// In en, this message translates to:
  /// **'Delete item?'**
  String get deleteItem2;

  /// No description provided for @deleteRoom2.
  ///
  /// In en, this message translates to:
  /// **'Delete room?'**
  String get deleteRoom2;

  /// No description provided for @deleteArea2.
  ///
  /// In en, this message translates to:
  /// **'Delete area?'**
  String get deleteArea2;

  /// No description provided for @releaseToDelete.
  ///
  /// In en, this message translates to:
  /// **'Release to delete'**
  String get releaseToDelete;

  /// No description provided for @swipeLeft.
  ///
  /// In en, this message translates to:
  /// **'Swipe left'**
  String get swipeLeft;

  /// No description provided for @swipeToMoveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Swipe to move to Trash'**
  String get swipeToMoveToTrash;

  /// No description provided for @releaseToMoveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Release to move to Trash'**
  String get releaseToMoveToTrash;

  /// No description provided for @notEnoughDataYet.
  ///
  /// In en, this message translates to:
  /// **'Not enough data yet'**
  String get notEnoughDataYet;

  /// No description provided for @completeMoreTasksToSeeMonthlyTrends.
  ///
  /// In en, this message translates to:
  /// **'Complete more tasks to see monthly trends.'**
  String get completeMoreTasksToSeeMonthlyTrends;

  /// No description provided for @noTaskDistribution.
  ///
  /// In en, this message translates to:
  /// **'No task distribution'**
  String get noTaskDistribution;

  /// No description provided for @scheduledPlansWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Scheduled plans will appear here.'**
  String get scheduledPlansWillAppearHere;

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// No description provided for @nextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// No description provided for @hour.
  ///
  /// In en, this message translates to:
  /// **'hour'**
  String get hour;

  /// No description provided for @hours2.
  ///
  /// In en, this message translates to:
  /// **'hours'**
  String get hours2;

  /// No description provided for @day.
  ///
  /// In en, this message translates to:
  /// **'day'**
  String get day;

  /// No description provided for @days2.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get days2;

  /// No description provided for @week.
  ///
  /// In en, this message translates to:
  /// **'week'**
  String get week;

  /// No description provided for @weeks2.
  ///
  /// In en, this message translates to:
  /// **'weeks'**
  String get weeks2;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'month'**
  String get month;

  /// No description provided for @months2.
  ///
  /// In en, this message translates to:
  /// **'months'**
  String get months2;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'year'**
  String get year;

  /// No description provided for @years2.
  ///
  /// In en, this message translates to:
  /// **'years'**
  String get years2;

  /// No description provided for @recurrenceEveryOne.
  ///
  /// In en, this message translates to:
  /// **'Every {unit}'**
  String recurrenceEveryOne(String unit);

  /// No description provided for @recurrenceEveryMany.
  ///
  /// In en, this message translates to:
  /// **'Every {count} {unit}'**
  String recurrenceEveryMany(int count, String unit);

  /// No description provided for @statusOverdueBy.
  ///
  /// In en, this message translates to:
  /// **'Overdue by {duration}'**
  String statusOverdueBy(String duration);

  /// No description provided for @statusDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String statusDueDate(String date);

  /// No description provided for @statusDueIn.
  ///
  /// In en, this message translates to:
  /// **'Due in {duration}'**
  String statusDueIn(String duration);

  /// No description provided for @durationDay.
  ///
  /// In en, this message translates to:
  /// **'{count} day'**
  String durationDay(int count);

  /// No description provided for @durationDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String durationDays(int count);

  /// No description provided for @durationMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String durationMinutesShort(int count);

  /// No description provided for @durationHoursMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String durationHoursMinutesShort(int hours, int minutes);

  /// No description provided for @taskUpdateCadence.
  ///
  /// In en, this message translates to:
  /// **'Cadence: {from} -> {to}'**
  String taskUpdateCadence(String from, String to);

  /// No description provided for @searchZones.
  ///
  /// In en, this message translates to:
  /// **'Search zones'**
  String get searchZones;

  /// No description provided for @cityOrZip.
  ///
  /// In en, this message translates to:
  /// **'City or ZIP'**
  String get cityOrZip;

  /// No description provided for @completionNotes.
  ///
  /// In en, this message translates to:
  /// **'Completion notes'**
  String get completionNotes;

  /// No description provided for @whatChangedWhatWasReplacedOrWhatNeedsFollowUp.
  ///
  /// In en, this message translates to:
  /// **'What changed, what was replaced, or what needs follow-up?'**
  String get whatChangedWhatWasReplacedOrWhatNeedsFollowUp;

  /// No description provided for @zoneName.
  ///
  /// In en, this message translates to:
  /// **'Zone name *'**
  String get zoneName;

  /// No description provided for @roomName.
  ///
  /// In en, this message translates to:
  /// **'Room name *'**
  String get roomName;

  /// No description provided for @zoneType.
  ///
  /// In en, this message translates to:
  /// **'Zone type'**
  String get zoneType;

  /// No description provided for @roomType.
  ///
  /// In en, this message translates to:
  /// **'Room type'**
  String get roomType;

  /// No description provided for @area.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get area;

  /// No description provided for @purchaseDate.
  ///
  /// In en, this message translates to:
  /// **'Purchase date'**
  String get purchaseDate;

  /// No description provided for @warrantyDate.
  ///
  /// In en, this message translates to:
  /// **'Warranty date'**
  String get warrantyDate;

  /// No description provided for @birthDate.
  ///
  /// In en, this message translates to:
  /// **'Birth date'**
  String get birthDate;

  /// No description provided for @lastRepotted.
  ///
  /// In en, this message translates to:
  /// **'Last repotted'**
  String get lastRepotted;

  /// No description provided for @installedDate.
  ///
  /// In en, this message translates to:
  /// **'Installed date'**
  String get installedDate;

  /// No description provided for @expirationDate.
  ///
  /// In en, this message translates to:
  /// **'Expiration date'**
  String get expirationDate;

  /// No description provided for @cleaning.
  ///
  /// In en, this message translates to:
  /// **'Cleaning'**
  String get cleaning;

  /// No description provided for @noExtraDetailsYet.
  ///
  /// In en, this message translates to:
  /// **'No extra details yet.'**
  String get noExtraDetailsYet;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @savedOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device'**
  String get savedOnThisDevice;

  /// No description provided for @cloudBackupUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup unavailable'**
  String get cloudBackupUnavailable;

  /// No description provided for @waitingForInternet.
  ///
  /// In en, this message translates to:
  /// **'Waiting for internet'**
  String get waitingForInternet;

  /// No description provided for @worksOffline.
  ///
  /// In en, this message translates to:
  /// **'Works offline'**
  String get worksOffline;

  /// No description provided for @backedUpPrivately.
  ///
  /// In en, this message translates to:
  /// **'Backed up privately'**
  String get backedUpPrivately;

  /// No description provided for @setUpCloudBackup.
  ///
  /// In en, this message translates to:
  /// **'Set up cloud backup'**
  String get setUpCloudBackup;

  /// No description provided for @cloudBackup.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup'**
  String get cloudBackup;

  /// No description provided for @recovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery'**
  String get recovery;

  /// No description provided for @welcomeToOwntend.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Owntend'**
  String get welcomeToOwntend;

  /// No description provided for @chooseHowYouWouldLikeToContinue.
  ///
  /// In en, this message translates to:
  /// **'Choose how you would like to continue.'**
  String get chooseHowYouWouldLikeToContinue;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @resumeCloudBackup.
  ///
  /// In en, this message translates to:
  /// **'Resume cloud backup'**
  String get resumeCloudBackup;

  /// No description provided for @pauseCloudBackup.
  ///
  /// In en, this message translates to:
  /// **'Pause cloud backup'**
  String get pauseCloudBackup;

  /// No description provided for @advancedSyncDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Advanced Sync Diagnostics'**
  String get advancedSyncDiagnostics;

  /// No description provided for @signOutOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Sign out on this device'**
  String get signOutOnThisDevice;

  /// No description provided for @unlinkLocalData.
  ///
  /// In en, this message translates to:
  /// **'Unlink local data'**
  String get unlinkLocalData;

  /// No description provided for @deleteCloudAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete cloud account'**
  String get deleteCloudAccount;

  /// No description provided for @protectedWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Protected with Google'**
  String get protectedWithGoogle;

  /// No description provided for @protectedAccount.
  ///
  /// In en, this message translates to:
  /// **'Protected account'**
  String get protectedAccount;

  /// No description provided for @accountAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Account already exists'**
  String get accountAlreadyExists;

  /// No description provided for @exportBackup.
  ///
  /// In en, this message translates to:
  /// **'Export Backup'**
  String get exportBackup;

  /// No description provided for @useExistingAccount.
  ///
  /// In en, this message translates to:
  /// **'Use existing account'**
  String get useExistingAccount;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @migrationState.
  ///
  /// In en, this message translates to:
  /// **'Migration state'**
  String get migrationState;

  /// No description provided for @pendingDataOperations.
  ///
  /// In en, this message translates to:
  /// **'Pending data operations'**
  String get pendingDataOperations;

  /// No description provided for @pendingMediaCleanup.
  ///
  /// In en, this message translates to:
  /// **'Pending media cleanup'**
  String get pendingMediaCleanup;

  /// No description provided for @clockSkewConflicts.
  ///
  /// In en, this message translates to:
  /// **'Clock-skew conflicts'**
  String get clockSkewConflicts;

  /// No description provided for @realtime.
  ///
  /// In en, this message translates to:
  /// **'Realtime'**
  String get realtime;

  /// No description provided for @lastAttempt.
  ///
  /// In en, this message translates to:
  /// **'Last attempt'**
  String get lastAttempt;

  /// No description provided for @lastSuccess.
  ///
  /// In en, this message translates to:
  /// **'Last success'**
  String get lastSuccess;

  /// No description provided for @lastFailure.
  ///
  /// In en, this message translates to:
  /// **'Last failure'**
  String get lastFailure;

  /// No description provided for @nextRetry.
  ///
  /// In en, this message translates to:
  /// **'Next retry'**
  String get nextRetry;

  /// No description provided for @backgroundResult.
  ///
  /// In en, this message translates to:
  /// **'Background result'**
  String get backgroundResult;

  /// No description provided for @blockedReason.
  ///
  /// In en, this message translates to:
  /// **'Blocked reason'**
  String get blockedReason;

  /// No description provided for @technicalLastError.
  ///
  /// In en, this message translates to:
  /// **'Technical last error'**
  String get technicalLastError;

  /// No description provided for @retryIncrementalSync.
  ///
  /// In en, this message translates to:
  /// **'Retry incremental sync'**
  String get retryIncrementalSync;

  /// No description provided for @fullReconciliation.
  ///
  /// In en, this message translates to:
  /// **'Full reconciliation'**
  String get fullReconciliation;

  /// No description provided for @exportDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Export diagnostics'**
  String get exportDiagnostics;

  /// No description provided for @diagnosticExportDisclosure.
  ///
  /// In en, this message translates to:
  /// **'This bundle contains only Owntend events and redacted technical metadata. It does not include full system logs, account emails, tokens, device serials, coordinates, or media paths.'**
  String get diagnosticExportDisclosure;

  /// No description provided for @exportingDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Preparing private diagnostics…'**
  String get exportingDiagnostics;

  /// No description provided for @owntendDiagnosticsShareText.
  ///
  /// In en, this message translates to:
  /// **'Owntend privacy-safe diagnostics'**
  String get owntendDiagnosticsShareText;

  /// No description provided for @diagnosticExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics could not be exported.'**
  String get diagnosticExportFailed;

  /// No description provided for @notRecorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get notRecorded;

  /// No description provided for @removeAvatar.
  ///
  /// In en, this message translates to:
  /// **'Remove avatar'**
  String get removeAvatar;

  /// No description provided for @avatarRemovalFailed.
  ///
  /// In en, this message translates to:
  /// **'Avatar removal failed'**
  String get avatarRemovalFailed;

  /// No description provided for @restoreLocallyAndPauseCloudBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore locally and pause cloud backup'**
  String get restoreLocallyAndPauseCloudBackup;

  /// No description provided for @restoreAndUpdateCloudBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore and update cloud backup'**
  String get restoreAndUpdateCloudBackup;

  /// No description provided for @lastSaved.
  ///
  /// In en, this message translates to:
  /// **'Last saved'**
  String get lastSaved;

  /// No description provided for @offlineChangesAreSavedOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Offline — changes are saved on this device.'**
  String get offlineChangesAreSavedOnThisDevice;

  /// No description provided for @needsAttentionOpenAdvancedSyncDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Needs attention. Open Advanced Sync Diagnostics.'**
  String get needsAttentionOpenAdvancedSyncDiagnostics;

  /// No description provided for @backingUpChanges.
  ///
  /// In en, this message translates to:
  /// **'Backing up changes…'**
  String get backingUpChanges;

  /// No description provided for @cloudBackupComplete.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup complete.'**
  String get cloudBackupComplete;

  /// No description provided for @savedOnThisDeviceCloudBackupIsPaused.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device. Cloud backup is paused.'**
  String get savedOnThisDeviceCloudBackupIsPaused;

  /// No description provided for @offlineSafe.
  ///
  /// In en, this message translates to:
  /// **'Offline-safe'**
  String get offlineSafe;

  /// No description provided for @needsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get needsAttention;

  /// No description provided for @backingUp.
  ///
  /// In en, this message translates to:
  /// **'Backing up'**
  String get backingUp;

  /// No description provided for @backupComplete.
  ///
  /// In en, this message translates to:
  /// **'Backup complete'**
  String get backupComplete;

  /// No description provided for @yourTasks.
  ///
  /// In en, this message translates to:
  /// **'Your Tasks,'**
  String get yourTasks;

  /// No description provided for @allInSync.
  ///
  /// In en, this message translates to:
  /// **'All in Sync'**
  String get allInSync;

  /// No description provided for @organizeTasksRoutinesAndRemindersAcrossAllYourDevicesAnytimeAnywhere.
  ///
  /// In en, this message translates to:
  /// **'Organize tasks, routines, and reminders across all your devices, anytime, anywhere.'**
  String
  get organizeTasksRoutinesAndRemindersAcrossAllYourDevicesAnytimeAnywhere;

  /// No description provided for @anyDevice.
  ///
  /// In en, this message translates to:
  /// **'Any Device'**
  String get anyDevice;

  /// No description provided for @accessTasksAnywhere.
  ///
  /// In en, this message translates to:
  /// **'Access tasks anywhere'**
  String get accessTasksAnywhere;

  /// No description provided for @smartRoutines.
  ///
  /// In en, this message translates to:
  /// **'Smart Routines'**
  String get smartRoutines;

  /// No description provided for @buildHabitsThatLast.
  ///
  /// In en, this message translates to:
  /// **'Build habits that last'**
  String get buildHabitsThatLast;

  /// No description provided for @progressInsights.
  ///
  /// In en, this message translates to:
  /// **'Progress Insights'**
  String get progressInsights;

  /// No description provided for @stayMotivated.
  ///
  /// In en, this message translates to:
  /// **'Stay motivated'**
  String get stayMotivated;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light mode'**
  String get lightMode;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @englishUs.
  ///
  /// In en, this message translates to:
  /// **'English (US)'**
  String get englishUs;

  /// No description provided for @securelyBringingBackYourTasksRoutinesAndReminders.
  ///
  /// In en, this message translates to:
  /// **'Securely bringing back your tasks, routines, and reminders.'**
  String get securelyBringingBackYourTasksRoutinesAndReminders;

  /// No description provided for @findingYourBackup.
  ///
  /// In en, this message translates to:
  /// **'Finding your backup'**
  String get findingYourBackup;

  /// No description provided for @restoringTasks.
  ///
  /// In en, this message translates to:
  /// **'Restoring tasks'**
  String get restoringTasks;

  /// No description provided for @restoringRoutines.
  ///
  /// In en, this message translates to:
  /// **'Restoring routines'**
  String get restoringRoutines;

  /// No description provided for @restoringReminders.
  ///
  /// In en, this message translates to:
  /// **'Restoring reminders'**
  String get restoringReminders;

  /// No description provided for @finalizingOwntend.
  ///
  /// In en, this message translates to:
  /// **'Finalizing Owntend'**
  String get finalizingOwntend;

  /// No description provided for @yourFlowIsReady.
  ///
  /// In en, this message translates to:
  /// **'Your flow is ready'**
  String get yourFlowIsReady;

  /// No description provided for @tipYourTasksStayAvailableEvenWhenYouAreOffline.
  ///
  /// In en, this message translates to:
  /// **'Tip — Your tasks stay available even when you are offline.'**
  String get tipYourTasksStayAvailableEvenWhenYouAreOffline;

  /// No description provided for @yourTasksRoutinesAndRemindersRestoreInDependencyOrder.
  ///
  /// In en, this message translates to:
  /// **'Your tasks, routines, and reminders restore in dependency order.'**
  String get yourTasksRoutinesAndRemindersRestoreInDependencyOrder;

  /// No description provided for @otherSynchronizedDevices.
  ///
  /// In en, this message translates to:
  /// **'Other synchronized devices'**
  String get otherSynchronizedDevices;

  /// No description provided for @deviceDetailsRemainSecurelySynchronized.
  ///
  /// In en, this message translates to:
  /// **'Device details remain securely synchronized.'**
  String get deviceDetailsRemainSecurelySynchronized;

  /// No description provided for @itemsPhotosLocalDatabaseRecordsBackupsAndHistoryStayOnThisDeviceUnlessYouExportA.
  ///
  /// In en, this message translates to:
  /// **'Items, photos, local database records, backups, and history stay on this device unless you export a backup or enable cloud sync.'**
  String
  get itemsPhotosLocalDatabaseRecordsBackupsAndHistoryStayOnThisDeviceUnlessYouExportA;

  /// No description provided for @structuredExportsAreAvailableNowBrandedPdfPacketsArePlannedForALaterRelease.
  ///
  /// In en, this message translates to:
  /// **'Structured exports are available now. Branded PDF packets are planned for a later release.'**
  String
  get structuredExportsAreAvailableNowBrandedPdfPacketsArePlannedForALaterRelease;

  /// No description provided for @tasksItemsHistoryTimelineStreaksStatisticsDataSettingsNotificationPreferencesPho.
  ///
  /// In en, this message translates to:
  /// **'Tasks, items, history, timeline, streaks, statistics data, settings, notification preferences, photos, and profile media are included.'**
  String
  get tasksItemsHistoryTimelineStreaksStatisticsDataSettingsNotificationPreferencesPho;

  /// No description provided for @keepRestorationVisible.
  ///
  /// In en, this message translates to:
  /// **'Keep restoration visible?'**
  String get keepRestorationVisible;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @checkConnection.
  ///
  /// In en, this message translates to:
  /// **'Check connection'**
  String get checkConnection;

  /// No description provided for @continueOffline.
  ///
  /// In en, this message translates to:
  /// **'Continue offline'**
  String get continueOffline;

  /// No description provided for @addZone.
  ///
  /// In en, this message translates to:
  /// **'Add zone'**
  String get addZone;

  /// No description provided for @appliances.
  ///
  /// In en, this message translates to:
  /// **'Appliances'**
  String get appliances;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @taskDisabled.
  ///
  /// In en, this message translates to:
  /// **'Task disabled'**
  String get taskDisabled;

  /// No description provided for @enableTask.
  ///
  /// In en, this message translates to:
  /// **'Enable task'**
  String get enableTask;

  /// No description provided for @disableTask.
  ///
  /// In en, this message translates to:
  /// **'Disable task'**
  String get disableTask;

  /// No description provided for @completedToday.
  ///
  /// In en, this message translates to:
  /// **'Completed today'**
  String get completedToday;

  /// No description provided for @dueNow.
  ///
  /// In en, this message translates to:
  /// **'Due now'**
  String get dueNow;

  /// No description provided for @nextValue.
  ///
  /// In en, this message translates to:
  /// **'Next: {value}'**
  String nextValue(String value);

  /// No description provided for @roomCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 room} other{{count} rooms}}'**
  String roomCount(int count);

  /// No description provided for @zoneCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 zone} other{{count} zones}}'**
  String zoneCount(int count);

  /// No description provided for @calendarDaySummary.
  ///
  /// In en, this message translates to:
  /// **'{today, select, true{{date}, {count, plural, =0{no tasks due, today} =1{1 task due, today} other{{count} tasks due, today}}} other{{date}, {count, plural, =0{no tasks due} =1{1 task due} other{{count} tasks due}}}}'**
  String calendarDaySummary(String today, String date, int count);

  /// No description provided for @searchOwntend.
  ///
  /// In en, this message translates to:
  /// **'Search Owntend'**
  String get searchOwntend;

  /// No description provided for @searchShort.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get searchShort;

  /// No description provided for @searchRoomsItems.
  ///
  /// In en, this message translates to:
  /// **'Search rooms, items…'**
  String get searchRoomsItems;

  /// No description provided for @itemActions.
  ///
  /// In en, this message translates to:
  /// **'Item actions'**
  String get itemActions;

  /// No description provided for @searchRoomsItemsTasksNotes.
  ///
  /// In en, this message translates to:
  /// **'Search rooms, items, tasks, notes'**
  String get searchRoomsItemsTasksNotes;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @deleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get deleteForever;

  /// No description provided for @emptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get emptyTrash;

  /// No description provided for @emptyTrashConfirmationTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash?'**
  String get emptyTrashConfirmationTitle;

  /// No description provided for @emptyTrashConfirmationMessage.
  ///
  /// In en, this message translates to:
  /// **'All items in Trash will be permanently deleted. This action cannot be undone.'**
  String get emptyTrashConfirmationMessage;

  /// No description provided for @trashEmptied.
  ///
  /// In en, this message translates to:
  /// **'Trash emptied.'**
  String get trashEmptied;

  /// No description provided for @emptyTrashAction.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get emptyTrashAction;

  /// No description provided for @trash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// No description provided for @inbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get inbox;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAll;

  /// No description provided for @taskIsNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'Task is no longer available.'**
  String get taskIsNoLongerAvailable;

  /// No description provided for @notificationActions.
  ///
  /// In en, this message translates to:
  /// **'Notification actions'**
  String get notificationActions;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @markRead.
  ///
  /// In en, this message translates to:
  /// **'Mark read'**
  String get markRead;

  /// No description provided for @fishBreedOrType.
  ///
  /// In en, this message translates to:
  /// **'Fish breed or type'**
  String get fishBreedOrType;

  /// No description provided for @taskType.
  ///
  /// In en, this message translates to:
  /// **'Task type'**
  String get taskType;

  /// No description provided for @inspectionCleaningFeeding.
  ///
  /// In en, this message translates to:
  /// **'Inspection, cleaning, feeding...'**
  String get inspectionCleaningFeeding;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location label'**
  String get locationLabel;

  /// No description provided for @topShelfLeftCabinet.
  ///
  /// In en, this message translates to:
  /// **'Top shelf, left cabinet...'**
  String get topShelfLeftCabinet;

  /// No description provided for @estMinutes.
  ///
  /// In en, this message translates to:
  /// **'Est. minutes'**
  String get estMinutes;

  /// No description provided for @use1OrMore.
  ///
  /// In en, this message translates to:
  /// **'Use 1 or more'**
  String get use1OrMore;

  /// No description provided for @remindDaysBefore.
  ///
  /// In en, this message translates to:
  /// **'Remind days before'**
  String get remindDaysBefore;

  /// No description provided for @use0OrMore.
  ///
  /// In en, this message translates to:
  /// **'Use 0 or more'**
  String get use0OrMore;

  /// No description provided for @requiredMaterials.
  ///
  /// In en, this message translates to:
  /// **'Required materials'**
  String get requiredMaterials;

  /// No description provided for @commaSeparated2.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated'**
  String get commaSeparated2;

  /// No description provided for @reminderNote.
  ///
  /// In en, this message translates to:
  /// **'Reminder note'**
  String get reminderNote;

  /// No description provided for @optionalContextForNotifications.
  ///
  /// In en, this message translates to:
  /// **'Optional context for notifications'**
  String get optionalContextForNotifications;

  /// No description provided for @photoSaved.
  ///
  /// In en, this message translates to:
  /// **'Photo saved.'**
  String get photoSaved;

  /// No description provided for @enableThisTaskBeforeSnoozingIt.
  ///
  /// In en, this message translates to:
  /// **'Enable this task before snoozing it.'**
  String get enableThisTaskBeforeSnoozingIt;

  /// No description provided for @taskRestored.
  ///
  /// In en, this message translates to:
  /// **'Task restored.'**
  String get taskRestored;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @includeRelatedTasks.
  ///
  /// In en, this message translates to:
  /// **'Include related tasks'**
  String get includeRelatedTasks;

  /// No description provided for @includePhotos.
  ///
  /// In en, this message translates to:
  /// **'Include photos'**
  String get includePhotos;

  /// No description provided for @nicknameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Nickname updated.'**
  String get nicknameUpdated;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @taskMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'Task moved to Trash.'**
  String get taskMovedToTrash;

  /// No description provided for @themeUpdateFailedError.
  ///
  /// In en, this message translates to:
  /// **'Theme update failed: {error}'**
  String themeUpdateFailedError(String error);

  /// No description provided for @locationUpdateFailedError.
  ///
  /// In en, this message translates to:
  /// **'Location update failed: {error}'**
  String locationUpdateFailedError(String error);

  /// No description provided for @notificationSetupFailedError.
  ///
  /// In en, this message translates to:
  /// **'Notification setup failed: {error}'**
  String notificationSetupFailedError(String error);

  /// No description provided for @testReminderFailedError.
  ///
  /// In en, this message translates to:
  /// **'Test reminder failed: {error}'**
  String testReminderFailedError(String error);

  /// No description provided for @undoFailedError.
  ///
  /// In en, this message translates to:
  /// **'Undo failed: {error}'**
  String undoFailedError(String error);

  /// No description provided for @backupCreatedFilename.
  ///
  /// In en, this message translates to:
  /// **'Backup created: {fileName}'**
  String backupCreatedFilename(String fileName);

  /// No description provided for @photoSaveFailedError.
  ///
  /// In en, this message translates to:
  /// **'Photo save failed: {error}'**
  String photoSaveFailedError(String error);

  /// No description provided for @snoozeTask.
  ///
  /// In en, this message translates to:
  /// **'Snooze {task}'**
  String snoozeTask(String task);

  /// No description provided for @tomorrowAtTime.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow at {time}'**
  String tomorrowAtTime(String time);

  /// No description provided for @taskSkippedForThisCycle.
  ///
  /// In en, this message translates to:
  /// **'{task} skipped for this cycle.'**
  String taskSkippedForThisCycle(String task);

  /// No description provided for @couldNotSkipTaskError.
  ///
  /// In en, this message translates to:
  /// **'Could not skip task: {error}'**
  String couldNotSkipTaskError(String error);

  /// No description provided for @couldNotPostponeTaskError.
  ///
  /// In en, this message translates to:
  /// **'Could not postpone task: {error}'**
  String couldNotPostponeTaskError(String error);

  /// No description provided for @couldNotCompleteTaskError.
  ///
  /// In en, this message translates to:
  /// **'Could not complete task: {error}'**
  String couldNotCompleteTaskError(String error);

  /// No description provided for @couldNotMoveTaskToTrashError.
  ///
  /// In en, this message translates to:
  /// **'Could not move task to Trash: {error}'**
  String couldNotMoveTaskToTrashError(String error);

  /// No description provided for @taskMovedButRemindersCouldNotRefreshError.
  ///
  /// In en, this message translates to:
  /// **'Task moved, but reminders could not refresh: {error}'**
  String taskMovedButRemindersCouldNotRefreshError(String error);

  /// No description provided for @nameMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'{name} moved to Trash.'**
  String nameMovedToTrash(String name);

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String dueDate(String date);

  /// No description provided for @failedError.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String failedError(String error);

  /// No description provided for @nicknameUpdateFailedError.
  ///
  /// In en, this message translates to:
  /// **'Nickname update failed: {error}'**
  String nicknameUpdateFailedError(String error);

  /// No description provided for @automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automatic;

  /// No description provided for @auto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// No description provided for @automaticUsesYourLocalTimeLightFrom6AmTo6PmDarkOvernight.
  ///
  /// In en, this message translates to:
  /// **'Automatic uses your local time: light from 6 AM to 6 PM, dark overnight.'**
  String get automaticUsesYourLocalTimeLightFrom6AmTo6PmDarkOvernight;

  /// No description provided for @manualSelectionStaysActiveUntilYouChooseAnotherMode.
  ///
  /// In en, this message translates to:
  /// **'Manual selection stays active until you choose another mode.'**
  String get manualSelectionStaysActiveUntilYouChooseAnotherMode;

  /// No description provided for @languageUpdateFailedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Language update failed. Please try again.'**
  String get languageUpdateFailedPleaseTryAgain;

  /// No description provided for @notificationWeatherAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'Weather alert'**
  String get notificationWeatherAlertTitle;

  /// No description provided for @notificationWeatherAlertBody.
  ///
  /// In en, this message translates to:
  /// **'{location}: {precipitation}% chance of precipitation, wind up to {wind} km/h.'**
  String notificationWeatherAlertBody(
    String location,
    int precipitation,
    int wind,
  );

  /// No description provided for @notificationTaskOverdueTitle.
  ///
  /// In en, this message translates to:
  /// **'{task} is overdue'**
  String notificationTaskOverdueTitle(String task);

  /// No description provided for @notificationTaskDueTodayTitle.
  ///
  /// In en, this message translates to:
  /// **'{task} is due today'**
  String notificationTaskDueTodayTitle(String task);

  /// No description provided for @notificationTaskBody.
  ///
  /// In en, this message translates to:
  /// **'Open Owntend to review this task.'**
  String get notificationTaskBody;

  /// No description provided for @notificationDailyDigestTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily maintenance digest'**
  String get notificationDailyDigestTitle;

  /// No description provided for @notificationDailyDigestBody.
  ///
  /// In en, this message translates to:
  /// **'{overdue} overdue, {dueToday} due today, {upcoming} due this week'**
  String notificationDailyDigestBody(int overdue, int dueToday, int upcoming);

  /// No description provided for @notificationGenericTitle.
  ///
  /// In en, this message translates to:
  /// **'Owntend update'**
  String get notificationGenericTitle;

  /// No description provided for @notificationGenericBody.
  ///
  /// In en, this message translates to:
  /// **'Open Owntend to view this update.'**
  String get notificationGenericBody;

  /// No description provided for @accessYourTasksAndRoutinesAcrossAllYourDevices.
  ///
  /// In en, this message translates to:
  /// **'Access your tasks and routines across all your devices.'**
  String get accessYourTasksAndRoutinesAcrossAllYourDevices;

  /// No description provided for @buildHabitsAndAutomateRoutinesThatKeepYouMoving.
  ///
  /// In en, this message translates to:
  /// **'Build habits and automate routines that keep you moving.'**
  String get buildHabitsAndAutomateRoutinesThatKeepYouMoving;

  /// No description provided for @trackProgressStreaksAndGoalsToStayMotivated.
  ///
  /// In en, this message translates to:
  /// **'Track progress, streaks, and goals to stay motivated.'**
  String get trackProgressStreaksAndGoalsToStayMotivated;

  /// No description provided for @cloudRestorationInProgress.
  ///
  /// In en, this message translates to:
  /// **'Cloud restoration in progress'**
  String get cloudRestorationInProgress;

  /// No description provided for @tomorrowSTasks.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow\'\'s tasks'**
  String get tomorrowSTasks;

  /// No description provided for @upcomingTasks.
  ///
  /// In en, this message translates to:
  /// **'Upcoming tasks'**
  String get upcomingTasks;

  /// No description provided for @skipThisOccurrence.
  ///
  /// In en, this message translates to:
  /// **'Skip this occurrence'**
  String get skipThisOccurrence;

  /// No description provided for @postponeDueDate.
  ///
  /// In en, this message translates to:
  /// **'Postpone due date'**
  String get postponeDueDate;

  /// No description provided for @reminder.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get reminder;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @materials.
  ///
  /// In en, this message translates to:
  /// **'Materials'**
  String get materials;

  /// No description provided for @moveOrCopy.
  ///
  /// In en, this message translates to:
  /// **'Move or copy'**
  String get moveOrCopy;

  /// No description provided for @relatedTasks.
  ///
  /// In en, this message translates to:
  /// **'Related tasks'**
  String get relatedTasks;

  /// No description provided for @noTasksYet.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get noTasksYet;

  /// No description provided for @completionHistoryAcrossRelatedTasks.
  ///
  /// In en, this message translates to:
  /// **'Completion history across related tasks'**
  String get completionHistoryAcrossRelatedTasks;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @deletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Delete photo?'**
  String get deletePhoto;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @next7Days.
  ///
  /// In en, this message translates to:
  /// **'Next 7 days'**
  String get next7Days;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @findRoomsItemsTagsNotesPhotosAndTasks.
  ///
  /// In en, this message translates to:
  /// **'Find rooms, items, tags, notes, photos, and tasks'**
  String get findRoomsItemsTagsNotesPhotosAndTasks;

  /// No description provided for @insights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get insights;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @accountAndCloudSync.
  ///
  /// In en, this message translates to:
  /// **'Account & Cloud Sync'**
  String get accountAndCloudSync;

  /// No description provided for @optionalGoogleSignInAndPrivateDeviceSync.
  ///
  /// In en, this message translates to:
  /// **'Optional Google sign-in and private device sync'**
  String get optionalGoogleSignInAndPrivateDeviceSync;

  /// No description provided for @createShareOrRestoreLocalZipBackups.
  ///
  /// In en, this message translates to:
  /// **'Create, share, or restore local ZIP backups'**
  String get createShareOrRestoreLocalZipBackups;

  /// No description provided for @restoreRecentlyRemovedRoomsItemsAndTasks.
  ///
  /// In en, this message translates to:
  /// **'Restore recently removed rooms, items, and tasks'**
  String get restoreRecentlyRemovedRoomsItemsAndTasks;

  /// No description provided for @themeRemindersPrivacyAndReleaseReadiness.
  ///
  /// In en, this message translates to:
  /// **'Theme, reminders, privacy, and release readiness'**
  String get themeRemindersPrivacyAndReleaseReadiness;

  /// No description provided for @searchYourHome.
  ///
  /// In en, this message translates to:
  /// **'Search your home'**
  String get searchYourHome;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @nothingToRestore.
  ///
  /// In en, this message translates to:
  /// **'Nothing to restore'**
  String get nothingToRestore;

  /// No description provided for @areas.
  ///
  /// In en, this message translates to:
  /// **'Areas'**
  String get areas;

  /// No description provided for @deleteAreaForever.
  ///
  /// In en, this message translates to:
  /// **'Delete area forever?'**
  String get deleteAreaForever;

  /// No description provided for @deleteRoomForever.
  ///
  /// In en, this message translates to:
  /// **'Delete room forever?'**
  String get deleteRoomForever;

  /// No description provided for @deleteItemForever.
  ///
  /// In en, this message translates to:
  /// **'Delete item forever?'**
  String get deleteItemForever;

  /// No description provided for @deleteTaskForever.
  ///
  /// In en, this message translates to:
  /// **'Delete task forever?'**
  String get deleteTaskForever;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// No description provided for @unread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get unread;

  /// No description provided for @monthlyCompletions.
  ///
  /// In en, this message translates to:
  /// **'Monthly Completions'**
  String get monthlyCompletions;

  /// No description provided for @taskDistribution.
  ///
  /// In en, this message translates to:
  /// **'Task Distribution'**
  String get taskDistribution;

  /// No description provided for @historyCompletion.
  ///
  /// In en, this message translates to:
  /// **'History completion'**
  String get historyCompletion;

  /// No description provided for @activeOverdue.
  ///
  /// In en, this message translates to:
  /// **'Active overdue'**
  String get activeOverdue;

  /// No description provided for @useThisDeviceLocation.
  ///
  /// In en, this message translates to:
  /// **'Use this device location?'**
  String get useThisDeviceLocation;

  /// No description provided for @allowOwntendReminders.
  ///
  /// In en, this message translates to:
  /// **'Allow Owntend reminders?'**
  String get allowOwntendReminders;

  /// No description provided for @allowPreciseReminderTiming.
  ///
  /// In en, this message translates to:
  /// **'Allow precise reminder timing?'**
  String get allowPreciseReminderTiming;

  /// No description provided for @sendATestReminder.
  ///
  /// In en, this message translates to:
  /// **'Send a test reminder?'**
  String get sendATestReminder;

  /// No description provided for @locationServicesAreOff.
  ///
  /// In en, this message translates to:
  /// **'Location services are off'**
  String get locationServicesAreOff;

  /// No description provided for @permissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Permission needed'**
  String get permissionNeeded;

  /// No description provided for @permissionBlocked.
  ///
  /// In en, this message translates to:
  /// **'Permission blocked'**
  String get permissionBlocked;

  /// No description provided for @backupsAreSavedLocallyAsPrivateZipFiles.
  ///
  /// In en, this message translates to:
  /// **'Backups are saved locally as private ZIP files.'**
  String get backupsAreSavedLocallyAsPrivateZipFiles;

  /// No description provided for @restoreFromABackup.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get restoreFromABackup;

  /// No description provided for @skipThisOccurrence2.
  ///
  /// In en, this message translates to:
  /// **'Skip this occurrence?'**
  String get skipThisOccurrence2;

  /// No description provided for @postponeTask.
  ///
  /// In en, this message translates to:
  /// **'Postpone task?'**
  String get postponeTask;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @moveTaskToTrash2.
  ///
  /// In en, this message translates to:
  /// **'Move task to Trash?'**
  String get moveTaskToTrash2;

  /// No description provided for @moveItemToTrash2.
  ///
  /// In en, this message translates to:
  /// **'Move item to Trash?'**
  String get moveItemToTrash2;

  /// No description provided for @moveRoomToTrash2.
  ///
  /// In en, this message translates to:
  /// **'Move room to Trash?'**
  String get moveRoomToTrash2;

  /// No description provided for @moveAreaToTrash2.
  ///
  /// In en, this message translates to:
  /// **'Move area to Trash?'**
  String get moveAreaToTrash2;

  /// No description provided for @moveOrCopyItem.
  ///
  /// In en, this message translates to:
  /// **'Move or copy item'**
  String get moveOrCopyItem;

  /// No description provided for @createARoomFirst.
  ///
  /// In en, this message translates to:
  /// **'Create a room first'**
  String get createARoomFirst;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @owntendTestReminder.
  ///
  /// In en, this message translates to:
  /// **'Owntend test reminder'**
  String get owntendTestReminder;

  /// No description provided for @signOut2.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get signOut2;

  /// No description provided for @deleteOwntendAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Owntend account?'**
  String get deleteOwntendAccount;

  /// No description provided for @editNickname.
  ///
  /// In en, this message translates to:
  /// **'Edit nickname'**
  String get editNickname;

  /// No description provided for @appearanceLocationAndNotifications.
  ///
  /// In en, this message translates to:
  /// **'Appearance, location, and notifications'**
  String get appearanceLocationAndNotifications;

  /// No description provided for @exportOrRestoreAnEncryptedOwntendArchive.
  ///
  /// In en, this message translates to:
  /// **'Export or restore an encrypted Owntend archive'**
  String get exportOrRestoreAnEncryptedOwntendArchive;

  /// No description provided for @google.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get google;

  /// No description provided for @somethingWentWrongPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrongPleaseTryAgain;

  /// No description provided for @owntendIsFinishingAnotherLocalOperationPleaseTryAgainInAMoment.
  ///
  /// In en, this message translates to:
  /// **'Owntend is finishing another local operation. Please try again in a moment.'**
  String get owntendIsFinishingAnotherLocalOperationPleaseTryAgainInAMoment;

  /// No description provided for @signInFailedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed. Please try again.'**
  String get signInFailedPleaseTryAgain;

  /// No description provided for @themeUpdateFailedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Theme update failed. Please try again.'**
  String get themeUpdateFailedPleaseTryAgain;

  /// No description provided for @locationUpdateFailedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Location update failed. Please try again.'**
  String get locationUpdateFailedPleaseTryAgain;

  /// No description provided for @notificationSetupFailedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Notification setup failed. Please try again.'**
  String get notificationSetupFailedPleaseTryAgain;

  /// No description provided for @theTestReminderCouldNotBeSentPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'The test reminder could not be sent. Please try again.'**
  String get theTestReminderCouldNotBeSentPleaseTryAgain;

  /// No description provided for @thePhotoCouldNotBeSavedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be saved. Please try again.'**
  String get thePhotoCouldNotBeSavedPleaseTryAgain;

  /// No description provided for @theTaskCouldNotBeUpdatedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'The task could not be updated. Please try again.'**
  String get theTaskCouldNotBeUpdatedPleaseTryAgain;

  /// No description provided for @undoFailedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Undo failed. Please try again.'**
  String get undoFailedPleaseTryAgain;

  /// No description provided for @cloudServicesAreUnavailablePleaseTryAgainLater.
  ///
  /// In en, this message translates to:
  /// **'Cloud services are unavailable. Please try again later.'**
  String get cloudServicesAreUnavailablePleaseTryAgainLater;

  /// No description provided for @thisBuildIsNotConfiguredCorrectly.
  ///
  /// In en, this message translates to:
  /// **'This build is not configured correctly.'**
  String get thisBuildIsNotConfiguredCorrectly;

  /// No description provided for @activeTaskCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No active tasks} =1{1 active task} other{{count} active tasks}}'**
  String activeTaskCount(int count);

  /// No description provided for @savedPhotoCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No photos saved} =1{1 photo saved} other{{count} photos saved}}'**
  String savedPhotoCount(int count);

  /// No description provided for @warrantyUntilDate.
  ///
  /// In en, this message translates to:
  /// **'Warranty until {date}'**
  String warrantyUntilDate(String date);

  /// No description provided for @trashAreaType.
  ///
  /// In en, this message translates to:
  /// **'Area - {type}'**
  String trashAreaType(String type);

  /// No description provided for @trashRoomType.
  ///
  /// In en, this message translates to:
  /// **'Room - {type}'**
  String trashRoomType(String type);

  /// No description provided for @trashItemType.
  ///
  /// In en, this message translates to:
  /// **'Item - {type}'**
  String trashItemType(String type);

  /// No description provided for @noMaintenancePlanYet.
  ///
  /// In en, this message translates to:
  /// **'No maintenance plan yet.'**
  String get noMaintenancePlanYet;

  /// No description provided for @addAMaintenanceTask.
  ///
  /// In en, this message translates to:
  /// **'Add a maintenance task.'**
  String get addAMaintenanceTask;

  /// No description provided for @overdueTaskSentence.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No overdue tasks.} =1{1 overdue task.} other{{count} overdue tasks.}}'**
  String overdueTaskSentence(int count);

  /// No description provided for @criticalTaskDueToday.
  ///
  /// In en, this message translates to:
  /// **'Critical task due today.'**
  String get criticalTaskDueToday;

  /// No description provided for @criticalCareIsDueSoon.
  ///
  /// In en, this message translates to:
  /// **'Critical care is due soon.'**
  String get criticalCareIsDueSoon;

  /// No description provided for @warrantyHasExpired.
  ///
  /// In en, this message translates to:
  /// **'Warranty has expired.'**
  String get warrantyHasExpired;

  /// No description provided for @warrantyExpiresWithin30Days.
  ///
  /// In en, this message translates to:
  /// **'Warranty expires within 30 days.'**
  String get warrantyExpiresWithin30Days;

  /// No description provided for @maintenanceIsOnTrack.
  ///
  /// In en, this message translates to:
  /// **'Maintenance is on track.'**
  String get maintenanceIsOnTrack;

  /// No description provided for @reviewUpcomingMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Review upcoming maintenance.'**
  String get reviewUpcomingMaintenance;

  /// No description provided for @noItemsInThisRoomYet.
  ///
  /// In en, this message translates to:
  /// **'No items in this room yet.'**
  String get noItemsInThisRoomYet;

  /// No description provided for @addTheFirstItem.
  ///
  /// In en, this message translates to:
  /// **'Add the first item.'**
  String get addTheFirstItem;

  /// No description provided for @itemCountSentence.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items.} =1{1 item.} other{{count} items.}}'**
  String itemCountSentence(int count);

  /// No description provided for @dueTodayTaskSentence.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing due today.} =1{1 task due today.} other{{count} tasks due today.}}'**
  String dueTodayTaskSentence(int count);

  /// No description provided for @roomIsOnTrack.
  ///
  /// In en, this message translates to:
  /// **'Room is on track.'**
  String get roomIsOnTrack;

  /// No description provided for @addMaintenanceTasksForThisRoom.
  ///
  /// In en, this message translates to:
  /// **'Add maintenance tasks for this room.'**
  String get addMaintenanceTasksForThisRoom;

  /// No description provided for @homeSetupIsIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Home setup is incomplete.'**
  String get homeSetupIsIncomplete;

  /// No description provided for @noSuccessfulBackupYet.
  ///
  /// In en, this message translates to:
  /// **'No successful backup yet.'**
  String get noSuccessfulBackupYet;

  /// No description provided for @warrantyAlertSentence.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No warranty alerts.} =1{1 warranty alert.} other{{count} warranty alerts.}}'**
  String warrantyAlertSentence(int count);

  /// No description provided for @homeMaintenanceIsReady.
  ///
  /// In en, this message translates to:
  /// **'Home maintenance is ready.'**
  String get homeMaintenanceIsReady;

  /// No description provided for @reviewUpcomingTasks.
  ///
  /// In en, this message translates to:
  /// **'Review upcoming tasks.'**
  String get reviewUpcomingTasks;

  /// No description provided for @owntendReminder.
  ///
  /// In en, this message translates to:
  /// **'Owntend reminder'**
  String get owntendReminder;

  /// No description provided for @snoozedReminderTask.
  ///
  /// In en, this message translates to:
  /// **'Snoozed reminder: {task}'**
  String snoozedReminderTask(String task);

  /// No description provided for @openOwntendToViewThisReminder.
  ///
  /// In en, this message translates to:
  /// **'Open Owntend to view this reminder.'**
  String get openOwntendToViewThisReminder;

  /// No description provided for @notificationsAreReadyThisScheduledTestShouldArriveNow.
  ///
  /// In en, this message translates to:
  /// **'Notifications are ready. This scheduled test should arrive now.'**
  String get notificationsAreReadyThisScheduledTestShouldArriveNow;

  /// No description provided for @deviceLocation.
  ///
  /// In en, this message translates to:
  /// **'Device location'**
  String get deviceLocation;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @clearWeather.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearWeather;

  /// No description provided for @partlyCloudy.
  ///
  /// In en, this message translates to:
  /// **'Partly cloudy'**
  String get partlyCloudy;

  /// No description provided for @cloudy.
  ///
  /// In en, this message translates to:
  /// **'Cloudy'**
  String get cloudy;

  /// No description provided for @fog.
  ///
  /// In en, this message translates to:
  /// **'Fog'**
  String get fog;

  /// No description provided for @drizzle.
  ///
  /// In en, this message translates to:
  /// **'Drizzle'**
  String get drizzle;

  /// No description provided for @rain.
  ///
  /// In en, this message translates to:
  /// **'Rain'**
  String get rain;

  /// No description provided for @snow.
  ///
  /// In en, this message translates to:
  /// **'Snow'**
  String get snow;

  /// No description provided for @storms.
  ///
  /// In en, this message translates to:
  /// **'Storms'**
  String get storms;

  /// No description provided for @weather.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get weather;

  /// No description provided for @updatedTime.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String updatedTime(String time);

  /// No description provided for @excellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get excellent;

  /// No description provided for @good.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get good;

  /// No description provided for @needsSetup.
  ///
  /// In en, this message translates to:
  /// **'Needs setup'**
  String get needsSetup;

  /// No description provided for @noBackup.
  ///
  /// In en, this message translates to:
  /// **'No backup'**
  String get noBackup;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @livingRoom.
  ///
  /// In en, this message translates to:
  /// **'Living room'**
  String get livingRoom;

  /// No description provided for @bedroom.
  ///
  /// In en, this message translates to:
  /// **'Bedroom'**
  String get bedroom;

  /// No description provided for @bathroom.
  ///
  /// In en, this message translates to:
  /// **'Bathroom'**
  String get bathroom;

  /// No description provided for @utility.
  ///
  /// In en, this message translates to:
  /// **'Utility'**
  String get utility;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @office.
  ///
  /// In en, this message translates to:
  /// **'Office'**
  String get office;

  /// No description provided for @diningRoom.
  ///
  /// In en, this message translates to:
  /// **'Dining room'**
  String get diningRoom;

  /// No description provided for @hallway.
  ///
  /// In en, this message translates to:
  /// **'Hallway'**
  String get hallway;

  /// No description provided for @entry.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get entry;

  /// No description provided for @garage.
  ///
  /// In en, this message translates to:
  /// **'Garage'**
  String get garage;

  /// No description provided for @patio.
  ///
  /// In en, this message translates to:
  /// **'Patio'**
  String get patio;

  /// No description provided for @balcony.
  ///
  /// In en, this message translates to:
  /// **'Balcony'**
  String get balcony;

  /// No description provided for @pool.
  ///
  /// In en, this message translates to:
  /// **'Pool'**
  String get pool;

  /// No description provided for @lawn.
  ///
  /// In en, this message translates to:
  /// **'Lawn'**
  String get lawn;

  /// No description provided for @shed.
  ///
  /// In en, this message translates to:
  /// **'Shed'**
  String get shed;

  /// No description provided for @driveway.
  ///
  /// In en, this message translates to:
  /// **'Driveway'**
  String get driveway;

  /// No description provided for @itemStatusOverdue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 overdue} other{{count} overdue}}'**
  String itemStatusOverdue(int count);

  /// No description provided for @itemStatusDueToday.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 due today} other{{count} due today}}'**
  String itemStatusDueToday(int count);

  /// No description provided for @itemStatusDueSoon.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Due soon} other{{count} due soon}}'**
  String itemStatusDueSoon(int count);

  /// No description provided for @onTrack.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get onTrack;

  /// No description provided for @taskEnabledConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Task enabled.'**
  String get taskEnabledConfirmation;

  /// No description provided for @taskDisabledConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Task disabled.'**
  String get taskDisabledConfirmation;

  /// No description provided for @taskAdded.
  ///
  /// In en, this message translates to:
  /// **'Task added'**
  String get taskAdded;

  /// No description provided for @taskDone.
  ///
  /// In en, this message translates to:
  /// **'Task done'**
  String get taskDone;

  /// No description provided for @taskDeleted.
  ///
  /// In en, this message translates to:
  /// **'Task deleted'**
  String get taskDeleted;

  /// No description provided for @taskSnoozedForDuration.
  ///
  /// In en, this message translates to:
  /// **'{task} snoozed for {duration}.'**
  String taskSnoozedForDuration(String task, String duration);

  /// No description provided for @hydrationConnectingSecurely.
  ///
  /// In en, this message translates to:
  /// **'Connecting securely'**
  String get hydrationConnectingSecurely;

  /// No description provided for @hydrationRestoringCloudData.
  ///
  /// In en, this message translates to:
  /// **'Restoring cloud data'**
  String get hydrationRestoringCloudData;

  /// No description provided for @hydrationRestoringPhotos.
  ///
  /// In en, this message translates to:
  /// **'Restoring photos'**
  String get hydrationRestoringPhotos;

  /// No description provided for @hydrationSyncingLocalChanges.
  ///
  /// In en, this message translates to:
  /// **'Syncing local changes'**
  String get hydrationSyncingLocalChanges;

  /// No description provided for @hydrationCheckingLatestUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking latest updates'**
  String get hydrationCheckingLatestUpdates;

  /// No description provided for @noMaintenancePlansYet.
  ///
  /// In en, this message translates to:
  /// **'No maintenance plans yet'**
  String get noMaintenancePlansYet;

  /// No description provided for @createYourFirstItem.
  ///
  /// In en, this message translates to:
  /// **'Create your first item'**
  String get createYourFirstItem;

  /// No description provided for @createYourFirstRoom.
  ///
  /// In en, this message translates to:
  /// **'Create your first room'**
  String get createYourFirstRoom;

  /// No description provided for @scheduleRecurringCareForAnItemToStartTracking.
  ///
  /// In en, this message translates to:
  /// **'Schedule recurring care for an item to start tracking.'**
  String get scheduleRecurringCareForAnItemToStartTracking;

  /// No description provided for @addAHomeItemFirst.
  ///
  /// In en, this message translates to:
  /// **'Add a device, plant, pet, safety item, or other home item first.'**
  String get addAHomeItemFirst;

  /// No description provided for @addARoomOrZoneBeforeAddingItems.
  ///
  /// In en, this message translates to:
  /// **'Add a room or zone before adding the items you maintain.'**
  String get addARoomOrZoneBeforeAddingItems;

  /// No description provided for @createFirstItem.
  ///
  /// In en, this message translates to:
  /// **'Create first item'**
  String get createFirstItem;

  /// No description provided for @createFirstRoom.
  ///
  /// In en, this message translates to:
  /// **'Create first room'**
  String get createFirstRoom;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @outdoorZones.
  ///
  /// In en, this message translates to:
  /// **'Outdoor zones'**
  String get outdoorZones;

  /// No description provided for @noZonesYet.
  ///
  /// In en, this message translates to:
  /// **'No zones yet'**
  String get noZonesYet;

  /// No description provided for @noRoomsYet.
  ///
  /// In en, this message translates to:
  /// **'No rooms yet'**
  String get noRoomsYet;

  /// No description provided for @zonesOrganizeOutdoorCare.
  ///
  /// In en, this message translates to:
  /// **'Zones help organize outdoor items, tasks, and weather-aware reminders.'**
  String get zonesOrganizeOutdoorCare;

  /// No description provided for @roomsOrganizeCareByLocation.
  ///
  /// In en, this message translates to:
  /// **'Rooms help organize items, tasks, and reminders by location.'**
  String get roomsOrganizeCareByLocation;

  /// No description provided for @tryADifferentNameOrType.
  ///
  /// In en, this message translates to:
  /// **'Try a different name or type.'**
  String get tryADifferentNameOrType;

  /// No description provided for @createRecurringCareForThisItem.
  ///
  /// In en, this message translates to:
  /// **'Create recurring care for this item.'**
  String get createRecurringCareForThisItem;

  /// No description provided for @deleteSavedPhotoFromItem.
  ///
  /// In en, this message translates to:
  /// **'This removes the saved photo from {item}.'**
  String deleteSavedPhotoFromItem(String item);

  /// No description provided for @completedTasksForThisItemAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Completed tasks for this item will appear here.'**
  String get completedTasksForThisItemAppearHere;

  /// No description provided for @completedWorkWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Completed work will appear here.'**
  String get completedWorkWillAppearHere;

  /// No description provided for @yourMaintenancePlanIsClearToday.
  ///
  /// In en, this message translates to:
  /// **'Your maintenance plan is clear for today.'**
  String get yourMaintenancePlanIsClearToday;

  /// No description provided for @yourMaintenancePlanIsUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Your maintenance plan is up to date.'**
  String get yourMaintenancePlanIsUpToDate;

  /// No description provided for @upcomingMaintenanceWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Upcoming maintenance will appear here.'**
  String get upcomingMaintenanceWillAppearHere;

  /// No description provided for @createATaskToStartPlanningMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Create a task to start planning maintenance.'**
  String get createATaskToStartPlanningMaintenance;

  /// No description provided for @taskCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No tasks} =1{1 task} other{{count} tasks}}'**
  String taskCountLabel(int count);

  /// No description provided for @findAllHomeContent.
  ///
  /// In en, this message translates to:
  /// **'Find rooms, items, tags, serial numbers, notes, photo captions, and maintenance tasks.'**
  String get findAllHomeContent;

  /// No description provided for @tryAnotherSearchTerm.
  ///
  /// In en, this message translates to:
  /// **'Try another item name, task title, tag, or note.'**
  String get tryAnotherSearchTerm;

  /// No description provided for @result.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get result;

  /// No description provided for @searchResultWithSnippet.
  ///
  /// In en, this message translates to:
  /// **'{type} - {snippet}'**
  String searchResultWithSnippet(String type, String snippet);

  /// No description provided for @trashIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get trashIsEmpty;

  /// No description provided for @trashItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String trashItemCount(int count);

  /// No description provided for @restoreOrDeleteForever.
  ///
  /// In en, this message translates to:
  /// **'Restore removed records or delete them forever.'**
  String get restoreOrDeleteForever;

  /// No description provided for @trashedContentAppearsHere.
  ///
  /// In en, this message translates to:
  /// **'Rooms, items, and tasks moved to Trash appear here.'**
  String get trashedContentAppearsHere;

  /// No description provided for @inboxMessagesAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Maintenance reminders, digests, and system messages will appear here.'**
  String get inboxMessagesAppearHere;

  /// No description provided for @changeFilterForOtherUpdates.
  ///
  /// In en, this message translates to:
  /// **'Change the filter to see other inbox updates.'**
  String get changeFilterForOtherUpdates;

  /// No description provided for @noUnreadNotifications.
  ///
  /// In en, this message translates to:
  /// **'No unread notifications'**
  String get noUnreadNotifications;

  /// No description provided for @noTaskNotifications.
  ///
  /// In en, this message translates to:
  /// **'No task notifications'**
  String get noTaskNotifications;

  /// No description provided for @noSystemNotifications.
  ///
  /// In en, this message translates to:
  /// **'No system notifications'**
  String get noSystemNotifications;

  /// No description provided for @completedAtTime.
  ///
  /// In en, this message translates to:
  /// **'Completed {time}'**
  String completedAtTime(String time);

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @weatherContextImprovesOutdoorTasks.
  ///
  /// In en, this message translates to:
  /// **'Weather context improves outdoor and seasonal tasks.'**
  String get weatherContextImprovesOutdoorTasks;

  /// No description provided for @noBackupCreatedOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'No backup has been created on this device yet.'**
  String get noBackupCreatedOnThisDevice;

  /// No description provided for @manualBackup.
  ///
  /// In en, this message translates to:
  /// **'Manual backup'**
  String get manualBackup;

  /// No description provided for @automaticBackup.
  ///
  /// In en, this message translates to:
  /// **'Automatic backup'**
  String get automaticBackup;

  /// No description provided for @safetyBackup.
  ///
  /// In en, this message translates to:
  /// **'Safety backup'**
  String get safetyBackup;

  /// No description provided for @lastBackupAt.
  ///
  /// In en, this message translates to:
  /// **'Last backup: {date}'**
  String lastBackupAt(String date);

  /// No description provided for @lastBackupAtWithSize.
  ///
  /// In en, this message translates to:
  /// **'Last backup: {date} - {size}'**
  String lastBackupAtWithSize(String date, String size);

  /// No description provided for @backupFailedAt.
  ///
  /// In en, this message translates to:
  /// **'{action} failed {date}'**
  String backupFailedAt(String action, String date);

  /// No description provided for @latestBackup.
  ///
  /// In en, this message translates to:
  /// **'Latest backup'**
  String get latestBackup;

  /// No description provided for @backupStatus.
  ///
  /// In en, this message translates to:
  /// **'Backup status'**
  String get backupStatus;

  /// No description provided for @backupFailedPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be completed. Please try again.'**
  String get backupFailedPleaseTryAgain;

  /// No description provided for @hideBackupDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide backup details'**
  String get hideBackupDetails;

  /// No description provided for @viewBackupDetails.
  ///
  /// In en, this message translates to:
  /// **'View backup details'**
  String get viewBackupDetails;

  /// No description provided for @allowNotificationsForReminders.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications so Owntend can deliver this test and your enabled task reminders.'**
  String get allowNotificationsForReminders;

  /// No description provided for @testReminderScheduled.
  ///
  /// In en, this message translates to:
  /// **'Test reminder scheduled for about 10 seconds from now.'**
  String get testReminderScheduled;

  /// No description provided for @turnOnLocationServices.
  ///
  /// In en, this message translates to:
  /// **'Turn on device location services, then return to Owntend.'**
  String get turnOnLocationServices;

  /// No description provided for @allowInSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'{message} You can allow it in system settings.'**
  String allowInSystemSettings(String message);

  /// No description provided for @allowPermissionInSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Allow this permission in system settings to use the feature.'**
  String get allowPermissionInSystemSettings;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @skipOccurrence.
  ///
  /// In en, this message translates to:
  /// **'Skip occurrence'**
  String get skipOccurrence;

  /// No description provided for @postpone.
  ///
  /// In en, this message translates to:
  /// **'Postpone'**
  String get postpone;

  /// No description provided for @postponeCurrentCycleMessage.
  ///
  /// In en, this message translates to:
  /// **'This changes the due date for the current cycle. Add a reason if useful for the timeline.'**
  String get postponeCurrentCycleMessage;

  /// No description provided for @taskPostponedUntil.
  ///
  /// In en, this message translates to:
  /// **'{task} postponed to {date}.'**
  String taskPostponedUntil(String task, String date);

  /// No description provided for @moveTaskToTrashMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes ‘{name}’ from active tasks. You can restore it from Trash.'**
  String moveTaskToTrashMessage(String name);

  /// No description provided for @moveItemToTrashMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes ‘{name}’ and its tasks from active views. You can restore them from Trash.'**
  String moveItemToTrashMessage(String name);

  /// No description provided for @moveRoomToTrashMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes ‘{name}’ and every item and task inside it from active views. You can restore them from Trash.'**
  String moveRoomToTrashMessage(String name);

  /// No description provided for @moveAreaToTrashMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes ‘{name}’ and every room, item, and task inside it from active views. You can restore them from Trash.'**
  String moveAreaToTrashMessage(String name);

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @copyItem.
  ///
  /// In en, this message translates to:
  /// **'Copy item'**
  String get copyItem;

  /// No description provided for @moveItem.
  ///
  /// In en, this message translates to:
  /// **'Move item'**
  String get moveItem;

  /// No description provided for @itemsNeedARoomToMoveOrCopy.
  ///
  /// In en, this message translates to:
  /// **'Items need a room before they can be moved or copied.'**
  String get itemsNeedARoomToMoveOrCopy;

  /// No description provided for @checkingAppBuild.
  ///
  /// In en, this message translates to:
  /// **'Checking app build...'**
  String get checkingAppBuild;

  /// No description provided for @appBuildInformationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'App build information unavailable'**
  String get appBuildInformationUnavailable;

  /// No description provided for @notificationTaskSkippedTitle.
  ///
  /// In en, this message translates to:
  /// **'Task skipped'**
  String get notificationTaskSkippedTitle;

  /// No description provided for @notificationTaskSkippedBody.
  ///
  /// In en, this message translates to:
  /// **'{mode, select, reason{{task} was skipped: {reason}} other{{task} was skipped for this occurrence.}}'**
  String notificationTaskSkippedBody(String mode, String task, String reason);

  /// No description provided for @notificationTaskPostponedTitle.
  ///
  /// In en, this message translates to:
  /// **'Task postponed'**
  String get notificationTaskPostponedTitle;

  /// No description provided for @notificationTaskPostponedBody.
  ///
  /// In en, this message translates to:
  /// **'{mode, select, reason{{task} was postponed: {reason}} other{{task} was postponed to {date}.}}'**
  String notificationTaskPostponedBody(
    String mode,
    String task,
    String reason,
    String date,
  );

  /// No description provided for @noScheduledTasks.
  ///
  /// In en, this message translates to:
  /// **'No scheduled tasks'**
  String get noScheduledTasks;

  /// No description provided for @createRecurringPlanForMaintenanceQueue.
  ///
  /// In en, this message translates to:
  /// **'Create a recurring plan for any item to populate your maintenance queue.'**
  String get createRecurringPlanForMaintenanceQueue;

  /// No description provided for @maintenanceTasksNeedAnItem.
  ///
  /// In en, this message translates to:
  /// **'Maintenance tasks need an item so Owntend knows what the work belongs to.'**
  String get maintenanceTasksNeedAnItem;

  /// No description provided for @addRoomOrZoneBeforeItemsAndTasks.
  ///
  /// In en, this message translates to:
  /// **'Add a room or zone before creating items and tasks.'**
  String get addRoomOrZoneBeforeItemsAndTasks;

  /// No description provided for @tag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get tag;

  /// No description provided for @skipCurrentCycleMessage.
  ///
  /// In en, this message translates to:
  /// **'This advances the next due date without marking the task complete. Add a reason if useful for the timeline.'**
  String get skipCurrentCycleMessage;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get goodMorning;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get goodEvening;

  /// No description provided for @there.
  ///
  /// In en, this message translates to:
  /// **'there'**
  String get there;

  /// No description provided for @personalGreeting.
  ///
  /// In en, this message translates to:
  /// **'{greeting}, {name}.'**
  String personalGreeting(String greeting, String name);

  /// No description provided for @creatingBackup.
  ///
  /// In en, this message translates to:
  /// **'Creating backup...'**
  String get creatingBackup;

  /// No description provided for @updatingBackupSettings.
  ///
  /// In en, this message translates to:
  /// **'Updating backup settings...'**
  String get updatingBackupSettings;

  /// No description provided for @checkingBackup.
  ///
  /// In en, this message translates to:
  /// **'Checking backup...'**
  String get checkingBackup;

  /// No description provided for @restoringBackup.
  ///
  /// In en, this message translates to:
  /// **'Restoring backup...'**
  String get restoringBackup;

  /// No description provided for @lastBackupFileMissing.
  ///
  /// In en, this message translates to:
  /// **'The last backup file is no longer on this device. Create a new backup.'**
  String get lastBackupFileMissing;

  /// No description provided for @owntendBackupShareText.
  ///
  /// In en, this message translates to:
  /// **'Owntend backup'**
  String get owntendBackupShareText;

  /// No description provided for @restoreReplacesLocalData.
  ///
  /// In en, this message translates to:
  /// **'This replaces the current Owntend data on this device with the backup from {date}.'**
  String restoreReplacesLocalData(String date);

  /// No description provided for @restoreReplacementWarning.
  ///
  /// In en, this message translates to:
  /// **'Current tasks, items, history, settings, notifications, streaks, and photos will be replaced. A safety copy is created before restore starts.'**
  String get restoreReplacementWarning;

  /// No description provided for @cloudRestoreSafetyNotice.
  ///
  /// In en, this message translates to:
  /// **'Cloud backup is active. Restoring locally and pausing cloud backup is the safest option.'**
  String get cloudRestoreSafetyNotice;

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'Backup restored. Owntend reloaded the restored data.'**
  String get backupRestored;

  /// No description provided for @backupFromDate.
  ///
  /// In en, this message translates to:
  /// **'Backup from {date}'**
  String backupFromDate(String date);

  /// No description provided for @backupFormatSummary.
  ///
  /// In en, this message translates to:
  /// **'Format {format}, schema {schema}, {size}'**
  String backupFormatSummary(int format, int schema, String size);

  /// No description provided for @backupWillRestore.
  ///
  /// In en, this message translates to:
  /// **'Will restore: {details}.'**
  String backupWillRestore(String details);

  /// No description provided for @backupNotIncluded.
  ///
  /// In en, this message translates to:
  /// **'Not included: {details}.'**
  String backupNotIncluded(String details);

  /// No description provided for @backupIncludedTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks and due dates'**
  String get backupIncludedTasks;

  /// No description provided for @backupIncludedItems.
  ///
  /// In en, this message translates to:
  /// **'Items, rooms, areas, categories, tags, and photos'**
  String get backupIncludedItems;

  /// No description provided for @backupIncludedHistory.
  ///
  /// In en, this message translates to:
  /// **'Task history, timeline, streaks, and statistics source data'**
  String get backupIncludedHistory;

  /// No description provided for @backupIncludedNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences, inbox history, and snooze defaults'**
  String get backupIncludedNotifications;

  /// No description provided for @backupIncludedSettings.
  ///
  /// In en, this message translates to:
  /// **'Theme, profile, weather location, and app settings'**
  String get backupIncludedSettings;

  /// No description provided for @backupExcludedAlarms.
  ///
  /// In en, this message translates to:
  /// **'Android scheduled alarm handles are recreated from restored tasks and settings'**
  String get backupExcludedAlarms;

  /// No description provided for @backupOlderFormatWarning.
  ///
  /// In en, this message translates to:
  /// **'This is an older backup format. Owntend will migrate it during restore.'**
  String get backupOlderFormatWarning;

  /// No description provided for @backupProfilePreviewWarning.
  ///
  /// In en, this message translates to:
  /// **'Profile settings could not be previewed.'**
  String get backupProfilePreviewWarning;

  /// No description provided for @backupGenericWarning.
  ///
  /// In en, this message translates to:
  /// **'This backup contains a compatibility warning. Review it before restoring.'**
  String get backupGenericWarning;

  /// No description provided for @startupStartingOwntend.
  ///
  /// In en, this message translates to:
  /// **'Starting Owntend'**
  String get startupStartingOwntend;

  /// Decorative tagline shown on the process startup splash.
  ///
  /// In en, this message translates to:
  /// **'Everything you own.\nWell tended.'**
  String get owntendSplashTagline;

  /// No description provided for @startupLoadedPreferences.
  ///
  /// In en, this message translates to:
  /// **'Loaded preferences'**
  String get startupLoadedPreferences;

  /// No description provided for @startupOpeningOwntend.
  ///
  /// In en, this message translates to:
  /// **'Opening Owntend'**
  String get startupOpeningOwntend;

  /// No description provided for @startupRestoringSession.
  ///
  /// In en, this message translates to:
  /// **'Restoring session'**
  String get startupRestoringSession;

  /// No description provided for @startupCheckingSyncState.
  ///
  /// In en, this message translates to:
  /// **'Checking sync state'**
  String get startupCheckingSyncState;

  /// No description provided for @startupLoadingHomeData.
  ///
  /// In en, this message translates to:
  /// **'Loading Home data'**
  String get startupLoadingHomeData;

  /// No description provided for @startupUpdatingWeather.
  ///
  /// In en, this message translates to:
  /// **'Updating weather'**
  String get startupUpdatingWeather;

  /// No description provided for @restoreProgressNotificationPermission.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications to see real Owntend restoration progress while the app is in the background.'**
  String get restoreProgressNotificationPermission;

  /// No description provided for @cloudDataStillWaiting.
  ///
  /// In en, this message translates to:
  /// **'Cloud data is still waiting'**
  String get cloudDataStillWaiting;

  /// No description provided for @hydrationStageFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'{stage} needs attention'**
  String hydrationStageFailureTitle(String stage);

  /// No description provided for @hydrationStageTimedOutMessage.
  ///
  /// In en, this message translates to:
  /// **'{stage} took longer than expected. Retry to continue.'**
  String hydrationStageTimedOutMessage(String stage);

  /// No description provided for @hydrationStageFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Owntend could not complete {stage}. Retry to continue.'**
  String hydrationStageFailedMessage(String stage);

  /// No description provided for @restoringYourFlow.
  ///
  /// In en, this message translates to:
  /// **'Restoring your flow'**
  String get restoringYourFlow;

  /// No description provided for @checkNetworkAndRetryWhenReady.
  ///
  /// In en, this message translates to:
  /// **'Check the network and retry when ready.'**
  String get checkNetworkAndRetryWhenReady;

  /// No description provided for @securelyRestoringTasksRoutinesAndReminders.
  ///
  /// In en, this message translates to:
  /// **'Securely bringing back your tasks,\nroutines, and reminders.'**
  String get securelyRestoringTasksRoutinesAndReminders;

  /// No description provided for @hydrationStepCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get hydrationStepCompleted;

  /// No description provided for @hydrationStepNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get hydrationStepNeedsAttention;

  /// No description provided for @hydrationStepInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get hydrationStepInProgress;

  /// No description provided for @hydrationStepPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get hydrationStepPending;

  /// No description provided for @homeReadinessNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get homeReadinessNeedsAttention;

  /// No description provided for @homeReadinessNextTaskReady.
  ///
  /// In en, this message translates to:
  /// **'Next task ready'**
  String get homeReadinessNextTaskReady;

  /// No description provided for @homeReadinessReadyForToday.
  ///
  /// In en, this message translates to:
  /// **'Ready for today'**
  String get homeReadinessReadyForToday;

  /// No description provided for @weatherNotSet.
  ///
  /// In en, this message translates to:
  /// **'Weather not set'**
  String get weatherNotSet;

  /// No description provided for @weatherUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Weather unavailable'**
  String get weatherUnavailable;

  /// No description provided for @addHomeLocationInSettings.
  ///
  /// In en, this message translates to:
  /// **'Add a home location in Settings.'**
  String get addHomeLocationInSettings;

  /// No description provided for @weatherWillUpdateWhenConnectionReturns.
  ///
  /// In en, this message translates to:
  /// **'Weather will update when connection returns.'**
  String get weatherWillUpdateWhenConnectionReturns;

  /// No description provided for @switchToLightMode.
  ///
  /// In en, this message translates to:
  /// **'Switch to light mode'**
  String get switchToLightMode;

  /// No description provided for @switchToDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Switch to dark mode'**
  String get switchToDarkMode;

  /// No description provided for @createAreaToOrganizeRoomsAndZones.
  ///
  /// In en, this message translates to:
  /// **'Create a floor or outdoor area to start organizing rooms and zones.'**
  String get createAreaToOrganizeRoomsAndZones;

  /// No description provided for @matchingRoomCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 matching room} other{{count} matching rooms}}'**
  String matchingRoomCount(int count);

  /// No description provided for @matchingZoneCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 matching zone} other{{count} matching zones}}'**
  String matchingZoneCount(int count);

  /// No description provided for @itemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String itemCount(int count);

  /// No description provided for @roomTaskStatusNoTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks'**
  String get roomTaskStatusNoTasks;

  /// No description provided for @roomTaskStatusOverdue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 overdue} other{{count} overdue}}'**
  String roomTaskStatusOverdue(int count);

  /// No description provided for @roomTaskStatusDueToday.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 due today} other{{count} due today}}'**
  String roomTaskStatusDueToday(int count);

  /// No description provided for @homeArea.
  ///
  /// In en, this message translates to:
  /// **'Home area'**
  String get homeArea;

  /// No description provided for @roomHealthSemantic.
  ///
  /// In en, this message translates to:
  /// **'Room health {score}% - {state}'**
  String roomHealthSemantic(int score, String state);

  /// No description provided for @itemHealthSemantic.
  ///
  /// In en, this message translates to:
  /// **'Item health {value}'**
  String itemHealthSemantic(String value);

  /// No description provided for @itemHealthPercent.
  ///
  /// In en, this message translates to:
  /// **'{score}%'**
  String itemHealthPercent(int score);

  /// No description provided for @addItemsToRoomBody.
  ///
  /// In en, this message translates to:
  /// **'Add devices, pets, plants, safety items, or general items here.'**
  String get addItemsToRoomBody;

  /// No description provided for @dueDateTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String dueDateTimeLabel(String date);

  /// No description provided for @primary.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get primary;

  /// No description provided for @createMaintenancePlanManually.
  ///
  /// In en, this message translates to:
  /// **'Create a maintenance plan manually'**
  String get createMaintenancePlanManually;

  /// No description provided for @tasksNeedItemFirst.
  ///
  /// In en, this message translates to:
  /// **'Tasks need an item first'**
  String get tasksNeedItemFirst;

  /// No description provided for @itemsNeedRoomFirst.
  ///
  /// In en, this message translates to:
  /// **'Items need a room first'**
  String get itemsNeedRoomFirst;

  /// No description provided for @calendarLegend.
  ///
  /// In en, this message translates to:
  /// **'Numbers show tasks due. Today is outlined. Selected dates are filled.'**
  String get calendarLegend;

  /// No description provided for @selectedDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Selected: {date}'**
  String selectedDateLabel(String date);

  /// No description provided for @permanentlyDeleteAreaMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes \"{name}\" and every room, item, task, photo, and timeline inside it.'**
  String permanentlyDeleteAreaMessage(String name);

  /// No description provided for @permanentlyDeleteRoomMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes \"{name}\" and every item, task, photo, and timeline inside it.'**
  String permanentlyDeleteRoomMessage(String name);

  /// No description provided for @permanentlyDeleteItemMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes \"{name}\", its photos, fields, tasks, and maintenance history.'**
  String permanentlyDeleteItemMessage(String name);

  /// No description provided for @permanentlyDeleteTaskMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes \"{name}\" and its completion timeline.'**
  String permanentlyDeleteTaskMessage(String name);

  /// No description provided for @nameRestored.
  ///
  /// In en, this message translates to:
  /// **'{name} restored.'**
  String nameRestored(String name);

  /// No description provided for @nameDeletedForever.
  ///
  /// In en, this message translates to:
  /// **'{name} deleted forever.'**
  String nameDeletedForever(String name);

  /// No description provided for @trashSectionItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String trashSectionItemCount(int count);

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @completeAction.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get completeAction;

  /// No description provided for @inboxUpdateCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 inbox update} other{{count} inbox updates}}'**
  String inboxUpdateCount(int count);

  /// No description provided for @unreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unread} other{{count} unread}}'**
  String unreadCount(int count);

  /// No description provided for @taskReminderCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task reminder} other{{count} task reminders}}'**
  String taskReminderCount(int count);

  /// No description provided for @filterUnreadCount.
  ///
  /// In en, this message translates to:
  /// **'{label}, {count, plural, =1{1 unread} other{{count} unread}}'**
  String filterUnreadCount(String label, int count);

  /// No description provided for @reminderCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task reminder} other{{count} task reminders}}'**
  String reminderCountLabel(int count);

  /// No description provided for @locationPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Owntend uses your location only to select local weather for household planning.'**
  String get locationPermissionBody;

  /// No description provided for @notificationsPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Notifications are used only for task reminders and the alerts you enable.'**
  String get notificationsPermissionBody;

  /// No description provided for @preciseAlarmsPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Precise alarms let Owntend deliver enabled reminders at the exact selected time.'**
  String get preciseAlarmsPermissionBody;

  /// No description provided for @approximateReminderTimingWarning.
  ///
  /// In en, this message translates to:
  /// **'Reminders will use approximate timing until precise alarms are allowed.'**
  String get approximateReminderTimingWarning;

  /// No description provided for @automaticBackupsDescription.
  ///
  /// In en, this message translates to:
  /// **'Creates one local backup per day when the app opens. Older automatic backups may be rotated by storage cleanup.'**
  String get automaticBackupsDescription;

  /// No description provided for @restorePreviewDescription.
  ///
  /// In en, this message translates to:
  /// **'Restoring will replace your current local data after you review the preview.'**
  String get restorePreviewDescription;

  /// No description provided for @snoozeReminderDescription.
  ///
  /// In en, this message translates to:
  /// **'Delay the reminder without changing the due date.'**
  String get snoozeReminderDescription;

  /// No description provided for @createArea.
  ///
  /// In en, this message translates to:
  /// **'Create area'**
  String get createArea;

  /// No description provided for @saveArea.
  ///
  /// In en, this message translates to:
  /// **'Save area'**
  String get saveArea;

  /// No description provided for @editZone.
  ///
  /// In en, this message translates to:
  /// **'Edit zone'**
  String get editZone;

  /// No description provided for @createZone.
  ///
  /// In en, this message translates to:
  /// **'Create zone'**
  String get createZone;

  /// No description provided for @saveZone.
  ///
  /// In en, this message translates to:
  /// **'Save zone'**
  String get saveZone;

  /// No description provided for @createRoom.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get createRoom;

  /// No description provided for @saveRoom.
  ///
  /// In en, this message translates to:
  /// **'Save room'**
  String get saveRoom;

  /// No description provided for @createItem.
  ///
  /// In en, this message translates to:
  /// **'Create item'**
  String get createItem;

  /// No description provided for @saveItem.
  ///
  /// In en, this message translates to:
  /// **'Save item'**
  String get saveItem;

  /// No description provided for @createTask.
  ///
  /// In en, this message translates to:
  /// **'Create task'**
  String get createTask;

  /// No description provided for @saveTask.
  ///
  /// In en, this message translates to:
  /// **'Save task'**
  String get saveTask;

  /// No description provided for @trackItemBody.
  ///
  /// In en, this message translates to:
  /// **'Track an item, where it lives, and its maintenance.'**
  String get trackItemBody;

  /// No description provided for @purchasedDate.
  ///
  /// In en, this message translates to:
  /// **'Purchased {date}'**
  String purchasedDate(String date);

  /// No description provided for @bornDate.
  ///
  /// In en, this message translates to:
  /// **'Born {date}'**
  String bornDate(String date);

  /// No description provided for @repottedDate.
  ///
  /// In en, this message translates to:
  /// **'Repotted {date}'**
  String repottedDate(String date);

  /// No description provided for @installedDateValue.
  ///
  /// In en, this message translates to:
  /// **'Installed {date}'**
  String installedDateValue(String date);

  /// No description provided for @expiresDate.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String expiresDate(String date);

  /// No description provided for @changeItemTypeWarning.
  ///
  /// In en, this message translates to:
  /// **'Type-specific fields from the previous type will not be saved.'**
  String get changeItemTypeWarning;

  /// No description provided for @maintenancePlansNeedItemBody.
  ///
  /// In en, this message translates to:
  /// **'Maintenance plans need an item so Owntend can organize the work.'**
  String get maintenancePlansNeedItemBody;

  /// No description provided for @planEditorIntro.
  ///
  /// In en, this message translates to:
  /// **'Set the cadence, priority, and next date for recurring work.'**
  String get planEditorIntro;

  /// No description provided for @petTypeDog.
  ///
  /// In en, this message translates to:
  /// **'Dog'**
  String get petTypeDog;

  /// No description provided for @petTypeCat.
  ///
  /// In en, this message translates to:
  /// **'Cat'**
  String get petTypeCat;

  /// No description provided for @petTypeFish.
  ///
  /// In en, this message translates to:
  /// **'Fish'**
  String get petTypeFish;

  /// No description provided for @petTypeBird.
  ///
  /// In en, this message translates to:
  /// **'Bird'**
  String get petTypeBird;

  /// No description provided for @petTypeRabbit.
  ///
  /// In en, this message translates to:
  /// **'Rabbit'**
  String get petTypeRabbit;

  /// No description provided for @petTypeReptile.
  ///
  /// In en, this message translates to:
  /// **'Reptile'**
  String get petTypeReptile;

  /// No description provided for @petTypeSmallMammal.
  ///
  /// In en, this message translates to:
  /// **'Small mammal'**
  String get petTypeSmallMammal;

  /// No description provided for @petTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get petTypeOther;

  /// No description provided for @fishTypeGoldfish.
  ///
  /// In en, this message translates to:
  /// **'Goldfish'**
  String get fishTypeGoldfish;

  /// No description provided for @fishTypeBetta.
  ///
  /// In en, this message translates to:
  /// **'Betta'**
  String get fishTypeBetta;

  /// No description provided for @fishTypeGuppy.
  ///
  /// In en, this message translates to:
  /// **'Guppy'**
  String get fishTypeGuppy;

  /// No description provided for @fishTypeTetra.
  ///
  /// In en, this message translates to:
  /// **'Tetra'**
  String get fishTypeTetra;

  /// No description provided for @fishTypeMolly.
  ///
  /// In en, this message translates to:
  /// **'Molly'**
  String get fishTypeMolly;

  /// No description provided for @fishTypePlaty.
  ///
  /// In en, this message translates to:
  /// **'Platy'**
  String get fishTypePlaty;

  /// No description provided for @fishTypeKoi.
  ///
  /// In en, this message translates to:
  /// **'Koi'**
  String get fishTypeKoi;

  /// No description provided for @accountSignOutBody.
  ///
  /// In en, this message translates to:
  /// **'Owntend requires Google sign-in. You will return to the sign-in screen until you authenticate again.'**
  String get accountSignOutBody;

  /// No description provided for @signedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out.'**
  String get signedOut;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your Owntend account, cloud data, private media, local app data, and app-private backups. Owntend will verify the signed-in Google account and only show Google\'\'s account chooser if silent verification is unavailable.'**
  String get deleteAccountBody;

  /// No description provided for @accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted.'**
  String get accountDeleted;

  /// No description provided for @accountDeletionFailed.
  ///
  /// In en, this message translates to:
  /// **'Account deletion could not be completed. Sign in again and retry.'**
  String get accountDeletionFailed;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @accountControls.
  ///
  /// In en, this message translates to:
  /// **'Account controls'**
  String get accountControls;

  /// No description provided for @accountControlsBody.
  ///
  /// In en, this message translates to:
  /// **'Account changes apply to your private Owntend data.'**
  String get accountControlsBody;

  /// No description provided for @onboardingHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Organize tasks, routines, and reminders\nacross all your devices, anytime.'**
  String get onboardingHeroSubtitle;

  /// No description provided for @yourDataStaysPrivateAndSecure.
  ///
  /// In en, this message translates to:
  /// **'Your data stays private and secure.'**
  String get yourDataStaysPrivateAndSecure;

  /// No description provided for @worksOnlineAndOffline.
  ///
  /// In en, this message translates to:
  /// **'Works online and offline'**
  String get worksOnlineAndOffline;

  /// No description provided for @restoreChannelName.
  ///
  /// In en, this message translates to:
  /// **'Owntend restoration'**
  String get restoreChannelName;

  /// No description provided for @restoreChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Shows real progress while Owntend restores protected data.'**
  String get restoreChannelDescription;

  /// No description provided for @restoringOwntend.
  ///
  /// In en, this message translates to:
  /// **'Restoring Owntend'**
  String get restoringOwntend;

  /// No description provided for @restoreNotificationProgress.
  ///
  /// In en, this message translates to:
  /// **'{percentage}% · {stage}'**
  String restoreNotificationProgress(int percentage, String stage);

  /// No description provided for @notificationChannelDueName.
  ///
  /// In en, this message translates to:
  /// **'Due reminders'**
  String get notificationChannelDueName;

  /// No description provided for @notificationChannelDueDescription.
  ///
  /// In en, this message translates to:
  /// **'Maintenance tasks that are due soon or today.'**
  String get notificationChannelDueDescription;

  /// No description provided for @notificationChannelOverdueName.
  ///
  /// In en, this message translates to:
  /// **'Overdue reminders'**
  String get notificationChannelOverdueName;

  /// No description provided for @notificationChannelOverdueDescription.
  ///
  /// In en, this message translates to:
  /// **'Maintenance tasks that are overdue.'**
  String get notificationChannelOverdueDescription;

  /// No description provided for @notificationChannelCriticalName.
  ///
  /// In en, this message translates to:
  /// **'Critical reminders'**
  String get notificationChannelCriticalName;

  /// No description provided for @notificationChannelCriticalDescription.
  ///
  /// In en, this message translates to:
  /// **'Critical safety or pet care maintenance reminders.'**
  String get notificationChannelCriticalDescription;

  /// No description provided for @notificationChannelDigestName.
  ///
  /// In en, this message translates to:
  /// **'Daily digests'**
  String get notificationChannelDigestName;

  /// No description provided for @notificationChannelDigestDescription.
  ///
  /// In en, this message translates to:
  /// **'Grouped maintenance summaries and reminder digests.'**
  String get notificationChannelDigestDescription;

  /// No description provided for @owntendReminderTicker.
  ///
  /// In en, this message translates to:
  /// **'Owntend reminder'**
  String get owntendReminderTicker;

  /// No description provided for @earnFreePoints.
  ///
  /// In en, this message translates to:
  /// **'Earn free points'**
  String get earnFreePoints;

  /// No description provided for @earnFreePointsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Watch an optional test-safe rewarded ad for 1 point.'**
  String get earnFreePointsSubtitle;

  /// No description provided for @privacyChoices.
  ///
  /// In en, this message translates to:
  /// **'Privacy choices'**
  String get privacyChoices;

  /// No description provided for @privacyChoicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review or change your advertising consent choices.'**
  String get privacyChoicesSubtitle;

  /// No description provided for @adInspector.
  ///
  /// In en, this message translates to:
  /// **'Ad Inspector'**
  String get adInspector;

  /// No description provided for @adInspectorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Launch Google\'\'s test-device ad troubleshooting overlay after consent and ads initialization.'**
  String get adInspectorSubtitle;

  /// No description provided for @adInspectorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Ad Inspector becomes available after consent and the ads SDK are ready on a test device.'**
  String get adInspectorUnavailable;

  /// No description provided for @adInspectorOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Ad Inspector could not be opened right now.'**
  String get adInspectorOpenFailed;

  /// No description provided for @todayCareComplete.
  ///
  /// In en, this message translates to:
  /// **'Today’s care is complete'**
  String get todayCareComplete;

  /// No description provided for @optionalDailyRewardDescription.
  ///
  /// In en, this message translates to:
  /// **'Watch a short video to earn 2 bonus points.'**
  String get optionalDailyRewardDescription;

  /// No description provided for @earnTwoPoints.
  ///
  /// In en, this message translates to:
  /// **'Earn 2 points'**
  String get earnTwoPoints;

  /// No description provided for @rewardWatchedVerifyingTwo.
  ///
  /// In en, this message translates to:
  /// **'Verifying your reward…'**
  String get rewardWatchedVerifyingTwo;

  /// No description provided for @noRewardAvailable.
  ///
  /// In en, this message translates to:
  /// **'No reward is available right now.'**
  String get noRewardAvailable;

  /// No description provided for @dailyRewardAlreadyClaimed.
  ///
  /// In en, this message translates to:
  /// **'Today’s completion reward was already claimed or is unavailable.'**
  String get dailyRewardAlreadyClaimed;

  /// No description provided for @pointsWallet.
  ///
  /// In en, this message translates to:
  /// **'Points wallet'**
  String get pointsWallet;

  /// No description provided for @pointsRuleExplanation.
  ///
  /// In en, this message translates to:
  /// **'Creating a new maintenance task costs 1 point. Creating items and safety tasks is always free. Completing and editing tasks never costs points.'**
  String get pointsRuleExplanation;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivity;

  /// No description provided for @activityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Activity unavailable'**
  String get activityUnavailable;

  /// No description provided for @noPointActivity.
  ///
  /// In en, this message translates to:
  /// **'No point activity yet.'**
  String get noPointActivity;

  /// No description provided for @startingPoints.
  ///
  /// In en, this message translates to:
  /// **'Starting points'**
  String get startingPoints;

  /// No description provided for @taskCreatedPointTransaction.
  ///
  /// In en, this message translates to:
  /// **'Task created'**
  String get taskCreatedPointTransaction;

  /// No description provided for @itemCreatedPointTransaction.
  ///
  /// In en, this message translates to:
  /// **'Item created'**
  String get itemCreatedPointTransaction;

  /// No description provided for @rewardedAdPointTransaction.
  ///
  /// In en, this message translates to:
  /// **'Rewarded ad'**
  String get rewardedAdPointTransaction;

  /// No description provided for @dailyCompletionReward.
  ///
  /// In en, this message translates to:
  /// **'Daily completion reward'**
  String get dailyCompletionReward;

  /// No description provided for @refundPointTransaction.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get refundPointTransaction;

  /// No description provided for @pointAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Point adjustment'**
  String get pointAdjustment;

  /// No description provided for @pointRewardsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Point rewards are temporarily unavailable.'**
  String get pointRewardsUnavailable;

  /// No description provided for @walletAlreadyFull.
  ///
  /// In en, this message translates to:
  /// **'Your wallet is already full.'**
  String get walletAlreadyFull;

  /// No description provided for @earnOnePoint.
  ///
  /// In en, this message translates to:
  /// **'Earn 1 point'**
  String get earnOnePoint;

  /// No description provided for @earnOnePointDescription.
  ///
  /// In en, this message translates to:
  /// **'Watch an optional rewarded ad. The point is added only after Owntend verifies Google’s server callback.'**
  String get earnOnePointDescription;

  /// No description provided for @watchAd.
  ///
  /// In en, this message translates to:
  /// **'Watch ad'**
  String get watchAd;

  /// No description provided for @loadingRewardedAd.
  ///
  /// In en, this message translates to:
  /// **'Loading rewarded ad…'**
  String get loadingRewardedAd;

  /// No description provided for @adWatchedVerifyingPoint.
  ///
  /// In en, this message translates to:
  /// **'Ad watched. Verifying your point securely…'**
  String get adWatchedVerifyingPoint;

  /// No description provided for @noRewardedAdAvailable.
  ///
  /// In en, this message translates to:
  /// **'No rewarded ad is available right now.'**
  String get noRewardedAdAvailable;

  /// No description provided for @rewardUnavailableOrClaimed.
  ///
  /// In en, this message translates to:
  /// **'This reward is not available yet or was already claimed today.'**
  String get rewardUnavailableOrClaimed;

  /// No description provided for @rewardAdClosedEarly.
  ///
  /// In en, this message translates to:
  /// **'Ad closed early. No points were added.'**
  String get rewardAdClosedEarly;

  /// No description provided for @rewardVerificationPending.
  ///
  /// In en, this message translates to:
  /// **'Reward verification is pending. Your confirmed balance will update automatically, even after reopening the app.'**
  String get rewardVerificationPending;

  /// No description provided for @needOnePoint.
  ///
  /// In en, this message translates to:
  /// **'You need 1 point'**
  String get needOnePoint;

  /// No description provided for @pointShortageDescription.
  ///
  /// In en, this message translates to:
  /// **'Your task draft is still here. Earn a free point with an optional rewarded ad, or switch the task to a safety category when that accurately describes it. Completing, editing, and deleting remain free.'**
  String get pointShortageDescription;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @earnAPoint.
  ///
  /// In en, this message translates to:
  /// **'Earn a point'**
  String get earnAPoint;

  /// No description provided for @offlineCopyDraftMessage.
  ///
  /// In en, this message translates to:
  /// **'This copy draft is kept open. Connect to create it securely.'**
  String get offlineCopyDraftMessage;

  /// No description provided for @offlineItemDraftMessage.
  ///
  /// In en, this message translates to:
  /// **'This draft is kept open. Connect to create the item securely.'**
  String get offlineItemDraftMessage;

  /// No description provided for @offlineTaskDraftMessage.
  ///
  /// In en, this message translates to:
  /// **'This draft is kept open. Connect to create the task securely.'**
  String get offlineTaskDraftMessage;

  /// No description provided for @pointsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Points unavailable'**
  String get pointsUnavailable;

  /// No description provided for @pointsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} points'**
  String pointsCount(int count);

  /// No description provided for @dashboardProductiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let\'\'s make today productive'**
  String get dashboardProductiveSubtitle;

  /// No description provided for @pointsLabel.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get pointsLabel;

  /// No description provided for @setUpYourHome.
  ///
  /// In en, this message translates to:
  /// **'Set up your home'**
  String get setUpYourHome;

  /// No description provided for @setupHomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Complete a few steps so we can build your maintenance plan.'**
  String get setupHomeSubtitle;

  /// No description provided for @setupProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed} of 3 complete'**
  String setupProgress(int completed);

  /// No description provided for @nextCreateFirstRoom.
  ///
  /// In en, this message translates to:
  /// **'Create your first room'**
  String get nextCreateFirstRoom;

  /// No description provided for @nextAddMaintainedItem.
  ///
  /// In en, this message translates to:
  /// **'Add an item you want to maintain'**
  String get nextAddMaintainedItem;

  /// No description provided for @nextScheduleMaintenanceTask.
  ///
  /// In en, this message translates to:
  /// **'Schedule your first maintenance task'**
  String get nextScheduleMaintenanceTask;

  /// No description provided for @getLocalMaintenanceTips.
  ///
  /// In en, this message translates to:
  /// **'Get local maintenance tips'**
  String get getLocalMaintenanceTips;

  /// No description provided for @locationEducationBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a city or use your current approximate location to show local weather for maintenance planning.'**
  String get locationEducationBody;

  /// No description provided for @locationEducationPrivacy.
  ///
  /// In en, this message translates to:
  /// **'If you use current location, Owntend saves an approximate home area. It does not continuously collect your location in the background.'**
  String get locationEducationPrivacy;

  /// No description provided for @enableLocation.
  ///
  /// In en, this message translates to:
  /// **'Enable location'**
  String get enableLocation;

  /// No description provided for @neverMissImportantMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Never miss important maintenance'**
  String get neverMissImportantMaintenance;

  /// No description provided for @notificationEducationBody.
  ///
  /// In en, this message translates to:
  /// **'Get reminders before tasks are due and alerts when something becomes overdue.'**
  String get notificationEducationBody;

  /// No description provided for @notificationEducationReassurance.
  ///
  /// In en, this message translates to:
  /// **'You can change notification preferences at any time.'**
  String get notificationEducationReassurance;

  /// No description provided for @enableNotificationsOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get enableNotificationsOnboarding;

  /// No description provided for @permissionStep.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String permissionStep(int current, int total);

  /// No description provided for @exactAlarmEducationTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep reminders on time'**
  String get exactAlarmEducationTitle;

  /// No description provided for @enableAlarmsAndRemindersOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Enable reminders'**
  String get enableAlarmsAndRemindersOnboarding;

  /// No description provided for @permissionSetup.
  ///
  /// In en, this message translates to:
  /// **'Permissions & setup'**
  String get permissionSetup;

  /// No description provided for @permissionSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a weather area, then control device reminders and optional precise timing.'**
  String get permissionSetupSubtitle;

  /// No description provided for @permissionsAlreadyEnabled.
  ///
  /// In en, this message translates to:
  /// **'Location, notifications, and reminders are already set up.'**
  String get permissionsAlreadyEnabled;

  /// No description provided for @permissionSetupFinishLater.
  ///
  /// In en, this message translates to:
  /// **'Finish later'**
  String get permissionSetupFinishLater;

  /// No description provided for @permissionSetupChooseLocation.
  ///
  /// In en, this message translates to:
  /// **'Choose location'**
  String get permissionSetupChooseLocation;

  /// No description provided for @permissionSetupUseCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Use current location'**
  String get permissionSetupUseCurrentLocation;

  /// No description provided for @permissionSetupWeatherTitle.
  ///
  /// In en, this message translates to:
  /// **'Set your weather area'**
  String get permissionSetupWeatherTitle;

  /// No description provided for @permissionSetupWeatherBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a city or use your current approximate location to show local weather for maintenance planning.'**
  String get permissionSetupWeatherBody;

  /// No description provided for @permissionSetupWeatherPrivacy.
  ///
  /// In en, this message translates to:
  /// **'If you use current location, Owntend saves an approximate home area. It does not continuously collect your location in the background.'**
  String get permissionSetupWeatherPrivacy;

  /// No description provided for @permissionSetupExactOptionalTitle.
  ///
  /// In en, this message translates to:
  /// **'Use precise reminder timing'**
  String get permissionSetupExactOptionalTitle;

  /// No description provided for @permissionSetupExactOptionalBody.
  ///
  /// In en, this message translates to:
  /// **'Android requires special access for reminders at the exact selected time. Without it, Owntend will use approximate timing.'**
  String get permissionSetupExactOptionalBody;

  /// No description provided for @permissionSetupUseApproximateTiming.
  ///
  /// In en, this message translates to:
  /// **'Use approximate timing'**
  String get permissionSetupUseApproximateTiming;

  /// No description provided for @permissionSetupAllowPreciseTiming.
  ///
  /// In en, this message translates to:
  /// **'Allow precise timing'**
  String get permissionSetupAllowPreciseTiming;

  /// No description provided for @permissionSetupManageInSettings.
  ///
  /// In en, this message translates to:
  /// **'Manage in settings'**
  String get permissionSetupManageInSettings;

  /// No description provided for @permissionSetupChangeLocation.
  ///
  /// In en, this message translates to:
  /// **'Change location'**
  String get permissionSetupChangeLocation;

  /// No description provided for @permissionSelectedArea.
  ///
  /// In en, this message translates to:
  /// **'Selected area: {area}'**
  String permissionSelectedArea(String area);

  /// No description provided for @permissionUsingCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Using current location'**
  String get permissionUsingCurrentLocation;

  /// No description provided for @weatherCurrentLocationShort.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get weatherCurrentLocationShort;

  /// No description provided for @permissionLocationAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'Location access is required to use the current location.'**
  String get permissionLocationAccessRequired;

  /// No description provided for @permissionNotificationAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'Android notification access is required for device reminders.'**
  String get permissionNotificationAccessRequired;

  /// No description provided for @permissionDeviceRemindersOff.
  ///
  /// In en, this message translates to:
  /// **'Device reminders are off in Owntend.'**
  String get permissionDeviceRemindersOff;

  /// No description provided for @permissionExactRequiresDeviceReminders.
  ///
  /// In en, this message translates to:
  /// **'Turn on device reminders before enabling precise timing.'**
  String get permissionExactRequiresDeviceReminders;

  /// No description provided for @permissionActionCouldNotComplete.
  ///
  /// In en, this message translates to:
  /// **'That action could not be completed. Try again.'**
  String get permissionActionCouldNotComplete;

  /// No description provided for @permissionSettingsCouldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Android settings could not be opened. Try again from device settings.'**
  String get permissionSettingsCouldNotOpen;

  /// No description provided for @owntendAlerts.
  ///
  /// In en, this message translates to:
  /// **'Owntend alerts'**
  String get owntendAlerts;

  /// No description provided for @owntendAlertsDescription.
  ///
  /// In en, this message translates to:
  /// **'Controls every Owntend alert channel. Device reminders still require Android access.'**
  String get owntendAlertsDescription;

  /// No description provided for @weatherAlertsInboxDescription.
  ///
  /// In en, this message translates to:
  /// **'Weather warnings shown in Owntend\'\'s inbox; device delivery follows the reminder setting.'**
  String get weatherAlertsInboxDescription;

  /// No description provided for @fix.
  ///
  /// In en, this message translates to:
  /// **'Fix'**
  String get fix;

  /// No description provided for @reminderDaysBeforeDue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{On the due date} =1{1 day before due} other{{count} days before due}}'**
  String reminderDaysBeforeDue(int count);

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String durationMinutes(int count);

  /// No description provided for @durationHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String durationHours(int count);

  /// No description provided for @recurrenceHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Every hour} other{Every {count} hours}}'**
  String recurrenceHours(int count);

  /// No description provided for @recurrenceDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Every day} other{Every {count} days}}'**
  String recurrenceDays(int count);

  /// No description provided for @recurrenceWeeks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Every week} other{Every {count} weeks}}'**
  String recurrenceWeeks(int count);

  /// No description provided for @recurrenceMonths.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Every month} other{Every {count} months}}'**
  String recurrenceMonths(int count);

  /// No description provided for @recurrenceYears.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Every year} other{Every {count} years}}'**
  String recurrenceYears(int count);
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
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
