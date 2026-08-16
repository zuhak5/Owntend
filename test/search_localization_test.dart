import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/data/repositories.dart';
import 'package:owntend/src/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late DriftSearchRepository repository;

  setUp(() async {
    db = AppDatabase(executor: NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    repository = DriftSearchRepository(db);
  });

  tearDown(() => db.close());

  test('Arabic category aliases find canonical categories without leaking aliases', () async {
    await repository.rebuildIndex();

    final results = await repository.search('تنظيف');
    final cleaning = results.singleWhere(
      (result) => result.entityId == 'category_cleaning',
    );

    expect(cleaning.entityType, 'category');
    expect(cleaning.title, 'Cleaning');
    expect(cleaning.snippet, isEmpty);
  });

  test('Arabic controlled type aliases find assets while display snippets stay user-authored', () async {
    await db.customStatement(
      "INSERT INTO areas(id, name, kind) VALUES ('search-area', 'Home', 'indoor')",
    );
    await db.customStatement(
      "INSERT INTO rooms(id, area_id, name, room_type) "
      "VALUES ('search-room', 'search-area', 'Kitchen', 'kitchen')",
    );
    await db.customStatement(
      "INSERT INTO assets(id, name, asset_type, category_id, room_id, notes) "
      "VALUES ('search-device', 'Purifier', 'device', "
      "'category_appliances', 'search-room', 'Quiet bedroom unit')",
    );

    await repository.rebuildIndex();

    final byArabicType = await repository.search('جهاز');
    final purifier = byArabicType.singleWhere(
      (result) => result.entityId == 'search-device',
    );
    expect(purifier.title, 'Purifier');
    expect(purifier.snippet, isEmpty);

    final byUserNote = await repository.search('Quiet');
    final noteMatch = byUserNote.singleWhere(
      (result) => result.entityId == 'search-device',
    );
    expect(noteMatch.snippet, contains('Quiet'));
    expect(noteMatch.snippet, isNot(contains('جهاز')));
    expect(noteMatch.snippet, isNot(contains('device appliance')));
  });
}
