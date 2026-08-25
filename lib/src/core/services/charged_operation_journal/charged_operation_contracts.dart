enum TaskCreationOperationState {
  draft,
  submitting,
  outcomeUnknown,
  serverAcceptedNeedsReconcile,
  permanentRejected,
  reconciled,
}

enum TaskCreationFailureCode {
  insufficientPoints,
  assetNotFound,
  invalidPayload,
  operationIdReused,
  networkTimeout,
  serverError,
  unauthenticated,
  draftSaveFailed,
  unknown,
}

class TaskCreationFailure implements Exception {
  const TaskCreationFailure(this.message, {required this.code});

  final String message;
  final TaskCreationFailureCode code;

  @override
  String toString() => message;
}

class TaskCreationOperation {
  const TaskCreationOperation({
    required this.operationId,
    required this.planId,
    required this.accountScope,
    required this.requestPayload,
    required this.requestHash,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  final String operationId;
  final String planId;
  final String accountScope;
  final Map<String, dynamic> requestPayload;
  final String requestHash;
  final TaskCreationOperationState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  TaskCreationOperation copyWith({
    TaskCreationOperationState? state,
    Map<String, dynamic>? requestPayload,
    DateTime? updatedAt,
    String? lastErrorCode,
    String? lastErrorMessage,
  }) {
    return TaskCreationOperation(
      operationId: operationId,
      planId: planId,
      accountScope: accountScope,
      requestPayload: requestPayload ?? this.requestPayload,
      requestHash: requestHash,
      state: state ?? this.state,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'operation_id': operationId,
      'plan_id': planId,
      'account_scope': accountScope,
      'request_payload': requestPayload,
      'request_hash': requestHash,
      'state': state.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
    };
  }

  factory TaskCreationOperation.fromJson(Map<String, dynamic> json) {
    return TaskCreationOperation(
      operationId: json['operation_id'] as String,
      planId: json['plan_id'] as String,
      accountScope: json['account_scope'] as String,
      requestPayload: Map<String, dynamic>.from(json['request_payload'] as Map),
      requestHash: json['request_hash'] as String,
      state: TaskCreationOperationState.values.byName(json['state'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastErrorCode: json['last_error_code'] as String?,
      lastErrorMessage: json['last_error_message'] as String?,
    );
  }
}
