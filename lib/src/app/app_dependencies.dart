/// The application composition surface.
///
/// Feature libraries import their narrow domain/application dependencies
/// directly. Bootstrap and tests may import this barrel when constructing the
/// complete Riverpod graph.
library;

export '../core/data/repositories.dart';
export '../core/database/app_database.dart' show databaseProvider;
export '../core/providers/app_providers.dart';
export '../core/sync/sync_providers.dart';
export '../features/auth/presentation/auth_providers.dart';
export '../features/permissions/application/permission_education_controller.dart'
    show
        devicePermissionGatewayProvider,
        permissionEducationControllerProvider,
        permissionEducationRepositoryProvider;
