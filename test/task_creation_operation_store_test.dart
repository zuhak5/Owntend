import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_store.dart';
import 'package:owntend/src/core/services/charged_operation_journal/charged_operation_contracts.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  test('account cleanup removes only matching task operations', () async {
    final storage = _MockSecureStorage();
    final stored = <String, String>{};
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((invocation) async {
      stored[invocation.namedArguments[#key] as String] =
          invocation.namedArguments[#value] as String;
    });
    when(() => storage.readAll()).thenAnswer((_) async => Map.of(stored));
    when(() => storage.read(key: any(named: 'key'))).thenAnswer(
      (invocation) async => stored[invocation.namedArguments[#key] as String],
    );
    when(() => storage.delete(key: any(named: 'key')))
        .thenAnswer((invocation) async {
          stored.remove(invocation.namedArguments[#key] as String);
        });
    final store = TaskCreationOperationStore(storage: storage);

    await store.saveOperation(_operation('operation-a', 'account-a'));
    await store.saveOperation(_operation('operation-b', 'account-b'));
    await store.clearOperationsForAccount('account-a');

    expect(await store.listOperationsForAccount('account-a'), isEmpty);
    expect(
      (await store.listOperationsForAccount('account-b')).single.operationId,
      'operation-b',
    );
    verify(() => storage.delete(key: 'task_creation_op_v1_operation-a'))
        .called(1);
    verifyNever(() => storage.delete(key: 'task_creation_op_v1_operation-b'));
  });
}

TaskCreationOperation _operation(String id, String account) {
  final now = DateTime.utc(2026, 8, 9);
  return TaskCreationOperation(
    operationId: id,
    planId: 'plan-$id',
    accountScope: account,
    requestPayload: const {'title': 'Private task'},
    requestHash: 'hash-$id',
    state: TaskCreationOperationState.draft,
    createdAt: now,
    updatedAt: now,
  );
}
