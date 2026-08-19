from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1, found {count}")
    path.write_text(text.replace(old, new, 1))


monetization_path = Path("lib/src/features/monetization/monetization.dart")
owner_decl = (
    "final pointWalletProvider =\n"
    "    NotifierProvider<PointWalletController, AsyncValue<PointWallet?>>(\n"
    "      PointWalletController.new,\n"
    "    );"
)
owner_and_view = (
    "final pointWalletControllerProvider =\n"
    "    NotifierProvider<PointWalletController, AsyncValue<PointWallet?>>(\n"
    "      PointWalletController.new,\n"
    "    );\n\n"
    "/// Read-only wallet view kept as the stable presentation/test seam.\n"
    "/// State is owned only by [pointWalletControllerProvider].\n"
    "final pointWalletProvider = Provider<AsyncValue<PointWallet?>>((ref) {\n"
    "  return ref.watch(pointWalletControllerProvider);\n"
    "});"
)
replace_once(
    monetization_path,
    owner_decl,
    owner_and_view,
    "wallet owner/view provider split",
)
monetization_path.write_text(
    monetization_path.read_text().replace(
        "pointWalletProvider.notifier",
        "pointWalletControllerProvider.notifier",
    )
)


task_path = Path(
    "lib/src/features/maintenance/application/task_creation_controller.dart"
)
task_anchor = (
    "        // CTC-006 & CTC-007: Reconcile canonical creation composite before\n"
)
task_insert = (
    "        ref.read(pointWalletControllerProvider.notifier)"
    ".adoptAuthoritativeMutationResult(\n"
    "          result.balance,\n"
    "          userId: accountScope,\n"
    "        );\n\n"
    + task_anchor
)
replace_once(task_path, task_anchor, task_insert, "task balance adoption")

old_provider = (
    "  return ChargedOperationResolver(\n"
    "    monetizationRepo: monetizationRepo,\n"
    "    localSyncStore: localSyncStore,\n"
    "    operationStore: ref.watch(taskCreationOperationStoreProvider),\n"
    "  );"
)
new_provider = (
    "  return ChargedOperationResolver(\n"
    "    monetizationRepo: monetizationRepo,\n"
    "    localSyncStore: localSyncStore,\n"
    "    operationStore: ref.watch(taskCreationOperationStoreProvider),\n"
    "    adoptAuthoritativeBalance: (userId, balance) {\n"
    "      ref\n"
    "          .read(pointWalletControllerProvider.notifier)\n"
    "          .adoptAuthoritativeMutationResult(balance, userId: userId);\n"
    "    },\n"
    "  );"
)
replace_once(task_path, old_provider, new_provider, "resolver provider callback")


resolver_path = Path("lib/src/features/monetization/charged_operation_resolver.dart")
old_ctor = (
    "  ChargedOperationResolver({\n"
    "    required this.monetizationRepo,\n"
    "    required this.localSyncStore,\n"
    "    required this.operationStore,\n"
    "  });"
)
new_ctor = (
    "  ChargedOperationResolver({\n"
    "    required this.monetizationRepo,\n"
    "    required this.localSyncStore,\n"
    "    required this.operationStore,\n"
    "    required void Function(String userId, int balance) "
    "adoptAuthoritativeBalance,\n"
    "  }) : _adoptAuthoritativeBalance =\n"
    "           ((userId, balance) => "
    "adoptAuthoritativeBalance(userId, balance));"
)
replace_once(resolver_path, old_ctor, new_ctor, "resolver constructor")
field_anchor = "  final TaskCreationOperationStore operationStore;\n"
field_insert = (
    field_anchor
    + "  final void Function(String userId, int balance) "
    "_adoptAuthoritativeBalance;\n"
)
replace_once(resolver_path, field_anchor, field_insert, "resolver callback field")

completed_anchor = (
    "            continue;\n"
    "          }\n"
    "          if (op.requestPayload.containsKey('plan') || status.plan != null) {"
)
completed_insert = (
    "            continue;\n"
    "          }\n"
    "          if (status.balance case final balance?) {\n"
    "            _adoptAuthoritativeBalance(accountScope, balance);\n"
    "            if (!_accountIsCurrent(accountScope)) return;\n"
    "          }\n"
    "          if (op.requestPayload.containsKey('plan') || status.plan != null) {"
)
replace_once(
    resolver_path,
    completed_anchor,
    completed_insert,
    "completed recovery balance",
)

task_replay = (
    "                final result = await monetizationRepo.createTask(\n"
    "                  op.requestPayload,\n"
    "                );\n"
    "                if (!_accountIsCurrent(accountScope)) return;\n"
    "                await localSyncStore.reconcileTaskCreationComposite("
)
task_replay_insert = (
    "                final result = await monetizationRepo.createTask(\n"
    "                  op.requestPayload,\n"
    "                );\n"
    "                if (!_accountIsCurrent(accountScope)) return;\n"
    "                _adoptAuthoritativeBalance(accountScope, result.balance);\n"
    "                if (!_accountIsCurrent(accountScope)) return;\n"
    "                await localSyncStore.reconcileTaskCreationComposite("
)
replace_once(
    resolver_path,
    task_replay,
    task_replay_insert,
    "task replay balance",
)

asset_replay = (
    "                final result = await monetizationRepo.createAsset(\n"
    "                  op.requestPayload,\n"
    "                );\n"
    "                if (!_accountIsCurrent(accountScope)) return;\n"
    "                await localSyncStore.reconcileAssetCreationComposite("
)
asset_replay_insert = (
    "                final result = await monetizationRepo.createAsset(\n"
    "                  op.requestPayload,\n"
    "                );\n"
    "                if (!_accountIsCurrent(accountScope)) return;\n"
    "                _adoptAuthoritativeBalance(accountScope, result.balance);\n"
    "                if (!_accountIsCurrent(accountScope)) return;\n"
    "                await localSyncStore.reconcileAssetCreationComposite("
)
replace_once(
    resolver_path,
    asset_replay,
    asset_replay_insert,
    "asset replay balance",
)


asset_path = Path("lib/src/features/assets/presentation/asset_dialogs.dart")
copy_rpc = "              final debit = await monetization.createAsset({\n"
copy_rpc_new = (
    "              final walletUserId = monetization.currentUserId;\n"
    "              final debit = await monetization.createAsset({\n"
)
replace_once(asset_path, copy_rpc, copy_rpc_new, "copy wallet identity capture")
copy_after = "              });\n              if (debit.charged == 1) {"
copy_after_new = (
    "              });\n"
    "              if (walletUserId != null) {\n"
    "                ref\n"
    "                    .read(pointWalletControllerProvider.notifier)\n"
    "                    .adoptAuthoritativeMutationResult(\n"
    "                      debit.balance,\n"
    "                      userId: walletUserId,\n"
    "                    );\n"
    "              }\n"
    "              if (debit.charged == 1) {"
)
replace_once(asset_path, copy_after, copy_after_new, "copy balance adoption")

create_rpc = "        debitResult = await monetization.createAsset({\n"
create_rpc_new = (
    "        final walletUserId = monetization.currentUserId;\n"
    "        final debit = await monetization.createAsset({\n"
)
replace_once(asset_path, create_rpc, create_rpc_new, "create wallet identity capture")
create_after = (
    "          'initial_plans': const <Map<String, dynamic>>[],\n"
    "        });\n"
    "      }"
)
create_after_new = (
    "          'initial_plans': const <Map<String, dynamic>>[],\n"
    "        });\n"
    "        debitResult = debit;\n"
    "        if (walletUserId != null) {\n"
    "          ref\n"
    "              .read(pointWalletControllerProvider.notifier)\n"
    "              .adoptAuthoritativeMutationResult(\n"
    "                debit.balance,\n"
    "                userId: walletUserId,\n"
    "              );\n"
    "        }\n"
    "      }"
)
replace_once(asset_path, create_after, create_after_new, "create balance adoption")


wallet_test = Path("test/problem_007_wallet_sync_test.dart")
test_text = wallet_test.read_text().replace(
    "pointWalletProvider.notifier",
    "pointWalletControllerProvider.notifier",
)
test_text = test_text.replace("    this.userId = 'user-a',\n", "")
test_text = test_text.replace(
    "  String? userId;\n",
    "  String? userId = 'user-a';\n",
    1,
)
external_update = (
    "    repository.emit(_wallet(6, 3));\n"
    "    await tester.pump();\n"
    "    expect(find.text('6'), findsOneWidget);"
)
external_update_wait = (
    "    repository.emit(_wallet(6, 3));\n"
    "    await tester.pump();\n"
    "    await tester.pump();\n"
    "    expect(find.text('6'), findsOneWidget);"
)
if test_text.count(external_update) != 1:
    raise SystemExit("external wallet widget update anchor mismatch")
test_text = test_text.replace(external_update, external_update_wait, 1)
wallet_test.write_text(test_text)
