// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $AreasTable extends Areas with TableInfo<$AreasTable, AreaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AreasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    kind,
    sortOrder,
    createdAt,
    updatedAt,
    archivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'areas';
  @override
  VerificationContext validateIntegrity(
    Insertable<AreaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AreaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AreaRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
    );
  }

  @override
  $AreasTable createAlias(String alias) {
    return $AreasTable(attachedDatabase, alias);
  }
}

class AreaRow extends DataClass implements Insertable<AreaRow> {
  final String id;
  final String name;
  final String kind;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  const AreaRow({
    required this.id,
    required this.name,
    required this.kind,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    return map;
  }

  AreasCompanion toCompanion(bool nullToAbsent) {
    return AreasCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
    );
  }

  factory AreaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AreaRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
    };
  }

  AreaRow copyWith({
    String? id,
    String? name,
    String? kind,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> archivedAt = const Value.absent(),
  }) => AreaRow(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
  );
  AreaRow copyWithCompanion(AreasCompanion data) {
    return AreaRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AreaRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, kind, sortOrder, createdAt, updatedAt, archivedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AreaRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.archivedAt == this.archivedAt);
}

class AreasCompanion extends UpdateCompanion<AreaRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> archivedAt;
  final Value<int> rowid;
  const AreasCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AreasCompanion.insert({
    required String id,
    required String name,
    required String kind,
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       kind = Value(kind);
  static Insertable<AreaRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AreasCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? kind,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? archivedAt,
    Value<int>? rowid,
  }) {
    return AreasCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AreasCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoomsTable extends Rooms with TableInfo<$RoomsTable, RoomRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaIdMeta = const VerificationMeta('areaId');
  @override
  late final GeneratedColumn<String> areaId = GeneratedColumn<String>(
    'area_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES areas (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomTypeMeta = const VerificationMeta(
    'roomType',
  );
  @override
  late final GeneratedColumn<String> roomType = GeneratedColumn<String>(
    'room_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('other'),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    areaId,
    name,
    roomType,
    notes,
    sortOrder,
    createdAt,
    updatedAt,
    archivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rooms';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoomRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('area_id')) {
      context.handle(
        _areaIdMeta,
        areaId.isAcceptableOrUnknown(data['area_id']!, _areaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_areaIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('room_type')) {
      context.handle(
        _roomTypeMeta,
        roomType.isAcceptableOrUnknown(data['room_type']!, _roomTypeMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {areaId, name},
  ];
  @override
  RoomRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoomRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      areaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      roomType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_type'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
    );
  }

  @override
  $RoomsTable createAlias(String alias) {
    return $RoomsTable(attachedDatabase, alias);
  }
}

class RoomRow extends DataClass implements Insertable<RoomRow> {
  final String id;
  final String areaId;
  final String name;
  final String roomType;
  final String? notes;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  const RoomRow({
    required this.id,
    required this.areaId,
    required this.name,
    required this.roomType,
    this.notes,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['area_id'] = Variable<String>(areaId);
    map['name'] = Variable<String>(name);
    map['room_type'] = Variable<String>(roomType);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    return map;
  }

  RoomsCompanion toCompanion(bool nullToAbsent) {
    return RoomsCompanion(
      id: Value(id),
      areaId: Value(areaId),
      name: Value(name),
      roomType: Value(roomType),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
    );
  }

  factory RoomRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoomRow(
      id: serializer.fromJson<String>(json['id']),
      areaId: serializer.fromJson<String>(json['areaId']),
      name: serializer.fromJson<String>(json['name']),
      roomType: serializer.fromJson<String>(json['roomType']),
      notes: serializer.fromJson<String?>(json['notes']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'areaId': serializer.toJson<String>(areaId),
      'name': serializer.toJson<String>(name),
      'roomType': serializer.toJson<String>(roomType),
      'notes': serializer.toJson<String?>(notes),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
    };
  }

  RoomRow copyWith({
    String? id,
    String? areaId,
    String? name,
    String? roomType,
    Value<String?> notes = const Value.absent(),
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> archivedAt = const Value.absent(),
  }) => RoomRow(
    id: id ?? this.id,
    areaId: areaId ?? this.areaId,
    name: name ?? this.name,
    roomType: roomType ?? this.roomType,
    notes: notes.present ? notes.value : this.notes,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
  );
  RoomRow copyWithCompanion(RoomsCompanion data) {
    return RoomRow(
      id: data.id.present ? data.id.value : this.id,
      areaId: data.areaId.present ? data.areaId.value : this.areaId,
      name: data.name.present ? data.name.value : this.name,
      roomType: data.roomType.present ? data.roomType.value : this.roomType,
      notes: data.notes.present ? data.notes.value : this.notes,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoomRow(')
          ..write('id: $id, ')
          ..write('areaId: $areaId, ')
          ..write('name: $name, ')
          ..write('roomType: $roomType, ')
          ..write('notes: $notes, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    areaId,
    name,
    roomType,
    notes,
    sortOrder,
    createdAt,
    updatedAt,
    archivedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoomRow &&
          other.id == this.id &&
          other.areaId == this.areaId &&
          other.name == this.name &&
          other.roomType == this.roomType &&
          other.notes == this.notes &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.archivedAt == this.archivedAt);
}

class RoomsCompanion extends UpdateCompanion<RoomRow> {
  final Value<String> id;
  final Value<String> areaId;
  final Value<String> name;
  final Value<String> roomType;
  final Value<String?> notes;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> archivedAt;
  final Value<int> rowid;
  const RoomsCompanion({
    this.id = const Value.absent(),
    this.areaId = const Value.absent(),
    this.name = const Value.absent(),
    this.roomType = const Value.absent(),
    this.notes = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomsCompanion.insert({
    required String id,
    required String areaId,
    required String name,
    this.roomType = const Value.absent(),
    this.notes = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       areaId = Value(areaId),
       name = Value(name);
  static Insertable<RoomRow> custom({
    Expression<String>? id,
    Expression<String>? areaId,
    Expression<String>? name,
    Expression<String>? roomType,
    Expression<String>? notes,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (areaId != null) 'area_id': areaId,
      if (name != null) 'name': name,
      if (roomType != null) 'room_type': roomType,
      if (notes != null) 'notes': notes,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomsCompanion copyWith({
    Value<String>? id,
    Value<String>? areaId,
    Value<String>? name,
    Value<String>? roomType,
    Value<String?>? notes,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? archivedAt,
    Value<int>? rowid,
  }) {
    return RoomsCompanion(
      id: id ?? this.id,
      areaId: areaId ?? this.areaId,
      name: name ?? this.name,
      roomType: roomType ?? this.roomType,
      notes: notes ?? this.notes,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (areaId.present) {
      map['area_id'] = Variable<String>(areaId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (roomType.present) {
      map['room_type'] = Variable<String>(roomType.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomsCompanion(')
          ..write('id: $id, ')
          ..write('areaId: $areaId, ')
          ..write('name: $name, ')
          ..write('roomType: $roomType, ')
          ..write('notes: $notes, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssetsTable extends Assets with TableInfo<$AssetsTable, AssetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetTypeMeta = const VerificationMeta(
    'assetType',
  );
  @override
  late final GeneratedColumn<String> assetType = GeneratedColumn<String>(
    'asset_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('general'),
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES rooms (id)',
    ),
  );
  static const VerificationMeta _placementMeta = const VerificationMeta(
    'placement',
  );
  @override
  late final GeneratedColumn<String> placement = GeneratedColumn<String>(
    'placement',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _purchaseDateMeta = const VerificationMeta(
    'purchaseDate',
  );
  @override
  late final GeneratedColumn<DateTime> purchaseDate = GeneratedColumn<DateTime>(
    'purchase_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    assetType,
    roomId,
    placement,
    notes,
    purchaseDate,
    createdAt,
    updatedAt,
    archivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('asset_type')) {
      context.handle(
        _assetTypeMeta,
        assetType.isAcceptableOrUnknown(data['asset_type']!, _assetTypeMeta),
      );
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('placement')) {
      context.handle(
        _placementMeta,
        placement.isAcceptableOrUnknown(data['placement']!, _placementMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('purchase_date')) {
      context.handle(
        _purchaseDateMeta,
        purchaseDate.isAcceptableOrUnknown(
          data['purchase_date']!,
          _purchaseDateMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      assetType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_type'],
      )!,
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      placement: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}placement'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      purchaseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}purchase_date'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
    );
  }

  @override
  $AssetsTable createAlias(String alias) {
    return $AssetsTable(attachedDatabase, alias);
  }
}

class AssetRow extends DataClass implements Insertable<AssetRow> {
  final String id;
  final String name;
  final String assetType;
  final String roomId;
  final String? placement;
  final String? notes;
  final DateTime? purchaseDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  const AssetRow({
    required this.id,
    required this.name,
    required this.assetType,
    required this.roomId,
    this.placement,
    this.notes,
    this.purchaseDate,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['asset_type'] = Variable<String>(assetType);
    map['room_id'] = Variable<String>(roomId);
    if (!nullToAbsent || placement != null) {
      map['placement'] = Variable<String>(placement);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || purchaseDate != null) {
      map['purchase_date'] = Variable<DateTime>(purchaseDate);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    return map;
  }

  AssetsCompanion toCompanion(bool nullToAbsent) {
    return AssetsCompanion(
      id: Value(id),
      name: Value(name),
      assetType: Value(assetType),
      roomId: Value(roomId),
      placement: placement == null && nullToAbsent
          ? const Value.absent()
          : Value(placement),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      purchaseDate: purchaseDate == null && nullToAbsent
          ? const Value.absent()
          : Value(purchaseDate),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
    );
  }

  factory AssetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      assetType: serializer.fromJson<String>(json['assetType']),
      roomId: serializer.fromJson<String>(json['roomId']),
      placement: serializer.fromJson<String?>(json['placement']),
      notes: serializer.fromJson<String?>(json['notes']),
      purchaseDate: serializer.fromJson<DateTime?>(json['purchaseDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'assetType': serializer.toJson<String>(assetType),
      'roomId': serializer.toJson<String>(roomId),
      'placement': serializer.toJson<String?>(placement),
      'notes': serializer.toJson<String?>(notes),
      'purchaseDate': serializer.toJson<DateTime?>(purchaseDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
    };
  }

  AssetRow copyWith({
    String? id,
    String? name,
    String? assetType,
    String? roomId,
    Value<String?> placement = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<DateTime?> purchaseDate = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> archivedAt = const Value.absent(),
  }) => AssetRow(
    id: id ?? this.id,
    name: name ?? this.name,
    assetType: assetType ?? this.assetType,
    roomId: roomId ?? this.roomId,
    placement: placement.present ? placement.value : this.placement,
    notes: notes.present ? notes.value : this.notes,
    purchaseDate: purchaseDate.present ? purchaseDate.value : this.purchaseDate,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
  );
  AssetRow copyWithCompanion(AssetsCompanion data) {
    return AssetRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      assetType: data.assetType.present ? data.assetType.value : this.assetType,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      placement: data.placement.present ? data.placement.value : this.placement,
      notes: data.notes.present ? data.notes.value : this.notes,
      purchaseDate: data.purchaseDate.present
          ? data.purchaseDate.value
          : this.purchaseDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('assetType: $assetType, ')
          ..write('roomId: $roomId, ')
          ..write('placement: $placement, ')
          ..write('notes: $notes, ')
          ..write('purchaseDate: $purchaseDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    assetType,
    roomId,
    placement,
    notes,
    purchaseDate,
    createdAt,
    updatedAt,
    archivedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.assetType == this.assetType &&
          other.roomId == this.roomId &&
          other.placement == this.placement &&
          other.notes == this.notes &&
          other.purchaseDate == this.purchaseDate &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.archivedAt == this.archivedAt);
}

class AssetsCompanion extends UpdateCompanion<AssetRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> assetType;
  final Value<String> roomId;
  final Value<String?> placement;
  final Value<String?> notes;
  final Value<DateTime?> purchaseDate;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> archivedAt;
  final Value<int> rowid;
  const AssetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.assetType = const Value.absent(),
    this.roomId = const Value.absent(),
    this.placement = const Value.absent(),
    this.notes = const Value.absent(),
    this.purchaseDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssetsCompanion.insert({
    required String id,
    required String name,
    this.assetType = const Value.absent(),
    required String roomId,
    this.placement = const Value.absent(),
    this.notes = const Value.absent(),
    this.purchaseDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       roomId = Value(roomId);
  static Insertable<AssetRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? assetType,
    Expression<String>? roomId,
    Expression<String>? placement,
    Expression<String>? notes,
    Expression<DateTime>? purchaseDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (assetType != null) 'asset_type': assetType,
      if (roomId != null) 'room_id': roomId,
      if (placement != null) 'placement': placement,
      if (notes != null) 'notes': notes,
      if (purchaseDate != null) 'purchase_date': purchaseDate,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? assetType,
    Value<String>? roomId,
    Value<String?>? placement,
    Value<String?>? notes,
    Value<DateTime?>? purchaseDate,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? archivedAt,
    Value<int>? rowid,
  }) {
    return AssetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      assetType: assetType ?? this.assetType,
      roomId: roomId ?? this.roomId,
      placement: placement ?? this.placement,
      notes: notes ?? this.notes,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (assetType.present) {
      map['asset_type'] = Variable<String>(assetType.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (placement.present) {
      map['placement'] = Variable<String>(placement.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (purchaseDate.present) {
      map['purchase_date'] = Variable<DateTime>(purchaseDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('assetType: $assetType, ')
          ..write('roomId: $roomId, ')
          ..write('placement: $placement, ')
          ..write('notes: $notes, ')
          ..write('purchaseDate: $purchaseDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeviceDetailsTableTable extends DeviceDetailsTable
    with TableInfo<$DeviceDetailsTableTable, DeviceDetailRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceDetailsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assets (id)',
    ),
  );
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serialNumberMeta = const VerificationMeta(
    'serialNumber',
  );
  @override
  late final GeneratedColumn<String> serialNumber = GeneratedColumn<String>(
    'serial_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _powerSourceMeta = const VerificationMeta(
    'powerSource',
  );
  @override
  late final GeneratedColumn<String> powerSource = GeneratedColumn<String>(
    'power_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _warrantyUntilMeta = const VerificationMeta(
    'warrantyUntil',
  );
  @override
  late final GeneratedColumn<DateTime> warrantyUntil =
      GeneratedColumn<DateTime>(
        'warranty_until',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _manualUrlMeta = const VerificationMeta(
    'manualUrl',
  );
  @override
  late final GeneratedColumn<String> manualUrl = GeneratedColumn<String>(
    'manual_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _consumableMeta = const VerificationMeta(
    'consumable',
  );
  @override
  late final GeneratedColumn<String> consumable = GeneratedColumn<String>(
    'consumable',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    assetId,
    brand,
    model,
    serialNumber,
    powerSource,
    warrantyUntil,
    manualUrl,
    consumable,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_details';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceDetailRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('serial_number')) {
      context.handle(
        _serialNumberMeta,
        serialNumber.isAcceptableOrUnknown(
          data['serial_number']!,
          _serialNumberMeta,
        ),
      );
    }
    if (data.containsKey('power_source')) {
      context.handle(
        _powerSourceMeta,
        powerSource.isAcceptableOrUnknown(
          data['power_source']!,
          _powerSourceMeta,
        ),
      );
    }
    if (data.containsKey('warranty_until')) {
      context.handle(
        _warrantyUntilMeta,
        warrantyUntil.isAcceptableOrUnknown(
          data['warranty_until']!,
          _warrantyUntilMeta,
        ),
      );
    }
    if (data.containsKey('manual_url')) {
      context.handle(
        _manualUrlMeta,
        manualUrl.isAcceptableOrUnknown(data['manual_url']!, _manualUrlMeta),
      );
    }
    if (data.containsKey('consumable')) {
      context.handle(
        _consumableMeta,
        consumable.isAcceptableOrUnknown(data['consumable']!, _consumableMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assetId};
  @override
  DeviceDetailRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceDetailRow(
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      serialNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}serial_number'],
      ),
      powerSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}power_source'],
      ),
      warrantyUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}warranty_until'],
      ),
      manualUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manual_url'],
      ),
      consumable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consumable'],
      ),
    );
  }

  @override
  $DeviceDetailsTableTable createAlias(String alias) {
    return $DeviceDetailsTableTable(attachedDatabase, alias);
  }
}

class DeviceDetailRow extends DataClass implements Insertable<DeviceDetailRow> {
  final String assetId;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final String? powerSource;
  final DateTime? warrantyUntil;
  final String? manualUrl;
  final String? consumable;
  const DeviceDetailRow({
    required this.assetId,
    this.brand,
    this.model,
    this.serialNumber,
    this.powerSource,
    this.warrantyUntil,
    this.manualUrl,
    this.consumable,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['asset_id'] = Variable<String>(assetId);
    if (!nullToAbsent || brand != null) {
      map['brand'] = Variable<String>(brand);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    if (!nullToAbsent || serialNumber != null) {
      map['serial_number'] = Variable<String>(serialNumber);
    }
    if (!nullToAbsent || powerSource != null) {
      map['power_source'] = Variable<String>(powerSource);
    }
    if (!nullToAbsent || warrantyUntil != null) {
      map['warranty_until'] = Variable<DateTime>(warrantyUntil);
    }
    if (!nullToAbsent || manualUrl != null) {
      map['manual_url'] = Variable<String>(manualUrl);
    }
    if (!nullToAbsent || consumable != null) {
      map['consumable'] = Variable<String>(consumable);
    }
    return map;
  }

  DeviceDetailsTableCompanion toCompanion(bool nullToAbsent) {
    return DeviceDetailsTableCompanion(
      assetId: Value(assetId),
      brand: brand == null && nullToAbsent
          ? const Value.absent()
          : Value(brand),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      serialNumber: serialNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(serialNumber),
      powerSource: powerSource == null && nullToAbsent
          ? const Value.absent()
          : Value(powerSource),
      warrantyUntil: warrantyUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(warrantyUntil),
      manualUrl: manualUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(manualUrl),
      consumable: consumable == null && nullToAbsent
          ? const Value.absent()
          : Value(consumable),
    );
  }

  factory DeviceDetailRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceDetailRow(
      assetId: serializer.fromJson<String>(json['assetId']),
      brand: serializer.fromJson<String?>(json['brand']),
      model: serializer.fromJson<String?>(json['model']),
      serialNumber: serializer.fromJson<String?>(json['serialNumber']),
      powerSource: serializer.fromJson<String?>(json['powerSource']),
      warrantyUntil: serializer.fromJson<DateTime?>(json['warrantyUntil']),
      manualUrl: serializer.fromJson<String?>(json['manualUrl']),
      consumable: serializer.fromJson<String?>(json['consumable']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assetId': serializer.toJson<String>(assetId),
      'brand': serializer.toJson<String?>(brand),
      'model': serializer.toJson<String?>(model),
      'serialNumber': serializer.toJson<String?>(serialNumber),
      'powerSource': serializer.toJson<String?>(powerSource),
      'warrantyUntil': serializer.toJson<DateTime?>(warrantyUntil),
      'manualUrl': serializer.toJson<String?>(manualUrl),
      'consumable': serializer.toJson<String?>(consumable),
    };
  }

  DeviceDetailRow copyWith({
    String? assetId,
    Value<String?> brand = const Value.absent(),
    Value<String?> model = const Value.absent(),
    Value<String?> serialNumber = const Value.absent(),
    Value<String?> powerSource = const Value.absent(),
    Value<DateTime?> warrantyUntil = const Value.absent(),
    Value<String?> manualUrl = const Value.absent(),
    Value<String?> consumable = const Value.absent(),
  }) => DeviceDetailRow(
    assetId: assetId ?? this.assetId,
    brand: brand.present ? brand.value : this.brand,
    model: model.present ? model.value : this.model,
    serialNumber: serialNumber.present ? serialNumber.value : this.serialNumber,
    powerSource: powerSource.present ? powerSource.value : this.powerSource,
    warrantyUntil: warrantyUntil.present
        ? warrantyUntil.value
        : this.warrantyUntil,
    manualUrl: manualUrl.present ? manualUrl.value : this.manualUrl,
    consumable: consumable.present ? consumable.value : this.consumable,
  );
  DeviceDetailRow copyWithCompanion(DeviceDetailsTableCompanion data) {
    return DeviceDetailRow(
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      brand: data.brand.present ? data.brand.value : this.brand,
      model: data.model.present ? data.model.value : this.model,
      serialNumber: data.serialNumber.present
          ? data.serialNumber.value
          : this.serialNumber,
      powerSource: data.powerSource.present
          ? data.powerSource.value
          : this.powerSource,
      warrantyUntil: data.warrantyUntil.present
          ? data.warrantyUntil.value
          : this.warrantyUntil,
      manualUrl: data.manualUrl.present ? data.manualUrl.value : this.manualUrl,
      consumable: data.consumable.present
          ? data.consumable.value
          : this.consumable,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceDetailRow(')
          ..write('assetId: $assetId, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('serialNumber: $serialNumber, ')
          ..write('powerSource: $powerSource, ')
          ..write('warrantyUntil: $warrantyUntil, ')
          ..write('manualUrl: $manualUrl, ')
          ..write('consumable: $consumable')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    assetId,
    brand,
    model,
    serialNumber,
    powerSource,
    warrantyUntil,
    manualUrl,
    consumable,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceDetailRow &&
          other.assetId == this.assetId &&
          other.brand == this.brand &&
          other.model == this.model &&
          other.serialNumber == this.serialNumber &&
          other.powerSource == this.powerSource &&
          other.warrantyUntil == this.warrantyUntil &&
          other.manualUrl == this.manualUrl &&
          other.consumable == this.consumable);
}

class DeviceDetailsTableCompanion extends UpdateCompanion<DeviceDetailRow> {
  final Value<String> assetId;
  final Value<String?> brand;
  final Value<String?> model;
  final Value<String?> serialNumber;
  final Value<String?> powerSource;
  final Value<DateTime?> warrantyUntil;
  final Value<String?> manualUrl;
  final Value<String?> consumable;
  final Value<int> rowid;
  const DeviceDetailsTableCompanion({
    this.assetId = const Value.absent(),
    this.brand = const Value.absent(),
    this.model = const Value.absent(),
    this.serialNumber = const Value.absent(),
    this.powerSource = const Value.absent(),
    this.warrantyUntil = const Value.absent(),
    this.manualUrl = const Value.absent(),
    this.consumable = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeviceDetailsTableCompanion.insert({
    required String assetId,
    this.brand = const Value.absent(),
    this.model = const Value.absent(),
    this.serialNumber = const Value.absent(),
    this.powerSource = const Value.absent(),
    this.warrantyUntil = const Value.absent(),
    this.manualUrl = const Value.absent(),
    this.consumable = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : assetId = Value(assetId);
  static Insertable<DeviceDetailRow> custom({
    Expression<String>? assetId,
    Expression<String>? brand,
    Expression<String>? model,
    Expression<String>? serialNumber,
    Expression<String>? powerSource,
    Expression<DateTime>? warrantyUntil,
    Expression<String>? manualUrl,
    Expression<String>? consumable,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assetId != null) 'asset_id': assetId,
      if (brand != null) 'brand': brand,
      if (model != null) 'model': model,
      if (serialNumber != null) 'serial_number': serialNumber,
      if (powerSource != null) 'power_source': powerSource,
      if (warrantyUntil != null) 'warranty_until': warrantyUntil,
      if (manualUrl != null) 'manual_url': manualUrl,
      if (consumable != null) 'consumable': consumable,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeviceDetailsTableCompanion copyWith({
    Value<String>? assetId,
    Value<String?>? brand,
    Value<String?>? model,
    Value<String?>? serialNumber,
    Value<String?>? powerSource,
    Value<DateTime?>? warrantyUntil,
    Value<String?>? manualUrl,
    Value<String?>? consumable,
    Value<int>? rowid,
  }) {
    return DeviceDetailsTableCompanion(
      assetId: assetId ?? this.assetId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      serialNumber: serialNumber ?? this.serialNumber,
      powerSource: powerSource ?? this.powerSource,
      warrantyUntil: warrantyUntil ?? this.warrantyUntil,
      manualUrl: manualUrl ?? this.manualUrl,
      consumable: consumable ?? this.consumable,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (serialNumber.present) {
      map['serial_number'] = Variable<String>(serialNumber.value);
    }
    if (powerSource.present) {
      map['power_source'] = Variable<String>(powerSource.value);
    }
    if (warrantyUntil.present) {
      map['warranty_until'] = Variable<DateTime>(warrantyUntil.value);
    }
    if (manualUrl.present) {
      map['manual_url'] = Variable<String>(manualUrl.value);
    }
    if (consumable.present) {
      map['consumable'] = Variable<String>(consumable.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceDetailsTableCompanion(')
          ..write('assetId: $assetId, ')
          ..write('brand: $brand, ')
          ..write('model: $model, ')
          ..write('serialNumber: $serialNumber, ')
          ..write('powerSource: $powerSource, ')
          ..write('warrantyUntil: $warrantyUntil, ')
          ..write('manualUrl: $manualUrl, ')
          ..write('consumable: $consumable, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PetDetailsTableTable extends PetDetailsTable
    with TableInfo<$PetDetailsTableTable, PetDetailRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PetDetailsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assets (id)',
    ),
  );
  static const VerificationMeta _speciesMeta = const VerificationMeta(
    'species',
  );
  @override
  late final GeneratedColumn<String> species = GeneratedColumn<String>(
    'species',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _breedMeta = const VerificationMeta('breed');
  @override
  late final GeneratedColumn<String> breed = GeneratedColumn<String>(
    'breed',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _birthDateMeta = const VerificationMeta(
    'birthDate',
  );
  @override
  late final GeneratedColumn<DateTime> birthDate = GeneratedColumn<DateTime>(
    'birth_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _microchipIdMeta = const VerificationMeta(
    'microchipId',
  );
  @override
  late final GeneratedColumn<String> microchipId = GeneratedColumn<String>(
    'microchip_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vetNameMeta = const VerificationMeta(
    'vetName',
  );
  @override
  late final GeneratedColumn<String> vetName = GeneratedColumn<String>(
    'vet_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vetPhoneMeta = const VerificationMeta(
    'vetPhone',
  );
  @override
  late final GeneratedColumn<String> vetPhone = GeneratedColumn<String>(
    'vet_phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _feedingNotesMeta = const VerificationMeta(
    'feedingNotes',
  );
  @override
  late final GeneratedColumn<String> feedingNotes = GeneratedColumn<String>(
    'feeding_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _medicalNotesMeta = const VerificationMeta(
    'medicalNotes',
  );
  @override
  late final GeneratedColumn<String> medicalNotes = GeneratedColumn<String>(
    'medical_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    assetId,
    species,
    breed,
    birthDate,
    microchipId,
    vetName,
    vetPhone,
    feedingNotes,
    medicalNotes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pet_details';
  @override
  VerificationContext validateIntegrity(
    Insertable<PetDetailRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('species')) {
      context.handle(
        _speciesMeta,
        species.isAcceptableOrUnknown(data['species']!, _speciesMeta),
      );
    }
    if (data.containsKey('breed')) {
      context.handle(
        _breedMeta,
        breed.isAcceptableOrUnknown(data['breed']!, _breedMeta),
      );
    }
    if (data.containsKey('birth_date')) {
      context.handle(
        _birthDateMeta,
        birthDate.isAcceptableOrUnknown(data['birth_date']!, _birthDateMeta),
      );
    }
    if (data.containsKey('microchip_id')) {
      context.handle(
        _microchipIdMeta,
        microchipId.isAcceptableOrUnknown(
          data['microchip_id']!,
          _microchipIdMeta,
        ),
      );
    }
    if (data.containsKey('vet_name')) {
      context.handle(
        _vetNameMeta,
        vetName.isAcceptableOrUnknown(data['vet_name']!, _vetNameMeta),
      );
    }
    if (data.containsKey('vet_phone')) {
      context.handle(
        _vetPhoneMeta,
        vetPhone.isAcceptableOrUnknown(data['vet_phone']!, _vetPhoneMeta),
      );
    }
    if (data.containsKey('feeding_notes')) {
      context.handle(
        _feedingNotesMeta,
        feedingNotes.isAcceptableOrUnknown(
          data['feeding_notes']!,
          _feedingNotesMeta,
        ),
      );
    }
    if (data.containsKey('medical_notes')) {
      context.handle(
        _medicalNotesMeta,
        medicalNotes.isAcceptableOrUnknown(
          data['medical_notes']!,
          _medicalNotesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assetId};
  @override
  PetDetailRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PetDetailRow(
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      species: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}species'],
      ),
      breed: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}breed'],
      ),
      birthDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}birth_date'],
      ),
      microchipId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}microchip_id'],
      ),
      vetName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vet_name'],
      ),
      vetPhone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vet_phone'],
      ),
      feedingNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}feeding_notes'],
      ),
      medicalNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}medical_notes'],
      ),
    );
  }

  @override
  $PetDetailsTableTable createAlias(String alias) {
    return $PetDetailsTableTable(attachedDatabase, alias);
  }
}

class PetDetailRow extends DataClass implements Insertable<PetDetailRow> {
  final String assetId;
  final String? species;
  final String? breed;
  final DateTime? birthDate;
  final String? microchipId;
  final String? vetName;
  final String? vetPhone;
  final String? feedingNotes;
  final String? medicalNotes;
  const PetDetailRow({
    required this.assetId,
    this.species,
    this.breed,
    this.birthDate,
    this.microchipId,
    this.vetName,
    this.vetPhone,
    this.feedingNotes,
    this.medicalNotes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['asset_id'] = Variable<String>(assetId);
    if (!nullToAbsent || species != null) {
      map['species'] = Variable<String>(species);
    }
    if (!nullToAbsent || breed != null) {
      map['breed'] = Variable<String>(breed);
    }
    if (!nullToAbsent || birthDate != null) {
      map['birth_date'] = Variable<DateTime>(birthDate);
    }
    if (!nullToAbsent || microchipId != null) {
      map['microchip_id'] = Variable<String>(microchipId);
    }
    if (!nullToAbsent || vetName != null) {
      map['vet_name'] = Variable<String>(vetName);
    }
    if (!nullToAbsent || vetPhone != null) {
      map['vet_phone'] = Variable<String>(vetPhone);
    }
    if (!nullToAbsent || feedingNotes != null) {
      map['feeding_notes'] = Variable<String>(feedingNotes);
    }
    if (!nullToAbsent || medicalNotes != null) {
      map['medical_notes'] = Variable<String>(medicalNotes);
    }
    return map;
  }

  PetDetailsTableCompanion toCompanion(bool nullToAbsent) {
    return PetDetailsTableCompanion(
      assetId: Value(assetId),
      species: species == null && nullToAbsent
          ? const Value.absent()
          : Value(species),
      breed: breed == null && nullToAbsent
          ? const Value.absent()
          : Value(breed),
      birthDate: birthDate == null && nullToAbsent
          ? const Value.absent()
          : Value(birthDate),
      microchipId: microchipId == null && nullToAbsent
          ? const Value.absent()
          : Value(microchipId),
      vetName: vetName == null && nullToAbsent
          ? const Value.absent()
          : Value(vetName),
      vetPhone: vetPhone == null && nullToAbsent
          ? const Value.absent()
          : Value(vetPhone),
      feedingNotes: feedingNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(feedingNotes),
      medicalNotes: medicalNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(medicalNotes),
    );
  }

  factory PetDetailRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PetDetailRow(
      assetId: serializer.fromJson<String>(json['assetId']),
      species: serializer.fromJson<String?>(json['species']),
      breed: serializer.fromJson<String?>(json['breed']),
      birthDate: serializer.fromJson<DateTime?>(json['birthDate']),
      microchipId: serializer.fromJson<String?>(json['microchipId']),
      vetName: serializer.fromJson<String?>(json['vetName']),
      vetPhone: serializer.fromJson<String?>(json['vetPhone']),
      feedingNotes: serializer.fromJson<String?>(json['feedingNotes']),
      medicalNotes: serializer.fromJson<String?>(json['medicalNotes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assetId': serializer.toJson<String>(assetId),
      'species': serializer.toJson<String?>(species),
      'breed': serializer.toJson<String?>(breed),
      'birthDate': serializer.toJson<DateTime?>(birthDate),
      'microchipId': serializer.toJson<String?>(microchipId),
      'vetName': serializer.toJson<String?>(vetName),
      'vetPhone': serializer.toJson<String?>(vetPhone),
      'feedingNotes': serializer.toJson<String?>(feedingNotes),
      'medicalNotes': serializer.toJson<String?>(medicalNotes),
    };
  }

  PetDetailRow copyWith({
    String? assetId,
    Value<String?> species = const Value.absent(),
    Value<String?> breed = const Value.absent(),
    Value<DateTime?> birthDate = const Value.absent(),
    Value<String?> microchipId = const Value.absent(),
    Value<String?> vetName = const Value.absent(),
    Value<String?> vetPhone = const Value.absent(),
    Value<String?> feedingNotes = const Value.absent(),
    Value<String?> medicalNotes = const Value.absent(),
  }) => PetDetailRow(
    assetId: assetId ?? this.assetId,
    species: species.present ? species.value : this.species,
    breed: breed.present ? breed.value : this.breed,
    birthDate: birthDate.present ? birthDate.value : this.birthDate,
    microchipId: microchipId.present ? microchipId.value : this.microchipId,
    vetName: vetName.present ? vetName.value : this.vetName,
    vetPhone: vetPhone.present ? vetPhone.value : this.vetPhone,
    feedingNotes: feedingNotes.present ? feedingNotes.value : this.feedingNotes,
    medicalNotes: medicalNotes.present ? medicalNotes.value : this.medicalNotes,
  );
  PetDetailRow copyWithCompanion(PetDetailsTableCompanion data) {
    return PetDetailRow(
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      species: data.species.present ? data.species.value : this.species,
      breed: data.breed.present ? data.breed.value : this.breed,
      birthDate: data.birthDate.present ? data.birthDate.value : this.birthDate,
      microchipId: data.microchipId.present
          ? data.microchipId.value
          : this.microchipId,
      vetName: data.vetName.present ? data.vetName.value : this.vetName,
      vetPhone: data.vetPhone.present ? data.vetPhone.value : this.vetPhone,
      feedingNotes: data.feedingNotes.present
          ? data.feedingNotes.value
          : this.feedingNotes,
      medicalNotes: data.medicalNotes.present
          ? data.medicalNotes.value
          : this.medicalNotes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PetDetailRow(')
          ..write('assetId: $assetId, ')
          ..write('species: $species, ')
          ..write('breed: $breed, ')
          ..write('birthDate: $birthDate, ')
          ..write('microchipId: $microchipId, ')
          ..write('vetName: $vetName, ')
          ..write('vetPhone: $vetPhone, ')
          ..write('feedingNotes: $feedingNotes, ')
          ..write('medicalNotes: $medicalNotes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    assetId,
    species,
    breed,
    birthDate,
    microchipId,
    vetName,
    vetPhone,
    feedingNotes,
    medicalNotes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PetDetailRow &&
          other.assetId == this.assetId &&
          other.species == this.species &&
          other.breed == this.breed &&
          other.birthDate == this.birthDate &&
          other.microchipId == this.microchipId &&
          other.vetName == this.vetName &&
          other.vetPhone == this.vetPhone &&
          other.feedingNotes == this.feedingNotes &&
          other.medicalNotes == this.medicalNotes);
}

class PetDetailsTableCompanion extends UpdateCompanion<PetDetailRow> {
  final Value<String> assetId;
  final Value<String?> species;
  final Value<String?> breed;
  final Value<DateTime?> birthDate;
  final Value<String?> microchipId;
  final Value<String?> vetName;
  final Value<String?> vetPhone;
  final Value<String?> feedingNotes;
  final Value<String?> medicalNotes;
  final Value<int> rowid;
  const PetDetailsTableCompanion({
    this.assetId = const Value.absent(),
    this.species = const Value.absent(),
    this.breed = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.microchipId = const Value.absent(),
    this.vetName = const Value.absent(),
    this.vetPhone = const Value.absent(),
    this.feedingNotes = const Value.absent(),
    this.medicalNotes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PetDetailsTableCompanion.insert({
    required String assetId,
    this.species = const Value.absent(),
    this.breed = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.microchipId = const Value.absent(),
    this.vetName = const Value.absent(),
    this.vetPhone = const Value.absent(),
    this.feedingNotes = const Value.absent(),
    this.medicalNotes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : assetId = Value(assetId);
  static Insertable<PetDetailRow> custom({
    Expression<String>? assetId,
    Expression<String>? species,
    Expression<String>? breed,
    Expression<DateTime>? birthDate,
    Expression<String>? microchipId,
    Expression<String>? vetName,
    Expression<String>? vetPhone,
    Expression<String>? feedingNotes,
    Expression<String>? medicalNotes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assetId != null) 'asset_id': assetId,
      if (species != null) 'species': species,
      if (breed != null) 'breed': breed,
      if (birthDate != null) 'birth_date': birthDate,
      if (microchipId != null) 'microchip_id': microchipId,
      if (vetName != null) 'vet_name': vetName,
      if (vetPhone != null) 'vet_phone': vetPhone,
      if (feedingNotes != null) 'feeding_notes': feedingNotes,
      if (medicalNotes != null) 'medical_notes': medicalNotes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PetDetailsTableCompanion copyWith({
    Value<String>? assetId,
    Value<String?>? species,
    Value<String?>? breed,
    Value<DateTime?>? birthDate,
    Value<String?>? microchipId,
    Value<String?>? vetName,
    Value<String?>? vetPhone,
    Value<String?>? feedingNotes,
    Value<String?>? medicalNotes,
    Value<int>? rowid,
  }) {
    return PetDetailsTableCompanion(
      assetId: assetId ?? this.assetId,
      species: species ?? this.species,
      breed: breed ?? this.breed,
      birthDate: birthDate ?? this.birthDate,
      microchipId: microchipId ?? this.microchipId,
      vetName: vetName ?? this.vetName,
      vetPhone: vetPhone ?? this.vetPhone,
      feedingNotes: feedingNotes ?? this.feedingNotes,
      medicalNotes: medicalNotes ?? this.medicalNotes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (species.present) {
      map['species'] = Variable<String>(species.value);
    }
    if (breed.present) {
      map['breed'] = Variable<String>(breed.value);
    }
    if (birthDate.present) {
      map['birth_date'] = Variable<DateTime>(birthDate.value);
    }
    if (microchipId.present) {
      map['microchip_id'] = Variable<String>(microchipId.value);
    }
    if (vetName.present) {
      map['vet_name'] = Variable<String>(vetName.value);
    }
    if (vetPhone.present) {
      map['vet_phone'] = Variable<String>(vetPhone.value);
    }
    if (feedingNotes.present) {
      map['feeding_notes'] = Variable<String>(feedingNotes.value);
    }
    if (medicalNotes.present) {
      map['medical_notes'] = Variable<String>(medicalNotes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PetDetailsTableCompanion(')
          ..write('assetId: $assetId, ')
          ..write('species: $species, ')
          ..write('breed: $breed, ')
          ..write('birthDate: $birthDate, ')
          ..write('microchipId: $microchipId, ')
          ..write('vetName: $vetName, ')
          ..write('vetPhone: $vetPhone, ')
          ..write('feedingNotes: $feedingNotes, ')
          ..write('medicalNotes: $medicalNotes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlantDetailsTableTable extends PlantDetailsTable
    with TableInfo<$PlantDetailsTableTable, PlantDetailRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlantDetailsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assets (id)',
    ),
  );
  static const VerificationMeta _speciesMeta = const VerificationMeta(
    'species',
  );
  @override
  late final GeneratedColumn<String> species = GeneratedColumn<String>(
    'species',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sunlightMeta = const VerificationMeta(
    'sunlight',
  );
  @override
  late final GeneratedColumn<String> sunlight = GeneratedColumn<String>(
    'sunlight',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wateringIntervalDaysMeta =
      const VerificationMeta('wateringIntervalDays');
  @override
  late final GeneratedColumn<int> wateringIntervalDays = GeneratedColumn<int>(
    'watering_interval_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _potSizeMeta = const VerificationMeta(
    'potSize',
  );
  @override
  late final GeneratedColumn<String> potSize = GeneratedColumn<String>(
    'pot_size',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastRepottedAtMeta = const VerificationMeta(
    'lastRepottedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastRepottedAt =
      GeneratedColumn<DateTime>(
        'last_repotted_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _toxicityNotesMeta = const VerificationMeta(
    'toxicityNotes',
  );
  @override
  late final GeneratedColumn<String> toxicityNotes = GeneratedColumn<String>(
    'toxicity_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    assetId,
    species,
    sunlight,
    wateringIntervalDays,
    potSize,
    lastRepottedAt,
    toxicityNotes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'plant_details';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlantDetailRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('species')) {
      context.handle(
        _speciesMeta,
        species.isAcceptableOrUnknown(data['species']!, _speciesMeta),
      );
    }
    if (data.containsKey('sunlight')) {
      context.handle(
        _sunlightMeta,
        sunlight.isAcceptableOrUnknown(data['sunlight']!, _sunlightMeta),
      );
    }
    if (data.containsKey('watering_interval_days')) {
      context.handle(
        _wateringIntervalDaysMeta,
        wateringIntervalDays.isAcceptableOrUnknown(
          data['watering_interval_days']!,
          _wateringIntervalDaysMeta,
        ),
      );
    }
    if (data.containsKey('pot_size')) {
      context.handle(
        _potSizeMeta,
        potSize.isAcceptableOrUnknown(data['pot_size']!, _potSizeMeta),
      );
    }
    if (data.containsKey('last_repotted_at')) {
      context.handle(
        _lastRepottedAtMeta,
        lastRepottedAt.isAcceptableOrUnknown(
          data['last_repotted_at']!,
          _lastRepottedAtMeta,
        ),
      );
    }
    if (data.containsKey('toxicity_notes')) {
      context.handle(
        _toxicityNotesMeta,
        toxicityNotes.isAcceptableOrUnknown(
          data['toxicity_notes']!,
          _toxicityNotesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assetId};
  @override
  PlantDetailRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlantDetailRow(
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      species: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}species'],
      ),
      sunlight: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sunlight'],
      ),
      wateringIntervalDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watering_interval_days'],
      ),
      potSize: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pot_size'],
      ),
      lastRepottedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_repotted_at'],
      ),
      toxicityNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}toxicity_notes'],
      ),
    );
  }

  @override
  $PlantDetailsTableTable createAlias(String alias) {
    return $PlantDetailsTableTable(attachedDatabase, alias);
  }
}

class PlantDetailRow extends DataClass implements Insertable<PlantDetailRow> {
  final String assetId;
  final String? species;
  final String? sunlight;
  final int? wateringIntervalDays;
  final String? potSize;
  final DateTime? lastRepottedAt;
  final String? toxicityNotes;
  const PlantDetailRow({
    required this.assetId,
    this.species,
    this.sunlight,
    this.wateringIntervalDays,
    this.potSize,
    this.lastRepottedAt,
    this.toxicityNotes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['asset_id'] = Variable<String>(assetId);
    if (!nullToAbsent || species != null) {
      map['species'] = Variable<String>(species);
    }
    if (!nullToAbsent || sunlight != null) {
      map['sunlight'] = Variable<String>(sunlight);
    }
    if (!nullToAbsent || wateringIntervalDays != null) {
      map['watering_interval_days'] = Variable<int>(wateringIntervalDays);
    }
    if (!nullToAbsent || potSize != null) {
      map['pot_size'] = Variable<String>(potSize);
    }
    if (!nullToAbsent || lastRepottedAt != null) {
      map['last_repotted_at'] = Variable<DateTime>(lastRepottedAt);
    }
    if (!nullToAbsent || toxicityNotes != null) {
      map['toxicity_notes'] = Variable<String>(toxicityNotes);
    }
    return map;
  }

  PlantDetailsTableCompanion toCompanion(bool nullToAbsent) {
    return PlantDetailsTableCompanion(
      assetId: Value(assetId),
      species: species == null && nullToAbsent
          ? const Value.absent()
          : Value(species),
      sunlight: sunlight == null && nullToAbsent
          ? const Value.absent()
          : Value(sunlight),
      wateringIntervalDays: wateringIntervalDays == null && nullToAbsent
          ? const Value.absent()
          : Value(wateringIntervalDays),
      potSize: potSize == null && nullToAbsent
          ? const Value.absent()
          : Value(potSize),
      lastRepottedAt: lastRepottedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRepottedAt),
      toxicityNotes: toxicityNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(toxicityNotes),
    );
  }

  factory PlantDetailRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlantDetailRow(
      assetId: serializer.fromJson<String>(json['assetId']),
      species: serializer.fromJson<String?>(json['species']),
      sunlight: serializer.fromJson<String?>(json['sunlight']),
      wateringIntervalDays: serializer.fromJson<int?>(
        json['wateringIntervalDays'],
      ),
      potSize: serializer.fromJson<String?>(json['potSize']),
      lastRepottedAt: serializer.fromJson<DateTime?>(json['lastRepottedAt']),
      toxicityNotes: serializer.fromJson<String?>(json['toxicityNotes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assetId': serializer.toJson<String>(assetId),
      'species': serializer.toJson<String?>(species),
      'sunlight': serializer.toJson<String?>(sunlight),
      'wateringIntervalDays': serializer.toJson<int?>(wateringIntervalDays),
      'potSize': serializer.toJson<String?>(potSize),
      'lastRepottedAt': serializer.toJson<DateTime?>(lastRepottedAt),
      'toxicityNotes': serializer.toJson<String?>(toxicityNotes),
    };
  }

  PlantDetailRow copyWith({
    String? assetId,
    Value<String?> species = const Value.absent(),
    Value<String?> sunlight = const Value.absent(),
    Value<int?> wateringIntervalDays = const Value.absent(),
    Value<String?> potSize = const Value.absent(),
    Value<DateTime?> lastRepottedAt = const Value.absent(),
    Value<String?> toxicityNotes = const Value.absent(),
  }) => PlantDetailRow(
    assetId: assetId ?? this.assetId,
    species: species.present ? species.value : this.species,
    sunlight: sunlight.present ? sunlight.value : this.sunlight,
    wateringIntervalDays: wateringIntervalDays.present
        ? wateringIntervalDays.value
        : this.wateringIntervalDays,
    potSize: potSize.present ? potSize.value : this.potSize,
    lastRepottedAt: lastRepottedAt.present
        ? lastRepottedAt.value
        : this.lastRepottedAt,
    toxicityNotes: toxicityNotes.present
        ? toxicityNotes.value
        : this.toxicityNotes,
  );
  PlantDetailRow copyWithCompanion(PlantDetailsTableCompanion data) {
    return PlantDetailRow(
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      species: data.species.present ? data.species.value : this.species,
      sunlight: data.sunlight.present ? data.sunlight.value : this.sunlight,
      wateringIntervalDays: data.wateringIntervalDays.present
          ? data.wateringIntervalDays.value
          : this.wateringIntervalDays,
      potSize: data.potSize.present ? data.potSize.value : this.potSize,
      lastRepottedAt: data.lastRepottedAt.present
          ? data.lastRepottedAt.value
          : this.lastRepottedAt,
      toxicityNotes: data.toxicityNotes.present
          ? data.toxicityNotes.value
          : this.toxicityNotes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlantDetailRow(')
          ..write('assetId: $assetId, ')
          ..write('species: $species, ')
          ..write('sunlight: $sunlight, ')
          ..write('wateringIntervalDays: $wateringIntervalDays, ')
          ..write('potSize: $potSize, ')
          ..write('lastRepottedAt: $lastRepottedAt, ')
          ..write('toxicityNotes: $toxicityNotes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    assetId,
    species,
    sunlight,
    wateringIntervalDays,
    potSize,
    lastRepottedAt,
    toxicityNotes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlantDetailRow &&
          other.assetId == this.assetId &&
          other.species == this.species &&
          other.sunlight == this.sunlight &&
          other.wateringIntervalDays == this.wateringIntervalDays &&
          other.potSize == this.potSize &&
          other.lastRepottedAt == this.lastRepottedAt &&
          other.toxicityNotes == this.toxicityNotes);
}

class PlantDetailsTableCompanion extends UpdateCompanion<PlantDetailRow> {
  final Value<String> assetId;
  final Value<String?> species;
  final Value<String?> sunlight;
  final Value<int?> wateringIntervalDays;
  final Value<String?> potSize;
  final Value<DateTime?> lastRepottedAt;
  final Value<String?> toxicityNotes;
  final Value<int> rowid;
  const PlantDetailsTableCompanion({
    this.assetId = const Value.absent(),
    this.species = const Value.absent(),
    this.sunlight = const Value.absent(),
    this.wateringIntervalDays = const Value.absent(),
    this.potSize = const Value.absent(),
    this.lastRepottedAt = const Value.absent(),
    this.toxicityNotes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlantDetailsTableCompanion.insert({
    required String assetId,
    this.species = const Value.absent(),
    this.sunlight = const Value.absent(),
    this.wateringIntervalDays = const Value.absent(),
    this.potSize = const Value.absent(),
    this.lastRepottedAt = const Value.absent(),
    this.toxicityNotes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : assetId = Value(assetId);
  static Insertable<PlantDetailRow> custom({
    Expression<String>? assetId,
    Expression<String>? species,
    Expression<String>? sunlight,
    Expression<int>? wateringIntervalDays,
    Expression<String>? potSize,
    Expression<DateTime>? lastRepottedAt,
    Expression<String>? toxicityNotes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assetId != null) 'asset_id': assetId,
      if (species != null) 'species': species,
      if (sunlight != null) 'sunlight': sunlight,
      if (wateringIntervalDays != null)
        'watering_interval_days': wateringIntervalDays,
      if (potSize != null) 'pot_size': potSize,
      if (lastRepottedAt != null) 'last_repotted_at': lastRepottedAt,
      if (toxicityNotes != null) 'toxicity_notes': toxicityNotes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlantDetailsTableCompanion copyWith({
    Value<String>? assetId,
    Value<String?>? species,
    Value<String?>? sunlight,
    Value<int?>? wateringIntervalDays,
    Value<String?>? potSize,
    Value<DateTime?>? lastRepottedAt,
    Value<String?>? toxicityNotes,
    Value<int>? rowid,
  }) {
    return PlantDetailsTableCompanion(
      assetId: assetId ?? this.assetId,
      species: species ?? this.species,
      sunlight: sunlight ?? this.sunlight,
      wateringIntervalDays: wateringIntervalDays ?? this.wateringIntervalDays,
      potSize: potSize ?? this.potSize,
      lastRepottedAt: lastRepottedAt ?? this.lastRepottedAt,
      toxicityNotes: toxicityNotes ?? this.toxicityNotes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (species.present) {
      map['species'] = Variable<String>(species.value);
    }
    if (sunlight.present) {
      map['sunlight'] = Variable<String>(sunlight.value);
    }
    if (wateringIntervalDays.present) {
      map['watering_interval_days'] = Variable<int>(wateringIntervalDays.value);
    }
    if (potSize.present) {
      map['pot_size'] = Variable<String>(potSize.value);
    }
    if (lastRepottedAt.present) {
      map['last_repotted_at'] = Variable<DateTime>(lastRepottedAt.value);
    }
    if (toxicityNotes.present) {
      map['toxicity_notes'] = Variable<String>(toxicityNotes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlantDetailsTableCompanion(')
          ..write('assetId: $assetId, ')
          ..write('species: $species, ')
          ..write('sunlight: $sunlight, ')
          ..write('wateringIntervalDays: $wateringIntervalDays, ')
          ..write('potSize: $potSize, ')
          ..write('lastRepottedAt: $lastRepottedAt, ')
          ..write('toxicityNotes: $toxicityNotes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SafetyDetailsTableTable extends SafetyDetailsTable
    with TableInfo<$SafetyDetailsTableTable, SafetyDetailRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SafetyDetailsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assets (id)',
    ),
  );
  static const VerificationMeta _safetyTypeMeta = const VerificationMeta(
    'safetyType',
  );
  @override
  late final GeneratedColumn<String> safetyType = GeneratedColumn<String>(
    'safety_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _batteryTypeMeta = const VerificationMeta(
    'batteryType',
  );
  @override
  late final GeneratedColumn<String> batteryType = GeneratedColumn<String>(
    'battery_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _testIntervalDaysMeta = const VerificationMeta(
    'testIntervalDays',
  );
  @override
  late final GeneratedColumn<int> testIntervalDays = GeneratedColumn<int>(
    'test_interval_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    assetId,
    safetyType,
    installedAt,
    expiresAt,
    batteryType,
    testIntervalDays,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'safety_details';
  @override
  VerificationContext validateIntegrity(
    Insertable<SafetyDetailRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('safety_type')) {
      context.handle(
        _safetyTypeMeta,
        safetyType.isAcceptableOrUnknown(data['safety_type']!, _safetyTypeMeta),
      );
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('battery_type')) {
      context.handle(
        _batteryTypeMeta,
        batteryType.isAcceptableOrUnknown(
          data['battery_type']!,
          _batteryTypeMeta,
        ),
      );
    }
    if (data.containsKey('test_interval_days')) {
      context.handle(
        _testIntervalDaysMeta,
        testIntervalDays.isAcceptableOrUnknown(
          data['test_interval_days']!,
          _testIntervalDaysMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assetId};
  @override
  SafetyDetailRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SafetyDetailRow(
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      safetyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}safety_type'],
      ),
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}installed_at'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      batteryType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}battery_type'],
      ),
      testIntervalDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}test_interval_days'],
      ),
    );
  }

  @override
  $SafetyDetailsTableTable createAlias(String alias) {
    return $SafetyDetailsTableTable(attachedDatabase, alias);
  }
}

class SafetyDetailRow extends DataClass implements Insertable<SafetyDetailRow> {
  final String assetId;
  final String? safetyType;
  final DateTime? installedAt;
  final DateTime? expiresAt;
  final String? batteryType;
  final int? testIntervalDays;
  const SafetyDetailRow({
    required this.assetId,
    this.safetyType,
    this.installedAt,
    this.expiresAt,
    this.batteryType,
    this.testIntervalDays,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['asset_id'] = Variable<String>(assetId);
    if (!nullToAbsent || safetyType != null) {
      map['safety_type'] = Variable<String>(safetyType);
    }
    if (!nullToAbsent || installedAt != null) {
      map['installed_at'] = Variable<DateTime>(installedAt);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || batteryType != null) {
      map['battery_type'] = Variable<String>(batteryType);
    }
    if (!nullToAbsent || testIntervalDays != null) {
      map['test_interval_days'] = Variable<int>(testIntervalDays);
    }
    return map;
  }

  SafetyDetailsTableCompanion toCompanion(bool nullToAbsent) {
    return SafetyDetailsTableCompanion(
      assetId: Value(assetId),
      safetyType: safetyType == null && nullToAbsent
          ? const Value.absent()
          : Value(safetyType),
      installedAt: installedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(installedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      batteryType: batteryType == null && nullToAbsent
          ? const Value.absent()
          : Value(batteryType),
      testIntervalDays: testIntervalDays == null && nullToAbsent
          ? const Value.absent()
          : Value(testIntervalDays),
    );
  }

  factory SafetyDetailRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SafetyDetailRow(
      assetId: serializer.fromJson<String>(json['assetId']),
      safetyType: serializer.fromJson<String?>(json['safetyType']),
      installedAt: serializer.fromJson<DateTime?>(json['installedAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      batteryType: serializer.fromJson<String?>(json['batteryType']),
      testIntervalDays: serializer.fromJson<int?>(json['testIntervalDays']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assetId': serializer.toJson<String>(assetId),
      'safetyType': serializer.toJson<String?>(safetyType),
      'installedAt': serializer.toJson<DateTime?>(installedAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'batteryType': serializer.toJson<String?>(batteryType),
      'testIntervalDays': serializer.toJson<int?>(testIntervalDays),
    };
  }

  SafetyDetailRow copyWith({
    String? assetId,
    Value<String?> safetyType = const Value.absent(),
    Value<DateTime?> installedAt = const Value.absent(),
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<String?> batteryType = const Value.absent(),
    Value<int?> testIntervalDays = const Value.absent(),
  }) => SafetyDetailRow(
    assetId: assetId ?? this.assetId,
    safetyType: safetyType.present ? safetyType.value : this.safetyType,
    installedAt: installedAt.present ? installedAt.value : this.installedAt,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    batteryType: batteryType.present ? batteryType.value : this.batteryType,
    testIntervalDays: testIntervalDays.present
        ? testIntervalDays.value
        : this.testIntervalDays,
  );
  SafetyDetailRow copyWithCompanion(SafetyDetailsTableCompanion data) {
    return SafetyDetailRow(
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      safetyType: data.safetyType.present
          ? data.safetyType.value
          : this.safetyType,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      batteryType: data.batteryType.present
          ? data.batteryType.value
          : this.batteryType,
      testIntervalDays: data.testIntervalDays.present
          ? data.testIntervalDays.value
          : this.testIntervalDays,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SafetyDetailRow(')
          ..write('assetId: $assetId, ')
          ..write('safetyType: $safetyType, ')
          ..write('installedAt: $installedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('batteryType: $batteryType, ')
          ..write('testIntervalDays: $testIntervalDays')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    assetId,
    safetyType,
    installedAt,
    expiresAt,
    batteryType,
    testIntervalDays,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SafetyDetailRow &&
          other.assetId == this.assetId &&
          other.safetyType == this.safetyType &&
          other.installedAt == this.installedAt &&
          other.expiresAt == this.expiresAt &&
          other.batteryType == this.batteryType &&
          other.testIntervalDays == this.testIntervalDays);
}

class SafetyDetailsTableCompanion extends UpdateCompanion<SafetyDetailRow> {
  final Value<String> assetId;
  final Value<String?> safetyType;
  final Value<DateTime?> installedAt;
  final Value<DateTime?> expiresAt;
  final Value<String?> batteryType;
  final Value<int?> testIntervalDays;
  final Value<int> rowid;
  const SafetyDetailsTableCompanion({
    this.assetId = const Value.absent(),
    this.safetyType = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.batteryType = const Value.absent(),
    this.testIntervalDays = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SafetyDetailsTableCompanion.insert({
    required String assetId,
    this.safetyType = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.batteryType = const Value.absent(),
    this.testIntervalDays = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : assetId = Value(assetId);
  static Insertable<SafetyDetailRow> custom({
    Expression<String>? assetId,
    Expression<String>? safetyType,
    Expression<DateTime>? installedAt,
    Expression<DateTime>? expiresAt,
    Expression<String>? batteryType,
    Expression<int>? testIntervalDays,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assetId != null) 'asset_id': assetId,
      if (safetyType != null) 'safety_type': safetyType,
      if (installedAt != null) 'installed_at': installedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (batteryType != null) 'battery_type': batteryType,
      if (testIntervalDays != null) 'test_interval_days': testIntervalDays,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SafetyDetailsTableCompanion copyWith({
    Value<String>? assetId,
    Value<String?>? safetyType,
    Value<DateTime?>? installedAt,
    Value<DateTime?>? expiresAt,
    Value<String?>? batteryType,
    Value<int?>? testIntervalDays,
    Value<int>? rowid,
  }) {
    return SafetyDetailsTableCompanion(
      assetId: assetId ?? this.assetId,
      safetyType: safetyType ?? this.safetyType,
      installedAt: installedAt ?? this.installedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      batteryType: batteryType ?? this.batteryType,
      testIntervalDays: testIntervalDays ?? this.testIntervalDays,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (safetyType.present) {
      map['safety_type'] = Variable<String>(safetyType.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (batteryType.present) {
      map['battery_type'] = Variable<String>(batteryType.value);
    }
    if (testIntervalDays.present) {
      map['test_interval_days'] = Variable<int>(testIntervalDays.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SafetyDetailsTableCompanion(')
          ..write('assetId: $assetId, ')
          ..write('safetyType: $safetyType, ')
          ..write('installedAt: $installedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('batteryType: $batteryType, ')
          ..write('testIntervalDays: $testIntervalDays, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class TagRow extends DataClass implements Insertable<TagRow> {
  final String id;
  final String name;
  final DateTime createdAt;
  const TagRow({required this.id, required this.name, required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory TagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TagRow copyWith({String? id, String? name, DateTime? createdAt}) => TagRow(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  TagRow copyWithCompanion(TagsCompanion data) {
    return TagRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class TagsCompanion extends UpdateCompanion<TagRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<TagRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssetTagsTable extends AssetTags
    with TableInfo<$AssetTagsTable, AssetTagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assets (id)',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [assetId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asset_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssetTagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assetId, tagId};
  @override
  AssetTagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetTagRow(
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $AssetTagsTable createAlias(String alias) {
    return $AssetTagsTable(attachedDatabase, alias);
  }
}

class AssetTagRow extends DataClass implements Insertable<AssetTagRow> {
  final String assetId;
  final String tagId;
  const AssetTagRow({required this.assetId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['asset_id'] = Variable<String>(assetId);
    map['tag_id'] = Variable<String>(tagId);
    return map;
  }

  AssetTagsCompanion toCompanion(bool nullToAbsent) {
    return AssetTagsCompanion(assetId: Value(assetId), tagId: Value(tagId));
  }

  factory AssetTagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetTagRow(
      assetId: serializer.fromJson<String>(json['assetId']),
      tagId: serializer.fromJson<String>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assetId': serializer.toJson<String>(assetId),
      'tagId': serializer.toJson<String>(tagId),
    };
  }

  AssetTagRow copyWith({String? assetId, String? tagId}) =>
      AssetTagRow(assetId: assetId ?? this.assetId, tagId: tagId ?? this.tagId);
  AssetTagRow copyWithCompanion(AssetTagsCompanion data) {
    return AssetTagRow(
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetTagRow(')
          ..write('assetId: $assetId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(assetId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetTagRow &&
          other.assetId == this.assetId &&
          other.tagId == this.tagId);
}

class AssetTagsCompanion extends UpdateCompanion<AssetTagRow> {
  final Value<String> assetId;
  final Value<String> tagId;
  final Value<int> rowid;
  const AssetTagsCompanion({
    this.assetId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssetTagsCompanion.insert({
    required String assetId,
    required String tagId,
    this.rowid = const Value.absent(),
  }) : assetId = Value(assetId),
       tagId = Value(tagId);
  static Insertable<AssetTagRow> custom({
    Expression<String>? assetId,
    Expression<String>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assetId != null) 'asset_id': assetId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssetTagsCompanion copyWith({
    Value<String>? assetId,
    Value<String>? tagId,
    Value<int>? rowid,
  }) {
    return AssetTagsCompanion(
      assetId: assetId ?? this.assetId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetTagsCompanion(')
          ..write('assetId: $assetId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssetPhotosTable extends AssetPhotos
    with TableInfo<$AssetPhotosTable, AssetPhotoRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetPhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assets (id)',
    ),
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _captionMeta = const VerificationMeta(
    'caption',
  );
  @override
  late final GeneratedColumn<String> caption = GeneratedColumn<String>(
    'caption',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
    'is_primary',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_primary" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assetId,
    relativePath,
    caption,
    isPrimary,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asset_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssetPhotoRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('caption')) {
      context.handle(
        _captionMeta,
        caption.isAcceptableOrUnknown(data['caption']!, _captionMeta),
      );
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssetPhotoRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetPhotoRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      caption: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caption'],
      ),
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_primary'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AssetPhotosTable createAlias(String alias) {
    return $AssetPhotosTable(attachedDatabase, alias);
  }
}

class AssetPhotoRow extends DataClass implements Insertable<AssetPhotoRow> {
  final String id;
  final String assetId;
  final String relativePath;
  final String? caption;
  final bool isPrimary;
  final DateTime createdAt;
  const AssetPhotoRow({
    required this.id,
    required this.assetId,
    required this.relativePath,
    this.caption,
    required this.isPrimary,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['asset_id'] = Variable<String>(assetId);
    map['relative_path'] = Variable<String>(relativePath);
    if (!nullToAbsent || caption != null) {
      map['caption'] = Variable<String>(caption);
    }
    map['is_primary'] = Variable<bool>(isPrimary);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AssetPhotosCompanion toCompanion(bool nullToAbsent) {
    return AssetPhotosCompanion(
      id: Value(id),
      assetId: Value(assetId),
      relativePath: Value(relativePath),
      caption: caption == null && nullToAbsent
          ? const Value.absent()
          : Value(caption),
      isPrimary: Value(isPrimary),
      createdAt: Value(createdAt),
    );
  }

  factory AssetPhotoRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetPhotoRow(
      id: serializer.fromJson<String>(json['id']),
      assetId: serializer.fromJson<String>(json['assetId']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      caption: serializer.fromJson<String?>(json['caption']),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assetId': serializer.toJson<String>(assetId),
      'relativePath': serializer.toJson<String>(relativePath),
      'caption': serializer.toJson<String?>(caption),
      'isPrimary': serializer.toJson<bool>(isPrimary),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AssetPhotoRow copyWith({
    String? id,
    String? assetId,
    String? relativePath,
    Value<String?> caption = const Value.absent(),
    bool? isPrimary,
    DateTime? createdAt,
  }) => AssetPhotoRow(
    id: id ?? this.id,
    assetId: assetId ?? this.assetId,
    relativePath: relativePath ?? this.relativePath,
    caption: caption.present ? caption.value : this.caption,
    isPrimary: isPrimary ?? this.isPrimary,
    createdAt: createdAt ?? this.createdAt,
  );
  AssetPhotoRow copyWithCompanion(AssetPhotosCompanion data) {
    return AssetPhotoRow(
      id: data.id.present ? data.id.value : this.id,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      caption: data.caption.present ? data.caption.value : this.caption,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetPhotoRow(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('relativePath: $relativePath, ')
          ..write('caption: $caption, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, assetId, relativePath, caption, isPrimary, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetPhotoRow &&
          other.id == this.id &&
          other.assetId == this.assetId &&
          other.relativePath == this.relativePath &&
          other.caption == this.caption &&
          other.isPrimary == this.isPrimary &&
          other.createdAt == this.createdAt);
}

class AssetPhotosCompanion extends UpdateCompanion<AssetPhotoRow> {
  final Value<String> id;
  final Value<String> assetId;
  final Value<String> relativePath;
  final Value<String?> caption;
  final Value<bool> isPrimary;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AssetPhotosCompanion({
    this.id = const Value.absent(),
    this.assetId = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.caption = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssetPhotosCompanion.insert({
    required String id,
    required String assetId,
    required String relativePath,
    this.caption = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       assetId = Value(assetId),
       relativePath = Value(relativePath);
  static Insertable<AssetPhotoRow> custom({
    Expression<String>? id,
    Expression<String>? assetId,
    Expression<String>? relativePath,
    Expression<String>? caption,
    Expression<bool>? isPrimary,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assetId != null) 'asset_id': assetId,
      if (relativePath != null) 'relative_path': relativePath,
      if (caption != null) 'caption': caption,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssetPhotosCompanion copyWith({
    Value<String>? id,
    Value<String>? assetId,
    Value<String>? relativePath,
    Value<String?>? caption,
    Value<bool>? isPrimary,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AssetPhotosCompanion(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      relativePath: relativePath ?? this.relativePath,
      caption: caption ?? this.caption,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (caption.present) {
      map['caption'] = Variable<String>(caption.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetPhotosCompanion(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('relativePath: $relativePath, ')
          ..write('caption: $caption, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MaintenancePlansTable extends MaintenancePlans
    with TableInfo<$MaintenancePlansTable, MaintenancePlanRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MaintenancePlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES assets (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _instructionsMeta = const VerificationMeta(
    'instructions',
  );
  @override
  late final GeneratedColumn<String> instructions = GeneratedColumn<String>(
    'instructions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recurrenceIntervalMeta =
      const VerificationMeta('recurrenceInterval');
  @override
  late final GeneratedColumn<int> recurrenceInterval = GeneratedColumn<int>(
    'recurrence_interval',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recurrenceUnitMeta = const VerificationMeta(
    'recurrenceUnit',
  );
  @override
  late final GeneratedColumn<String> recurrenceUnit = GeneratedColumn<String>(
    'recurrence_unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<String> priority = GeneratedColumn<String>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextDueDateMeta = const VerificationMeta(
    'nextDueDate',
  );
  @override
  late final GeneratedColumn<DateTime> nextDueDate = GeneratedColumn<DateTime>(
    'next_due_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reminderDaysBeforeMeta =
      const VerificationMeta('reminderDaysBefore');
  @override
  late final GeneratedColumn<int> reminderDaysBefore = GeneratedColumn<int>(
    'reminder_days_before',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isEnabledMeta = const VerificationMeta(
    'isEnabled',
  );
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
    'is_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _healthGroupMeta = const VerificationMeta(
    'healthGroup',
  );
  @override
  late final GeneratedColumn<String> healthGroup = GeneratedColumn<String>(
    'health_group',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assetId,
    title,
    instructions,
    recurrenceInterval,
    recurrenceUnit,
    priority,
    nextDueDate,
    reminderDaysBefore,
    isEnabled,
    healthGroup,
    createdAt,
    updatedAt,
    archivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maintenance_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<MaintenancePlanRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('instructions')) {
      context.handle(
        _instructionsMeta,
        instructions.isAcceptableOrUnknown(
          data['instructions']!,
          _instructionsMeta,
        ),
      );
    }
    if (data.containsKey('recurrence_interval')) {
      context.handle(
        _recurrenceIntervalMeta,
        recurrenceInterval.isAcceptableOrUnknown(
          data['recurrence_interval']!,
          _recurrenceIntervalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recurrenceIntervalMeta);
    }
    if (data.containsKey('recurrence_unit')) {
      context.handle(
        _recurrenceUnitMeta,
        recurrenceUnit.isAcceptableOrUnknown(
          data['recurrence_unit']!,
          _recurrenceUnitMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recurrenceUnitMeta);
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    } else if (isInserting) {
      context.missing(_priorityMeta);
    }
    if (data.containsKey('next_due_date')) {
      context.handle(
        _nextDueDateMeta,
        nextDueDate.isAcceptableOrUnknown(
          data['next_due_date']!,
          _nextDueDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextDueDateMeta);
    }
    if (data.containsKey('reminder_days_before')) {
      context.handle(
        _reminderDaysBeforeMeta,
        reminderDaysBefore.isAcceptableOrUnknown(
          data['reminder_days_before']!,
          _reminderDaysBeforeMeta,
        ),
      );
    }
    if (data.containsKey('is_enabled')) {
      context.handle(
        _isEnabledMeta,
        isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta),
      );
    }
    if (data.containsKey('health_group')) {
      context.handle(
        _healthGroupMeta,
        healthGroup.isAcceptableOrUnknown(
          data['health_group']!,
          _healthGroupMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_healthGroupMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MaintenancePlanRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MaintenancePlanRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      instructions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instructions'],
      ),
      recurrenceInterval: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recurrence_interval'],
      )!,
      recurrenceUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurrence_unit'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}priority'],
      )!,
      nextDueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_due_date'],
      )!,
      reminderDaysBefore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reminder_days_before'],
      )!,
      isEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_enabled'],
      )!,
      healthGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}health_group'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
    );
  }

  @override
  $MaintenancePlansTable createAlias(String alias) {
    return $MaintenancePlansTable(attachedDatabase, alias);
  }
}

class MaintenancePlanRow extends DataClass
    implements Insertable<MaintenancePlanRow> {
  final String id;
  final String assetId;
  final String title;
  final String? instructions;
  final int recurrenceInterval;
  final String recurrenceUnit;
  final String priority;
  final DateTime nextDueDate;
  final int reminderDaysBefore;
  final bool isEnabled;
  final String healthGroup;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  const MaintenancePlanRow({
    required this.id,
    required this.assetId,
    required this.title,
    this.instructions,
    required this.recurrenceInterval,
    required this.recurrenceUnit,
    required this.priority,
    required this.nextDueDate,
    required this.reminderDaysBefore,
    required this.isEnabled,
    required this.healthGroup,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['asset_id'] = Variable<String>(assetId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || instructions != null) {
      map['instructions'] = Variable<String>(instructions);
    }
    map['recurrence_interval'] = Variable<int>(recurrenceInterval);
    map['recurrence_unit'] = Variable<String>(recurrenceUnit);
    map['priority'] = Variable<String>(priority);
    map['next_due_date'] = Variable<DateTime>(nextDueDate);
    map['reminder_days_before'] = Variable<int>(reminderDaysBefore);
    map['is_enabled'] = Variable<bool>(isEnabled);
    map['health_group'] = Variable<String>(healthGroup);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    return map;
  }

  MaintenancePlansCompanion toCompanion(bool nullToAbsent) {
    return MaintenancePlansCompanion(
      id: Value(id),
      assetId: Value(assetId),
      title: Value(title),
      instructions: instructions == null && nullToAbsent
          ? const Value.absent()
          : Value(instructions),
      recurrenceInterval: Value(recurrenceInterval),
      recurrenceUnit: Value(recurrenceUnit),
      priority: Value(priority),
      nextDueDate: Value(nextDueDate),
      reminderDaysBefore: Value(reminderDaysBefore),
      isEnabled: Value(isEnabled),
      healthGroup: Value(healthGroup),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
    );
  }

  factory MaintenancePlanRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MaintenancePlanRow(
      id: serializer.fromJson<String>(json['id']),
      assetId: serializer.fromJson<String>(json['assetId']),
      title: serializer.fromJson<String>(json['title']),
      instructions: serializer.fromJson<String?>(json['instructions']),
      recurrenceInterval: serializer.fromJson<int>(json['recurrenceInterval']),
      recurrenceUnit: serializer.fromJson<String>(json['recurrenceUnit']),
      priority: serializer.fromJson<String>(json['priority']),
      nextDueDate: serializer.fromJson<DateTime>(json['nextDueDate']),
      reminderDaysBefore: serializer.fromJson<int>(json['reminderDaysBefore']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
      healthGroup: serializer.fromJson<String>(json['healthGroup']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assetId': serializer.toJson<String>(assetId),
      'title': serializer.toJson<String>(title),
      'instructions': serializer.toJson<String?>(instructions),
      'recurrenceInterval': serializer.toJson<int>(recurrenceInterval),
      'recurrenceUnit': serializer.toJson<String>(recurrenceUnit),
      'priority': serializer.toJson<String>(priority),
      'nextDueDate': serializer.toJson<DateTime>(nextDueDate),
      'reminderDaysBefore': serializer.toJson<int>(reminderDaysBefore),
      'isEnabled': serializer.toJson<bool>(isEnabled),
      'healthGroup': serializer.toJson<String>(healthGroup),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
    };
  }

  MaintenancePlanRow copyWith({
    String? id,
    String? assetId,
    String? title,
    Value<String?> instructions = const Value.absent(),
    int? recurrenceInterval,
    String? recurrenceUnit,
    String? priority,
    DateTime? nextDueDate,
    int? reminderDaysBefore,
    bool? isEnabled,
    String? healthGroup,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> archivedAt = const Value.absent(),
  }) => MaintenancePlanRow(
    id: id ?? this.id,
    assetId: assetId ?? this.assetId,
    title: title ?? this.title,
    instructions: instructions.present ? instructions.value : this.instructions,
    recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
    recurrenceUnit: recurrenceUnit ?? this.recurrenceUnit,
    priority: priority ?? this.priority,
    nextDueDate: nextDueDate ?? this.nextDueDate,
    reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
    isEnabled: isEnabled ?? this.isEnabled,
    healthGroup: healthGroup ?? this.healthGroup,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
  );
  MaintenancePlanRow copyWithCompanion(MaintenancePlansCompanion data) {
    return MaintenancePlanRow(
      id: data.id.present ? data.id.value : this.id,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      title: data.title.present ? data.title.value : this.title,
      instructions: data.instructions.present
          ? data.instructions.value
          : this.instructions,
      recurrenceInterval: data.recurrenceInterval.present
          ? data.recurrenceInterval.value
          : this.recurrenceInterval,
      recurrenceUnit: data.recurrenceUnit.present
          ? data.recurrenceUnit.value
          : this.recurrenceUnit,
      priority: data.priority.present ? data.priority.value : this.priority,
      nextDueDate: data.nextDueDate.present
          ? data.nextDueDate.value
          : this.nextDueDate,
      reminderDaysBefore: data.reminderDaysBefore.present
          ? data.reminderDaysBefore.value
          : this.reminderDaysBefore,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
      healthGroup: data.healthGroup.present
          ? data.healthGroup.value
          : this.healthGroup,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MaintenancePlanRow(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('title: $title, ')
          ..write('instructions: $instructions, ')
          ..write('recurrenceInterval: $recurrenceInterval, ')
          ..write('recurrenceUnit: $recurrenceUnit, ')
          ..write('priority: $priority, ')
          ..write('nextDueDate: $nextDueDate, ')
          ..write('reminderDaysBefore: $reminderDaysBefore, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('healthGroup: $healthGroup, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assetId,
    title,
    instructions,
    recurrenceInterval,
    recurrenceUnit,
    priority,
    nextDueDate,
    reminderDaysBefore,
    isEnabled,
    healthGroup,
    createdAt,
    updatedAt,
    archivedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MaintenancePlanRow &&
          other.id == this.id &&
          other.assetId == this.assetId &&
          other.title == this.title &&
          other.instructions == this.instructions &&
          other.recurrenceInterval == this.recurrenceInterval &&
          other.recurrenceUnit == this.recurrenceUnit &&
          other.priority == this.priority &&
          other.nextDueDate == this.nextDueDate &&
          other.reminderDaysBefore == this.reminderDaysBefore &&
          other.isEnabled == this.isEnabled &&
          other.healthGroup == this.healthGroup &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.archivedAt == this.archivedAt);
}

class MaintenancePlansCompanion extends UpdateCompanion<MaintenancePlanRow> {
  final Value<String> id;
  final Value<String> assetId;
  final Value<String> title;
  final Value<String?> instructions;
  final Value<int> recurrenceInterval;
  final Value<String> recurrenceUnit;
  final Value<String> priority;
  final Value<DateTime> nextDueDate;
  final Value<int> reminderDaysBefore;
  final Value<bool> isEnabled;
  final Value<String> healthGroup;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> archivedAt;
  final Value<int> rowid;
  const MaintenancePlansCompanion({
    this.id = const Value.absent(),
    this.assetId = const Value.absent(),
    this.title = const Value.absent(),
    this.instructions = const Value.absent(),
    this.recurrenceInterval = const Value.absent(),
    this.recurrenceUnit = const Value.absent(),
    this.priority = const Value.absent(),
    this.nextDueDate = const Value.absent(),
    this.reminderDaysBefore = const Value.absent(),
    this.isEnabled = const Value.absent(),
    this.healthGroup = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MaintenancePlansCompanion.insert({
    required String id,
    required String assetId,
    required String title,
    this.instructions = const Value.absent(),
    required int recurrenceInterval,
    required String recurrenceUnit,
    required String priority,
    required DateTime nextDueDate,
    this.reminderDaysBefore = const Value.absent(),
    this.isEnabled = const Value.absent(),
    required String healthGroup,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       assetId = Value(assetId),
       title = Value(title),
       recurrenceInterval = Value(recurrenceInterval),
       recurrenceUnit = Value(recurrenceUnit),
       priority = Value(priority),
       nextDueDate = Value(nextDueDate),
       healthGroup = Value(healthGroup);
  static Insertable<MaintenancePlanRow> custom({
    Expression<String>? id,
    Expression<String>? assetId,
    Expression<String>? title,
    Expression<String>? instructions,
    Expression<int>? recurrenceInterval,
    Expression<String>? recurrenceUnit,
    Expression<String>? priority,
    Expression<DateTime>? nextDueDate,
    Expression<int>? reminderDaysBefore,
    Expression<bool>? isEnabled,
    Expression<String>? healthGroup,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? archivedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assetId != null) 'asset_id': assetId,
      if (title != null) 'title': title,
      if (instructions != null) 'instructions': instructions,
      if (recurrenceInterval != null) 'recurrence_interval': recurrenceInterval,
      if (recurrenceUnit != null) 'recurrence_unit': recurrenceUnit,
      if (priority != null) 'priority': priority,
      if (nextDueDate != null) 'next_due_date': nextDueDate,
      if (reminderDaysBefore != null)
        'reminder_days_before': reminderDaysBefore,
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (healthGroup != null) 'health_group': healthGroup,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MaintenancePlansCompanion copyWith({
    Value<String>? id,
    Value<String>? assetId,
    Value<String>? title,
    Value<String?>? instructions,
    Value<int>? recurrenceInterval,
    Value<String>? recurrenceUnit,
    Value<String>? priority,
    Value<DateTime>? nextDueDate,
    Value<int>? reminderDaysBefore,
    Value<bool>? isEnabled,
    Value<String>? healthGroup,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? archivedAt,
    Value<int>? rowid,
  }) {
    return MaintenancePlansCompanion(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      title: title ?? this.title,
      instructions: instructions ?? this.instructions,
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
      recurrenceUnit: recurrenceUnit ?? this.recurrenceUnit,
      priority: priority ?? this.priority,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
      isEnabled: isEnabled ?? this.isEnabled,
      healthGroup: healthGroup ?? this.healthGroup,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (instructions.present) {
      map['instructions'] = Variable<String>(instructions.value);
    }
    if (recurrenceInterval.present) {
      map['recurrence_interval'] = Variable<int>(recurrenceInterval.value);
    }
    if (recurrenceUnit.present) {
      map['recurrence_unit'] = Variable<String>(recurrenceUnit.value);
    }
    if (priority.present) {
      map['priority'] = Variable<String>(priority.value);
    }
    if (nextDueDate.present) {
      map['next_due_date'] = Variable<DateTime>(nextDueDate.value);
    }
    if (reminderDaysBefore.present) {
      map['reminder_days_before'] = Variable<int>(reminderDaysBefore.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    if (healthGroup.present) {
      map['health_group'] = Variable<String>(healthGroup.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MaintenancePlansCompanion(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('title: $title, ')
          ..write('instructions: $instructions, ')
          ..write('recurrenceInterval: $recurrenceInterval, ')
          ..write('recurrenceUnit: $recurrenceUnit, ')
          ..write('priority: $priority, ')
          ..write('nextDueDate: $nextDueDate, ')
          ..write('reminderDaysBefore: $reminderDaysBefore, ')
          ..write('isEnabled: $isEnabled, ')
          ..write('healthGroup: $healthGroup, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MaintenancePlanMetadataTable extends MaintenancePlanMetadata
    with TableInfo<$MaintenancePlanMetadataTable, MaintenancePlanMetadataRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MaintenancePlanMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES maintenance_plans (id)',
    ),
  );
  static const VerificationMeta _taskTypeMeta = const VerificationMeta(
    'taskType',
  );
  @override
  late final GeneratedColumn<String> taskType = GeneratedColumn<String>(
    'task_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationLabelMeta = const VerificationMeta(
    'locationLabel',
  );
  @override
  late final GeneratedColumn<String> locationLabel = GeneratedColumn<String>(
    'location_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedDurationMinutesMeta =
      const VerificationMeta('estimatedDurationMinutes');
  @override
  late final GeneratedColumn<int> estimatedDurationMinutes =
      GeneratedColumn<int>(
        'estimated_duration_minutes',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _requiredMaterialsJsonMeta =
      const VerificationMeta('requiredMaterialsJson');
  @override
  late final GeneratedColumn<String> requiredMaterialsJson =
      GeneratedColumn<String>(
        'required_materials_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _reminderRecommendationMeta =
      const VerificationMeta('reminderRecommendation');
  @override
  late final GeneratedColumn<String> reminderRecommendation =
      GeneratedColumn<String>(
        'reminder_recommendation',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    planId,
    taskType,
    locationLabel,
    estimatedDurationMinutes,
    requiredMaterialsJson,
    reminderRecommendation,
    sortOrder,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maintenance_plan_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<MaintenancePlanMetadataRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('task_type')) {
      context.handle(
        _taskTypeMeta,
        taskType.isAcceptableOrUnknown(data['task_type']!, _taskTypeMeta),
      );
    }
    if (data.containsKey('location_label')) {
      context.handle(
        _locationLabelMeta,
        locationLabel.isAcceptableOrUnknown(
          data['location_label']!,
          _locationLabelMeta,
        ),
      );
    }
    if (data.containsKey('estimated_duration_minutes')) {
      context.handle(
        _estimatedDurationMinutesMeta,
        estimatedDurationMinutes.isAcceptableOrUnknown(
          data['estimated_duration_minutes']!,
          _estimatedDurationMinutesMeta,
        ),
      );
    }
    if (data.containsKey('required_materials_json')) {
      context.handle(
        _requiredMaterialsJsonMeta,
        requiredMaterialsJson.isAcceptableOrUnknown(
          data['required_materials_json']!,
          _requiredMaterialsJsonMeta,
        ),
      );
    }
    if (data.containsKey('reminder_recommendation')) {
      context.handle(
        _reminderRecommendationMeta,
        reminderRecommendation.isAcceptableOrUnknown(
          data['reminder_recommendation']!,
          _reminderRecommendationMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {planId};
  @override
  MaintenancePlanMetadataRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MaintenancePlanMetadataRow(
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      taskType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_type'],
      ),
      locationLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_label'],
      ),
      estimatedDurationMinutes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}estimated_duration_minutes'],
      ),
      requiredMaterialsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}required_materials_json'],
      )!,
      reminderRecommendation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reminder_recommendation'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MaintenancePlanMetadataTable createAlias(String alias) {
    return $MaintenancePlanMetadataTable(attachedDatabase, alias);
  }
}

class MaintenancePlanMetadataRow extends DataClass
    implements Insertable<MaintenancePlanMetadataRow> {
  final String planId;
  final String? taskType;
  final String? locationLabel;
  final int? estimatedDurationMinutes;
  final String requiredMaterialsJson;
  final String? reminderRecommendation;
  final int? sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  const MaintenancePlanMetadataRow({
    required this.planId,
    this.taskType,
    this.locationLabel,
    this.estimatedDurationMinutes,
    required this.requiredMaterialsJson,
    this.reminderRecommendation,
    this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['plan_id'] = Variable<String>(planId);
    if (!nullToAbsent || taskType != null) {
      map['task_type'] = Variable<String>(taskType);
    }
    if (!nullToAbsent || locationLabel != null) {
      map['location_label'] = Variable<String>(locationLabel);
    }
    if (!nullToAbsent || estimatedDurationMinutes != null) {
      map['estimated_duration_minutes'] = Variable<int>(
        estimatedDurationMinutes,
      );
    }
    map['required_materials_json'] = Variable<String>(requiredMaterialsJson);
    if (!nullToAbsent || reminderRecommendation != null) {
      map['reminder_recommendation'] = Variable<String>(reminderRecommendation);
    }
    if (!nullToAbsent || sortOrder != null) {
      map['sort_order'] = Variable<int>(sortOrder);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MaintenancePlanMetadataCompanion toCompanion(bool nullToAbsent) {
    return MaintenancePlanMetadataCompanion(
      planId: Value(planId),
      taskType: taskType == null && nullToAbsent
          ? const Value.absent()
          : Value(taskType),
      locationLabel: locationLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(locationLabel),
      estimatedDurationMinutes: estimatedDurationMinutes == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedDurationMinutes),
      requiredMaterialsJson: Value(requiredMaterialsJson),
      reminderRecommendation: reminderRecommendation == null && nullToAbsent
          ? const Value.absent()
          : Value(reminderRecommendation),
      sortOrder: sortOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(sortOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MaintenancePlanMetadataRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MaintenancePlanMetadataRow(
      planId: serializer.fromJson<String>(json['planId']),
      taskType: serializer.fromJson<String?>(json['taskType']),
      locationLabel: serializer.fromJson<String?>(json['locationLabel']),
      estimatedDurationMinutes: serializer.fromJson<int?>(
        json['estimatedDurationMinutes'],
      ),
      requiredMaterialsJson: serializer.fromJson<String>(
        json['requiredMaterialsJson'],
      ),
      reminderRecommendation: serializer.fromJson<String?>(
        json['reminderRecommendation'],
      ),
      sortOrder: serializer.fromJson<int?>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'planId': serializer.toJson<String>(planId),
      'taskType': serializer.toJson<String?>(taskType),
      'locationLabel': serializer.toJson<String?>(locationLabel),
      'estimatedDurationMinutes': serializer.toJson<int?>(
        estimatedDurationMinutes,
      ),
      'requiredMaterialsJson': serializer.toJson<String>(requiredMaterialsJson),
      'reminderRecommendation': serializer.toJson<String?>(
        reminderRecommendation,
      ),
      'sortOrder': serializer.toJson<int?>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MaintenancePlanMetadataRow copyWith({
    String? planId,
    Value<String?> taskType = const Value.absent(),
    Value<String?> locationLabel = const Value.absent(),
    Value<int?> estimatedDurationMinutes = const Value.absent(),
    String? requiredMaterialsJson,
    Value<String?> reminderRecommendation = const Value.absent(),
    Value<int?> sortOrder = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => MaintenancePlanMetadataRow(
    planId: planId ?? this.planId,
    taskType: taskType.present ? taskType.value : this.taskType,
    locationLabel: locationLabel.present
        ? locationLabel.value
        : this.locationLabel,
    estimatedDurationMinutes: estimatedDurationMinutes.present
        ? estimatedDurationMinutes.value
        : this.estimatedDurationMinutes,
    requiredMaterialsJson: requiredMaterialsJson ?? this.requiredMaterialsJson,
    reminderRecommendation: reminderRecommendation.present
        ? reminderRecommendation.value
        : this.reminderRecommendation,
    sortOrder: sortOrder.present ? sortOrder.value : this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MaintenancePlanMetadataRow copyWithCompanion(
    MaintenancePlanMetadataCompanion data,
  ) {
    return MaintenancePlanMetadataRow(
      planId: data.planId.present ? data.planId.value : this.planId,
      taskType: data.taskType.present ? data.taskType.value : this.taskType,
      locationLabel: data.locationLabel.present
          ? data.locationLabel.value
          : this.locationLabel,
      estimatedDurationMinutes: data.estimatedDurationMinutes.present
          ? data.estimatedDurationMinutes.value
          : this.estimatedDurationMinutes,
      requiredMaterialsJson: data.requiredMaterialsJson.present
          ? data.requiredMaterialsJson.value
          : this.requiredMaterialsJson,
      reminderRecommendation: data.reminderRecommendation.present
          ? data.reminderRecommendation.value
          : this.reminderRecommendation,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MaintenancePlanMetadataRow(')
          ..write('planId: $planId, ')
          ..write('taskType: $taskType, ')
          ..write('locationLabel: $locationLabel, ')
          ..write('estimatedDurationMinutes: $estimatedDurationMinutes, ')
          ..write('requiredMaterialsJson: $requiredMaterialsJson, ')
          ..write('reminderRecommendation: $reminderRecommendation, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    planId,
    taskType,
    locationLabel,
    estimatedDurationMinutes,
    requiredMaterialsJson,
    reminderRecommendation,
    sortOrder,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MaintenancePlanMetadataRow &&
          other.planId == this.planId &&
          other.taskType == this.taskType &&
          other.locationLabel == this.locationLabel &&
          other.estimatedDurationMinutes == this.estimatedDurationMinutes &&
          other.requiredMaterialsJson == this.requiredMaterialsJson &&
          other.reminderRecommendation == this.reminderRecommendation &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MaintenancePlanMetadataCompanion
    extends UpdateCompanion<MaintenancePlanMetadataRow> {
  final Value<String> planId;
  final Value<String?> taskType;
  final Value<String?> locationLabel;
  final Value<int?> estimatedDurationMinutes;
  final Value<String> requiredMaterialsJson;
  final Value<String?> reminderRecommendation;
  final Value<int?> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const MaintenancePlanMetadataCompanion({
    this.planId = const Value.absent(),
    this.taskType = const Value.absent(),
    this.locationLabel = const Value.absent(),
    this.estimatedDurationMinutes = const Value.absent(),
    this.requiredMaterialsJson = const Value.absent(),
    this.reminderRecommendation = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MaintenancePlanMetadataCompanion.insert({
    required String planId,
    this.taskType = const Value.absent(),
    this.locationLabel = const Value.absent(),
    this.estimatedDurationMinutes = const Value.absent(),
    this.requiredMaterialsJson = const Value.absent(),
    this.reminderRecommendation = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : planId = Value(planId);
  static Insertable<MaintenancePlanMetadataRow> custom({
    Expression<String>? planId,
    Expression<String>? taskType,
    Expression<String>? locationLabel,
    Expression<int>? estimatedDurationMinutes,
    Expression<String>? requiredMaterialsJson,
    Expression<String>? reminderRecommendation,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (planId != null) 'plan_id': planId,
      if (taskType != null) 'task_type': taskType,
      if (locationLabel != null) 'location_label': locationLabel,
      if (estimatedDurationMinutes != null)
        'estimated_duration_minutes': estimatedDurationMinutes,
      if (requiredMaterialsJson != null)
        'required_materials_json': requiredMaterialsJson,
      if (reminderRecommendation != null)
        'reminder_recommendation': reminderRecommendation,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MaintenancePlanMetadataCompanion copyWith({
    Value<String>? planId,
    Value<String?>? taskType,
    Value<String?>? locationLabel,
    Value<int?>? estimatedDurationMinutes,
    Value<String>? requiredMaterialsJson,
    Value<String?>? reminderRecommendation,
    Value<int?>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return MaintenancePlanMetadataCompanion(
      planId: planId ?? this.planId,
      taskType: taskType ?? this.taskType,
      locationLabel: locationLabel ?? this.locationLabel,
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      requiredMaterialsJson:
          requiredMaterialsJson ?? this.requiredMaterialsJson,
      reminderRecommendation:
          reminderRecommendation ?? this.reminderRecommendation,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (taskType.present) {
      map['task_type'] = Variable<String>(taskType.value);
    }
    if (locationLabel.present) {
      map['location_label'] = Variable<String>(locationLabel.value);
    }
    if (estimatedDurationMinutes.present) {
      map['estimated_duration_minutes'] = Variable<int>(
        estimatedDurationMinutes.value,
      );
    }
    if (requiredMaterialsJson.present) {
      map['required_materials_json'] = Variable<String>(
        requiredMaterialsJson.value,
      );
    }
    if (reminderRecommendation.present) {
      map['reminder_recommendation'] = Variable<String>(
        reminderRecommendation.value,
      );
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MaintenancePlanMetadataCompanion(')
          ..write('planId: $planId, ')
          ..write('taskType: $taskType, ')
          ..write('locationLabel: $locationLabel, ')
          ..write('estimatedDurationMinutes: $estimatedDurationMinutes, ')
          ..write('requiredMaterialsJson: $requiredMaterialsJson, ')
          ..write('reminderRecommendation: $reminderRecommendation, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MaintenanceRecordsTable extends MaintenanceRecords
    with TableInfo<$MaintenanceRecordsTable, MaintenanceRecordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MaintenanceRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES maintenance_plans (id)',
    ),
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    planId,
    dueDate,
    completedAt,
    notes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'maintenance_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<MaintenanceRecordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    } else if (isInserting) {
      context.missing(_dueDateMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MaintenanceRecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MaintenanceRecordRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
    );
  }

  @override
  $MaintenanceRecordsTable createAlias(String alias) {
    return $MaintenanceRecordsTable(attachedDatabase, alias);
  }
}

class MaintenanceRecordRow extends DataClass
    implements Insertable<MaintenanceRecordRow> {
  final String id;
  final String planId;
  final DateTime dueDate;
  final DateTime completedAt;
  final String? notes;
  const MaintenanceRecordRow({
    required this.id,
    required this.planId,
    required this.dueDate,
    required this.completedAt,
    this.notes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['plan_id'] = Variable<String>(planId);
    map['due_date'] = Variable<DateTime>(dueDate);
    map['completed_at'] = Variable<DateTime>(completedAt);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    return map;
  }

  MaintenanceRecordsCompanion toCompanion(bool nullToAbsent) {
    return MaintenanceRecordsCompanion(
      id: Value(id),
      planId: Value(planId),
      dueDate: Value(dueDate),
      completedAt: Value(completedAt),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
    );
  }

  factory MaintenanceRecordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MaintenanceRecordRow(
      id: serializer.fromJson<String>(json['id']),
      planId: serializer.fromJson<String>(json['planId']),
      dueDate: serializer.fromJson<DateTime>(json['dueDate']),
      completedAt: serializer.fromJson<DateTime>(json['completedAt']),
      notes: serializer.fromJson<String?>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'planId': serializer.toJson<String>(planId),
      'dueDate': serializer.toJson<DateTime>(dueDate),
      'completedAt': serializer.toJson<DateTime>(completedAt),
      'notes': serializer.toJson<String?>(notes),
    };
  }

  MaintenanceRecordRow copyWith({
    String? id,
    String? planId,
    DateTime? dueDate,
    DateTime? completedAt,
    Value<String?> notes = const Value.absent(),
  }) => MaintenanceRecordRow(
    id: id ?? this.id,
    planId: planId ?? this.planId,
    dueDate: dueDate ?? this.dueDate,
    completedAt: completedAt ?? this.completedAt,
    notes: notes.present ? notes.value : this.notes,
  );
  MaintenanceRecordRow copyWithCompanion(MaintenanceRecordsCompanion data) {
    return MaintenanceRecordRow(
      id: data.id.present ? data.id.value : this.id,
      planId: data.planId.present ? data.planId.value : this.planId,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordRow(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('dueDate: $dueDate, ')
          ..write('completedAt: $completedAt, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, planId, dueDate, completedAt, notes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MaintenanceRecordRow &&
          other.id == this.id &&
          other.planId == this.planId &&
          other.dueDate == this.dueDate &&
          other.completedAt == this.completedAt &&
          other.notes == this.notes);
}

class MaintenanceRecordsCompanion
    extends UpdateCompanion<MaintenanceRecordRow> {
  final Value<String> id;
  final Value<String> planId;
  final Value<DateTime> dueDate;
  final Value<DateTime> completedAt;
  final Value<String?> notes;
  final Value<int> rowid;
  const MaintenanceRecordsCompanion({
    this.id = const Value.absent(),
    this.planId = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MaintenanceRecordsCompanion.insert({
    required String id,
    required String planId,
    required DateTime dueDate,
    this.completedAt = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       planId = Value(planId),
       dueDate = Value(dueDate);
  static Insertable<MaintenanceRecordRow> custom({
    Expression<String>? id,
    Expression<String>? planId,
    Expression<DateTime>? dueDate,
    Expression<DateTime>? completedAt,
    Expression<String>? notes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (planId != null) 'plan_id': planId,
      if (dueDate != null) 'due_date': dueDate,
      if (completedAt != null) 'completed_at': completedAt,
      if (notes != null) 'notes': notes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MaintenanceRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? planId,
    Value<DateTime>? dueDate,
    Value<DateTime>? completedAt,
    Value<String?>? notes,
    Value<int>? rowid,
  }) {
    return MaintenanceRecordsCompanion(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MaintenanceRecordsCompanion(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('dueDate: $dueDate, ')
          ..write('completedAt: $completedAt, ')
          ..write('notes: $notes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppNotificationsTable extends AppNotifications
    with TableInfo<$AppNotificationsTable, NotificationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppNotificationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES maintenance_plans (id)',
    ),
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledForMeta = const VerificationMeta(
    'scheduledFor',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledFor = GeneratedColumn<DateTime>(
    'scheduled_for',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    planId,
    channel,
    scheduledFor,
    deliveredAt,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notifications';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('scheduled_for')) {
      context.handle(
        _scheduledForMeta,
        scheduledFor.isAcceptableOrUnknown(
          data['scheduled_for']!,
          _scheduledForMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledForMeta);
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NotificationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      )!,
      scheduledFor: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_for'],
      )!,
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}delivered_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AppNotificationsTable createAlias(String alias) {
    return $AppNotificationsTable(attachedDatabase, alias);
  }
}

class NotificationRow extends DataClass implements Insertable<NotificationRow> {
  final String id;
  final String planId;
  final String channel;
  final DateTime scheduledFor;
  final DateTime? deliveredAt;
  final DateTime createdAt;
  const NotificationRow({
    required this.id,
    required this.planId,
    required this.channel,
    required this.scheduledFor,
    this.deliveredAt,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['plan_id'] = Variable<String>(planId);
    map['channel'] = Variable<String>(channel);
    map['scheduled_for'] = Variable<DateTime>(scheduledFor);
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AppNotificationsCompanion toCompanion(bool nullToAbsent) {
    return AppNotificationsCompanion(
      id: Value(id),
      planId: Value(planId),
      channel: Value(channel),
      scheduledFor: Value(scheduledFor),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      createdAt: Value(createdAt),
    );
  }

  factory NotificationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationRow(
      id: serializer.fromJson<String>(json['id']),
      planId: serializer.fromJson<String>(json['planId']),
      channel: serializer.fromJson<String>(json['channel']),
      scheduledFor: serializer.fromJson<DateTime>(json['scheduledFor']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'planId': serializer.toJson<String>(planId),
      'channel': serializer.toJson<String>(channel),
      'scheduledFor': serializer.toJson<DateTime>(scheduledFor),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NotificationRow copyWith({
    String? id,
    String? planId,
    String? channel,
    DateTime? scheduledFor,
    Value<DateTime?> deliveredAt = const Value.absent(),
    DateTime? createdAt,
  }) => NotificationRow(
    id: id ?? this.id,
    planId: planId ?? this.planId,
    channel: channel ?? this.channel,
    scheduledFor: scheduledFor ?? this.scheduledFor,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    createdAt: createdAt ?? this.createdAt,
  );
  NotificationRow copyWithCompanion(AppNotificationsCompanion data) {
    return NotificationRow(
      id: data.id.present ? data.id.value : this.id,
      planId: data.planId.present ? data.planId.value : this.planId,
      channel: data.channel.present ? data.channel.value : this.channel,
      scheduledFor: data.scheduledFor.present
          ? data.scheduledFor.value
          : this.scheduledFor,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationRow(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('channel: $channel, ')
          ..write('scheduledFor: $scheduledFor, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, planId, channel, scheduledFor, deliveredAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationRow &&
          other.id == this.id &&
          other.planId == this.planId &&
          other.channel == this.channel &&
          other.scheduledFor == this.scheduledFor &&
          other.deliveredAt == this.deliveredAt &&
          other.createdAt == this.createdAt);
}

class AppNotificationsCompanion extends UpdateCompanion<NotificationRow> {
  final Value<String> id;
  final Value<String> planId;
  final Value<String> channel;
  final Value<DateTime> scheduledFor;
  final Value<DateTime?> deliveredAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AppNotificationsCompanion({
    this.id = const Value.absent(),
    this.planId = const Value.absent(),
    this.channel = const Value.absent(),
    this.scheduledFor = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppNotificationsCompanion.insert({
    required String id,
    required String planId,
    required String channel,
    required DateTime scheduledFor,
    this.deliveredAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       planId = Value(planId),
       channel = Value(channel),
       scheduledFor = Value(scheduledFor);
  static Insertable<NotificationRow> custom({
    Expression<String>? id,
    Expression<String>? planId,
    Expression<String>? channel,
    Expression<DateTime>? scheduledFor,
    Expression<DateTime>? deliveredAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (planId != null) 'plan_id': planId,
      if (channel != null) 'channel': channel,
      if (scheduledFor != null) 'scheduled_for': scheduledFor,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppNotificationsCompanion copyWith({
    Value<String>? id,
    Value<String>? planId,
    Value<String>? channel,
    Value<DateTime>? scheduledFor,
    Value<DateTime?>? deliveredAt,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AppNotificationsCompanion(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      channel: channel ?? this.channel,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (scheduledFor.present) {
      map['scheduled_for'] = Variable<DateTime>(scheduledFor.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppNotificationsCompanion(')
          ..write('id: $id, ')
          ..write('planId: $planId, ')
          ..write('channel: $channel, ')
          ..write('scheduledFor: $scheduledFor, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InboxNotificationsTable extends InboxNotifications
    with TableInfo<$InboxNotificationsTable, InboxNotificationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InboxNotificationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _routeMeta = const VerificationMeta('route');
  @override
  late final GeneratedColumn<String> route = GeneratedColumn<String>(
    'route',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES maintenance_plans (id)',
    ),
  );
  static const VerificationMeta _messageCodeMeta = const VerificationMeta(
    'messageCode',
  );
  @override
  late final GeneratedColumn<String> messageCode = GeneratedColumn<String>(
    'message_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _messageArgsMeta = const VerificationMeta(
    'messageArgs',
  );
  @override
  late final GeneratedColumn<String> messageArgs = GeneratedColumn<String>(
    'message_args',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _dedupeKeyMeta = const VerificationMeta(
    'dedupeKey',
  );
  @override
  late final GeneratedColumn<String> dedupeKey = GeneratedColumn<String>(
    'dedupe_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    body,
    kind,
    route,
    planId,
    messageCode,
    messageArgs,
    dedupeKey,
    readAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notification_inbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<InboxNotificationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('route')) {
      context.handle(
        _routeMeta,
        route.isAcceptableOrUnknown(data['route']!, _routeMeta),
      );
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    }
    if (data.containsKey('message_code')) {
      context.handle(
        _messageCodeMeta,
        messageCode.isAcceptableOrUnknown(
          data['message_code']!,
          _messageCodeMeta,
        ),
      );
    }
    if (data.containsKey('message_args')) {
      context.handle(
        _messageArgsMeta,
        messageArgs.isAcceptableOrUnknown(
          data['message_args']!,
          _messageArgsMeta,
        ),
      );
    }
    if (data.containsKey('dedupe_key')) {
      context.handle(
        _dedupeKeyMeta,
        dedupeKey.isAcceptableOrUnknown(data['dedupe_key']!, _dedupeKeyMeta),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InboxNotificationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InboxNotificationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      route: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route'],
      ),
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      ),
      messageCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_code'],
      ),
      messageArgs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_args'],
      )!,
      dedupeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dedupe_key'],
      )!,
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}read_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $InboxNotificationsTable createAlias(String alias) {
    return $InboxNotificationsTable(attachedDatabase, alias);
  }
}

class InboxNotificationRow extends DataClass
    implements Insertable<InboxNotificationRow> {
  final String id;
  final String title;
  final String body;
  final String kind;
  final String? route;
  final String? planId;
  final String? messageCode;
  final String messageArgs;
  final String dedupeKey;
  final DateTime? readAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const InboxNotificationRow({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    this.route,
    this.planId,
    this.messageCode,
    required this.messageArgs,
    required this.dedupeKey,
    this.readAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || route != null) {
      map['route'] = Variable<String>(route);
    }
    if (!nullToAbsent || planId != null) {
      map['plan_id'] = Variable<String>(planId);
    }
    if (!nullToAbsent || messageCode != null) {
      map['message_code'] = Variable<String>(messageCode);
    }
    map['message_args'] = Variable<String>(messageArgs);
    map['dedupe_key'] = Variable<String>(dedupeKey);
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  InboxNotificationsCompanion toCompanion(bool nullToAbsent) {
    return InboxNotificationsCompanion(
      id: Value(id),
      title: Value(title),
      body: Value(body),
      kind: Value(kind),
      route: route == null && nullToAbsent
          ? const Value.absent()
          : Value(route),
      planId: planId == null && nullToAbsent
          ? const Value.absent()
          : Value(planId),
      messageCode: messageCode == null && nullToAbsent
          ? const Value.absent()
          : Value(messageCode),
      messageArgs: Value(messageArgs),
      dedupeKey: Value(dedupeKey),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory InboxNotificationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InboxNotificationRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      kind: serializer.fromJson<String>(json['kind']),
      route: serializer.fromJson<String?>(json['route']),
      planId: serializer.fromJson<String?>(json['planId']),
      messageCode: serializer.fromJson<String?>(json['messageCode']),
      messageArgs: serializer.fromJson<String>(json['messageArgs']),
      dedupeKey: serializer.fromJson<String>(json['dedupeKey']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'kind': serializer.toJson<String>(kind),
      'route': serializer.toJson<String?>(route),
      'planId': serializer.toJson<String?>(planId),
      'messageCode': serializer.toJson<String?>(messageCode),
      'messageArgs': serializer.toJson<String>(messageArgs),
      'dedupeKey': serializer.toJson<String>(dedupeKey),
      'readAt': serializer.toJson<DateTime?>(readAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  InboxNotificationRow copyWith({
    String? id,
    String? title,
    String? body,
    String? kind,
    Value<String?> route = const Value.absent(),
    Value<String?> planId = const Value.absent(),
    Value<String?> messageCode = const Value.absent(),
    String? messageArgs,
    String? dedupeKey,
    Value<DateTime?> readAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => InboxNotificationRow(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    kind: kind ?? this.kind,
    route: route.present ? route.value : this.route,
    planId: planId.present ? planId.value : this.planId,
    messageCode: messageCode.present ? messageCode.value : this.messageCode,
    messageArgs: messageArgs ?? this.messageArgs,
    dedupeKey: dedupeKey ?? this.dedupeKey,
    readAt: readAt.present ? readAt.value : this.readAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  InboxNotificationRow copyWithCompanion(InboxNotificationsCompanion data) {
    return InboxNotificationRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      kind: data.kind.present ? data.kind.value : this.kind,
      route: data.route.present ? data.route.value : this.route,
      planId: data.planId.present ? data.planId.value : this.planId,
      messageCode: data.messageCode.present
          ? data.messageCode.value
          : this.messageCode,
      messageArgs: data.messageArgs.present
          ? data.messageArgs.value
          : this.messageArgs,
      dedupeKey: data.dedupeKey.present ? data.dedupeKey.value : this.dedupeKey,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InboxNotificationRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('kind: $kind, ')
          ..write('route: $route, ')
          ..write('planId: $planId, ')
          ..write('messageCode: $messageCode, ')
          ..write('messageArgs: $messageArgs, ')
          ..write('dedupeKey: $dedupeKey, ')
          ..write('readAt: $readAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    body,
    kind,
    route,
    planId,
    messageCode,
    messageArgs,
    dedupeKey,
    readAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InboxNotificationRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.body == this.body &&
          other.kind == this.kind &&
          other.route == this.route &&
          other.planId == this.planId &&
          other.messageCode == this.messageCode &&
          other.messageArgs == this.messageArgs &&
          other.dedupeKey == this.dedupeKey &&
          other.readAt == this.readAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class InboxNotificationsCompanion
    extends UpdateCompanion<InboxNotificationRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> body;
  final Value<String> kind;
  final Value<String?> route;
  final Value<String?> planId;
  final Value<String?> messageCode;
  final Value<String> messageArgs;
  final Value<String> dedupeKey;
  final Value<DateTime?> readAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const InboxNotificationsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.kind = const Value.absent(),
    this.route = const Value.absent(),
    this.planId = const Value.absent(),
    this.messageCode = const Value.absent(),
    this.messageArgs = const Value.absent(),
    this.dedupeKey = const Value.absent(),
    this.readAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InboxNotificationsCompanion.insert({
    required String id,
    required String title,
    required String body,
    required String kind,
    this.route = const Value.absent(),
    this.planId = const Value.absent(),
    this.messageCode = const Value.absent(),
    this.messageArgs = const Value.absent(),
    this.dedupeKey = const Value.absent(),
    this.readAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       body = Value(body),
       kind = Value(kind);
  static Insertable<InboxNotificationRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? kind,
    Expression<String>? route,
    Expression<String>? planId,
    Expression<String>? messageCode,
    Expression<String>? messageArgs,
    Expression<String>? dedupeKey,
    Expression<DateTime>? readAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (kind != null) 'kind': kind,
      if (route != null) 'route': route,
      if (planId != null) 'plan_id': planId,
      if (messageCode != null) 'message_code': messageCode,
      if (messageArgs != null) 'message_args': messageArgs,
      if (dedupeKey != null) 'dedupe_key': dedupeKey,
      if (readAt != null) 'read_at': readAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InboxNotificationsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? body,
    Value<String>? kind,
    Value<String?>? route,
    Value<String?>? planId,
    Value<String?>? messageCode,
    Value<String>? messageArgs,
    Value<String>? dedupeKey,
    Value<DateTime?>? readAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return InboxNotificationsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      kind: kind ?? this.kind,
      route: route ?? this.route,
      planId: planId ?? this.planId,
      messageCode: messageCode ?? this.messageCode,
      messageArgs: messageArgs ?? this.messageArgs,
      dedupeKey: dedupeKey ?? this.dedupeKey,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (route.present) {
      map['route'] = Variable<String>(route.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (messageCode.present) {
      map['message_code'] = Variable<String>(messageCode.value);
    }
    if (messageArgs.present) {
      map['message_args'] = Variable<String>(messageArgs.value);
    }
    if (dedupeKey.present) {
      map['dedupe_key'] = Variable<String>(dedupeKey.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InboxNotificationsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('kind: $kind, ')
          ..write('route: $route, ')
          ..write('planId: $planId, ')
          ..write('messageCode: $messageCode, ')
          ..write('messageArgs: $messageArgs, ')
          ..write('dedupeKey: $dedupeKey, ')
          ..write('readAt: $readAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const SettingRow({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SettingRow copyWith({String? key, String? value, DateTime? updatedAt}) =>
      SettingRow(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StreaksTable extends Streaks with TableInfo<$StreaksTable, StreakRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StreaksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentStreakMeta = const VerificationMeta(
    'currentStreak',
  );
  @override
  late final GeneratedColumn<int> currentStreak = GeneratedColumn<int>(
    'current_streak',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bestStreakMeta = const VerificationMeta(
    'bestStreak',
  );
  @override
  late final GeneratedColumn<int> bestStreak = GeneratedColumn<int>(
    'best_streak',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastCompletedDateMeta = const VerificationMeta(
    'lastCompletedDate',
  );
  @override
  late final GeneratedColumn<DateTime> lastCompletedDate =
      GeneratedColumn<DateTime>(
        'last_completed_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    currentStreak,
    bestStreak,
    lastCompletedDate,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'streaks';
  @override
  VerificationContext validateIntegrity(
    Insertable<StreakRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('current_streak')) {
      context.handle(
        _currentStreakMeta,
        currentStreak.isAcceptableOrUnknown(
          data['current_streak']!,
          _currentStreakMeta,
        ),
      );
    }
    if (data.containsKey('best_streak')) {
      context.handle(
        _bestStreakMeta,
        bestStreak.isAcceptableOrUnknown(data['best_streak']!, _bestStreakMeta),
      );
    }
    if (data.containsKey('last_completed_date')) {
      context.handle(
        _lastCompletedDateMeta,
        lastCompletedDate.isAcceptableOrUnknown(
          data['last_completed_date']!,
          _lastCompletedDateMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StreakRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StreakRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      currentStreak: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_streak'],
      )!,
      bestStreak: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}best_streak'],
      )!,
      lastCompletedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_completed_date'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StreaksTable createAlias(String alias) {
    return $StreaksTable(attachedDatabase, alias);
  }
}

class StreakRow extends DataClass implements Insertable<StreakRow> {
  final String id;
  final int currentStreak;
  final int bestStreak;
  final DateTime? lastCompletedDate;
  final DateTime updatedAt;
  const StreakRow({
    required this.id,
    required this.currentStreak,
    required this.bestStreak,
    this.lastCompletedDate,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['current_streak'] = Variable<int>(currentStreak);
    map['best_streak'] = Variable<int>(bestStreak);
    if (!nullToAbsent || lastCompletedDate != null) {
      map['last_completed_date'] = Variable<DateTime>(lastCompletedDate);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  StreaksCompanion toCompanion(bool nullToAbsent) {
    return StreaksCompanion(
      id: Value(id),
      currentStreak: Value(currentStreak),
      bestStreak: Value(bestStreak),
      lastCompletedDate: lastCompletedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCompletedDate),
      updatedAt: Value(updatedAt),
    );
  }

  factory StreakRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StreakRow(
      id: serializer.fromJson<String>(json['id']),
      currentStreak: serializer.fromJson<int>(json['currentStreak']),
      bestStreak: serializer.fromJson<int>(json['bestStreak']),
      lastCompletedDate: serializer.fromJson<DateTime?>(
        json['lastCompletedDate'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'currentStreak': serializer.toJson<int>(currentStreak),
      'bestStreak': serializer.toJson<int>(bestStreak),
      'lastCompletedDate': serializer.toJson<DateTime?>(lastCompletedDate),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  StreakRow copyWith({
    String? id,
    int? currentStreak,
    int? bestStreak,
    Value<DateTime?> lastCompletedDate = const Value.absent(),
    DateTime? updatedAt,
  }) => StreakRow(
    id: id ?? this.id,
    currentStreak: currentStreak ?? this.currentStreak,
    bestStreak: bestStreak ?? this.bestStreak,
    lastCompletedDate: lastCompletedDate.present
        ? lastCompletedDate.value
        : this.lastCompletedDate,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  StreakRow copyWithCompanion(StreaksCompanion data) {
    return StreakRow(
      id: data.id.present ? data.id.value : this.id,
      currentStreak: data.currentStreak.present
          ? data.currentStreak.value
          : this.currentStreak,
      bestStreak: data.bestStreak.present
          ? data.bestStreak.value
          : this.bestStreak,
      lastCompletedDate: data.lastCompletedDate.present
          ? data.lastCompletedDate.value
          : this.lastCompletedDate,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StreakRow(')
          ..write('id: $id, ')
          ..write('currentStreak: $currentStreak, ')
          ..write('bestStreak: $bestStreak, ')
          ..write('lastCompletedDate: $lastCompletedDate, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, currentStreak, bestStreak, lastCompletedDate, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StreakRow &&
          other.id == this.id &&
          other.currentStreak == this.currentStreak &&
          other.bestStreak == this.bestStreak &&
          other.lastCompletedDate == this.lastCompletedDate &&
          other.updatedAt == this.updatedAt);
}

class StreaksCompanion extends UpdateCompanion<StreakRow> {
  final Value<String> id;
  final Value<int> currentStreak;
  final Value<int> bestStreak;
  final Value<DateTime?> lastCompletedDate;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const StreaksCompanion({
    this.id = const Value.absent(),
    this.currentStreak = const Value.absent(),
    this.bestStreak = const Value.absent(),
    this.lastCompletedDate = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StreaksCompanion.insert({
    required String id,
    this.currentStreak = const Value.absent(),
    this.bestStreak = const Value.absent(),
    this.lastCompletedDate = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<StreakRow> custom({
    Expression<String>? id,
    Expression<int>? currentStreak,
    Expression<int>? bestStreak,
    Expression<DateTime>? lastCompletedDate,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (currentStreak != null) 'current_streak': currentStreak,
      if (bestStreak != null) 'best_streak': bestStreak,
      if (lastCompletedDate != null) 'last_completed_date': lastCompletedDate,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StreaksCompanion copyWith({
    Value<String>? id,
    Value<int>? currentStreak,
    Value<int>? bestStreak,
    Value<DateTime?>? lastCompletedDate,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return StreaksCompanion(
      id: id ?? this.id,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      lastCompletedDate: lastCompletedDate ?? this.lastCompletedDate,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (currentStreak.present) {
      map['current_streak'] = Variable<int>(currentStreak.value);
    }
    if (bestStreak.present) {
      map['best_streak'] = Variable<int>(bestStreak.value);
    }
    if (lastCompletedDate.present) {
      map['last_completed_date'] = Variable<DateTime>(lastCompletedDate.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StreaksCompanion(')
          ..write('id: $id, ')
          ..write('currentStreak: $currentStreak, ')
          ..write('bestStreak: $bestStreak, ')
          ..write('lastCompletedDate: $lastCompletedDate, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordKeyMeta = const VerificationMeta(
    'recordKey',
  );
  @override
  late final GeneratedColumn<String> recordKey = GeneratedColumn<String>(
    'record_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _changedAtMeta = const VerificationMeta(
    'changedAt',
  );
  @override
  late final GeneratedColumn<DateTime> changedAt = GeneratedColumn<DateTime>(
    'changed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    entity,
    recordKey,
    operation,
    payloadJson,
    userId,
    changedAt,
    createdAt,
    state,
    attempts,
    nextAttemptAt,
    lastErrorCode,
    lastError,
    generation,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_mutation_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('record_key')) {
      context.handle(
        _recordKeyMeta,
        recordKey.isAcceptableOrUnknown(data['record_key']!, _recordKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_recordKeyMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('changed_at')) {
      context.handle(
        _changedAtMeta,
        changedAt.isAcceptableOrUnknown(data['changed_at']!, _changedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entity, recordKey};
  @override
  SyncOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxData(
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      recordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_key'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      ),
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      changedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}changed_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxData extends DataClass implements Insertable<SyncOutboxData> {
  final String entity;
  final String recordKey;
  final String operation;
  final String? payloadJson;
  final String? userId;
  final DateTime changedAt;
  final DateTime? createdAt;
  final String state;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final String? lastError;
  final int generation;
  const SyncOutboxData({
    required this.entity,
    required this.recordKey,
    required this.operation,
    this.payloadJson,
    this.userId,
    required this.changedAt,
    this.createdAt,
    required this.state,
    required this.attempts,
    this.nextAttemptAt,
    this.lastErrorCode,
    this.lastError,
    required this.generation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['record_key'] = Variable<String>(recordKey);
    map['operation'] = Variable<String>(operation);
    if (!nullToAbsent || payloadJson != null) {
      map['payload_json'] = Variable<String>(payloadJson);
    }
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['changed_at'] = Variable<DateTime>(changedAt);
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['generation'] = Variable<int>(generation);
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      entity: Value(entity),
      recordKey: Value(recordKey),
      operation: Value(operation),
      payloadJson: payloadJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadJson),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      changedAt: Value(changedAt),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      state: Value(state),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      generation: Value(generation),
    );
  }

  factory SyncOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxData(
      entity: serializer.fromJson<String>(json['entity']),
      recordKey: serializer.fromJson<String>(json['recordKey']),
      operation: serializer.fromJson<String>(json['operation']),
      payloadJson: serializer.fromJson<String?>(json['payloadJson']),
      userId: serializer.fromJson<String?>(json['userId']),
      changedAt: serializer.fromJson<DateTime>(json['changedAt']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      generation: serializer.fromJson<int>(json['generation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'recordKey': serializer.toJson<String>(recordKey),
      'operation': serializer.toJson<String>(operation),
      'payloadJson': serializer.toJson<String?>(payloadJson),
      'userId': serializer.toJson<String?>(userId),
      'changedAt': serializer.toJson<DateTime>(changedAt),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastError': serializer.toJson<String?>(lastError),
      'generation': serializer.toJson<int>(generation),
    };
  }

  SyncOutboxData copyWith({
    String? entity,
    String? recordKey,
    String? operation,
    Value<String?> payloadJson = const Value.absent(),
    Value<String?> userId = const Value.absent(),
    DateTime? changedAt,
    Value<DateTime?> createdAt = const Value.absent(),
    String? state,
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    int? generation,
  }) => SyncOutboxData(
    entity: entity ?? this.entity,
    recordKey: recordKey ?? this.recordKey,
    operation: operation ?? this.operation,
    payloadJson: payloadJson.present ? payloadJson.value : this.payloadJson,
    userId: userId.present ? userId.value : this.userId,
    changedAt: changedAt ?? this.changedAt,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    lastError: lastError.present ? lastError.value : this.lastError,
    generation: generation ?? this.generation,
  );
  SyncOutboxData copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxData(
      entity: data.entity.present ? data.entity.value : this.entity,
      recordKey: data.recordKey.present ? data.recordKey.value : this.recordKey,
      operation: data.operation.present ? data.operation.value : this.operation,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      userId: data.userId.present ? data.userId.value : this.userId,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxData(')
          ..write('entity: $entity, ')
          ..write('recordKey: $recordKey, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('userId: $userId, ')
          ..write('changedAt: $changedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastError: $lastError, ')
          ..write('generation: $generation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    entity,
    recordKey,
    operation,
    payloadJson,
    userId,
    changedAt,
    createdAt,
    state,
    attempts,
    nextAttemptAt,
    lastErrorCode,
    lastError,
    generation,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxData &&
          other.entity == this.entity &&
          other.recordKey == this.recordKey &&
          other.operation == this.operation &&
          other.payloadJson == this.payloadJson &&
          other.userId == this.userId &&
          other.changedAt == this.changedAt &&
          other.createdAt == this.createdAt &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastError == this.lastError &&
          other.generation == this.generation);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxData> {
  final Value<String> entity;
  final Value<String> recordKey;
  final Value<String> operation;
  final Value<String?> payloadJson;
  final Value<String?> userId;
  final Value<DateTime> changedAt;
  final Value<DateTime?> createdAt;
  final Value<String> state;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastErrorCode;
  final Value<String?> lastError;
  final Value<int> generation;
  final Value<int> rowid;
  const SyncOutboxCompanion({
    this.entity = const Value.absent(),
    this.recordKey = const Value.absent(),
    this.operation = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.userId = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastError = const Value.absent(),
    this.generation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    required String entity,
    required String recordKey,
    required String operation,
    this.payloadJson = const Value.absent(),
    this.userId = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastError = const Value.absent(),
    this.generation = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entity = Value(entity),
       recordKey = Value(recordKey),
       operation = Value(operation);
  static Insertable<SyncOutboxData> custom({
    Expression<String>? entity,
    Expression<String>? recordKey,
    Expression<String>? operation,
    Expression<String>? payloadJson,
    Expression<String>? userId,
    Expression<DateTime>? changedAt,
    Expression<DateTime>? createdAt,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastErrorCode,
    Expression<String>? lastError,
    Expression<int>? generation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (recordKey != null) 'record_key': recordKey,
      if (operation != null) 'operation': operation,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (userId != null) 'user_id': userId,
      if (changedAt != null) 'changed_at': changedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastError != null) 'last_error': lastError,
      if (generation != null) 'generation': generation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<String>? entity,
    Value<String>? recordKey,
    Value<String>? operation,
    Value<String?>? payloadJson,
    Value<String?>? userId,
    Value<DateTime>? changedAt,
    Value<DateTime?>? createdAt,
    Value<String>? state,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastErrorCode,
    Value<String?>? lastError,
    Value<int>? generation,
    Value<int>? rowid,
  }) {
    return SyncOutboxCompanion(
      entity: entity ?? this.entity,
      recordKey: recordKey ?? this.recordKey,
      operation: operation ?? this.operation,
      payloadJson: payloadJson ?? this.payloadJson,
      userId: userId ?? this.userId,
      changedAt: changedAt ?? this.changedAt,
      createdAt: createdAt ?? this.createdAt,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastError: lastError ?? this.lastError,
      generation: generation ?? this.generation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (recordKey.present) {
      map['record_key'] = Variable<String>(recordKey.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<DateTime>(changedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('entity: $entity, ')
          ..write('recordKey: $recordKey, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('userId: $userId, ')
          ..write('changedAt: $changedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastError: $lastError, ')
          ..write('generation: $generation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReminderScheduleSnapshotsTable extends ReminderScheduleSnapshots
    with TableInfo<$ReminderScheduleSnapshotsTable, ReminderScheduleSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReminderScheduleSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _identityMeta = const VerificationMeta(
    'identity',
  );
  @override
  late final GeneratedColumn<String> identity = GeneratedColumn<String>(
    'identity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notificationIdMeta = const VerificationMeta(
    'notificationId',
  );
  @override
  late final GeneratedColumn<int> notificationId = GeneratedColumn<int>(
    'notification_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _planRevisionMeta = const VerificationMeta(
    'planRevision',
  );
  @override
  late final GeneratedColumn<String> planRevision = GeneratedColumn<String>(
    'plan_revision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
    'scheduled_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timezoneMeta = const VerificationMeta(
    'timezone',
  );
  @override
  late final GeneratedColumn<String> timezone = GeneratedColumn<String>(
    'timezone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localComponentsMeta = const VerificationMeta(
    'localComponents',
  );
  @override
  late final GeneratedColumn<String> localComponents = GeneratedColumn<String>(
    'local_components',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduleModeMeta = const VerificationMeta(
    'scheduleMode',
  );
  @override
  late final GeneratedColumn<String> scheduleMode = GeneratedColumn<String>(
    'schedule_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentVersionMeta = const VerificationMeta(
    'contentVersion',
  );
  @override
  late final GeneratedColumn<String> contentVersion = GeneratedColumn<String>(
    'content_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    identity,
    notificationId,
    planRevision,
    scheduledAt,
    timezone,
    localComponents,
    scheduleMode,
    contentVersion,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reminder_schedule_snapshot';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReminderScheduleSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('identity')) {
      context.handle(
        _identityMeta,
        identity.isAcceptableOrUnknown(data['identity']!, _identityMeta),
      );
    } else if (isInserting) {
      context.missing(_identityMeta);
    }
    if (data.containsKey('notification_id')) {
      context.handle(
        _notificationIdMeta,
        notificationId.isAcceptableOrUnknown(
          data['notification_id']!,
          _notificationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_notificationIdMeta);
    }
    if (data.containsKey('plan_revision')) {
      context.handle(
        _planRevisionMeta,
        planRevision.isAcceptableOrUnknown(
          data['plan_revision']!,
          _planRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_planRevisionMeta);
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('timezone')) {
      context.handle(
        _timezoneMeta,
        timezone.isAcceptableOrUnknown(data['timezone']!, _timezoneMeta),
      );
    } else if (isInserting) {
      context.missing(_timezoneMeta);
    }
    if (data.containsKey('local_components')) {
      context.handle(
        _localComponentsMeta,
        localComponents.isAcceptableOrUnknown(
          data['local_components']!,
          _localComponentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localComponentsMeta);
    }
    if (data.containsKey('schedule_mode')) {
      context.handle(
        _scheduleModeMeta,
        scheduleMode.isAcceptableOrUnknown(
          data['schedule_mode']!,
          _scheduleModeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduleModeMeta);
    }
    if (data.containsKey('content_version')) {
      context.handle(
        _contentVersionMeta,
        contentVersion.isAcceptableOrUnknown(
          data['content_version']!,
          _contentVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentVersionMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {identity};
  @override
  ReminderScheduleSnapshot map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReminderScheduleSnapshot(
      identity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity'],
      )!,
      notificationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}notification_id'],
      )!,
      planRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_revision'],
      )!,
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_at'],
      )!,
      timezone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timezone'],
      )!,
      localComponents: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_components'],
      )!,
      scheduleMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_mode'],
      )!,
      contentVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReminderScheduleSnapshotsTable createAlias(String alias) {
    return $ReminderScheduleSnapshotsTable(attachedDatabase, alias);
  }
}

class ReminderScheduleSnapshot extends DataClass
    implements Insertable<ReminderScheduleSnapshot> {
  final String identity;
  final int notificationId;
  final String planRevision;
  final DateTime scheduledAt;
  final String timezone;
  final String localComponents;
  final String scheduleMode;
  final String contentVersion;
  final DateTime updatedAt;
  const ReminderScheduleSnapshot({
    required this.identity,
    required this.notificationId,
    required this.planRevision,
    required this.scheduledAt,
    required this.timezone,
    required this.localComponents,
    required this.scheduleMode,
    required this.contentVersion,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['identity'] = Variable<String>(identity);
    map['notification_id'] = Variable<int>(notificationId);
    map['plan_revision'] = Variable<String>(planRevision);
    map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    map['timezone'] = Variable<String>(timezone);
    map['local_components'] = Variable<String>(localComponents);
    map['schedule_mode'] = Variable<String>(scheduleMode);
    map['content_version'] = Variable<String>(contentVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReminderScheduleSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return ReminderScheduleSnapshotsCompanion(
      identity: Value(identity),
      notificationId: Value(notificationId),
      planRevision: Value(planRevision),
      scheduledAt: Value(scheduledAt),
      timezone: Value(timezone),
      localComponents: Value(localComponents),
      scheduleMode: Value(scheduleMode),
      contentVersion: Value(contentVersion),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReminderScheduleSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReminderScheduleSnapshot(
      identity: serializer.fromJson<String>(json['identity']),
      notificationId: serializer.fromJson<int>(json['notificationId']),
      planRevision: serializer.fromJson<String>(json['planRevision']),
      scheduledAt: serializer.fromJson<DateTime>(json['scheduledAt']),
      timezone: serializer.fromJson<String>(json['timezone']),
      localComponents: serializer.fromJson<String>(json['localComponents']),
      scheduleMode: serializer.fromJson<String>(json['scheduleMode']),
      contentVersion: serializer.fromJson<String>(json['contentVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'identity': serializer.toJson<String>(identity),
      'notificationId': serializer.toJson<int>(notificationId),
      'planRevision': serializer.toJson<String>(planRevision),
      'scheduledAt': serializer.toJson<DateTime>(scheduledAt),
      'timezone': serializer.toJson<String>(timezone),
      'localComponents': serializer.toJson<String>(localComponents),
      'scheduleMode': serializer.toJson<String>(scheduleMode),
      'contentVersion': serializer.toJson<String>(contentVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReminderScheduleSnapshot copyWith({
    String? identity,
    int? notificationId,
    String? planRevision,
    DateTime? scheduledAt,
    String? timezone,
    String? localComponents,
    String? scheduleMode,
    String? contentVersion,
    DateTime? updatedAt,
  }) => ReminderScheduleSnapshot(
    identity: identity ?? this.identity,
    notificationId: notificationId ?? this.notificationId,
    planRevision: planRevision ?? this.planRevision,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    timezone: timezone ?? this.timezone,
    localComponents: localComponents ?? this.localComponents,
    scheduleMode: scheduleMode ?? this.scheduleMode,
    contentVersion: contentVersion ?? this.contentVersion,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReminderScheduleSnapshot copyWithCompanion(
    ReminderScheduleSnapshotsCompanion data,
  ) {
    return ReminderScheduleSnapshot(
      identity: data.identity.present ? data.identity.value : this.identity,
      notificationId: data.notificationId.present
          ? data.notificationId.value
          : this.notificationId,
      planRevision: data.planRevision.present
          ? data.planRevision.value
          : this.planRevision,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      timezone: data.timezone.present ? data.timezone.value : this.timezone,
      localComponents: data.localComponents.present
          ? data.localComponents.value
          : this.localComponents,
      scheduleMode: data.scheduleMode.present
          ? data.scheduleMode.value
          : this.scheduleMode,
      contentVersion: data.contentVersion.present
          ? data.contentVersion.value
          : this.contentVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReminderScheduleSnapshot(')
          ..write('identity: $identity, ')
          ..write('notificationId: $notificationId, ')
          ..write('planRevision: $planRevision, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('timezone: $timezone, ')
          ..write('localComponents: $localComponents, ')
          ..write('scheduleMode: $scheduleMode, ')
          ..write('contentVersion: $contentVersion, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    identity,
    notificationId,
    planRevision,
    scheduledAt,
    timezone,
    localComponents,
    scheduleMode,
    contentVersion,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReminderScheduleSnapshot &&
          other.identity == this.identity &&
          other.notificationId == this.notificationId &&
          other.planRevision == this.planRevision &&
          other.scheduledAt == this.scheduledAt &&
          other.timezone == this.timezone &&
          other.localComponents == this.localComponents &&
          other.scheduleMode == this.scheduleMode &&
          other.contentVersion == this.contentVersion &&
          other.updatedAt == this.updatedAt);
}

class ReminderScheduleSnapshotsCompanion
    extends UpdateCompanion<ReminderScheduleSnapshot> {
  final Value<String> identity;
  final Value<int> notificationId;
  final Value<String> planRevision;
  final Value<DateTime> scheduledAt;
  final Value<String> timezone;
  final Value<String> localComponents;
  final Value<String> scheduleMode;
  final Value<String> contentVersion;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReminderScheduleSnapshotsCompanion({
    this.identity = const Value.absent(),
    this.notificationId = const Value.absent(),
    this.planRevision = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.timezone = const Value.absent(),
    this.localComponents = const Value.absent(),
    this.scheduleMode = const Value.absent(),
    this.contentVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReminderScheduleSnapshotsCompanion.insert({
    required String identity,
    required int notificationId,
    required String planRevision,
    required DateTime scheduledAt,
    required String timezone,
    required String localComponents,
    required String scheduleMode,
    required String contentVersion,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : identity = Value(identity),
       notificationId = Value(notificationId),
       planRevision = Value(planRevision),
       scheduledAt = Value(scheduledAt),
       timezone = Value(timezone),
       localComponents = Value(localComponents),
       scheduleMode = Value(scheduleMode),
       contentVersion = Value(contentVersion);
  static Insertable<ReminderScheduleSnapshot> custom({
    Expression<String>? identity,
    Expression<int>? notificationId,
    Expression<String>? planRevision,
    Expression<DateTime>? scheduledAt,
    Expression<String>? timezone,
    Expression<String>? localComponents,
    Expression<String>? scheduleMode,
    Expression<String>? contentVersion,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (identity != null) 'identity': identity,
      if (notificationId != null) 'notification_id': notificationId,
      if (planRevision != null) 'plan_revision': planRevision,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (timezone != null) 'timezone': timezone,
      if (localComponents != null) 'local_components': localComponents,
      if (scheduleMode != null) 'schedule_mode': scheduleMode,
      if (contentVersion != null) 'content_version': contentVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReminderScheduleSnapshotsCompanion copyWith({
    Value<String>? identity,
    Value<int>? notificationId,
    Value<String>? planRevision,
    Value<DateTime>? scheduledAt,
    Value<String>? timezone,
    Value<String>? localComponents,
    Value<String>? scheduleMode,
    Value<String>? contentVersion,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReminderScheduleSnapshotsCompanion(
      identity: identity ?? this.identity,
      notificationId: notificationId ?? this.notificationId,
      planRevision: planRevision ?? this.planRevision,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      timezone: timezone ?? this.timezone,
      localComponents: localComponents ?? this.localComponents,
      scheduleMode: scheduleMode ?? this.scheduleMode,
      contentVersion: contentVersion ?? this.contentVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (identity.present) {
      map['identity'] = Variable<String>(identity.value);
    }
    if (notificationId.present) {
      map['notification_id'] = Variable<int>(notificationId.value);
    }
    if (planRevision.present) {
      map['plan_revision'] = Variable<String>(planRevision.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (timezone.present) {
      map['timezone'] = Variable<String>(timezone.value);
    }
    if (localComponents.present) {
      map['local_components'] = Variable<String>(localComponents.value);
    }
    if (scheduleMode.present) {
      map['schedule_mode'] = Variable<String>(scheduleMode.value);
    }
    if (contentVersion.present) {
      map['content_version'] = Variable<String>(contentVersion.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReminderScheduleSnapshotsCompanion(')
          ..write('identity: $identity, ')
          ..write('notificationId: $notificationId, ')
          ..write('planRevision: $planRevision, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('timezone: $timezone, ')
          ..write('localComponents: $localComponents, ')
          ..write('scheduleMode: $scheduleMode, ')
          ..write('contentVersion: $contentVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, SyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSyncSeqMeta = const VerificationMeta(
    'lastSyncSeq',
  );
  @override
  late final GeneratedColumn<int> lastSyncSeq = GeneratedColumn<int>(
    'last_sync_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastRecordKeyMeta = const VerificationMeta(
    'lastRecordKey',
  );
  @override
  late final GeneratedColumn<String> lastRecordKey = GeneratedColumn<String>(
    'last_record_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [entity, lastSyncSeq, lastRecordKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('last_sync_seq')) {
      context.handle(
        _lastSyncSeqMeta,
        lastSyncSeq.isAcceptableOrUnknown(
          data['last_sync_seq']!,
          _lastSyncSeqMeta,
        ),
      );
    }
    if (data.containsKey('last_record_key')) {
      context.handle(
        _lastRecordKeyMeta,
        lastRecordKey.isAcceptableOrUnknown(
          data['last_record_key']!,
          _lastRecordKeyMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entity};
  @override
  SyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursor(
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      lastSyncSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_sync_seq'],
      )!,
      lastRecordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_record_key'],
      ),
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class SyncCursor extends DataClass implements Insertable<SyncCursor> {
  final String entity;
  final int lastSyncSeq;
  final String? lastRecordKey;
  const SyncCursor({
    required this.entity,
    required this.lastSyncSeq,
    this.lastRecordKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['last_sync_seq'] = Variable<int>(lastSyncSeq);
    if (!nullToAbsent || lastRecordKey != null) {
      map['last_record_key'] = Variable<String>(lastRecordKey);
    }
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      entity: Value(entity),
      lastSyncSeq: Value(lastSyncSeq),
      lastRecordKey: lastRecordKey == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRecordKey),
    );
  }

  factory SyncCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursor(
      entity: serializer.fromJson<String>(json['entity']),
      lastSyncSeq: serializer.fromJson<int>(json['lastSyncSeq']),
      lastRecordKey: serializer.fromJson<String?>(json['lastRecordKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'lastSyncSeq': serializer.toJson<int>(lastSyncSeq),
      'lastRecordKey': serializer.toJson<String?>(lastRecordKey),
    };
  }

  SyncCursor copyWith({
    String? entity,
    int? lastSyncSeq,
    Value<String?> lastRecordKey = const Value.absent(),
  }) => SyncCursor(
    entity: entity ?? this.entity,
    lastSyncSeq: lastSyncSeq ?? this.lastSyncSeq,
    lastRecordKey: lastRecordKey.present
        ? lastRecordKey.value
        : this.lastRecordKey,
  );
  SyncCursor copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursor(
      entity: data.entity.present ? data.entity.value : this.entity,
      lastSyncSeq: data.lastSyncSeq.present
          ? data.lastSyncSeq.value
          : this.lastSyncSeq,
      lastRecordKey: data.lastRecordKey.present
          ? data.lastRecordKey.value
          : this.lastRecordKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursor(')
          ..write('entity: $entity, ')
          ..write('lastSyncSeq: $lastSyncSeq, ')
          ..write('lastRecordKey: $lastRecordKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entity, lastSyncSeq, lastRecordKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursor &&
          other.entity == this.entity &&
          other.lastSyncSeq == this.lastSyncSeq &&
          other.lastRecordKey == this.lastRecordKey);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursor> {
  final Value<String> entity;
  final Value<int> lastSyncSeq;
  final Value<String?> lastRecordKey;
  final Value<int> rowid;
  const SyncCursorsCompanion({
    this.entity = const Value.absent(),
    this.lastSyncSeq = const Value.absent(),
    this.lastRecordKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String entity,
    this.lastSyncSeq = const Value.absent(),
    this.lastRecordKey = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entity = Value(entity);
  static Insertable<SyncCursor> custom({
    Expression<String>? entity,
    Expression<int>? lastSyncSeq,
    Expression<String>? lastRecordKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (lastSyncSeq != null) 'last_sync_seq': lastSyncSeq,
      if (lastRecordKey != null) 'last_record_key': lastRecordKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<String>? entity,
    Value<int>? lastSyncSeq,
    Value<String?>? lastRecordKey,
    Value<int>? rowid,
  }) {
    return SyncCursorsCompanion(
      entity: entity ?? this.entity,
      lastSyncSeq: lastSyncSeq ?? this.lastSyncSeq,
      lastRecordKey: lastRecordKey ?? this.lastRecordKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (lastSyncSeq.present) {
      map['last_sync_seq'] = Variable<int>(lastSyncSeq.value);
    }
    if (lastRecordKey.present) {
      map['last_record_key'] = Variable<String>(lastRecordKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('entity: $entity, ')
          ..write('lastSyncSeq: $lastSyncSeq, ')
          ..write('lastRecordKey: $lastRecordKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncShadowsTable extends SyncShadows
    with TableInfo<$SyncShadowsTable, SyncShadow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncShadowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordKeyMeta = const VerificationMeta(
    'recordKey',
  );
  @override
  late final GeneratedColumn<String> recordKey = GeneratedColumn<String>(
    'record_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteRevisionMeta = const VerificationMeta(
    'remoteRevision',
  );
  @override
  late final GeneratedColumn<int> remoteRevision = GeneratedColumn<int>(
    'remote_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteModifiedAtMeta = const VerificationMeta(
    'remoteModifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> remoteModifiedAt =
      GeneratedColumn<DateTime>(
        'remote_modified_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _payloadHashMeta = const VerificationMeta(
    'payloadHash',
  );
  @override
  late final GeneratedColumn<String> payloadHash = GeneratedColumn<String>(
    'payload_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    entity,
    recordKey,
    remoteRevision,
    remoteModifiedAt,
    payloadHash,
    lastSyncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_shadows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncShadow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('record_key')) {
      context.handle(
        _recordKeyMeta,
        recordKey.isAcceptableOrUnknown(data['record_key']!, _recordKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_recordKeyMeta);
    }
    if (data.containsKey('remote_revision')) {
      context.handle(
        _remoteRevisionMeta,
        remoteRevision.isAcceptableOrUnknown(
          data['remote_revision']!,
          _remoteRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_remoteRevisionMeta);
    }
    if (data.containsKey('remote_modified_at')) {
      context.handle(
        _remoteModifiedAtMeta,
        remoteModifiedAt.isAcceptableOrUnknown(
          data['remote_modified_at']!,
          _remoteModifiedAtMeta,
        ),
      );
    }
    if (data.containsKey('payload_hash')) {
      context.handle(
        _payloadHashMeta,
        payloadHash.isAcceptableOrUnknown(
          data['payload_hash']!,
          _payloadHashMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entity, recordKey};
  @override
  SyncShadow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncShadow(
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      recordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_key'],
      )!,
      remoteRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_revision'],
      )!,
      remoteModifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}remote_modified_at'],
      ),
      payloadHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_hash'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      )!,
    );
  }

  @override
  $SyncShadowsTable createAlias(String alias) {
    return $SyncShadowsTable(attachedDatabase, alias);
  }
}

class SyncShadow extends DataClass implements Insertable<SyncShadow> {
  final String entity;
  final String recordKey;
  final int remoteRevision;
  final DateTime? remoteModifiedAt;
  final String? payloadHash;
  final DateTime lastSyncedAt;
  const SyncShadow({
    required this.entity,
    required this.recordKey,
    required this.remoteRevision,
    this.remoteModifiedAt,
    this.payloadHash,
    required this.lastSyncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity'] = Variable<String>(entity);
    map['record_key'] = Variable<String>(recordKey);
    map['remote_revision'] = Variable<int>(remoteRevision);
    if (!nullToAbsent || remoteModifiedAt != null) {
      map['remote_modified_at'] = Variable<DateTime>(remoteModifiedAt);
    }
    if (!nullToAbsent || payloadHash != null) {
      map['payload_hash'] = Variable<String>(payloadHash);
    }
    map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    return map;
  }

  SyncShadowsCompanion toCompanion(bool nullToAbsent) {
    return SyncShadowsCompanion(
      entity: Value(entity),
      recordKey: Value(recordKey),
      remoteRevision: Value(remoteRevision),
      remoteModifiedAt: remoteModifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteModifiedAt),
      payloadHash: payloadHash == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadHash),
      lastSyncedAt: Value(lastSyncedAt),
    );
  }

  factory SyncShadow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncShadow(
      entity: serializer.fromJson<String>(json['entity']),
      recordKey: serializer.fromJson<String>(json['recordKey']),
      remoteRevision: serializer.fromJson<int>(json['remoteRevision']),
      remoteModifiedAt: serializer.fromJson<DateTime?>(
        json['remoteModifiedAt'],
      ),
      payloadHash: serializer.fromJson<String?>(json['payloadHash']),
      lastSyncedAt: serializer.fromJson<DateTime>(json['lastSyncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entity': serializer.toJson<String>(entity),
      'recordKey': serializer.toJson<String>(recordKey),
      'remoteRevision': serializer.toJson<int>(remoteRevision),
      'remoteModifiedAt': serializer.toJson<DateTime?>(remoteModifiedAt),
      'payloadHash': serializer.toJson<String?>(payloadHash),
      'lastSyncedAt': serializer.toJson<DateTime>(lastSyncedAt),
    };
  }

  SyncShadow copyWith({
    String? entity,
    String? recordKey,
    int? remoteRevision,
    Value<DateTime?> remoteModifiedAt = const Value.absent(),
    Value<String?> payloadHash = const Value.absent(),
    DateTime? lastSyncedAt,
  }) => SyncShadow(
    entity: entity ?? this.entity,
    recordKey: recordKey ?? this.recordKey,
    remoteRevision: remoteRevision ?? this.remoteRevision,
    remoteModifiedAt: remoteModifiedAt.present
        ? remoteModifiedAt.value
        : this.remoteModifiedAt,
    payloadHash: payloadHash.present ? payloadHash.value : this.payloadHash,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );
  SyncShadow copyWithCompanion(SyncShadowsCompanion data) {
    return SyncShadow(
      entity: data.entity.present ? data.entity.value : this.entity,
      recordKey: data.recordKey.present ? data.recordKey.value : this.recordKey,
      remoteRevision: data.remoteRevision.present
          ? data.remoteRevision.value
          : this.remoteRevision,
      remoteModifiedAt: data.remoteModifiedAt.present
          ? data.remoteModifiedAt.value
          : this.remoteModifiedAt,
      payloadHash: data.payloadHash.present
          ? data.payloadHash.value
          : this.payloadHash,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncShadow(')
          ..write('entity: $entity, ')
          ..write('recordKey: $recordKey, ')
          ..write('remoteRevision: $remoteRevision, ')
          ..write('remoteModifiedAt: $remoteModifiedAt, ')
          ..write('payloadHash: $payloadHash, ')
          ..write('lastSyncedAt: $lastSyncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    entity,
    recordKey,
    remoteRevision,
    remoteModifiedAt,
    payloadHash,
    lastSyncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncShadow &&
          other.entity == this.entity &&
          other.recordKey == this.recordKey &&
          other.remoteRevision == this.remoteRevision &&
          other.remoteModifiedAt == this.remoteModifiedAt &&
          other.payloadHash == this.payloadHash &&
          other.lastSyncedAt == this.lastSyncedAt);
}

class SyncShadowsCompanion extends UpdateCompanion<SyncShadow> {
  final Value<String> entity;
  final Value<String> recordKey;
  final Value<int> remoteRevision;
  final Value<DateTime?> remoteModifiedAt;
  final Value<String?> payloadHash;
  final Value<DateTime> lastSyncedAt;
  final Value<int> rowid;
  const SyncShadowsCompanion({
    this.entity = const Value.absent(),
    this.recordKey = const Value.absent(),
    this.remoteRevision = const Value.absent(),
    this.remoteModifiedAt = const Value.absent(),
    this.payloadHash = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncShadowsCompanion.insert({
    required String entity,
    required String recordKey,
    required int remoteRevision,
    this.remoteModifiedAt = const Value.absent(),
    this.payloadHash = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entity = Value(entity),
       recordKey = Value(recordKey),
       remoteRevision = Value(remoteRevision);
  static Insertable<SyncShadow> custom({
    Expression<String>? entity,
    Expression<String>? recordKey,
    Expression<int>? remoteRevision,
    Expression<DateTime>? remoteModifiedAt,
    Expression<String>? payloadHash,
    Expression<DateTime>? lastSyncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entity != null) 'entity': entity,
      if (recordKey != null) 'record_key': recordKey,
      if (remoteRevision != null) 'remote_revision': remoteRevision,
      if (remoteModifiedAt != null) 'remote_modified_at': remoteModifiedAt,
      if (payloadHash != null) 'payload_hash': payloadHash,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncShadowsCompanion copyWith({
    Value<String>? entity,
    Value<String>? recordKey,
    Value<int>? remoteRevision,
    Value<DateTime?>? remoteModifiedAt,
    Value<String?>? payloadHash,
    Value<DateTime>? lastSyncedAt,
    Value<int>? rowid,
  }) {
    return SyncShadowsCompanion(
      entity: entity ?? this.entity,
      recordKey: recordKey ?? this.recordKey,
      remoteRevision: remoteRevision ?? this.remoteRevision,
      remoteModifiedAt: remoteModifiedAt ?? this.remoteModifiedAt,
      payloadHash: payloadHash ?? this.payloadHash,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (recordKey.present) {
      map['record_key'] = Variable<String>(recordKey.value);
    }
    if (remoteRevision.present) {
      map['remote_revision'] = Variable<int>(remoteRevision.value);
    }
    if (remoteModifiedAt.present) {
      map['remote_modified_at'] = Variable<DateTime>(remoteModifiedAt.value);
    }
    if (payloadHash.present) {
      map['payload_hash'] = Variable<String>(payloadHash.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncShadowsCompanion(')
          ..write('entity: $entity, ')
          ..write('recordKey: $recordKey, ')
          ..write('remoteRevision: $remoteRevision, ')
          ..write('remoteModifiedAt: $remoteModifiedAt, ')
          ..write('payloadHash: $payloadHash, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncRuntimeTable extends SyncRuntime
    with TableInfo<$SyncRuntimeTable, SyncRuntimeData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncRuntimeTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _suppressOutboxMeta = const VerificationMeta(
    'suppressOutbox',
  );
  @override
  late final GeneratedColumn<bool> suppressOutbox = GeneratedColumn<bool>(
    'suppress_outbox',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("suppress_outbox" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _leaseOwnerMeta = const VerificationMeta(
    'leaseOwner',
  );
  @override
  late final GeneratedColumn<String> leaseOwner = GeneratedColumn<String>(
    'lease_owner',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _leaseExpiresAtMeta = const VerificationMeta(
    'leaseExpiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> leaseExpiresAt =
      GeneratedColumn<DateTime>(
        'lease_expires_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    suppressOutbox,
    leaseOwner,
    leaseExpiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_runtime';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncRuntimeData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('suppress_outbox')) {
      context.handle(
        _suppressOutboxMeta,
        suppressOutbox.isAcceptableOrUnknown(
          data['suppress_outbox']!,
          _suppressOutboxMeta,
        ),
      );
    }
    if (data.containsKey('lease_owner')) {
      context.handle(
        _leaseOwnerMeta,
        leaseOwner.isAcceptableOrUnknown(data['lease_owner']!, _leaseOwnerMeta),
      );
    }
    if (data.containsKey('lease_expires_at')) {
      context.handle(
        _leaseExpiresAtMeta,
        leaseExpiresAt.isAcceptableOrUnknown(
          data['lease_expires_at']!,
          _leaseExpiresAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncRuntimeData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncRuntimeData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      suppressOutbox: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}suppress_outbox'],
      )!,
      leaseOwner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lease_owner'],
      ),
      leaseExpiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}lease_expires_at'],
      ),
    );
  }

  @override
  $SyncRuntimeTable createAlias(String alias) {
    return $SyncRuntimeTable(attachedDatabase, alias);
  }
}

class SyncRuntimeData extends DataClass implements Insertable<SyncRuntimeData> {
  final int id;
  final bool suppressOutbox;
  final String? leaseOwner;
  final DateTime? leaseExpiresAt;
  const SyncRuntimeData({
    required this.id,
    required this.suppressOutbox,
    this.leaseOwner,
    this.leaseExpiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['suppress_outbox'] = Variable<bool>(suppressOutbox);
    if (!nullToAbsent || leaseOwner != null) {
      map['lease_owner'] = Variable<String>(leaseOwner);
    }
    if (!nullToAbsent || leaseExpiresAt != null) {
      map['lease_expires_at'] = Variable<DateTime>(leaseExpiresAt);
    }
    return map;
  }

  SyncRuntimeCompanion toCompanion(bool nullToAbsent) {
    return SyncRuntimeCompanion(
      id: Value(id),
      suppressOutbox: Value(suppressOutbox),
      leaseOwner: leaseOwner == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseOwner),
      leaseExpiresAt: leaseExpiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseExpiresAt),
    );
  }

  factory SyncRuntimeData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncRuntimeData(
      id: serializer.fromJson<int>(json['id']),
      suppressOutbox: serializer.fromJson<bool>(json['suppressOutbox']),
      leaseOwner: serializer.fromJson<String?>(json['leaseOwner']),
      leaseExpiresAt: serializer.fromJson<DateTime?>(json['leaseExpiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'suppressOutbox': serializer.toJson<bool>(suppressOutbox),
      'leaseOwner': serializer.toJson<String?>(leaseOwner),
      'leaseExpiresAt': serializer.toJson<DateTime?>(leaseExpiresAt),
    };
  }

  SyncRuntimeData copyWith({
    int? id,
    bool? suppressOutbox,
    Value<String?> leaseOwner = const Value.absent(),
    Value<DateTime?> leaseExpiresAt = const Value.absent(),
  }) => SyncRuntimeData(
    id: id ?? this.id,
    suppressOutbox: suppressOutbox ?? this.suppressOutbox,
    leaseOwner: leaseOwner.present ? leaseOwner.value : this.leaseOwner,
    leaseExpiresAt: leaseExpiresAt.present
        ? leaseExpiresAt.value
        : this.leaseExpiresAt,
  );
  SyncRuntimeData copyWithCompanion(SyncRuntimeCompanion data) {
    return SyncRuntimeData(
      id: data.id.present ? data.id.value : this.id,
      suppressOutbox: data.suppressOutbox.present
          ? data.suppressOutbox.value
          : this.suppressOutbox,
      leaseOwner: data.leaseOwner.present
          ? data.leaseOwner.value
          : this.leaseOwner,
      leaseExpiresAt: data.leaseExpiresAt.present
          ? data.leaseExpiresAt.value
          : this.leaseExpiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncRuntimeData(')
          ..write('id: $id, ')
          ..write('suppressOutbox: $suppressOutbox, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseExpiresAt: $leaseExpiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, suppressOutbox, leaseOwner, leaseExpiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncRuntimeData &&
          other.id == this.id &&
          other.suppressOutbox == this.suppressOutbox &&
          other.leaseOwner == this.leaseOwner &&
          other.leaseExpiresAt == this.leaseExpiresAt);
}

class SyncRuntimeCompanion extends UpdateCompanion<SyncRuntimeData> {
  final Value<int> id;
  final Value<bool> suppressOutbox;
  final Value<String?> leaseOwner;
  final Value<DateTime?> leaseExpiresAt;
  const SyncRuntimeCompanion({
    this.id = const Value.absent(),
    this.suppressOutbox = const Value.absent(),
    this.leaseOwner = const Value.absent(),
    this.leaseExpiresAt = const Value.absent(),
  });
  SyncRuntimeCompanion.insert({
    this.id = const Value.absent(),
    this.suppressOutbox = const Value.absent(),
    this.leaseOwner = const Value.absent(),
    this.leaseExpiresAt = const Value.absent(),
  });
  static Insertable<SyncRuntimeData> custom({
    Expression<int>? id,
    Expression<bool>? suppressOutbox,
    Expression<String>? leaseOwner,
    Expression<DateTime>? leaseExpiresAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (suppressOutbox != null) 'suppress_outbox': suppressOutbox,
      if (leaseOwner != null) 'lease_owner': leaseOwner,
      if (leaseExpiresAt != null) 'lease_expires_at': leaseExpiresAt,
    });
  }

  SyncRuntimeCompanion copyWith({
    Value<int>? id,
    Value<bool>? suppressOutbox,
    Value<String?>? leaseOwner,
    Value<DateTime?>? leaseExpiresAt,
  }) {
    return SyncRuntimeCompanion(
      id: id ?? this.id,
      suppressOutbox: suppressOutbox ?? this.suppressOutbox,
      leaseOwner: leaseOwner ?? this.leaseOwner,
      leaseExpiresAt: leaseExpiresAt ?? this.leaseExpiresAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (suppressOutbox.present) {
      map['suppress_outbox'] = Variable<bool>(suppressOutbox.value);
    }
    if (leaseOwner.present) {
      map['lease_owner'] = Variable<String>(leaseOwner.value);
    }
    if (leaseExpiresAt.present) {
      map['lease_expires_at'] = Variable<DateTime>(leaseExpiresAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncRuntimeCompanion(')
          ..write('id: $id, ')
          ..write('suppressOutbox: $suppressOutbox, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseExpiresAt: $leaseExpiresAt')
          ..write(')'))
        .toString();
  }
}

class $SyncMediaCleanupTable extends SyncMediaCleanup
    with TableInfo<$SyncMediaCleanupTable, SyncMediaCleanupData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMediaCleanupTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _objectPathMeta = const VerificationMeta(
    'objectPath',
  );
  @override
  late final GeneratedColumn<String> objectPath = GeneratedColumn<String>(
    'object_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordKeyMeta = const VerificationMeta(
    'recordKey',
  );
  @override
  late final GeneratedColumn<String> recordKey = GeneratedColumn<String>(
    'record_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    objectPath,
    userId,
    entity,
    recordKey,
    createdAt,
    attempts,
    nextAttemptAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_media_cleanup';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMediaCleanupData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('object_path')) {
      context.handle(
        _objectPathMeta,
        objectPath.isAcceptableOrUnknown(data['object_path']!, _objectPathMeta),
      );
    } else if (isInserting) {
      context.missing(_objectPathMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('record_key')) {
      context.handle(
        _recordKeyMeta,
        recordKey.isAcceptableOrUnknown(data['record_key']!, _recordKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_recordKeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {objectPath};
  @override
  SyncMediaCleanupData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMediaCleanupData(
      objectPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_path'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      recordKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_key'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $SyncMediaCleanupTable createAlias(String alias) {
    return $SyncMediaCleanupTable(attachedDatabase, alias);
  }
}

class SyncMediaCleanupData extends DataClass
    implements Insertable<SyncMediaCleanupData> {
  final String objectPath;
  final String userId;
  final String entity;
  final String recordKey;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;
  const SyncMediaCleanupData({
    required this.objectPath,
    required this.userId,
    required this.entity,
    required this.recordKey,
    required this.createdAt,
    required this.attempts,
    this.nextAttemptAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['object_path'] = Variable<String>(objectPath);
    map['user_id'] = Variable<String>(userId);
    map['entity'] = Variable<String>(entity);
    map['record_key'] = Variable<String>(recordKey);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  SyncMediaCleanupCompanion toCompanion(bool nullToAbsent) {
    return SyncMediaCleanupCompanion(
      objectPath: Value(objectPath),
      userId: Value(userId),
      entity: Value(entity),
      recordKey: Value(recordKey),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory SyncMediaCleanupData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMediaCleanupData(
      objectPath: serializer.fromJson<String>(json['objectPath']),
      userId: serializer.fromJson<String>(json['userId']),
      entity: serializer.fromJson<String>(json['entity']),
      recordKey: serializer.fromJson<String>(json['recordKey']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'objectPath': serializer.toJson<String>(objectPath),
      'userId': serializer.toJson<String>(userId),
      'entity': serializer.toJson<String>(entity),
      'recordKey': serializer.toJson<String>(recordKey),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  SyncMediaCleanupData copyWith({
    String? objectPath,
    String? userId,
    String? entity,
    String? recordKey,
    DateTime? createdAt,
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) => SyncMediaCleanupData(
    objectPath: objectPath ?? this.objectPath,
    userId: userId ?? this.userId,
    entity: entity ?? this.entity,
    recordKey: recordKey ?? this.recordKey,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  SyncMediaCleanupData copyWithCompanion(SyncMediaCleanupCompanion data) {
    return SyncMediaCleanupData(
      objectPath: data.objectPath.present
          ? data.objectPath.value
          : this.objectPath,
      userId: data.userId.present ? data.userId.value : this.userId,
      entity: data.entity.present ? data.entity.value : this.entity,
      recordKey: data.recordKey.present ? data.recordKey.value : this.recordKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMediaCleanupData(')
          ..write('objectPath: $objectPath, ')
          ..write('userId: $userId, ')
          ..write('entity: $entity, ')
          ..write('recordKey: $recordKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    objectPath,
    userId,
    entity,
    recordKey,
    createdAt,
    attempts,
    nextAttemptAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMediaCleanupData &&
          other.objectPath == this.objectPath &&
          other.userId == this.userId &&
          other.entity == this.entity &&
          other.recordKey == this.recordKey &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError);
}

class SyncMediaCleanupCompanion extends UpdateCompanion<SyncMediaCleanupData> {
  final Value<String> objectPath;
  final Value<String> userId;
  final Value<String> entity;
  final Value<String> recordKey;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const SyncMediaCleanupCompanion({
    this.objectPath = const Value.absent(),
    this.userId = const Value.absent(),
    this.entity = const Value.absent(),
    this.recordKey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMediaCleanupCompanion.insert({
    required String objectPath,
    required String userId,
    required String entity,
    required String recordKey,
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : objectPath = Value(objectPath),
       userId = Value(userId),
       entity = Value(entity),
       recordKey = Value(recordKey);
  static Insertable<SyncMediaCleanupData> custom({
    Expression<String>? objectPath,
    Expression<String>? userId,
    Expression<String>? entity,
    Expression<String>? recordKey,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (objectPath != null) 'object_path': objectPath,
      if (userId != null) 'user_id': userId,
      if (entity != null) 'entity': entity,
      if (recordKey != null) 'record_key': recordKey,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMediaCleanupCompanion copyWith({
    Value<String>? objectPath,
    Value<String>? userId,
    Value<String>? entity,
    Value<String>? recordKey,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return SyncMediaCleanupCompanion(
      objectPath: objectPath ?? this.objectPath,
      userId: userId ?? this.userId,
      entity: entity ?? this.entity,
      recordKey: recordKey ?? this.recordKey,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (objectPath.present) {
      map['object_path'] = Variable<String>(objectPath.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (recordKey.present) {
      map['record_key'] = Variable<String>(recordKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMediaCleanupCompanion(')
          ..write('objectPath: $objectPath, ')
          ..write('userId: $userId, ')
          ..write('entity: $entity, ')
          ..write('recordKey: $recordKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncAccountTable extends SyncAccount
    with TableInfo<$SyncAccountTable, SyncAccountData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncAccountTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _boundUserIdMeta = const VerificationMeta(
    'boundUserId',
  );
  @override
  late final GeneratedColumn<String> boundUserId = GeneratedColumn<String>(
    'bound_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _migrationStateMeta = const VerificationMeta(
    'migrationState',
  );
  @override
  late final GeneratedColumn<String> migrationState = GeneratedColumn<String>(
    'migration_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('localOnly'),
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncAttemptAtMeta = const VerificationMeta(
    'lastSyncAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncAttemptAt =
      GeneratedColumn<DateTime>(
        'last_sync_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastSyncFailureAtMeta = const VerificationMeta(
    'lastSyncFailureAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncFailureAt =
      GeneratedColumn<DateTime>(
        'last_sync_failure_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastIntegrityCheckAtMeta =
      const VerificationMeta('lastIntegrityCheckAt');
  @override
  late final GeneratedColumn<DateTime> lastIntegrityCheckAt =
      GeneratedColumn<DateTime>(
        'last_integrity_check_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _blockedReasonMeta = const VerificationMeta(
    'blockedReason',
  );
  @override
  late final GeneratedColumn<String> blockedReason = GeneratedColumn<String>(
    'blocked_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restorePendingMeta = const VerificationMeta(
    'restorePending',
  );
  @override
  late final GeneratedColumn<bool> restorePending = GeneratedColumn<bool>(
    'restore_pending',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("restore_pending" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _backgroundResultMeta = const VerificationMeta(
    'backgroundResult',
  );
  @override
  late final GeneratedColumn<String> backgroundResult = GeneratedColumn<String>(
    'background_result',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hydrationRunIdMeta = const VerificationMeta(
    'hydrationRunId',
  );
  @override
  late final GeneratedColumn<String> hydrationRunId = GeneratedColumn<String>(
    'hydration_run_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hydrationStateMeta = const VerificationMeta(
    'hydrationState',
  );
  @override
  late final GeneratedColumn<String> hydrationState = GeneratedColumn<String>(
    'hydration_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hydrationStageMeta = const VerificationMeta(
    'hydrationStage',
  );
  @override
  late final GeneratedColumn<String> hydrationStage = GeneratedColumn<String>(
    'hydration_stage',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hydrationCompletedUnitsMeta =
      const VerificationMeta('hydrationCompletedUnits');
  @override
  late final GeneratedColumn<int> hydrationCompletedUnits =
      GeneratedColumn<int>(
        'hydration_completed_units',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _hydrationTotalUnitsMeta =
      const VerificationMeta('hydrationTotalUnits');
  @override
  late final GeneratedColumn<int> hydrationTotalUnits = GeneratedColumn<int>(
    'hydration_total_units',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _hydrationStartedAtMeta =
      const VerificationMeta('hydrationStartedAt');
  @override
  late final GeneratedColumn<DateTime> hydrationStartedAt =
      GeneratedColumn<DateTime>(
        'hydration_started_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _hydrationUpdatedAtMeta =
      const VerificationMeta('hydrationUpdatedAt');
  @override
  late final GeneratedColumn<DateTime> hydrationUpdatedAt =
      GeneratedColumn<DateTime>(
        'hydration_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _hydrationErrorMeta = const VerificationMeta(
    'hydrationError',
  );
  @override
  late final GeneratedColumn<String> hydrationError = GeneratedColumn<String>(
    'hydration_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uploadProhibitedMeta = const VerificationMeta(
    'uploadProhibited',
  );
  @override
  late final GeneratedColumn<bool> uploadProhibited = GeneratedColumn<bool>(
    'upload_prohibited',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("upload_prohibited" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _quarantineReasonMeta = const VerificationMeta(
    'quarantineReason',
  );
  @override
  late final GeneratedColumn<String> quarantineReason = GeneratedColumn<String>(
    'quarantine_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _legacyOwnerIdMeta = const VerificationMeta(
    'legacyOwnerId',
  );
  @override
  late final GeneratedColumn<String> legacyOwnerId = GeneratedColumn<String>(
    'legacy_owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    boundUserId,
    enabled,
    migrationState,
    lastSyncedAt,
    lastSyncAttemptAt,
    lastSyncFailureAt,
    lastIntegrityCheckAt,
    lastError,
    blockedReason,
    restorePending,
    backgroundResult,
    hydrationRunId,
    hydrationState,
    hydrationStage,
    hydrationCompletedUnits,
    hydrationTotalUnits,
    hydrationStartedAt,
    hydrationUpdatedAt,
    hydrationError,
    uploadProhibited,
    quarantineReason,
    legacyOwnerId,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_account';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncAccountData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('bound_user_id')) {
      context.handle(
        _boundUserIdMeta,
        boundUserId.isAcceptableOrUnknown(
          data['bound_user_id']!,
          _boundUserIdMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('migration_state')) {
      context.handle(
        _migrationStateMeta,
        migrationState.isAcceptableOrUnknown(
          data['migration_state']!,
          _migrationStateMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_attempt_at')) {
      context.handle(
        _lastSyncAttemptAtMeta,
        lastSyncAttemptAt.isAcceptableOrUnknown(
          data['last_sync_attempt_at']!,
          _lastSyncAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_sync_failure_at')) {
      context.handle(
        _lastSyncFailureAtMeta,
        lastSyncFailureAt.isAcceptableOrUnknown(
          data['last_sync_failure_at']!,
          _lastSyncFailureAtMeta,
        ),
      );
    }
    if (data.containsKey('last_integrity_check_at')) {
      context.handle(
        _lastIntegrityCheckAtMeta,
        lastIntegrityCheckAt.isAcceptableOrUnknown(
          data['last_integrity_check_at']!,
          _lastIntegrityCheckAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('blocked_reason')) {
      context.handle(
        _blockedReasonMeta,
        blockedReason.isAcceptableOrUnknown(
          data['blocked_reason']!,
          _blockedReasonMeta,
        ),
      );
    }
    if (data.containsKey('restore_pending')) {
      context.handle(
        _restorePendingMeta,
        restorePending.isAcceptableOrUnknown(
          data['restore_pending']!,
          _restorePendingMeta,
        ),
      );
    }
    if (data.containsKey('background_result')) {
      context.handle(
        _backgroundResultMeta,
        backgroundResult.isAcceptableOrUnknown(
          data['background_result']!,
          _backgroundResultMeta,
        ),
      );
    }
    if (data.containsKey('hydration_run_id')) {
      context.handle(
        _hydrationRunIdMeta,
        hydrationRunId.isAcceptableOrUnknown(
          data['hydration_run_id']!,
          _hydrationRunIdMeta,
        ),
      );
    }
    if (data.containsKey('hydration_state')) {
      context.handle(
        _hydrationStateMeta,
        hydrationState.isAcceptableOrUnknown(
          data['hydration_state']!,
          _hydrationStateMeta,
        ),
      );
    }
    if (data.containsKey('hydration_stage')) {
      context.handle(
        _hydrationStageMeta,
        hydrationStage.isAcceptableOrUnknown(
          data['hydration_stage']!,
          _hydrationStageMeta,
        ),
      );
    }
    if (data.containsKey('hydration_completed_units')) {
      context.handle(
        _hydrationCompletedUnitsMeta,
        hydrationCompletedUnits.isAcceptableOrUnknown(
          data['hydration_completed_units']!,
          _hydrationCompletedUnitsMeta,
        ),
      );
    }
    if (data.containsKey('hydration_total_units')) {
      context.handle(
        _hydrationTotalUnitsMeta,
        hydrationTotalUnits.isAcceptableOrUnknown(
          data['hydration_total_units']!,
          _hydrationTotalUnitsMeta,
        ),
      );
    }
    if (data.containsKey('hydration_started_at')) {
      context.handle(
        _hydrationStartedAtMeta,
        hydrationStartedAt.isAcceptableOrUnknown(
          data['hydration_started_at']!,
          _hydrationStartedAtMeta,
        ),
      );
    }
    if (data.containsKey('hydration_updated_at')) {
      context.handle(
        _hydrationUpdatedAtMeta,
        hydrationUpdatedAt.isAcceptableOrUnknown(
          data['hydration_updated_at']!,
          _hydrationUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('hydration_error')) {
      context.handle(
        _hydrationErrorMeta,
        hydrationError.isAcceptableOrUnknown(
          data['hydration_error']!,
          _hydrationErrorMeta,
        ),
      );
    }
    if (data.containsKey('upload_prohibited')) {
      context.handle(
        _uploadProhibitedMeta,
        uploadProhibited.isAcceptableOrUnknown(
          data['upload_prohibited']!,
          _uploadProhibitedMeta,
        ),
      );
    }
    if (data.containsKey('quarantine_reason')) {
      context.handle(
        _quarantineReasonMeta,
        quarantineReason.isAcceptableOrUnknown(
          data['quarantine_reason']!,
          _quarantineReasonMeta,
        ),
      );
    }
    if (data.containsKey('legacy_owner_id')) {
      context.handle(
        _legacyOwnerIdMeta,
        legacyOwnerId.isAcceptableOrUnknown(
          data['legacy_owner_id']!,
          _legacyOwnerIdMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncAccountData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncAccountData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      boundUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bound_user_id'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      migrationState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}migration_state'],
      )!,
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      ),
      lastSyncAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_attempt_at'],
      ),
      lastSyncFailureAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_sync_failure_at'],
      ),
      lastIntegrityCheckAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_integrity_check_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      blockedReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blocked_reason'],
      ),
      restorePending: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}restore_pending'],
      )!,
      backgroundResult: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}background_result'],
      ),
      hydrationRunId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hydration_run_id'],
      ),
      hydrationState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hydration_state'],
      ),
      hydrationStage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hydration_stage'],
      ),
      hydrationCompletedUnits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hydration_completed_units'],
      )!,
      hydrationTotalUnits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hydration_total_units'],
      )!,
      hydrationStartedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}hydration_started_at'],
      ),
      hydrationUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}hydration_updated_at'],
      ),
      hydrationError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hydration_error'],
      ),
      uploadProhibited: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}upload_prohibited'],
      )!,
      quarantineReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quarantine_reason'],
      ),
      legacyOwnerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}legacy_owner_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncAccountTable createAlias(String alias) {
    return $SyncAccountTable(attachedDatabase, alias);
  }
}

class SyncAccountData extends DataClass implements Insertable<SyncAccountData> {
  final int id;
  final String deviceId;
  final String? boundUserId;
  final bool enabled;
  final String migrationState;
  final DateTime? lastSyncedAt;
  final DateTime? lastSyncAttemptAt;
  final DateTime? lastSyncFailureAt;
  final DateTime? lastIntegrityCheckAt;
  final String? lastError;
  final String? blockedReason;
  final bool restorePending;
  final String? backgroundResult;
  final String? hydrationRunId;
  final String? hydrationState;
  final String? hydrationStage;
  final int hydrationCompletedUnits;
  final int hydrationTotalUnits;
  final DateTime? hydrationStartedAt;
  final DateTime? hydrationUpdatedAt;
  final String? hydrationError;
  final bool uploadProhibited;
  final String? quarantineReason;
  final String? legacyOwnerId;
  final DateTime updatedAt;
  const SyncAccountData({
    required this.id,
    required this.deviceId,
    this.boundUserId,
    required this.enabled,
    required this.migrationState,
    this.lastSyncedAt,
    this.lastSyncAttemptAt,
    this.lastSyncFailureAt,
    this.lastIntegrityCheckAt,
    this.lastError,
    this.blockedReason,
    required this.restorePending,
    this.backgroundResult,
    this.hydrationRunId,
    this.hydrationState,
    this.hydrationStage,
    required this.hydrationCompletedUnits,
    required this.hydrationTotalUnits,
    this.hydrationStartedAt,
    this.hydrationUpdatedAt,
    this.hydrationError,
    required this.uploadProhibited,
    this.quarantineReason,
    this.legacyOwnerId,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || boundUserId != null) {
      map['bound_user_id'] = Variable<String>(boundUserId);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['migration_state'] = Variable<String>(migrationState);
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    }
    if (!nullToAbsent || lastSyncAttemptAt != null) {
      map['last_sync_attempt_at'] = Variable<DateTime>(lastSyncAttemptAt);
    }
    if (!nullToAbsent || lastSyncFailureAt != null) {
      map['last_sync_failure_at'] = Variable<DateTime>(lastSyncFailureAt);
    }
    if (!nullToAbsent || lastIntegrityCheckAt != null) {
      map['last_integrity_check_at'] = Variable<DateTime>(lastIntegrityCheckAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || blockedReason != null) {
      map['blocked_reason'] = Variable<String>(blockedReason);
    }
    map['restore_pending'] = Variable<bool>(restorePending);
    if (!nullToAbsent || backgroundResult != null) {
      map['background_result'] = Variable<String>(backgroundResult);
    }
    if (!nullToAbsent || hydrationRunId != null) {
      map['hydration_run_id'] = Variable<String>(hydrationRunId);
    }
    if (!nullToAbsent || hydrationState != null) {
      map['hydration_state'] = Variable<String>(hydrationState);
    }
    if (!nullToAbsent || hydrationStage != null) {
      map['hydration_stage'] = Variable<String>(hydrationStage);
    }
    map['hydration_completed_units'] = Variable<int>(hydrationCompletedUnits);
    map['hydration_total_units'] = Variable<int>(hydrationTotalUnits);
    if (!nullToAbsent || hydrationStartedAt != null) {
      map['hydration_started_at'] = Variable<DateTime>(hydrationStartedAt);
    }
    if (!nullToAbsent || hydrationUpdatedAt != null) {
      map['hydration_updated_at'] = Variable<DateTime>(hydrationUpdatedAt);
    }
    if (!nullToAbsent || hydrationError != null) {
      map['hydration_error'] = Variable<String>(hydrationError);
    }
    map['upload_prohibited'] = Variable<bool>(uploadProhibited);
    if (!nullToAbsent || quarantineReason != null) {
      map['quarantine_reason'] = Variable<String>(quarantineReason);
    }
    if (!nullToAbsent || legacyOwnerId != null) {
      map['legacy_owner_id'] = Variable<String>(legacyOwnerId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncAccountCompanion toCompanion(bool nullToAbsent) {
    return SyncAccountCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      boundUserId: boundUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(boundUserId),
      enabled: Value(enabled),
      migrationState: Value(migrationState),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
      lastSyncAttemptAt: lastSyncAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncAttemptAt),
      lastSyncFailureAt: lastSyncFailureAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncFailureAt),
      lastIntegrityCheckAt: lastIntegrityCheckAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastIntegrityCheckAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      blockedReason: blockedReason == null && nullToAbsent
          ? const Value.absent()
          : Value(blockedReason),
      restorePending: Value(restorePending),
      backgroundResult: backgroundResult == null && nullToAbsent
          ? const Value.absent()
          : Value(backgroundResult),
      hydrationRunId: hydrationRunId == null && nullToAbsent
          ? const Value.absent()
          : Value(hydrationRunId),
      hydrationState: hydrationState == null && nullToAbsent
          ? const Value.absent()
          : Value(hydrationState),
      hydrationStage: hydrationStage == null && nullToAbsent
          ? const Value.absent()
          : Value(hydrationStage),
      hydrationCompletedUnits: Value(hydrationCompletedUnits),
      hydrationTotalUnits: Value(hydrationTotalUnits),
      hydrationStartedAt: hydrationStartedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(hydrationStartedAt),
      hydrationUpdatedAt: hydrationUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(hydrationUpdatedAt),
      hydrationError: hydrationError == null && nullToAbsent
          ? const Value.absent()
          : Value(hydrationError),
      uploadProhibited: Value(uploadProhibited),
      quarantineReason: quarantineReason == null && nullToAbsent
          ? const Value.absent()
          : Value(quarantineReason),
      legacyOwnerId: legacyOwnerId == null && nullToAbsent
          ? const Value.absent()
          : Value(legacyOwnerId),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncAccountData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncAccountData(
      id: serializer.fromJson<int>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      boundUserId: serializer.fromJson<String?>(json['boundUserId']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      migrationState: serializer.fromJson<String>(json['migrationState']),
      lastSyncedAt: serializer.fromJson<DateTime?>(json['lastSyncedAt']),
      lastSyncAttemptAt: serializer.fromJson<DateTime?>(
        json['lastSyncAttemptAt'],
      ),
      lastSyncFailureAt: serializer.fromJson<DateTime?>(
        json['lastSyncFailureAt'],
      ),
      lastIntegrityCheckAt: serializer.fromJson<DateTime?>(
        json['lastIntegrityCheckAt'],
      ),
      lastError: serializer.fromJson<String?>(json['lastError']),
      blockedReason: serializer.fromJson<String?>(json['blockedReason']),
      restorePending: serializer.fromJson<bool>(json['restorePending']),
      backgroundResult: serializer.fromJson<String?>(json['backgroundResult']),
      hydrationRunId: serializer.fromJson<String?>(json['hydrationRunId']),
      hydrationState: serializer.fromJson<String?>(json['hydrationState']),
      hydrationStage: serializer.fromJson<String?>(json['hydrationStage']),
      hydrationCompletedUnits: serializer.fromJson<int>(
        json['hydrationCompletedUnits'],
      ),
      hydrationTotalUnits: serializer.fromJson<int>(
        json['hydrationTotalUnits'],
      ),
      hydrationStartedAt: serializer.fromJson<DateTime?>(
        json['hydrationStartedAt'],
      ),
      hydrationUpdatedAt: serializer.fromJson<DateTime?>(
        json['hydrationUpdatedAt'],
      ),
      hydrationError: serializer.fromJson<String?>(json['hydrationError']),
      uploadProhibited: serializer.fromJson<bool>(json['uploadProhibited']),
      quarantineReason: serializer.fromJson<String?>(json['quarantineReason']),
      legacyOwnerId: serializer.fromJson<String?>(json['legacyOwnerId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'boundUserId': serializer.toJson<String?>(boundUserId),
      'enabled': serializer.toJson<bool>(enabled),
      'migrationState': serializer.toJson<String>(migrationState),
      'lastSyncedAt': serializer.toJson<DateTime?>(lastSyncedAt),
      'lastSyncAttemptAt': serializer.toJson<DateTime?>(lastSyncAttemptAt),
      'lastSyncFailureAt': serializer.toJson<DateTime?>(lastSyncFailureAt),
      'lastIntegrityCheckAt': serializer.toJson<DateTime?>(
        lastIntegrityCheckAt,
      ),
      'lastError': serializer.toJson<String?>(lastError),
      'blockedReason': serializer.toJson<String?>(blockedReason),
      'restorePending': serializer.toJson<bool>(restorePending),
      'backgroundResult': serializer.toJson<String?>(backgroundResult),
      'hydrationRunId': serializer.toJson<String?>(hydrationRunId),
      'hydrationState': serializer.toJson<String?>(hydrationState),
      'hydrationStage': serializer.toJson<String?>(hydrationStage),
      'hydrationCompletedUnits': serializer.toJson<int>(
        hydrationCompletedUnits,
      ),
      'hydrationTotalUnits': serializer.toJson<int>(hydrationTotalUnits),
      'hydrationStartedAt': serializer.toJson<DateTime?>(hydrationStartedAt),
      'hydrationUpdatedAt': serializer.toJson<DateTime?>(hydrationUpdatedAt),
      'hydrationError': serializer.toJson<String?>(hydrationError),
      'uploadProhibited': serializer.toJson<bool>(uploadProhibited),
      'quarantineReason': serializer.toJson<String?>(quarantineReason),
      'legacyOwnerId': serializer.toJson<String?>(legacyOwnerId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncAccountData copyWith({
    int? id,
    String? deviceId,
    Value<String?> boundUserId = const Value.absent(),
    bool? enabled,
    String? migrationState,
    Value<DateTime?> lastSyncedAt = const Value.absent(),
    Value<DateTime?> lastSyncAttemptAt = const Value.absent(),
    Value<DateTime?> lastSyncFailureAt = const Value.absent(),
    Value<DateTime?> lastIntegrityCheckAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    Value<String?> blockedReason = const Value.absent(),
    bool? restorePending,
    Value<String?> backgroundResult = const Value.absent(),
    Value<String?> hydrationRunId = const Value.absent(),
    Value<String?> hydrationState = const Value.absent(),
    Value<String?> hydrationStage = const Value.absent(),
    int? hydrationCompletedUnits,
    int? hydrationTotalUnits,
    Value<DateTime?> hydrationStartedAt = const Value.absent(),
    Value<DateTime?> hydrationUpdatedAt = const Value.absent(),
    Value<String?> hydrationError = const Value.absent(),
    bool? uploadProhibited,
    Value<String?> quarantineReason = const Value.absent(),
    Value<String?> legacyOwnerId = const Value.absent(),
    DateTime? updatedAt,
  }) => SyncAccountData(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    boundUserId: boundUserId.present ? boundUserId.value : this.boundUserId,
    enabled: enabled ?? this.enabled,
    migrationState: migrationState ?? this.migrationState,
    lastSyncedAt: lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
    lastSyncAttemptAt: lastSyncAttemptAt.present
        ? lastSyncAttemptAt.value
        : this.lastSyncAttemptAt,
    lastSyncFailureAt: lastSyncFailureAt.present
        ? lastSyncFailureAt.value
        : this.lastSyncFailureAt,
    lastIntegrityCheckAt: lastIntegrityCheckAt.present
        ? lastIntegrityCheckAt.value
        : this.lastIntegrityCheckAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    blockedReason: blockedReason.present
        ? blockedReason.value
        : this.blockedReason,
    restorePending: restorePending ?? this.restorePending,
    backgroundResult: backgroundResult.present
        ? backgroundResult.value
        : this.backgroundResult,
    hydrationRunId: hydrationRunId.present
        ? hydrationRunId.value
        : this.hydrationRunId,
    hydrationState: hydrationState.present
        ? hydrationState.value
        : this.hydrationState,
    hydrationStage: hydrationStage.present
        ? hydrationStage.value
        : this.hydrationStage,
    hydrationCompletedUnits:
        hydrationCompletedUnits ?? this.hydrationCompletedUnits,
    hydrationTotalUnits: hydrationTotalUnits ?? this.hydrationTotalUnits,
    hydrationStartedAt: hydrationStartedAt.present
        ? hydrationStartedAt.value
        : this.hydrationStartedAt,
    hydrationUpdatedAt: hydrationUpdatedAt.present
        ? hydrationUpdatedAt.value
        : this.hydrationUpdatedAt,
    hydrationError: hydrationError.present
        ? hydrationError.value
        : this.hydrationError,
    uploadProhibited: uploadProhibited ?? this.uploadProhibited,
    quarantineReason: quarantineReason.present
        ? quarantineReason.value
        : this.quarantineReason,
    legacyOwnerId: legacyOwnerId.present
        ? legacyOwnerId.value
        : this.legacyOwnerId,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncAccountData copyWithCompanion(SyncAccountCompanion data) {
    return SyncAccountData(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      boundUserId: data.boundUserId.present
          ? data.boundUserId.value
          : this.boundUserId,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      migrationState: data.migrationState.present
          ? data.migrationState.value
          : this.migrationState,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      lastSyncAttemptAt: data.lastSyncAttemptAt.present
          ? data.lastSyncAttemptAt.value
          : this.lastSyncAttemptAt,
      lastSyncFailureAt: data.lastSyncFailureAt.present
          ? data.lastSyncFailureAt.value
          : this.lastSyncFailureAt,
      lastIntegrityCheckAt: data.lastIntegrityCheckAt.present
          ? data.lastIntegrityCheckAt.value
          : this.lastIntegrityCheckAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      blockedReason: data.blockedReason.present
          ? data.blockedReason.value
          : this.blockedReason,
      restorePending: data.restorePending.present
          ? data.restorePending.value
          : this.restorePending,
      backgroundResult: data.backgroundResult.present
          ? data.backgroundResult.value
          : this.backgroundResult,
      hydrationRunId: data.hydrationRunId.present
          ? data.hydrationRunId.value
          : this.hydrationRunId,
      hydrationState: data.hydrationState.present
          ? data.hydrationState.value
          : this.hydrationState,
      hydrationStage: data.hydrationStage.present
          ? data.hydrationStage.value
          : this.hydrationStage,
      hydrationCompletedUnits: data.hydrationCompletedUnits.present
          ? data.hydrationCompletedUnits.value
          : this.hydrationCompletedUnits,
      hydrationTotalUnits: data.hydrationTotalUnits.present
          ? data.hydrationTotalUnits.value
          : this.hydrationTotalUnits,
      hydrationStartedAt: data.hydrationStartedAt.present
          ? data.hydrationStartedAt.value
          : this.hydrationStartedAt,
      hydrationUpdatedAt: data.hydrationUpdatedAt.present
          ? data.hydrationUpdatedAt.value
          : this.hydrationUpdatedAt,
      hydrationError: data.hydrationError.present
          ? data.hydrationError.value
          : this.hydrationError,
      uploadProhibited: data.uploadProhibited.present
          ? data.uploadProhibited.value
          : this.uploadProhibited,
      quarantineReason: data.quarantineReason.present
          ? data.quarantineReason.value
          : this.quarantineReason,
      legacyOwnerId: data.legacyOwnerId.present
          ? data.legacyOwnerId.value
          : this.legacyOwnerId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncAccountData(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('boundUserId: $boundUserId, ')
          ..write('enabled: $enabled, ')
          ..write('migrationState: $migrationState, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('lastSyncAttemptAt: $lastSyncAttemptAt, ')
          ..write('lastSyncFailureAt: $lastSyncFailureAt, ')
          ..write('lastIntegrityCheckAt: $lastIntegrityCheckAt, ')
          ..write('lastError: $lastError, ')
          ..write('blockedReason: $blockedReason, ')
          ..write('restorePending: $restorePending, ')
          ..write('backgroundResult: $backgroundResult, ')
          ..write('hydrationRunId: $hydrationRunId, ')
          ..write('hydrationState: $hydrationState, ')
          ..write('hydrationStage: $hydrationStage, ')
          ..write('hydrationCompletedUnits: $hydrationCompletedUnits, ')
          ..write('hydrationTotalUnits: $hydrationTotalUnits, ')
          ..write('hydrationStartedAt: $hydrationStartedAt, ')
          ..write('hydrationUpdatedAt: $hydrationUpdatedAt, ')
          ..write('hydrationError: $hydrationError, ')
          ..write('uploadProhibited: $uploadProhibited, ')
          ..write('quarantineReason: $quarantineReason, ')
          ..write('legacyOwnerId: $legacyOwnerId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    deviceId,
    boundUserId,
    enabled,
    migrationState,
    lastSyncedAt,
    lastSyncAttemptAt,
    lastSyncFailureAt,
    lastIntegrityCheckAt,
    lastError,
    blockedReason,
    restorePending,
    backgroundResult,
    hydrationRunId,
    hydrationState,
    hydrationStage,
    hydrationCompletedUnits,
    hydrationTotalUnits,
    hydrationStartedAt,
    hydrationUpdatedAt,
    hydrationError,
    uploadProhibited,
    quarantineReason,
    legacyOwnerId,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncAccountData &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.boundUserId == this.boundUserId &&
          other.enabled == this.enabled &&
          other.migrationState == this.migrationState &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.lastSyncAttemptAt == this.lastSyncAttemptAt &&
          other.lastSyncFailureAt == this.lastSyncFailureAt &&
          other.lastIntegrityCheckAt == this.lastIntegrityCheckAt &&
          other.lastError == this.lastError &&
          other.blockedReason == this.blockedReason &&
          other.restorePending == this.restorePending &&
          other.backgroundResult == this.backgroundResult &&
          other.hydrationRunId == this.hydrationRunId &&
          other.hydrationState == this.hydrationState &&
          other.hydrationStage == this.hydrationStage &&
          other.hydrationCompletedUnits == this.hydrationCompletedUnits &&
          other.hydrationTotalUnits == this.hydrationTotalUnits &&
          other.hydrationStartedAt == this.hydrationStartedAt &&
          other.hydrationUpdatedAt == this.hydrationUpdatedAt &&
          other.hydrationError == this.hydrationError &&
          other.uploadProhibited == this.uploadProhibited &&
          other.quarantineReason == this.quarantineReason &&
          other.legacyOwnerId == this.legacyOwnerId &&
          other.updatedAt == this.updatedAt);
}

class SyncAccountCompanion extends UpdateCompanion<SyncAccountData> {
  final Value<int> id;
  final Value<String> deviceId;
  final Value<String?> boundUserId;
  final Value<bool> enabled;
  final Value<String> migrationState;
  final Value<DateTime?> lastSyncedAt;
  final Value<DateTime?> lastSyncAttemptAt;
  final Value<DateTime?> lastSyncFailureAt;
  final Value<DateTime?> lastIntegrityCheckAt;
  final Value<String?> lastError;
  final Value<String?> blockedReason;
  final Value<bool> restorePending;
  final Value<String?> backgroundResult;
  final Value<String?> hydrationRunId;
  final Value<String?> hydrationState;
  final Value<String?> hydrationStage;
  final Value<int> hydrationCompletedUnits;
  final Value<int> hydrationTotalUnits;
  final Value<DateTime?> hydrationStartedAt;
  final Value<DateTime?> hydrationUpdatedAt;
  final Value<String?> hydrationError;
  final Value<bool> uploadProhibited;
  final Value<String?> quarantineReason;
  final Value<String?> legacyOwnerId;
  final Value<DateTime> updatedAt;
  const SyncAccountCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.boundUserId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.migrationState = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.lastSyncAttemptAt = const Value.absent(),
    this.lastSyncFailureAt = const Value.absent(),
    this.lastIntegrityCheckAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.blockedReason = const Value.absent(),
    this.restorePending = const Value.absent(),
    this.backgroundResult = const Value.absent(),
    this.hydrationRunId = const Value.absent(),
    this.hydrationState = const Value.absent(),
    this.hydrationStage = const Value.absent(),
    this.hydrationCompletedUnits = const Value.absent(),
    this.hydrationTotalUnits = const Value.absent(),
    this.hydrationStartedAt = const Value.absent(),
    this.hydrationUpdatedAt = const Value.absent(),
    this.hydrationError = const Value.absent(),
    this.uploadProhibited = const Value.absent(),
    this.quarantineReason = const Value.absent(),
    this.legacyOwnerId = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SyncAccountCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    this.boundUserId = const Value.absent(),
    this.enabled = const Value.absent(),
    this.migrationState = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.lastSyncAttemptAt = const Value.absent(),
    this.lastSyncFailureAt = const Value.absent(),
    this.lastIntegrityCheckAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.blockedReason = const Value.absent(),
    this.restorePending = const Value.absent(),
    this.backgroundResult = const Value.absent(),
    this.hydrationRunId = const Value.absent(),
    this.hydrationState = const Value.absent(),
    this.hydrationStage = const Value.absent(),
    this.hydrationCompletedUnits = const Value.absent(),
    this.hydrationTotalUnits = const Value.absent(),
    this.hydrationStartedAt = const Value.absent(),
    this.hydrationUpdatedAt = const Value.absent(),
    this.hydrationError = const Value.absent(),
    this.uploadProhibited = const Value.absent(),
    this.quarantineReason = const Value.absent(),
    this.legacyOwnerId = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : deviceId = Value(deviceId);
  static Insertable<SyncAccountData> custom({
    Expression<int>? id,
    Expression<String>? deviceId,
    Expression<String>? boundUserId,
    Expression<bool>? enabled,
    Expression<String>? migrationState,
    Expression<DateTime>? lastSyncedAt,
    Expression<DateTime>? lastSyncAttemptAt,
    Expression<DateTime>? lastSyncFailureAt,
    Expression<DateTime>? lastIntegrityCheckAt,
    Expression<String>? lastError,
    Expression<String>? blockedReason,
    Expression<bool>? restorePending,
    Expression<String>? backgroundResult,
    Expression<String>? hydrationRunId,
    Expression<String>? hydrationState,
    Expression<String>? hydrationStage,
    Expression<int>? hydrationCompletedUnits,
    Expression<int>? hydrationTotalUnits,
    Expression<DateTime>? hydrationStartedAt,
    Expression<DateTime>? hydrationUpdatedAt,
    Expression<String>? hydrationError,
    Expression<bool>? uploadProhibited,
    Expression<String>? quarantineReason,
    Expression<String>? legacyOwnerId,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (boundUserId != null) 'bound_user_id': boundUserId,
      if (enabled != null) 'enabled': enabled,
      if (migrationState != null) 'migration_state': migrationState,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (lastSyncAttemptAt != null) 'last_sync_attempt_at': lastSyncAttemptAt,
      if (lastSyncFailureAt != null) 'last_sync_failure_at': lastSyncFailureAt,
      if (lastIntegrityCheckAt != null)
        'last_integrity_check_at': lastIntegrityCheckAt,
      if (lastError != null) 'last_error': lastError,
      if (blockedReason != null) 'blocked_reason': blockedReason,
      if (restorePending != null) 'restore_pending': restorePending,
      if (backgroundResult != null) 'background_result': backgroundResult,
      if (hydrationRunId != null) 'hydration_run_id': hydrationRunId,
      if (hydrationState != null) 'hydration_state': hydrationState,
      if (hydrationStage != null) 'hydration_stage': hydrationStage,
      if (hydrationCompletedUnits != null)
        'hydration_completed_units': hydrationCompletedUnits,
      if (hydrationTotalUnits != null)
        'hydration_total_units': hydrationTotalUnits,
      if (hydrationStartedAt != null)
        'hydration_started_at': hydrationStartedAt,
      if (hydrationUpdatedAt != null)
        'hydration_updated_at': hydrationUpdatedAt,
      if (hydrationError != null) 'hydration_error': hydrationError,
      if (uploadProhibited != null) 'upload_prohibited': uploadProhibited,
      if (quarantineReason != null) 'quarantine_reason': quarantineReason,
      if (legacyOwnerId != null) 'legacy_owner_id': legacyOwnerId,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SyncAccountCompanion copyWith({
    Value<int>? id,
    Value<String>? deviceId,
    Value<String?>? boundUserId,
    Value<bool>? enabled,
    Value<String>? migrationState,
    Value<DateTime?>? lastSyncedAt,
    Value<DateTime?>? lastSyncAttemptAt,
    Value<DateTime?>? lastSyncFailureAt,
    Value<DateTime?>? lastIntegrityCheckAt,
    Value<String?>? lastError,
    Value<String?>? blockedReason,
    Value<bool>? restorePending,
    Value<String?>? backgroundResult,
    Value<String?>? hydrationRunId,
    Value<String?>? hydrationState,
    Value<String?>? hydrationStage,
    Value<int>? hydrationCompletedUnits,
    Value<int>? hydrationTotalUnits,
    Value<DateTime?>? hydrationStartedAt,
    Value<DateTime?>? hydrationUpdatedAt,
    Value<String?>? hydrationError,
    Value<bool>? uploadProhibited,
    Value<String?>? quarantineReason,
    Value<String?>? legacyOwnerId,
    Value<DateTime>? updatedAt,
  }) {
    return SyncAccountCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      boundUserId: boundUserId ?? this.boundUserId,
      enabled: enabled ?? this.enabled,
      migrationState: migrationState ?? this.migrationState,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastSyncAttemptAt: lastSyncAttemptAt ?? this.lastSyncAttemptAt,
      lastSyncFailureAt: lastSyncFailureAt ?? this.lastSyncFailureAt,
      lastIntegrityCheckAt: lastIntegrityCheckAt ?? this.lastIntegrityCheckAt,
      lastError: lastError ?? this.lastError,
      blockedReason: blockedReason ?? this.blockedReason,
      restorePending: restorePending ?? this.restorePending,
      backgroundResult: backgroundResult ?? this.backgroundResult,
      hydrationRunId: hydrationRunId ?? this.hydrationRunId,
      hydrationState: hydrationState ?? this.hydrationState,
      hydrationStage: hydrationStage ?? this.hydrationStage,
      hydrationCompletedUnits:
          hydrationCompletedUnits ?? this.hydrationCompletedUnits,
      hydrationTotalUnits: hydrationTotalUnits ?? this.hydrationTotalUnits,
      hydrationStartedAt: hydrationStartedAt ?? this.hydrationStartedAt,
      hydrationUpdatedAt: hydrationUpdatedAt ?? this.hydrationUpdatedAt,
      hydrationError: hydrationError ?? this.hydrationError,
      uploadProhibited: uploadProhibited ?? this.uploadProhibited,
      quarantineReason: quarantineReason ?? this.quarantineReason,
      legacyOwnerId: legacyOwnerId ?? this.legacyOwnerId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (boundUserId.present) {
      map['bound_user_id'] = Variable<String>(boundUserId.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (migrationState.present) {
      map['migration_state'] = Variable<String>(migrationState.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (lastSyncAttemptAt.present) {
      map['last_sync_attempt_at'] = Variable<DateTime>(lastSyncAttemptAt.value);
    }
    if (lastSyncFailureAt.present) {
      map['last_sync_failure_at'] = Variable<DateTime>(lastSyncFailureAt.value);
    }
    if (lastIntegrityCheckAt.present) {
      map['last_integrity_check_at'] = Variable<DateTime>(
        lastIntegrityCheckAt.value,
      );
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (blockedReason.present) {
      map['blocked_reason'] = Variable<String>(blockedReason.value);
    }
    if (restorePending.present) {
      map['restore_pending'] = Variable<bool>(restorePending.value);
    }
    if (backgroundResult.present) {
      map['background_result'] = Variable<String>(backgroundResult.value);
    }
    if (hydrationRunId.present) {
      map['hydration_run_id'] = Variable<String>(hydrationRunId.value);
    }
    if (hydrationState.present) {
      map['hydration_state'] = Variable<String>(hydrationState.value);
    }
    if (hydrationStage.present) {
      map['hydration_stage'] = Variable<String>(hydrationStage.value);
    }
    if (hydrationCompletedUnits.present) {
      map['hydration_completed_units'] = Variable<int>(
        hydrationCompletedUnits.value,
      );
    }
    if (hydrationTotalUnits.present) {
      map['hydration_total_units'] = Variable<int>(hydrationTotalUnits.value);
    }
    if (hydrationStartedAt.present) {
      map['hydration_started_at'] = Variable<DateTime>(
        hydrationStartedAt.value,
      );
    }
    if (hydrationUpdatedAt.present) {
      map['hydration_updated_at'] = Variable<DateTime>(
        hydrationUpdatedAt.value,
      );
    }
    if (hydrationError.present) {
      map['hydration_error'] = Variable<String>(hydrationError.value);
    }
    if (uploadProhibited.present) {
      map['upload_prohibited'] = Variable<bool>(uploadProhibited.value);
    }
    if (quarantineReason.present) {
      map['quarantine_reason'] = Variable<String>(quarantineReason.value);
    }
    if (legacyOwnerId.present) {
      map['legacy_owner_id'] = Variable<String>(legacyOwnerId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncAccountCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('boundUserId: $boundUserId, ')
          ..write('enabled: $enabled, ')
          ..write('migrationState: $migrationState, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('lastSyncAttemptAt: $lastSyncAttemptAt, ')
          ..write('lastSyncFailureAt: $lastSyncFailureAt, ')
          ..write('lastIntegrityCheckAt: $lastIntegrityCheckAt, ')
          ..write('lastError: $lastError, ')
          ..write('blockedReason: $blockedReason, ')
          ..write('restorePending: $restorePending, ')
          ..write('backgroundResult: $backgroundResult, ')
          ..write('hydrationRunId: $hydrationRunId, ')
          ..write('hydrationState: $hydrationState, ')
          ..write('hydrationStage: $hydrationStage, ')
          ..write('hydrationCompletedUnits: $hydrationCompletedUnits, ')
          ..write('hydrationTotalUnits: $hydrationTotalUnits, ')
          ..write('hydrationStartedAt: $hydrationStartedAt, ')
          ..write('hydrationUpdatedAt: $hydrationUpdatedAt, ')
          ..write('hydrationError: $hydrationError, ')
          ..write('uploadProhibited: $uploadProhibited, ')
          ..write('quarantineReason: $quarantineReason, ')
          ..write('legacyOwnerId: $legacyOwnerId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $NotificationReconciliationRequestsTable
    extends NotificationReconciliationRequests
    with
        TableInfo<
          $NotificationReconciliationRequestsTable,
          NotificationReconciliationRequestRow
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotificationReconciliationRequestsTable(
    this.attachedDatabase, [
    this._alias,
  ]);
  static const VerificationMeta _scopeKeyMeta = const VerificationMeta(
    'scopeKey',
  );
  @override
  late final GeneratedColumn<String> scopeKey = GeneratedColumn<String>(
    'scope_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMessageMeta = const VerificationMeta(
    'lastErrorMessage',
  );
  @override
  late final GeneratedColumn<String> lastErrorMessage = GeneratedColumn<String>(
    'last_error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _requiresFullRebuildMeta =
      const VerificationMeta('requiresFullRebuild');
  @override
  late final GeneratedColumn<bool> requiresFullRebuild = GeneratedColumn<bool>(
    'requires_full_rebuild',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("requires_full_rebuild" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    scopeKey,
    planId,
    reason,
    createdAt,
    updatedAt,
    attempts,
    nextAttemptAt,
    lastErrorCode,
    lastErrorMessage,
    requiresFullRebuild,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notification_reconciliation_requests';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationReconciliationRequestRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope_key')) {
      context.handle(
        _scopeKeyMeta,
        scopeKey.isAcceptableOrUnknown(data['scope_key']!, _scopeKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeKeyMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('last_error_message')) {
      context.handle(
        _lastErrorMessageMeta,
        lastErrorMessage.isAcceptableOrUnknown(
          data['last_error_message']!,
          _lastErrorMessageMeta,
        ),
      );
    }
    if (data.containsKey('requires_full_rebuild')) {
      context.handle(
        _requiresFullRebuildMeta,
        requiresFullRebuild.isAcceptableOrUnknown(
          data['requires_full_rebuild']!,
          _requiresFullRebuildMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scopeKey};
  @override
  NotificationReconciliationRequestRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationReconciliationRequestRow(
      scopeKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_key'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      ),
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      lastErrorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_message'],
      ),
      requiresFullRebuild: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}requires_full_rebuild'],
      )!,
    );
  }

  @override
  $NotificationReconciliationRequestsTable createAlias(String alias) {
    return $NotificationReconciliationRequestsTable(attachedDatabase, alias);
  }
}

class NotificationReconciliationRequestRow extends DataClass
    implements Insertable<NotificationReconciliationRequestRow> {
  final String scopeKey;
  final String? planId;
  final String reason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final bool requiresFullRebuild;
  const NotificationReconciliationRequestRow({
    required this.scopeKey,
    this.planId,
    required this.reason,
    required this.createdAt,
    required this.updatedAt,
    required this.attempts,
    this.nextAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    required this.requiresFullRebuild,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope_key'] = Variable<String>(scopeKey);
    if (!nullToAbsent || planId != null) {
      map['plan_id'] = Variable<String>(planId);
    }
    map['reason'] = Variable<String>(reason);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastErrorMessage != null) {
      map['last_error_message'] = Variable<String>(lastErrorMessage);
    }
    map['requires_full_rebuild'] = Variable<bool>(requiresFullRebuild);
    return map;
  }

  NotificationReconciliationRequestsCompanion toCompanion(bool nullToAbsent) {
    return NotificationReconciliationRequestsCompanion(
      scopeKey: Value(scopeKey),
      planId: planId == null && nullToAbsent
          ? const Value.absent()
          : Value(planId),
      reason: Value(reason),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      lastErrorMessage: lastErrorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorMessage),
      requiresFullRebuild: Value(requiresFullRebuild),
    );
  }

  factory NotificationReconciliationRequestRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationReconciliationRequestRow(
      scopeKey: serializer.fromJson<String>(json['scopeKey']),
      planId: serializer.fromJson<String?>(json['planId']),
      reason: serializer.fromJson<String>(json['reason']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastErrorMessage: serializer.fromJson<String?>(json['lastErrorMessage']),
      requiresFullRebuild: serializer.fromJson<bool>(
        json['requiresFullRebuild'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scopeKey': serializer.toJson<String>(scopeKey),
      'planId': serializer.toJson<String?>(planId),
      'reason': serializer.toJson<String>(reason),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastErrorMessage': serializer.toJson<String?>(lastErrorMessage),
      'requiresFullRebuild': serializer.toJson<bool>(requiresFullRebuild),
    };
  }

  NotificationReconciliationRequestRow copyWith({
    String? scopeKey,
    Value<String?> planId = const Value.absent(),
    String? reason,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastErrorMessage = const Value.absent(),
    bool? requiresFullRebuild,
  }) => NotificationReconciliationRequestRow(
    scopeKey: scopeKey ?? this.scopeKey,
    planId: planId.present ? planId.value : this.planId,
    reason: reason ?? this.reason,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    lastErrorMessage: lastErrorMessage.present
        ? lastErrorMessage.value
        : this.lastErrorMessage,
    requiresFullRebuild: requiresFullRebuild ?? this.requiresFullRebuild,
  );
  NotificationReconciliationRequestRow copyWithCompanion(
    NotificationReconciliationRequestsCompanion data,
  ) {
    return NotificationReconciliationRequestRow(
      scopeKey: data.scopeKey.present ? data.scopeKey.value : this.scopeKey,
      planId: data.planId.present ? data.planId.value : this.planId,
      reason: data.reason.present ? data.reason.value : this.reason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      lastErrorMessage: data.lastErrorMessage.present
          ? data.lastErrorMessage.value
          : this.lastErrorMessage,
      requiresFullRebuild: data.requiresFullRebuild.present
          ? data.requiresFullRebuild.value
          : this.requiresFullRebuild,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationReconciliationRequestRow(')
          ..write('scopeKey: $scopeKey, ')
          ..write('planId: $planId, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('requiresFullRebuild: $requiresFullRebuild')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    scopeKey,
    planId,
    reason,
    createdAt,
    updatedAt,
    attempts,
    nextAttemptAt,
    lastErrorCode,
    lastErrorMessage,
    requiresFullRebuild,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationReconciliationRequestRow &&
          other.scopeKey == this.scopeKey &&
          other.planId == this.planId &&
          other.reason == this.reason &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastErrorMessage == this.lastErrorMessage &&
          other.requiresFullRebuild == this.requiresFullRebuild);
}

class NotificationReconciliationRequestsCompanion
    extends UpdateCompanion<NotificationReconciliationRequestRow> {
  final Value<String> scopeKey;
  final Value<String?> planId;
  final Value<String> reason;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastErrorCode;
  final Value<String?> lastErrorMessage;
  final Value<bool> requiresFullRebuild;
  final Value<int> rowid;
  const NotificationReconciliationRequestsCompanion({
    this.scopeKey = const Value.absent(),
    this.planId = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.requiresFullRebuild = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotificationReconciliationRequestsCompanion.insert({
    required String scopeKey,
    this.planId = const Value.absent(),
    required String reason,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.requiresFullRebuild = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : scopeKey = Value(scopeKey),
       reason = Value(reason);
  static Insertable<NotificationReconciliationRequestRow> custom({
    Expression<String>? scopeKey,
    Expression<String>? planId,
    Expression<String>? reason,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastErrorCode,
    Expression<String>? lastErrorMessage,
    Expression<bool>? requiresFullRebuild,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scopeKey != null) 'scope_key': scopeKey,
      if (planId != null) 'plan_id': planId,
      if (reason != null) 'reason': reason,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
      if (requiresFullRebuild != null)
        'requires_full_rebuild': requiresFullRebuild,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotificationReconciliationRequestsCompanion copyWith({
    Value<String>? scopeKey,
    Value<String?>? planId,
    Value<String>? reason,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastErrorCode,
    Value<String?>? lastErrorMessage,
    Value<bool>? requiresFullRebuild,
    Value<int>? rowid,
  }) {
    return NotificationReconciliationRequestsCompanion(
      scopeKey: scopeKey ?? this.scopeKey,
      planId: planId ?? this.planId,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      requiresFullRebuild: requiresFullRebuild ?? this.requiresFullRebuild,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scopeKey.present) {
      map['scope_key'] = Variable<String>(scopeKey.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastErrorMessage.present) {
      map['last_error_message'] = Variable<String>(lastErrorMessage.value);
    }
    if (requiresFullRebuild.present) {
      map['requires_full_rebuild'] = Variable<bool>(requiresFullRebuild.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationReconciliationRequestsCompanion(')
          ..write('scopeKey: $scopeKey, ')
          ..write('planId: $planId, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('requiresFullRebuild: $requiresFullRebuild, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AreasTable areas = $AreasTable(this);
  late final $RoomsTable rooms = $RoomsTable(this);
  late final $AssetsTable assets = $AssetsTable(this);
  late final $DeviceDetailsTableTable deviceDetailsTable =
      $DeviceDetailsTableTable(this);
  late final $PetDetailsTableTable petDetailsTable = $PetDetailsTableTable(
    this,
  );
  late final $PlantDetailsTableTable plantDetailsTable =
      $PlantDetailsTableTable(this);
  late final $SafetyDetailsTableTable safetyDetailsTable =
      $SafetyDetailsTableTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $AssetTagsTable assetTags = $AssetTagsTable(this);
  late final $AssetPhotosTable assetPhotos = $AssetPhotosTable(this);
  late final $MaintenancePlansTable maintenancePlans = $MaintenancePlansTable(
    this,
  );
  late final $MaintenancePlanMetadataTable maintenancePlanMetadata =
      $MaintenancePlanMetadataTable(this);
  late final $MaintenanceRecordsTable maintenanceRecords =
      $MaintenanceRecordsTable(this);
  late final $AppNotificationsTable appNotifications = $AppNotificationsTable(
    this,
  );
  late final $InboxNotificationsTable inboxNotifications =
      $InboxNotificationsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $StreaksTable streaks = $StreaksTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $ReminderScheduleSnapshotsTable reminderScheduleSnapshots =
      $ReminderScheduleSnapshotsTable(this);
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $SyncShadowsTable syncShadows = $SyncShadowsTable(this);
  late final $SyncRuntimeTable syncRuntime = $SyncRuntimeTable(this);
  late final $SyncMediaCleanupTable syncMediaCleanup = $SyncMediaCleanupTable(
    this,
  );
  late final $SyncAccountTable syncAccount = $SyncAccountTable(this);
  late final $NotificationReconciliationRequestsTable
  notificationReconciliationRequests = $NotificationReconciliationRequestsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    areas,
    rooms,
    assets,
    deviceDetailsTable,
    petDetailsTable,
    plantDetailsTable,
    safetyDetailsTable,
    tags,
    assetTags,
    assetPhotos,
    maintenancePlans,
    maintenancePlanMetadata,
    maintenanceRecords,
    appNotifications,
    inboxNotifications,
    settings,
    streaks,
    syncOutbox,
    reminderScheduleSnapshots,
    syncCursors,
    syncShadows,
    syncRuntime,
    syncMediaCleanup,
    syncAccount,
    notificationReconciliationRequests,
  ];
}

typedef $$AreasTableCreateCompanionBuilder = AreasCompanion Function({
  required String id,
  required String name,
  required String kind,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> archivedAt,
  Value<int> rowid,
});
typedef $$AreasTableUpdateCompanionBuilder = AreasCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> kind,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> archivedAt,
  Value<int> rowid,
});

final class $$AreasTableReferences
    extends BaseReferences<_$AppDatabase, $AreasTable, AreaRow> {
  $$AreasTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$RoomsTable, List<RoomRow>> _roomsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.rooms,
    aliasName: 'areas__id__rooms__area_id',
  );

  $$RoomsTableProcessedTableManager get roomsRefs {
    final manager = $$RoomsTableTableManager(
      $_db,
      $_db.rooms,
    ).filter((f) => f.areaId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_roomsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AreasTableFilterComposer extends Composer<_$AppDatabase, $AreasTable> {
  $$AreasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> roomsRefs(
    Expression<bool> Function($$RoomsTableFilterComposer f) f,
  ) {
    final $$RoomsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rooms,
      getReferencedColumn: (t) => t.areaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomsTableFilterComposer(
            $db: $db,
            $table: $db.rooms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AreasTableOrderingComposer
    extends Composer<_$AppDatabase, $AreasTable> {
  $$AreasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AreasTableAnnotationComposer
    extends Composer<_$AppDatabase, $AreasTable> {
  $$AreasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  Expression<T> roomsRefs<T extends Object>(
    Expression<T> Function($$RoomsTableAnnotationComposer a) f,
  ) {
    final $$RoomsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.rooms,
      getReferencedColumn: (t) => t.areaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomsTableAnnotationComposer(
            $db: $db,
            $table: $db.rooms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AreasTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AreasTable,
          AreaRow,
          $$AreasTableFilterComposer,
          $$AreasTableOrderingComposer,
          $$AreasTableAnnotationComposer,
          $$AreasTableCreateCompanionBuilder,
          $$AreasTableUpdateCompanionBuilder,
          (AreaRow, $$AreasTableReferences),
          AreaRow,
          PrefetchHooks Function({bool roomsRefs})
        > {
  $$AreasTableTableManager(_$AppDatabase db, $AreasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AreasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AreasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AreasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AreasCompanion(
                id: id,
                name: name,
                kind: kind,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String kind,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AreasCompanion.insert(
                id: id,
                name: name,
                kind: kind,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$AreasTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({roomsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (roomsRefs) db.rooms],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (roomsRefs)
                    await $_getPrefetchedData<AreaRow, $AreasTable, RoomRow>(
                      currentTable: table,
                      referencedTable: $$AreasTableReferences._roomsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$AreasTableReferences(db, table, p0).roomsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.areaId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$AreasTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AreasTable,
      AreaRow,
      $$AreasTableFilterComposer,
      $$AreasTableOrderingComposer,
      $$AreasTableAnnotationComposer,
      $$AreasTableCreateCompanionBuilder,
      $$AreasTableUpdateCompanionBuilder,
      (AreaRow, $$AreasTableReferences),
      AreaRow,
      PrefetchHooks Function({bool roomsRefs})
    >;
typedef $$RoomsTableCreateCompanionBuilder = RoomsCompanion Function({
  required String id,
  required String areaId,
  required String name,
  Value<String> roomType,
  Value<String?> notes,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> archivedAt,
  Value<int> rowid,
});
typedef $$RoomsTableUpdateCompanionBuilder = RoomsCompanion Function({
  Value<String> id,
  Value<String> areaId,
  Value<String> name,
  Value<String> roomType,
  Value<String?> notes,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> archivedAt,
  Value<int> rowid,
});

final class $$RoomsTableReferences
    extends BaseReferences<_$AppDatabase, $RoomsTable, RoomRow> {
  $$RoomsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AreasTable _areaIdTable(_$AppDatabase db) =>
      db.areas.createAlias('rooms__area_id__areas__id');

  $$AreasTableProcessedTableManager get areaId {
    final $_column = $_itemColumn<String>('area_id')!;

    final manager = $$AreasTableTableManager(
      $_db,
      $_db.areas,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_areaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$AssetsTable, List<AssetRow>> _assetsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.assets,
    aliasName: 'rooms__id__assets__room_id',
  );

  $$AssetsTableProcessedTableManager get assetsRefs {
    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.roomId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RoomsTableFilterComposer extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roomType => $composableBuilder(
    column: $table.roomType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AreasTableFilterComposer get areaId {
    final $$AreasTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.areaId,
      referencedTable: $db.areas,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AreasTableFilterComposer(
            $db: $db,
            $table: $db.areas,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> assetsRefs(
    Expression<bool> Function($$AssetsTableFilterComposer f) f,
  ) {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.roomId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RoomsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roomType => $composableBuilder(
    column: $table.roomType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AreasTableOrderingComposer get areaId {
    final $$AreasTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.areaId,
      referencedTable: $db.areas,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AreasTableOrderingComposer(
            $db: $db,
            $table: $db.areas,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RoomsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get roomType =>
      $composableBuilder(column: $table.roomType, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  $$AreasTableAnnotationComposer get areaId {
    final $$AreasTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.areaId,
      referencedTable: $db.areas,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AreasTableAnnotationComposer(
            $db: $db,
            $table: $db.areas,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> assetsRefs<T extends Object>(
    Expression<T> Function($$AssetsTableAnnotationComposer a) f,
  ) {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.roomId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RoomsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoomsTable,
          RoomRow,
          $$RoomsTableFilterComposer,
          $$RoomsTableOrderingComposer,
          $$RoomsTableAnnotationComposer,
          $$RoomsTableCreateCompanionBuilder,
          $$RoomsTableUpdateCompanionBuilder,
          (RoomRow, $$RoomsTableReferences),
          RoomRow,
          PrefetchHooks Function({bool areaId, bool assetsRefs})
        > {
  $$RoomsTableTableManager(_$AppDatabase db, $RoomsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoomsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoomsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoomsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> areaId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> roomType = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomsCompanion(
                id: id,
                areaId: areaId,
                name: name,
                roomType: roomType,
                notes: notes,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String areaId,
                required String name,
                Value<String> roomType = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomsCompanion.insert(
                id: id,
                areaId: areaId,
                name: name,
                roomType: roomType,
                notes: notes,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$RoomsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({areaId = false, assetsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (assetsRefs) db.assets],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (areaId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.areaId,
                        referencedTable: $$RoomsTableReferences._areaIdTable(
                          db,
                        ),
                        referencedColumn: $$RoomsTableReferences
                            ._areaIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (assetsRefs)
                    await $_getPrefetchedData<RoomRow, $RoomsTable, AssetRow>(
                      currentTable: table,
                      referencedTable: $$RoomsTableReferences._assetsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$RoomsTableReferences(db, table, p0).assetsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.roomId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$RoomsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoomsTable,
      RoomRow,
      $$RoomsTableFilterComposer,
      $$RoomsTableOrderingComposer,
      $$RoomsTableAnnotationComposer,
      $$RoomsTableCreateCompanionBuilder,
      $$RoomsTableUpdateCompanionBuilder,
      (RoomRow, $$RoomsTableReferences),
      RoomRow,
      PrefetchHooks Function({bool areaId, bool assetsRefs})
    >;
typedef $$AssetsTableCreateCompanionBuilder = AssetsCompanion Function({
  required String id,
  required String name,
  Value<String> assetType,
  required String roomId,
  Value<String?> placement,
  Value<String?> notes,
  Value<DateTime?> purchaseDate,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> archivedAt,
  Value<int> rowid,
});
typedef $$AssetsTableUpdateCompanionBuilder = AssetsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> assetType,
  Value<String> roomId,
  Value<String?> placement,
  Value<String?> notes,
  Value<DateTime?> purchaseDate,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> archivedAt,
  Value<int> rowid,
});

final class $$AssetsTableReferences
    extends BaseReferences<_$AppDatabase, $AssetsTable, AssetRow> {
  $$AssetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RoomsTable _roomIdTable(_$AppDatabase db) =>
      db.rooms.createAlias('assets__room_id__rooms__id');

  $$RoomsTableProcessedTableManager get roomId {
    final $_column = $_itemColumn<String>('room_id')!;

    final manager = $$RoomsTableTableManager(
      $_db,
      $_db.rooms,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_roomIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$DeviceDetailsTableTable, List<DeviceDetailRow>>
  _deviceDetailsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.deviceDetailsTable,
        aliasName: 'assets__id__device_details__asset_id',
      );

  $$DeviceDetailsTableTableProcessedTableManager get deviceDetailsTableRefs {
    final manager = $$DeviceDetailsTableTableTableManager(
      $_db,
      $_db.deviceDetailsTable,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _deviceDetailsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PetDetailsTableTable, List<PetDetailRow>>
  _petDetailsTableRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.petDetailsTable,
    aliasName: 'assets__id__pet_details__asset_id',
  );

  $$PetDetailsTableTableProcessedTableManager get petDetailsTableRefs {
    final manager = $$PetDetailsTableTableTableManager(
      $_db,
      $_db.petDetailsTable,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _petDetailsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PlantDetailsTableTable, List<PlantDetailRow>>
  _plantDetailsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.plantDetailsTable,
        aliasName: 'assets__id__plant_details__asset_id',
      );

  $$PlantDetailsTableTableProcessedTableManager get plantDetailsTableRefs {
    final manager = $$PlantDetailsTableTableTableManager(
      $_db,
      $_db.plantDetailsTable,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _plantDetailsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SafetyDetailsTableTable, List<SafetyDetailRow>>
  _safetyDetailsTableRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.safetyDetailsTable,
        aliasName: 'assets__id__safety_details__asset_id',
      );

  $$SafetyDetailsTableTableProcessedTableManager get safetyDetailsTableRefs {
    final manager = $$SafetyDetailsTableTableTableManager(
      $_db,
      $_db.safetyDetailsTable,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _safetyDetailsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AssetTagsTable, List<AssetTagRow>>
  _assetTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.assetTags,
    aliasName: 'assets__id__asset_tags__asset_id',
  );

  $$AssetTagsTableProcessedTableManager get assetTagsRefs {
    final manager = $$AssetTagsTableTableManager(
      $_db,
      $_db.assetTags,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assetTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AssetPhotosTable, List<AssetPhotoRow>>
  _assetPhotosRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.assetPhotos,
    aliasName: 'assets__id__asset_photos__asset_id',
  );

  $$AssetPhotosTableProcessedTableManager get assetPhotosRefs {
    final manager = $$AssetPhotosTableTableManager(
      $_db,
      $_db.assetPhotos,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assetPhotosRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MaintenancePlansTable, List<MaintenancePlanRow>>
  _maintenancePlansRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.maintenancePlans,
    aliasName: 'assets__id__maintenance_plans__asset_id',
  );

  $$MaintenancePlansTableProcessedTableManager get maintenancePlansRefs {
    final manager = $$MaintenancePlansTableTableManager(
      $_db,
      $_db.maintenancePlans,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _maintenancePlansRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AssetsTableFilterComposer
    extends Composer<_$AppDatabase, $AssetsTable> {
  $$AssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetType => $composableBuilder(
    column: $table.assetType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placement => $composableBuilder(
    column: $table.placement,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$RoomsTableFilterComposer get roomId {
    final $$RoomsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roomId,
      referencedTable: $db.rooms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomsTableFilterComposer(
            $db: $db,
            $table: $db.rooms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> deviceDetailsTableRefs(
    Expression<bool> Function($$DeviceDetailsTableTableFilterComposer f) f,
  ) {
    final $$DeviceDetailsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.deviceDetailsTable,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DeviceDetailsTableTableFilterComposer(
            $db: $db,
            $table: $db.deviceDetailsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> petDetailsTableRefs(
    Expression<bool> Function($$PetDetailsTableTableFilterComposer f) f,
  ) {
    final $$PetDetailsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.petDetailsTable,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PetDetailsTableTableFilterComposer(
            $db: $db,
            $table: $db.petDetailsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> plantDetailsTableRefs(
    Expression<bool> Function($$PlantDetailsTableTableFilterComposer f) f,
  ) {
    final $$PlantDetailsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.plantDetailsTable,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlantDetailsTableTableFilterComposer(
            $db: $db,
            $table: $db.plantDetailsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> safetyDetailsTableRefs(
    Expression<bool> Function($$SafetyDetailsTableTableFilterComposer f) f,
  ) {
    final $$SafetyDetailsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.safetyDetailsTable,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SafetyDetailsTableTableFilterComposer(
            $db: $db,
            $table: $db.safetyDetailsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> assetTagsRefs(
    Expression<bool> Function($$AssetTagsTableFilterComposer f) f,
  ) {
    final $$AssetTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetTags,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetTagsTableFilterComposer(
            $db: $db,
            $table: $db.assetTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> assetPhotosRefs(
    Expression<bool> Function($$AssetPhotosTableFilterComposer f) f,
  ) {
    final $$AssetPhotosTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetPhotos,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetPhotosTableFilterComposer(
            $db: $db,
            $table: $db.assetPhotos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> maintenancePlansRefs(
    Expression<bool> Function($$MaintenancePlansTableFilterComposer f) f,
  ) {
    final $$MaintenancePlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableFilterComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssetsTable> {
  $$AssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetType => $composableBuilder(
    column: $table.assetType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placement => $composableBuilder(
    column: $table.placement,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$RoomsTableOrderingComposer get roomId {
    final $$RoomsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roomId,
      referencedTable: $db.rooms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomsTableOrderingComposer(
            $db: $db,
            $table: $db.rooms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssetsTable> {
  $$AssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get assetType =>
      $composableBuilder(column: $table.assetType, builder: (column) => column);

  GeneratedColumn<String> get placement =>
      $composableBuilder(column: $table.placement, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get purchaseDate => $composableBuilder(
    column: $table.purchaseDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  $$RoomsTableAnnotationComposer get roomId {
    final $$RoomsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roomId,
      referencedTable: $db.rooms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomsTableAnnotationComposer(
            $db: $db,
            $table: $db.rooms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> deviceDetailsTableRefs<T extends Object>(
    Expression<T> Function($$DeviceDetailsTableTableAnnotationComposer a) f,
  ) {
    final $$DeviceDetailsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.deviceDetailsTable,
          getReferencedColumn: (t) => t.assetId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DeviceDetailsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.deviceDetailsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> petDetailsTableRefs<T extends Object>(
    Expression<T> Function($$PetDetailsTableTableAnnotationComposer a) f,
  ) {
    final $$PetDetailsTableTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.petDetailsTable,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PetDetailsTableTableAnnotationComposer(
            $db: $db,
            $table: $db.petDetailsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> plantDetailsTableRefs<T extends Object>(
    Expression<T> Function($$PlantDetailsTableTableAnnotationComposer a) f,
  ) {
    final $$PlantDetailsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.plantDetailsTable,
          getReferencedColumn: (t) => t.assetId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PlantDetailsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.plantDetailsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> safetyDetailsTableRefs<T extends Object>(
    Expression<T> Function($$SafetyDetailsTableTableAnnotationComposer a) f,
  ) {
    final $$SafetyDetailsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.safetyDetailsTable,
          getReferencedColumn: (t) => t.assetId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SafetyDetailsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.safetyDetailsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> assetTagsRefs<T extends Object>(
    Expression<T> Function($$AssetTagsTableAnnotationComposer a) f,
  ) {
    final $$AssetTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetTags,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.assetTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> assetPhotosRefs<T extends Object>(
    Expression<T> Function($$AssetPhotosTableAnnotationComposer a) f,
  ) {
    final $$AssetPhotosTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetPhotos,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetPhotosTableAnnotationComposer(
            $db: $db,
            $table: $db.assetPhotos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> maintenancePlansRefs<T extends Object>(
    Expression<T> Function($$MaintenancePlansTableAnnotationComposer a) f,
  ) {
    final $$MaintenancePlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableAnnotationComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AssetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssetsTable,
          AssetRow,
          $$AssetsTableFilterComposer,
          $$AssetsTableOrderingComposer,
          $$AssetsTableAnnotationComposer,
          $$AssetsTableCreateCompanionBuilder,
          $$AssetsTableUpdateCompanionBuilder,
          (AssetRow, $$AssetsTableReferences),
          AssetRow,
          PrefetchHooks Function({
            bool roomId,
            bool deviceDetailsTableRefs,
            bool petDetailsTableRefs,
            bool plantDetailsTableRefs,
            bool safetyDetailsTableRefs,
            bool assetTagsRefs,
            bool assetPhotosRefs,
            bool maintenancePlansRefs,
          })
        > {
  $$AssetsTableTableManager(_$AppDatabase db, $AssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> assetType = const Value.absent(),
                Value<String> roomId = const Value.absent(),
                Value<String?> placement = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> purchaseDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion(
                id: id,
                name: name,
                assetType: assetType,
                roomId: roomId,
                placement: placement,
                notes: notes,
                purchaseDate: purchaseDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> assetType = const Value.absent(),
                required String roomId,
                Value<String?> placement = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> purchaseDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetsCompanion.insert(
                id: id,
                name: name,
                assetType: assetType,
                roomId: roomId,
                placement: placement,
                notes: notes,
                purchaseDate: purchaseDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$AssetsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                roomId = false,
                deviceDetailsTableRefs = false,
                petDetailsTableRefs = false,
                plantDetailsTableRefs = false,
                safetyDetailsTableRefs = false,
                assetTagsRefs = false,
                assetPhotosRefs = false,
                maintenancePlansRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (deviceDetailsTableRefs) db.deviceDetailsTable,
                    if (petDetailsTableRefs) db.petDetailsTable,
                    if (plantDetailsTableRefs) db.plantDetailsTable,
                    if (safetyDetailsTableRefs) db.safetyDetailsTable,
                    if (assetTagsRefs) db.assetTags,
                    if (assetPhotosRefs) db.assetPhotos,
                    if (maintenancePlansRefs) db.maintenancePlans,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (roomId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.roomId,
                            referencedTable: $$AssetsTableReferences
                                ._roomIdTable(db),
                            referencedColumn: $$AssetsTableReferences
                                ._roomIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (deviceDetailsTableRefs)
                        await $_getPrefetchedData<
                          AssetRow,
                          $AssetsTable,
                          DeviceDetailRow
                        >(
                          currentTable: table,
                          referencedTable: $$AssetsTableReferences
                              ._deviceDetailsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).deviceDetailsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (petDetailsTableRefs)
                        await $_getPrefetchedData<
                          AssetRow,
                          $AssetsTable,
                          PetDetailRow
                        >(
                          currentTable: table,
                          referencedTable: $$AssetsTableReferences
                              ._petDetailsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).petDetailsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (plantDetailsTableRefs)
                        await $_getPrefetchedData<
                          AssetRow,
                          $AssetsTable,
                          PlantDetailRow
                        >(
                          currentTable: table,
                          referencedTable: $$AssetsTableReferences
                              ._plantDetailsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).plantDetailsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (safetyDetailsTableRefs)
                        await $_getPrefetchedData<
                          AssetRow,
                          $AssetsTable,
                          SafetyDetailRow
                        >(
                          currentTable: table,
                          referencedTable: $$AssetsTableReferences
                              ._safetyDetailsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).safetyDetailsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (assetTagsRefs)
                        await $_getPrefetchedData<
                          AssetRow,
                          $AssetsTable,
                          AssetTagRow
                        >(
                          currentTable: table,
                          referencedTable: $$AssetsTableReferences
                              ._assetTagsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).assetTagsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (assetPhotosRefs)
                        await $_getPrefetchedData<
                          AssetRow,
                          $AssetsTable,
                          AssetPhotoRow
                        >(
                          currentTable: table,
                          referencedTable: $$AssetsTableReferences
                              ._assetPhotosRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).assetPhotosRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (maintenancePlansRefs)
                        await $_getPrefetchedData<
                          AssetRow,
                          $AssetsTable,
                          MaintenancePlanRow
                        >(
                          currentTable: table,
                          referencedTable: $$AssetsTableReferences
                              ._maintenancePlansRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).maintenancePlansRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssetsTable,
      AssetRow,
      $$AssetsTableFilterComposer,
      $$AssetsTableOrderingComposer,
      $$AssetsTableAnnotationComposer,
      $$AssetsTableCreateCompanionBuilder,
      $$AssetsTableUpdateCompanionBuilder,
      (AssetRow, $$AssetsTableReferences),
      AssetRow,
      PrefetchHooks Function({
        bool roomId,
        bool deviceDetailsTableRefs,
        bool petDetailsTableRefs,
        bool plantDetailsTableRefs,
        bool safetyDetailsTableRefs,
        bool assetTagsRefs,
        bool assetPhotosRefs,
        bool maintenancePlansRefs,
      })
    >;
typedef $$DeviceDetailsTableTableCreateCompanionBuilder =
    DeviceDetailsTableCompanion Function({
      required String assetId,
      Value<String?> brand,
      Value<String?> model,
      Value<String?> serialNumber,
      Value<String?> powerSource,
      Value<DateTime?> warrantyUntil,
      Value<String?> manualUrl,
      Value<String?> consumable,
      Value<int> rowid,
    });
typedef $$DeviceDetailsTableTableUpdateCompanionBuilder =
    DeviceDetailsTableCompanion Function({
      Value<String> assetId,
      Value<String?> brand,
      Value<String?> model,
      Value<String?> serialNumber,
      Value<String?> powerSource,
      Value<DateTime?> warrantyUntil,
      Value<String?> manualUrl,
      Value<String?> consumable,
      Value<int> rowid,
    });

final class $$DeviceDetailsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $DeviceDetailsTableTable,
          DeviceDetailRow
        > {
  $$DeviceDetailsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssetsTable _assetIdTable(_$AppDatabase db) =>
      db.assets.createAlias('device_details__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DeviceDetailsTableTableFilterComposer
    extends Composer<_$AppDatabase, $DeviceDetailsTableTable> {
  $$DeviceDetailsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serialNumber => $composableBuilder(
    column: $table.serialNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get powerSource => $composableBuilder(
    column: $table.powerSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get warrantyUntil => $composableBuilder(
    column: $table.warrantyUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manualUrl => $composableBuilder(
    column: $table.manualUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get consumable => $composableBuilder(
    column: $table.consumable,
    builder: (column) => ColumnFilters(column),
  );

  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceDetailsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DeviceDetailsTableTable> {
  $$DeviceDetailsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serialNumber => $composableBuilder(
    column: $table.serialNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get powerSource => $composableBuilder(
    column: $table.powerSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get warrantyUntil => $composableBuilder(
    column: $table.warrantyUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manualUrl => $composableBuilder(
    column: $table.manualUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get consumable => $composableBuilder(
    column: $table.consumable,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceDetailsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DeviceDetailsTableTable> {
  $$DeviceDetailsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get serialNumber => $composableBuilder(
    column: $table.serialNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get powerSource => $composableBuilder(
    column: $table.powerSource,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get warrantyUntil => $composableBuilder(
    column: $table.warrantyUntil,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manualUrl =>
      $composableBuilder(column: $table.manualUrl, builder: (column) => column);

  GeneratedColumn<String> get consumable => $composableBuilder(
    column: $table.consumable,
    builder: (column) => column,
  );

  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceDetailsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DeviceDetailsTableTable,
          DeviceDetailRow,
          $$DeviceDetailsTableTableFilterComposer,
          $$DeviceDetailsTableTableOrderingComposer,
          $$DeviceDetailsTableTableAnnotationComposer,
          $$DeviceDetailsTableTableCreateCompanionBuilder,
          $$DeviceDetailsTableTableUpdateCompanionBuilder,
          (DeviceDetailRow, $$DeviceDetailsTableTableReferences),
          DeviceDetailRow,
          PrefetchHooks Function({bool assetId})
        > {
  $$DeviceDetailsTableTableTableManager(
    _$AppDatabase db,
    $DeviceDetailsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceDetailsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceDetailsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceDetailsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> assetId = const Value.absent(),
                Value<String?> brand = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> serialNumber = const Value.absent(),
                Value<String?> powerSource = const Value.absent(),
                Value<DateTime?> warrantyUntil = const Value.absent(),
                Value<String?> manualUrl = const Value.absent(),
                Value<String?> consumable = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceDetailsTableCompanion(
                assetId: assetId,
                brand: brand,
                model: model,
                serialNumber: serialNumber,
                powerSource: powerSource,
                warrantyUntil: warrantyUntil,
                manualUrl: manualUrl,
                consumable: consumable,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assetId,
                Value<String?> brand = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> serialNumber = const Value.absent(),
                Value<String?> powerSource = const Value.absent(),
                Value<DateTime?> warrantyUntil = const Value.absent(),
                Value<String?> manualUrl = const Value.absent(),
                Value<String?> consumable = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceDetailsTableCompanion.insert(
                assetId: assetId,
                brand: brand,
                model: model,
                serialNumber: serialNumber,
                powerSource: powerSource,
                warrantyUntil: warrantyUntil,
                manualUrl: manualUrl,
                consumable: consumable,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DeviceDetailsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.assetId,
                        referencedTable: $$DeviceDetailsTableTableReferences
                            ._assetIdTable(db),
                        referencedColumn: $$DeviceDetailsTableTableReferences
                            ._assetIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DeviceDetailsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DeviceDetailsTableTable,
      DeviceDetailRow,
      $$DeviceDetailsTableTableFilterComposer,
      $$DeviceDetailsTableTableOrderingComposer,
      $$DeviceDetailsTableTableAnnotationComposer,
      $$DeviceDetailsTableTableCreateCompanionBuilder,
      $$DeviceDetailsTableTableUpdateCompanionBuilder,
      (DeviceDetailRow, $$DeviceDetailsTableTableReferences),
      DeviceDetailRow,
      PrefetchHooks Function({bool assetId})
    >;
typedef $$PetDetailsTableTableCreateCompanionBuilder =
    PetDetailsTableCompanion Function({
      required String assetId,
      Value<String?> species,
      Value<String?> breed,
      Value<DateTime?> birthDate,
      Value<String?> microchipId,
      Value<String?> vetName,
      Value<String?> vetPhone,
      Value<String?> feedingNotes,
      Value<String?> medicalNotes,
      Value<int> rowid,
    });
typedef $$PetDetailsTableTableUpdateCompanionBuilder =
    PetDetailsTableCompanion Function({
      Value<String> assetId,
      Value<String?> species,
      Value<String?> breed,
      Value<DateTime?> birthDate,
      Value<String?> microchipId,
      Value<String?> vetName,
      Value<String?> vetPhone,
      Value<String?> feedingNotes,
      Value<String?> medicalNotes,
      Value<int> rowid,
    });

final class $$PetDetailsTableTableReferences
    extends BaseReferences<_$AppDatabase, $PetDetailsTableTable, PetDetailRow> {
  $$PetDetailsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssetsTable _assetIdTable(_$AppDatabase db) =>
      db.assets.createAlias('pet_details__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PetDetailsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PetDetailsTableTable> {
  $$PetDetailsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get species => $composableBuilder(
    column: $table.species,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get breed => $composableBuilder(
    column: $table.breed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get microchipId => $composableBuilder(
    column: $table.microchipId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vetName => $composableBuilder(
    column: $table.vetName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vetPhone => $composableBuilder(
    column: $table.vetPhone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get feedingNotes => $composableBuilder(
    column: $table.feedingNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get medicalNotes => $composableBuilder(
    column: $table.medicalNotes,
    builder: (column) => ColumnFilters(column),
  );

  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PetDetailsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PetDetailsTableTable> {
  $$PetDetailsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get species => $composableBuilder(
    column: $table.species,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get breed => $composableBuilder(
    column: $table.breed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get birthDate => $composableBuilder(
    column: $table.birthDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get microchipId => $composableBuilder(
    column: $table.microchipId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vetName => $composableBuilder(
    column: $table.vetName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vetPhone => $composableBuilder(
    column: $table.vetPhone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get feedingNotes => $composableBuilder(
    column: $table.feedingNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get medicalNotes => $composableBuilder(
    column: $table.medicalNotes,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PetDetailsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PetDetailsTableTable> {
  $$PetDetailsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get species =>
      $composableBuilder(column: $table.species, builder: (column) => column);

  GeneratedColumn<String> get breed =>
      $composableBuilder(column: $table.breed, builder: (column) => column);

  GeneratedColumn<DateTime> get birthDate =>
      $composableBuilder(column: $table.birthDate, builder: (column) => column);

  GeneratedColumn<String> get microchipId => $composableBuilder(
    column: $table.microchipId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get vetName =>
      $composableBuilder(column: $table.vetName, builder: (column) => column);

  GeneratedColumn<String> get vetPhone =>
      $composableBuilder(column: $table.vetPhone, builder: (column) => column);

  GeneratedColumn<String> get feedingNotes => $composableBuilder(
    column: $table.feedingNotes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get medicalNotes => $composableBuilder(
    column: $table.medicalNotes,
    builder: (column) => column,
  );

  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PetDetailsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PetDetailsTableTable,
          PetDetailRow,
          $$PetDetailsTableTableFilterComposer,
          $$PetDetailsTableTableOrderingComposer,
          $$PetDetailsTableTableAnnotationComposer,
          $$PetDetailsTableTableCreateCompanionBuilder,
          $$PetDetailsTableTableUpdateCompanionBuilder,
          (PetDetailRow, $$PetDetailsTableTableReferences),
          PetDetailRow,
          PrefetchHooks Function({bool assetId})
        > {
  $$PetDetailsTableTableTableManager(
    _$AppDatabase db,
    $PetDetailsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PetDetailsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PetDetailsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PetDetailsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> assetId = const Value.absent(),
                Value<String?> species = const Value.absent(),
                Value<String?> breed = const Value.absent(),
                Value<DateTime?> birthDate = const Value.absent(),
                Value<String?> microchipId = const Value.absent(),
                Value<String?> vetName = const Value.absent(),
                Value<String?> vetPhone = const Value.absent(),
                Value<String?> feedingNotes = const Value.absent(),
                Value<String?> medicalNotes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PetDetailsTableCompanion(
                assetId: assetId,
                species: species,
                breed: breed,
                birthDate: birthDate,
                microchipId: microchipId,
                vetName: vetName,
                vetPhone: vetPhone,
                feedingNotes: feedingNotes,
                medicalNotes: medicalNotes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assetId,
                Value<String?> species = const Value.absent(),
                Value<String?> breed = const Value.absent(),
                Value<DateTime?> birthDate = const Value.absent(),
                Value<String?> microchipId = const Value.absent(),
                Value<String?> vetName = const Value.absent(),
                Value<String?> vetPhone = const Value.absent(),
                Value<String?> feedingNotes = const Value.absent(),
                Value<String?> medicalNotes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PetDetailsTableCompanion.insert(
                assetId: assetId,
                species: species,
                breed: breed,
                birthDate: birthDate,
                microchipId: microchipId,
                vetName: vetName,
                vetPhone: vetPhone,
                feedingNotes: feedingNotes,
                medicalNotes: medicalNotes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PetDetailsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.assetId,
                        referencedTable: $$PetDetailsTableTableReferences
                            ._assetIdTable(db),
                        referencedColumn: $$PetDetailsTableTableReferences
                            ._assetIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PetDetailsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PetDetailsTableTable,
      PetDetailRow,
      $$PetDetailsTableTableFilterComposer,
      $$PetDetailsTableTableOrderingComposer,
      $$PetDetailsTableTableAnnotationComposer,
      $$PetDetailsTableTableCreateCompanionBuilder,
      $$PetDetailsTableTableUpdateCompanionBuilder,
      (PetDetailRow, $$PetDetailsTableTableReferences),
      PetDetailRow,
      PrefetchHooks Function({bool assetId})
    >;
typedef $$PlantDetailsTableTableCreateCompanionBuilder =
    PlantDetailsTableCompanion Function({
      required String assetId,
      Value<String?> species,
      Value<String?> sunlight,
      Value<int?> wateringIntervalDays,
      Value<String?> potSize,
      Value<DateTime?> lastRepottedAt,
      Value<String?> toxicityNotes,
      Value<int> rowid,
    });
typedef $$PlantDetailsTableTableUpdateCompanionBuilder =
    PlantDetailsTableCompanion Function({
      Value<String> assetId,
      Value<String?> species,
      Value<String?> sunlight,
      Value<int?> wateringIntervalDays,
      Value<String?> potSize,
      Value<DateTime?> lastRepottedAt,
      Value<String?> toxicityNotes,
      Value<int> rowid,
    });

final class $$PlantDetailsTableTableReferences
    extends
        BaseReferences<_$AppDatabase, $PlantDetailsTableTable, PlantDetailRow> {
  $$PlantDetailsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssetsTable _assetIdTable(_$AppDatabase db) =>
      db.assets.createAlias('plant_details__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlantDetailsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PlantDetailsTableTable> {
  $$PlantDetailsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get species => $composableBuilder(
    column: $table.species,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sunlight => $composableBuilder(
    column: $table.sunlight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wateringIntervalDays => $composableBuilder(
    column: $table.wateringIntervalDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get potSize => $composableBuilder(
    column: $table.potSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastRepottedAt => $composableBuilder(
    column: $table.lastRepottedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toxicityNotes => $composableBuilder(
    column: $table.toxicityNotes,
    builder: (column) => ColumnFilters(column),
  );

  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlantDetailsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PlantDetailsTableTable> {
  $$PlantDetailsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get species => $composableBuilder(
    column: $table.species,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sunlight => $composableBuilder(
    column: $table.sunlight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wateringIntervalDays => $composableBuilder(
    column: $table.wateringIntervalDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get potSize => $composableBuilder(
    column: $table.potSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastRepottedAt => $composableBuilder(
    column: $table.lastRepottedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toxicityNotes => $composableBuilder(
    column: $table.toxicityNotes,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlantDetailsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlantDetailsTableTable> {
  $$PlantDetailsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get species =>
      $composableBuilder(column: $table.species, builder: (column) => column);

  GeneratedColumn<String> get sunlight =>
      $composableBuilder(column: $table.sunlight, builder: (column) => column);

  GeneratedColumn<int> get wateringIntervalDays => $composableBuilder(
    column: $table.wateringIntervalDays,
    builder: (column) => column,
  );

  GeneratedColumn<String> get potSize =>
      $composableBuilder(column: $table.potSize, builder: (column) => column);

  GeneratedColumn<DateTime> get lastRepottedAt => $composableBuilder(
    column: $table.lastRepottedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toxicityNotes => $composableBuilder(
    column: $table.toxicityNotes,
    builder: (column) => column,
  );

  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlantDetailsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlantDetailsTableTable,
          PlantDetailRow,
          $$PlantDetailsTableTableFilterComposer,
          $$PlantDetailsTableTableOrderingComposer,
          $$PlantDetailsTableTableAnnotationComposer,
          $$PlantDetailsTableTableCreateCompanionBuilder,
          $$PlantDetailsTableTableUpdateCompanionBuilder,
          (PlantDetailRow, $$PlantDetailsTableTableReferences),
          PlantDetailRow,
          PrefetchHooks Function({bool assetId})
        > {
  $$PlantDetailsTableTableTableManager(
    _$AppDatabase db,
    $PlantDetailsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlantDetailsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlantDetailsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlantDetailsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> assetId = const Value.absent(),
                Value<String?> species = const Value.absent(),
                Value<String?> sunlight = const Value.absent(),
                Value<int?> wateringIntervalDays = const Value.absent(),
                Value<String?> potSize = const Value.absent(),
                Value<DateTime?> lastRepottedAt = const Value.absent(),
                Value<String?> toxicityNotes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlantDetailsTableCompanion(
                assetId: assetId,
                species: species,
                sunlight: sunlight,
                wateringIntervalDays: wateringIntervalDays,
                potSize: potSize,
                lastRepottedAt: lastRepottedAt,
                toxicityNotes: toxicityNotes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assetId,
                Value<String?> species = const Value.absent(),
                Value<String?> sunlight = const Value.absent(),
                Value<int?> wateringIntervalDays = const Value.absent(),
                Value<String?> potSize = const Value.absent(),
                Value<DateTime?> lastRepottedAt = const Value.absent(),
                Value<String?> toxicityNotes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlantDetailsTableCompanion.insert(
                assetId: assetId,
                species: species,
                sunlight: sunlight,
                wateringIntervalDays: wateringIntervalDays,
                potSize: potSize,
                lastRepottedAt: lastRepottedAt,
                toxicityNotes: toxicityNotes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PlantDetailsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.assetId,
                        referencedTable: $$PlantDetailsTableTableReferences
                            ._assetIdTable(db),
                        referencedColumn: $$PlantDetailsTableTableReferences
                            ._assetIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PlantDetailsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlantDetailsTableTable,
      PlantDetailRow,
      $$PlantDetailsTableTableFilterComposer,
      $$PlantDetailsTableTableOrderingComposer,
      $$PlantDetailsTableTableAnnotationComposer,
      $$PlantDetailsTableTableCreateCompanionBuilder,
      $$PlantDetailsTableTableUpdateCompanionBuilder,
      (PlantDetailRow, $$PlantDetailsTableTableReferences),
      PlantDetailRow,
      PrefetchHooks Function({bool assetId})
    >;
typedef $$SafetyDetailsTableTableCreateCompanionBuilder =
    SafetyDetailsTableCompanion Function({
      required String assetId,
      Value<String?> safetyType,
      Value<DateTime?> installedAt,
      Value<DateTime?> expiresAt,
      Value<String?> batteryType,
      Value<int?> testIntervalDays,
      Value<int> rowid,
    });
typedef $$SafetyDetailsTableTableUpdateCompanionBuilder =
    SafetyDetailsTableCompanion Function({
      Value<String> assetId,
      Value<String?> safetyType,
      Value<DateTime?> installedAt,
      Value<DateTime?> expiresAt,
      Value<String?> batteryType,
      Value<int?> testIntervalDays,
      Value<int> rowid,
    });

final class $$SafetyDetailsTableTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $SafetyDetailsTableTable,
          SafetyDetailRow
        > {
  $$SafetyDetailsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssetsTable _assetIdTable(_$AppDatabase db) =>
      db.assets.createAlias('safety_details__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SafetyDetailsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SafetyDetailsTableTable> {
  $$SafetyDetailsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get safetyType => $composableBuilder(
    column: $table.safetyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get batteryType => $composableBuilder(
    column: $table.batteryType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get testIntervalDays => $composableBuilder(
    column: $table.testIntervalDays,
    builder: (column) => ColumnFilters(column),
  );

  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SafetyDetailsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SafetyDetailsTableTable> {
  $$SafetyDetailsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get safetyType => $composableBuilder(
    column: $table.safetyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get batteryType => $composableBuilder(
    column: $table.batteryType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get testIntervalDays => $composableBuilder(
    column: $table.testIntervalDays,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SafetyDetailsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SafetyDetailsTableTable> {
  $$SafetyDetailsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get safetyType => $composableBuilder(
    column: $table.safetyType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get batteryType => $composableBuilder(
    column: $table.batteryType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get testIntervalDays => $composableBuilder(
    column: $table.testIntervalDays,
    builder: (column) => column,
  );

  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SafetyDetailsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SafetyDetailsTableTable,
          SafetyDetailRow,
          $$SafetyDetailsTableTableFilterComposer,
          $$SafetyDetailsTableTableOrderingComposer,
          $$SafetyDetailsTableTableAnnotationComposer,
          $$SafetyDetailsTableTableCreateCompanionBuilder,
          $$SafetyDetailsTableTableUpdateCompanionBuilder,
          (SafetyDetailRow, $$SafetyDetailsTableTableReferences),
          SafetyDetailRow,
          PrefetchHooks Function({bool assetId})
        > {
  $$SafetyDetailsTableTableTableManager(
    _$AppDatabase db,
    $SafetyDetailsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SafetyDetailsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SafetyDetailsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SafetyDetailsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> assetId = const Value.absent(),
                Value<String?> safetyType = const Value.absent(),
                Value<DateTime?> installedAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> batteryType = const Value.absent(),
                Value<int?> testIntervalDays = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SafetyDetailsTableCompanion(
                assetId: assetId,
                safetyType: safetyType,
                installedAt: installedAt,
                expiresAt: expiresAt,
                batteryType: batteryType,
                testIntervalDays: testIntervalDays,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assetId,
                Value<String?> safetyType = const Value.absent(),
                Value<DateTime?> installedAt = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> batteryType = const Value.absent(),
                Value<int?> testIntervalDays = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SafetyDetailsTableCompanion.insert(
                assetId: assetId,
                safetyType: safetyType,
                installedAt: installedAt,
                expiresAt: expiresAt,
                batteryType: batteryType,
                testIntervalDays: testIntervalDays,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SafetyDetailsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.assetId,
                        referencedTable: $$SafetyDetailsTableTableReferences
                            ._assetIdTable(db),
                        referencedColumn: $$SafetyDetailsTableTableReferences
                            ._assetIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SafetyDetailsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SafetyDetailsTableTable,
      SafetyDetailRow,
      $$SafetyDetailsTableTableFilterComposer,
      $$SafetyDetailsTableTableOrderingComposer,
      $$SafetyDetailsTableTableAnnotationComposer,
      $$SafetyDetailsTableTableCreateCompanionBuilder,
      $$SafetyDetailsTableTableUpdateCompanionBuilder,
      (SafetyDetailRow, $$SafetyDetailsTableTableReferences),
      SafetyDetailRow,
      PrefetchHooks Function({bool assetId})
    >;
typedef $$TagsTableCreateCompanionBuilder = TagsCompanion Function({
  required String id,
  required String name,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$TagsTableUpdateCompanionBuilder = TagsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$TagsTableReferences
    extends BaseReferences<_$AppDatabase, $TagsTable, TagRow> {
  $$TagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AssetTagsTable, List<AssetTagRow>>
  _assetTagsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.assetTags,
    aliasName: 'tags__id__asset_tags__tag_id',
  );

  $$AssetTagsTableProcessedTableManager get assetTagsRefs {
    final manager = $$AssetTagsTableTableManager(
      $_db,
      $_db.assetTags,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_assetTagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> assetTagsRefs(
    Expression<bool> Function($$AssetTagsTableFilterComposer f) f,
  ) {
    final $$AssetTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetTagsTableFilterComposer(
            $db: $db,
            $table: $db.assetTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> assetTagsRefs<T extends Object>(
    Expression<T> Function($$AssetTagsTableAnnotationComposer a) f,
  ) {
    final $$AssetTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.assetTags,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.assetTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          TagRow,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (TagRow, $$TagsTableReferences),
          TagRow,
          PrefetchHooks Function({bool assetTagsRefs})
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TagsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({assetTagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (assetTagsRefs) db.assetTags],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (assetTagsRefs)
                    await $_getPrefetchedData<TagRow, $TagsTable, AssetTagRow>(
                      currentTable: table,
                      referencedTable: $$TagsTableReferences
                          ._assetTagsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TagsTableReferences(db, table, p0).assetTagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      TagRow,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (TagRow, $$TagsTableReferences),
      TagRow,
      PrefetchHooks Function({bool assetTagsRefs})
    >;
typedef $$AssetTagsTableCreateCompanionBuilder = AssetTagsCompanion Function({
  required String assetId,
  required String tagId,
  Value<int> rowid,
});
typedef $$AssetTagsTableUpdateCompanionBuilder = AssetTagsCompanion Function({
  Value<String> assetId,
  Value<String> tagId,
  Value<int> rowid,
});

final class $$AssetTagsTableReferences
    extends BaseReferences<_$AppDatabase, $AssetTagsTable, AssetTagRow> {
  $$AssetTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AssetsTable _assetIdTable(_$AppDatabase db) =>
      db.assets.createAlias('asset_tags__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagsTable _tagIdTable(_$AppDatabase db) =>
      db.tags.createAlias('asset_tags__tag_id__tags__id');

  $$TagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AssetTagsTableFilterComposer
    extends Composer<_$AppDatabase, $AssetTagsTable> {
  $$AssetTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableFilterComposer get tagId {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssetTagsTable> {
  $$AssetTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableOrderingComposer get tagId {
    final $$TagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssetTagsTable> {
  $$AssetTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableAnnotationComposer get tagId {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssetTagsTable,
          AssetTagRow,
          $$AssetTagsTableFilterComposer,
          $$AssetTagsTableOrderingComposer,
          $$AssetTagsTableAnnotationComposer,
          $$AssetTagsTableCreateCompanionBuilder,
          $$AssetTagsTableUpdateCompanionBuilder,
          (AssetTagRow, $$AssetTagsTableReferences),
          AssetTagRow,
          PrefetchHooks Function({bool assetId, bool tagId})
        > {
  $$AssetTagsTableTableManager(_$AppDatabase db, $AssetTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> assetId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetTagsCompanion(
                assetId: assetId,
                tagId: tagId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assetId,
                required String tagId,
                Value<int> rowid = const Value.absent(),
              }) => AssetTagsCompanion.insert(
                assetId: assetId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AssetTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.assetId,
                        referencedTable: $$AssetTagsTableReferences
                            ._assetIdTable(db),
                        referencedColumn: $$AssetTagsTableReferences
                            ._assetIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (tagId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.tagId,
                        referencedTable: $$AssetTagsTableReferences._tagIdTable(
                          db,
                        ),
                        referencedColumn: $$AssetTagsTableReferences
                            ._tagIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AssetTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssetTagsTable,
      AssetTagRow,
      $$AssetTagsTableFilterComposer,
      $$AssetTagsTableOrderingComposer,
      $$AssetTagsTableAnnotationComposer,
      $$AssetTagsTableCreateCompanionBuilder,
      $$AssetTagsTableUpdateCompanionBuilder,
      (AssetTagRow, $$AssetTagsTableReferences),
      AssetTagRow,
      PrefetchHooks Function({bool assetId, bool tagId})
    >;
typedef $$AssetPhotosTableCreateCompanionBuilder =
    AssetPhotosCompanion Function({
      required String id,
      required String assetId,
      required String relativePath,
      Value<String?> caption,
      Value<bool> isPrimary,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$AssetPhotosTableUpdateCompanionBuilder =
    AssetPhotosCompanion Function({
      Value<String> id,
      Value<String> assetId,
      Value<String> relativePath,
      Value<String?> caption,
      Value<bool> isPrimary,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$AssetPhotosTableReferences
    extends BaseReferences<_$AppDatabase, $AssetPhotosTable, AssetPhotoRow> {
  $$AssetPhotosTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AssetsTable _assetIdTable(_$AppDatabase db) =>
      db.assets.createAlias('asset_photos__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AssetPhotosTableFilterComposer
    extends Composer<_$AppDatabase, $AssetPhotosTable> {
  $$AssetPhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetPhotosTableOrderingComposer
    extends Composer<_$AppDatabase, $AssetPhotosTable> {
  $$AssetPhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetPhotosTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssetPhotosTable> {
  $$AssetPhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get caption =>
      $composableBuilder(column: $table.caption, builder: (column) => column);

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AssetPhotosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssetPhotosTable,
          AssetPhotoRow,
          $$AssetPhotosTableFilterComposer,
          $$AssetPhotosTableOrderingComposer,
          $$AssetPhotosTableAnnotationComposer,
          $$AssetPhotosTableCreateCompanionBuilder,
          $$AssetPhotosTableUpdateCompanionBuilder,
          (AssetPhotoRow, $$AssetPhotosTableReferences),
          AssetPhotoRow,
          PrefetchHooks Function({bool assetId})
        > {
  $$AssetPhotosTableTableManager(_$AppDatabase db, $AssetPhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetPhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetPhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetPhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetPhotosCompanion(
                id: id,
                assetId: assetId,
                relativePath: relativePath,
                caption: caption,
                isPrimary: isPrimary,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String assetId,
                required String relativePath,
                Value<String?> caption = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AssetPhotosCompanion.insert(
                id: id,
                assetId: assetId,
                relativePath: relativePath,
                caption: caption,
                isPrimary: isPrimary,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AssetPhotosTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.assetId,
                        referencedTable: $$AssetPhotosTableReferences
                            ._assetIdTable(db),
                        referencedColumn: $$AssetPhotosTableReferences
                            ._assetIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AssetPhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssetPhotosTable,
      AssetPhotoRow,
      $$AssetPhotosTableFilterComposer,
      $$AssetPhotosTableOrderingComposer,
      $$AssetPhotosTableAnnotationComposer,
      $$AssetPhotosTableCreateCompanionBuilder,
      $$AssetPhotosTableUpdateCompanionBuilder,
      (AssetPhotoRow, $$AssetPhotosTableReferences),
      AssetPhotoRow,
      PrefetchHooks Function({bool assetId})
    >;
typedef $$MaintenancePlansTableCreateCompanionBuilder =
    MaintenancePlansCompanion Function({
      required String id,
      required String assetId,
      required String title,
      Value<String?> instructions,
      required int recurrenceInterval,
      required String recurrenceUnit,
      required String priority,
      required DateTime nextDueDate,
      Value<int> reminderDaysBefore,
      Value<bool> isEnabled,
      required String healthGroup,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> archivedAt,
      Value<int> rowid,
    });
typedef $$MaintenancePlansTableUpdateCompanionBuilder =
    MaintenancePlansCompanion Function({
      Value<String> id,
      Value<String> assetId,
      Value<String> title,
      Value<String?> instructions,
      Value<int> recurrenceInterval,
      Value<String> recurrenceUnit,
      Value<String> priority,
      Value<DateTime> nextDueDate,
      Value<int> reminderDaysBefore,
      Value<bool> isEnabled,
      Value<String> healthGroup,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> archivedAt,
      Value<int> rowid,
    });

final class $$MaintenancePlansTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $MaintenancePlansTable,
          MaintenancePlanRow
        > {
  $$MaintenancePlansTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AssetsTable _assetIdTable(_$AppDatabase db) =>
      db.assets.createAlias('maintenance_plans__asset_id__assets__id');

  $$AssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$AssetsTableTableManager(
      $_db,
      $_db.assets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $MaintenancePlanMetadataTable,
    List<MaintenancePlanMetadataRow>
  >
  _maintenancePlanMetadataRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.maintenancePlanMetadata,
        aliasName: 'maintenance_plans__id__maintenance_plan_metadata__plan_id',
      );

  $$MaintenancePlanMetadataTableProcessedTableManager
  get maintenancePlanMetadataRefs {
    final manager = $$MaintenancePlanMetadataTableTableManager(
      $_db,
      $_db.maintenancePlanMetadata,
    ).filter((f) => f.planId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _maintenancePlanMetadataRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $MaintenanceRecordsTable,
    List<MaintenanceRecordRow>
  >
  _maintenanceRecordsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.maintenanceRecords,
        aliasName: 'maintenance_plans__id__maintenance_records__plan_id',
      );

  $$MaintenanceRecordsTableProcessedTableManager get maintenanceRecordsRefs {
    final manager = $$MaintenanceRecordsTableTableManager(
      $_db,
      $_db.maintenanceRecords,
    ).filter((f) => f.planId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _maintenanceRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AppNotificationsTable, List<NotificationRow>>
  _appNotificationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.appNotifications,
    aliasName: 'maintenance_plans__id__notifications__plan_id',
  );

  $$AppNotificationsTableProcessedTableManager get appNotificationsRefs {
    final manager = $$AppNotificationsTableTableManager(
      $_db,
      $_db.appNotifications,
    ).filter((f) => f.planId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _appNotificationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $InboxNotificationsTable,
    List<InboxNotificationRow>
  >
  _inboxNotificationsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.inboxNotifications,
        aliasName: 'maintenance_plans__id__notification_inbox__plan_id',
      );

  $$InboxNotificationsTableProcessedTableManager get inboxNotificationsRefs {
    final manager = $$InboxNotificationsTableTableManager(
      $_db,
      $_db.inboxNotifications,
    ).filter((f) => f.planId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _inboxNotificationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MaintenancePlansTableFilterComposer
    extends Composer<_$AppDatabase, $MaintenancePlansTable> {
  $$MaintenancePlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get instructions => $composableBuilder(
    column: $table.instructions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recurrenceInterval => $composableBuilder(
    column: $table.recurrenceInterval,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurrenceUnit => $composableBuilder(
    column: $table.recurrenceUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextDueDate => $composableBuilder(
    column: $table.nextDueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reminderDaysBefore => $composableBuilder(
    column: $table.reminderDaysBefore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get healthGroup => $composableBuilder(
    column: $table.healthGroup,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AssetsTableFilterComposer get assetId {
    final $$AssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableFilterComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> maintenancePlanMetadataRefs(
    Expression<bool> Function($$MaintenancePlanMetadataTableFilterComposer f) f,
  ) {
    final $$MaintenancePlanMetadataTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.maintenancePlanMetadata,
          getReferencedColumn: (t) => t.planId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MaintenancePlanMetadataTableFilterComposer(
                $db: $db,
                $table: $db.maintenancePlanMetadata,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> maintenanceRecordsRefs(
    Expression<bool> Function($$MaintenanceRecordsTableFilterComposer f) f,
  ) {
    final $$MaintenanceRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.maintenanceRecords,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenanceRecordsTableFilterComposer(
            $db: $db,
            $table: $db.maintenanceRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> appNotificationsRefs(
    Expression<bool> Function($$AppNotificationsTableFilterComposer f) f,
  ) {
    final $$AppNotificationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.appNotifications,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AppNotificationsTableFilterComposer(
            $db: $db,
            $table: $db.appNotifications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> inboxNotificationsRefs(
    Expression<bool> Function($$InboxNotificationsTableFilterComposer f) f,
  ) {
    final $$InboxNotificationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.inboxNotifications,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InboxNotificationsTableFilterComposer(
            $db: $db,
            $table: $db.inboxNotifications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MaintenancePlansTableOrderingComposer
    extends Composer<_$AppDatabase, $MaintenancePlansTable> {
  $$MaintenancePlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get instructions => $composableBuilder(
    column: $table.instructions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recurrenceInterval => $composableBuilder(
    column: $table.recurrenceInterval,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrenceUnit => $composableBuilder(
    column: $table.recurrenceUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextDueDate => $composableBuilder(
    column: $table.nextDueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reminderDaysBefore => $composableBuilder(
    column: $table.reminderDaysBefore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
    column: $table.isEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get healthGroup => $composableBuilder(
    column: $table.healthGroup,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AssetsTableOrderingComposer get assetId {
    final $$AssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableOrderingComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MaintenancePlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $MaintenancePlansTable> {
  $$MaintenancePlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get instructions => $composableBuilder(
    column: $table.instructions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recurrenceInterval => $composableBuilder(
    column: $table.recurrenceInterval,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recurrenceUnit => $composableBuilder(
    column: $table.recurrenceUnit,
    builder: (column) => column,
  );

  GeneratedColumn<String> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<DateTime> get nextDueDate => $composableBuilder(
    column: $table.nextDueDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reminderDaysBefore => $composableBuilder(
    column: $table.reminderDaysBefore,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  GeneratedColumn<String> get healthGroup => $composableBuilder(
    column: $table.healthGroup,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  $$AssetsTableAnnotationComposer get assetId {
    final $$AssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.assets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.assets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> maintenancePlanMetadataRefs<T extends Object>(
    Expression<T> Function($$MaintenancePlanMetadataTableAnnotationComposer a)
    f,
  ) {
    final $$MaintenancePlanMetadataTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.maintenancePlanMetadata,
          getReferencedColumn: (t) => t.planId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MaintenancePlanMetadataTableAnnotationComposer(
                $db: $db,
                $table: $db.maintenancePlanMetadata,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> maintenanceRecordsRefs<T extends Object>(
    Expression<T> Function($$MaintenanceRecordsTableAnnotationComposer a) f,
  ) {
    final $$MaintenanceRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.maintenanceRecords,
          getReferencedColumn: (t) => t.planId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$MaintenanceRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.maintenanceRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> appNotificationsRefs<T extends Object>(
    Expression<T> Function($$AppNotificationsTableAnnotationComposer a) f,
  ) {
    final $$AppNotificationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.appNotifications,
      getReferencedColumn: (t) => t.planId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AppNotificationsTableAnnotationComposer(
            $db: $db,
            $table: $db.appNotifications,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> inboxNotificationsRefs<T extends Object>(
    Expression<T> Function($$InboxNotificationsTableAnnotationComposer a) f,
  ) {
    final $$InboxNotificationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.inboxNotifications,
          getReferencedColumn: (t) => t.planId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InboxNotificationsTableAnnotationComposer(
                $db: $db,
                $table: $db.inboxNotifications,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$MaintenancePlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MaintenancePlansTable,
          MaintenancePlanRow,
          $$MaintenancePlansTableFilterComposer,
          $$MaintenancePlansTableOrderingComposer,
          $$MaintenancePlansTableAnnotationComposer,
          $$MaintenancePlansTableCreateCompanionBuilder,
          $$MaintenancePlansTableUpdateCompanionBuilder,
          (MaintenancePlanRow, $$MaintenancePlansTableReferences),
          MaintenancePlanRow,
          PrefetchHooks Function({
            bool assetId,
            bool maintenancePlanMetadataRefs,
            bool maintenanceRecordsRefs,
            bool appNotificationsRefs,
            bool inboxNotificationsRefs,
          })
        > {
  $$MaintenancePlansTableTableManager(
    _$AppDatabase db,
    $MaintenancePlansTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MaintenancePlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MaintenancePlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MaintenancePlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> instructions = const Value.absent(),
                Value<int> recurrenceInterval = const Value.absent(),
                Value<String> recurrenceUnit = const Value.absent(),
                Value<String> priority = const Value.absent(),
                Value<DateTime> nextDueDate = const Value.absent(),
                Value<int> reminderDaysBefore = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                Value<String> healthGroup = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenancePlansCompanion(
                id: id,
                assetId: assetId,
                title: title,
                instructions: instructions,
                recurrenceInterval: recurrenceInterval,
                recurrenceUnit: recurrenceUnit,
                priority: priority,
                nextDueDate: nextDueDate,
                reminderDaysBefore: reminderDaysBefore,
                isEnabled: isEnabled,
                healthGroup: healthGroup,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String assetId,
                required String title,
                Value<String?> instructions = const Value.absent(),
                required int recurrenceInterval,
                required String recurrenceUnit,
                required String priority,
                required DateTime nextDueDate,
                Value<int> reminderDaysBefore = const Value.absent(),
                Value<bool> isEnabled = const Value.absent(),
                required String healthGroup,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenancePlansCompanion.insert(
                id: id,
                assetId: assetId,
                title: title,
                instructions: instructions,
                recurrenceInterval: recurrenceInterval,
                recurrenceUnit: recurrenceUnit,
                priority: priority,
                nextDueDate: nextDueDate,
                reminderDaysBefore: reminderDaysBefore,
                isEnabled: isEnabled,
                healthGroup: healthGroup,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MaintenancePlansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                assetId = false,
                maintenancePlanMetadataRefs = false,
                maintenanceRecordsRefs = false,
                appNotificationsRefs = false,
                inboxNotificationsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (maintenancePlanMetadataRefs) db.maintenancePlanMetadata,
                    if (maintenanceRecordsRefs) db.maintenanceRecords,
                    if (appNotificationsRefs) db.appNotifications,
                    if (inboxNotificationsRefs) db.inboxNotifications,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (assetId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.assetId,
                            referencedTable: $$MaintenancePlansTableReferences
                                ._assetIdTable(db),
                            referencedColumn: $$MaintenancePlansTableReferences
                                ._assetIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (maintenancePlanMetadataRefs)
                        await $_getPrefetchedData<
                          MaintenancePlanRow,
                          $MaintenancePlansTable,
                          MaintenancePlanMetadataRow
                        >(
                          currentTable: table,
                          referencedTable: $$MaintenancePlansTableReferences
                              ._maintenancePlanMetadataRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MaintenancePlansTableReferences(
                                db,
                                table,
                                p0,
                              ).maintenancePlanMetadataRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.planId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (maintenanceRecordsRefs)
                        await $_getPrefetchedData<
                          MaintenancePlanRow,
                          $MaintenancePlansTable,
                          MaintenanceRecordRow
                        >(
                          currentTable: table,
                          referencedTable: $$MaintenancePlansTableReferences
                              ._maintenanceRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MaintenancePlansTableReferences(
                                db,
                                table,
                                p0,
                              ).maintenanceRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.planId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (appNotificationsRefs)
                        await $_getPrefetchedData<
                          MaintenancePlanRow,
                          $MaintenancePlansTable,
                          NotificationRow
                        >(
                          currentTable: table,
                          referencedTable: $$MaintenancePlansTableReferences
                              ._appNotificationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MaintenancePlansTableReferences(
                                db,
                                table,
                                p0,
                              ).appNotificationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.planId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (inboxNotificationsRefs)
                        await $_getPrefetchedData<
                          MaintenancePlanRow,
                          $MaintenancePlansTable,
                          InboxNotificationRow
                        >(
                          currentTable: table,
                          referencedTable: $$MaintenancePlansTableReferences
                              ._inboxNotificationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MaintenancePlansTableReferences(
                                db,
                                table,
                                p0,
                              ).inboxNotificationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.planId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MaintenancePlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MaintenancePlansTable,
      MaintenancePlanRow,
      $$MaintenancePlansTableFilterComposer,
      $$MaintenancePlansTableOrderingComposer,
      $$MaintenancePlansTableAnnotationComposer,
      $$MaintenancePlansTableCreateCompanionBuilder,
      $$MaintenancePlansTableUpdateCompanionBuilder,
      (MaintenancePlanRow, $$MaintenancePlansTableReferences),
      MaintenancePlanRow,
      PrefetchHooks Function({
        bool assetId,
        bool maintenancePlanMetadataRefs,
        bool maintenanceRecordsRefs,
        bool appNotificationsRefs,
        bool inboxNotificationsRefs,
      })
    >;
typedef $$MaintenancePlanMetadataTableCreateCompanionBuilder =
    MaintenancePlanMetadataCompanion Function({
      required String planId,
      Value<String?> taskType,
      Value<String?> locationLabel,
      Value<int?> estimatedDurationMinutes,
      Value<String> requiredMaterialsJson,
      Value<String?> reminderRecommendation,
      Value<int?> sortOrder,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$MaintenancePlanMetadataTableUpdateCompanionBuilder =
    MaintenancePlanMetadataCompanion Function({
      Value<String> planId,
      Value<String?> taskType,
      Value<String?> locationLabel,
      Value<int?> estimatedDurationMinutes,
      Value<String> requiredMaterialsJson,
      Value<String?> reminderRecommendation,
      Value<int?> sortOrder,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$MaintenancePlanMetadataTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $MaintenancePlanMetadataTable,
          MaintenancePlanMetadataRow
        > {
  $$MaintenancePlanMetadataTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MaintenancePlansTable _planIdTable(_$AppDatabase db) => db
      .maintenancePlans
      .createAlias('maintenance_plan_metadata__plan_id__maintenance_plans__id');

  $$MaintenancePlansTableProcessedTableManager get planId {
    final $_column = $_itemColumn<String>('plan_id')!;

    final manager = $$MaintenancePlansTableTableManager(
      $_db,
      $_db.maintenancePlans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MaintenancePlanMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $MaintenancePlanMetadataTable> {
  $$MaintenancePlanMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationLabel => $composableBuilder(
    column: $table.locationLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get estimatedDurationMinutes => $composableBuilder(
    column: $table.estimatedDurationMinutes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requiredMaterialsJson => $composableBuilder(
    column: $table.requiredMaterialsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reminderRecommendation => $composableBuilder(
    column: $table.reminderRecommendation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MaintenancePlansTableFilterComposer get planId {
    final $$MaintenancePlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableFilterComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MaintenancePlanMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $MaintenancePlanMetadataTable> {
  $$MaintenancePlanMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationLabel => $composableBuilder(
    column: $table.locationLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get estimatedDurationMinutes => $composableBuilder(
    column: $table.estimatedDurationMinutes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requiredMaterialsJson => $composableBuilder(
    column: $table.requiredMaterialsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reminderRecommendation => $composableBuilder(
    column: $table.reminderRecommendation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MaintenancePlansTableOrderingComposer get planId {
    final $$MaintenancePlansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableOrderingComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MaintenancePlanMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $MaintenancePlanMetadataTable> {
  $$MaintenancePlanMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get taskType =>
      $composableBuilder(column: $table.taskType, builder: (column) => column);

  GeneratedColumn<String> get locationLabel => $composableBuilder(
    column: $table.locationLabel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get estimatedDurationMinutes => $composableBuilder(
    column: $table.estimatedDurationMinutes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requiredMaterialsJson => $composableBuilder(
    column: $table.requiredMaterialsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reminderRecommendation => $composableBuilder(
    column: $table.reminderRecommendation,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$MaintenancePlansTableAnnotationComposer get planId {
    final $$MaintenancePlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableAnnotationComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MaintenancePlanMetadataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MaintenancePlanMetadataTable,
          MaintenancePlanMetadataRow,
          $$MaintenancePlanMetadataTableFilterComposer,
          $$MaintenancePlanMetadataTableOrderingComposer,
          $$MaintenancePlanMetadataTableAnnotationComposer,
          $$MaintenancePlanMetadataTableCreateCompanionBuilder,
          $$MaintenancePlanMetadataTableUpdateCompanionBuilder,
          (
            MaintenancePlanMetadataRow,
            $$MaintenancePlanMetadataTableReferences,
          ),
          MaintenancePlanMetadataRow,
          PrefetchHooks Function({bool planId})
        > {
  $$MaintenancePlanMetadataTableTableManager(
    _$AppDatabase db,
    $MaintenancePlanMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MaintenancePlanMetadataTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$MaintenancePlanMetadataTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MaintenancePlanMetadataTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> planId = const Value.absent(),
                Value<String?> taskType = const Value.absent(),
                Value<String?> locationLabel = const Value.absent(),
                Value<int?> estimatedDurationMinutes = const Value.absent(),
                Value<String> requiredMaterialsJson = const Value.absent(),
                Value<String?> reminderRecommendation = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenancePlanMetadataCompanion(
                planId: planId,
                taskType: taskType,
                locationLabel: locationLabel,
                estimatedDurationMinutes: estimatedDurationMinutes,
                requiredMaterialsJson: requiredMaterialsJson,
                reminderRecommendation: reminderRecommendation,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String planId,
                Value<String?> taskType = const Value.absent(),
                Value<String?> locationLabel = const Value.absent(),
                Value<int?> estimatedDurationMinutes = const Value.absent(),
                Value<String> requiredMaterialsJson = const Value.absent(),
                Value<String?> reminderRecommendation = const Value.absent(),
                Value<int?> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenancePlanMetadataCompanion.insert(
                planId: planId,
                taskType: taskType,
                locationLabel: locationLabel,
                estimatedDurationMinutes: estimatedDurationMinutes,
                requiredMaterialsJson: requiredMaterialsJson,
                reminderRecommendation: reminderRecommendation,
                sortOrder: sortOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MaintenancePlanMetadataTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({planId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (planId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.planId,
                        referencedTable:
                            $$MaintenancePlanMetadataTableReferences
                                ._planIdTable(db),
                        referencedColumn:
                            $$MaintenancePlanMetadataTableReferences
                                ._planIdTable(db)
                                .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MaintenancePlanMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MaintenancePlanMetadataTable,
      MaintenancePlanMetadataRow,
      $$MaintenancePlanMetadataTableFilterComposer,
      $$MaintenancePlanMetadataTableOrderingComposer,
      $$MaintenancePlanMetadataTableAnnotationComposer,
      $$MaintenancePlanMetadataTableCreateCompanionBuilder,
      $$MaintenancePlanMetadataTableUpdateCompanionBuilder,
      (MaintenancePlanMetadataRow, $$MaintenancePlanMetadataTableReferences),
      MaintenancePlanMetadataRow,
      PrefetchHooks Function({bool planId})
    >;
typedef $$MaintenanceRecordsTableCreateCompanionBuilder =
    MaintenanceRecordsCompanion Function({
      required String id,
      required String planId,
      required DateTime dueDate,
      Value<DateTime> completedAt,
      Value<String?> notes,
      Value<int> rowid,
    });
typedef $$MaintenanceRecordsTableUpdateCompanionBuilder =
    MaintenanceRecordsCompanion Function({
      Value<String> id,
      Value<String> planId,
      Value<DateTime> dueDate,
      Value<DateTime> completedAt,
      Value<String?> notes,
      Value<int> rowid,
    });

final class $$MaintenanceRecordsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $MaintenanceRecordsTable,
          MaintenanceRecordRow
        > {
  $$MaintenanceRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MaintenancePlansTable _planIdTable(_$AppDatabase db) => db
      .maintenancePlans
      .createAlias('maintenance_records__plan_id__maintenance_plans__id');

  $$MaintenancePlansTableProcessedTableManager get planId {
    final $_column = $_itemColumn<String>('plan_id')!;

    final manager = $$MaintenancePlansTableTableManager(
      $_db,
      $_db.maintenancePlans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MaintenanceRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $MaintenanceRecordsTable> {
  $$MaintenanceRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  $$MaintenancePlansTableFilterComposer get planId {
    final $$MaintenancePlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableFilterComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MaintenanceRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $MaintenanceRecordsTable> {
  $$MaintenanceRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  $$MaintenancePlansTableOrderingComposer get planId {
    final $$MaintenancePlansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableOrderingComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MaintenanceRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MaintenanceRecordsTable> {
  $$MaintenanceRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  $$MaintenancePlansTableAnnotationComposer get planId {
    final $$MaintenancePlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableAnnotationComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MaintenanceRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MaintenanceRecordsTable,
          MaintenanceRecordRow,
          $$MaintenanceRecordsTableFilterComposer,
          $$MaintenanceRecordsTableOrderingComposer,
          $$MaintenanceRecordsTableAnnotationComposer,
          $$MaintenanceRecordsTableCreateCompanionBuilder,
          $$MaintenanceRecordsTableUpdateCompanionBuilder,
          (MaintenanceRecordRow, $$MaintenanceRecordsTableReferences),
          MaintenanceRecordRow,
          PrefetchHooks Function({bool planId})
        > {
  $$MaintenanceRecordsTableTableManager(
    _$AppDatabase db,
    $MaintenanceRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MaintenanceRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MaintenanceRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MaintenanceRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> planId = const Value.absent(),
                Value<DateTime> dueDate = const Value.absent(),
                Value<DateTime> completedAt = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenanceRecordsCompanion(
                id: id,
                planId: planId,
                dueDate: dueDate,
                completedAt: completedAt,
                notes: notes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String planId,
                required DateTime dueDate,
                Value<DateTime> completedAt = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MaintenanceRecordsCompanion.insert(
                id: id,
                planId: planId,
                dueDate: dueDate,
                completedAt: completedAt,
                notes: notes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MaintenanceRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({planId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (planId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.planId,
                        referencedTable: $$MaintenanceRecordsTableReferences
                            ._planIdTable(db),
                        referencedColumn: $$MaintenanceRecordsTableReferences
                            ._planIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MaintenanceRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MaintenanceRecordsTable,
      MaintenanceRecordRow,
      $$MaintenanceRecordsTableFilterComposer,
      $$MaintenanceRecordsTableOrderingComposer,
      $$MaintenanceRecordsTableAnnotationComposer,
      $$MaintenanceRecordsTableCreateCompanionBuilder,
      $$MaintenanceRecordsTableUpdateCompanionBuilder,
      (MaintenanceRecordRow, $$MaintenanceRecordsTableReferences),
      MaintenanceRecordRow,
      PrefetchHooks Function({bool planId})
    >;
typedef $$AppNotificationsTableCreateCompanionBuilder =
    AppNotificationsCompanion Function({
      required String id,
      required String planId,
      required String channel,
      required DateTime scheduledFor,
      Value<DateTime?> deliveredAt,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$AppNotificationsTableUpdateCompanionBuilder =
    AppNotificationsCompanion Function({
      Value<String> id,
      Value<String> planId,
      Value<String> channel,
      Value<DateTime> scheduledFor,
      Value<DateTime?> deliveredAt,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$AppNotificationsTableReferences
    extends
        BaseReferences<_$AppDatabase, $AppNotificationsTable, NotificationRow> {
  $$AppNotificationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MaintenancePlansTable _planIdTable(_$AppDatabase db) => db
      .maintenancePlans
      .createAlias('notifications__plan_id__maintenance_plans__id');

  $$MaintenancePlansTableProcessedTableManager get planId {
    final $_column = $_itemColumn<String>('plan_id')!;

    final manager = $$MaintenancePlansTableTableManager(
      $_db,
      $_db.maintenancePlans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AppNotificationsTableFilterComposer
    extends Composer<_$AppDatabase, $AppNotificationsTable> {
  $$AppNotificationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledFor => $composableBuilder(
    column: $table.scheduledFor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MaintenancePlansTableFilterComposer get planId {
    final $$MaintenancePlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableFilterComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AppNotificationsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppNotificationsTable> {
  $$AppNotificationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledFor => $composableBuilder(
    column: $table.scheduledFor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MaintenancePlansTableOrderingComposer get planId {
    final $$MaintenancePlansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableOrderingComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AppNotificationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppNotificationsTable> {
  $$AppNotificationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledFor => $composableBuilder(
    column: $table.scheduledFor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$MaintenancePlansTableAnnotationComposer get planId {
    final $$MaintenancePlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableAnnotationComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AppNotificationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppNotificationsTable,
          NotificationRow,
          $$AppNotificationsTableFilterComposer,
          $$AppNotificationsTableOrderingComposer,
          $$AppNotificationsTableAnnotationComposer,
          $$AppNotificationsTableCreateCompanionBuilder,
          $$AppNotificationsTableUpdateCompanionBuilder,
          (NotificationRow, $$AppNotificationsTableReferences),
          NotificationRow,
          PrefetchHooks Function({bool planId})
        > {
  $$AppNotificationsTableTableManager(
    _$AppDatabase db,
    $AppNotificationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppNotificationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppNotificationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppNotificationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> planId = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<DateTime> scheduledFor = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppNotificationsCompanion(
                id: id,
                planId: planId,
                channel: channel,
                scheduledFor: scheduledFor,
                deliveredAt: deliveredAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String planId,
                required String channel,
                required DateTime scheduledFor,
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppNotificationsCompanion.insert(
                id: id,
                planId: planId,
                channel: channel,
                scheduledFor: scheduledFor,
                deliveredAt: deliveredAt,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AppNotificationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({planId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (planId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.planId,
                        referencedTable: $$AppNotificationsTableReferences
                            ._planIdTable(db),
                        referencedColumn: $$AppNotificationsTableReferences
                            ._planIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AppNotificationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppNotificationsTable,
      NotificationRow,
      $$AppNotificationsTableFilterComposer,
      $$AppNotificationsTableOrderingComposer,
      $$AppNotificationsTableAnnotationComposer,
      $$AppNotificationsTableCreateCompanionBuilder,
      $$AppNotificationsTableUpdateCompanionBuilder,
      (NotificationRow, $$AppNotificationsTableReferences),
      NotificationRow,
      PrefetchHooks Function({bool planId})
    >;
typedef $$InboxNotificationsTableCreateCompanionBuilder =
    InboxNotificationsCompanion Function({
      required String id,
      required String title,
      required String body,
      required String kind,
      Value<String?> route,
      Value<String?> planId,
      Value<String?> messageCode,
      Value<String> messageArgs,
      Value<String> dedupeKey,
      Value<DateTime?> readAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$InboxNotificationsTableUpdateCompanionBuilder =
    InboxNotificationsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> body,
      Value<String> kind,
      Value<String?> route,
      Value<String?> planId,
      Value<String?> messageCode,
      Value<String> messageArgs,
      Value<String> dedupeKey,
      Value<DateTime?> readAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$InboxNotificationsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $InboxNotificationsTable,
          InboxNotificationRow
        > {
  $$InboxNotificationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MaintenancePlansTable _planIdTable(_$AppDatabase db) => db
      .maintenancePlans
      .createAlias('notification_inbox__plan_id__maintenance_plans__id');

  $$MaintenancePlansTableProcessedTableManager? get planId {
    final $_column = $_itemColumn<String>('plan_id');
    if ($_column == null) return null;
    final manager = $$MaintenancePlansTableTableManager(
      $_db,
      $_db.maintenancePlans,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_planIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$InboxNotificationsTableFilterComposer
    extends Composer<_$AppDatabase, $InboxNotificationsTable> {
  $$InboxNotificationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageCode => $composableBuilder(
    column: $table.messageCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageArgs => $composableBuilder(
    column: $table.messageArgs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dedupeKey => $composableBuilder(
    column: $table.dedupeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MaintenancePlansTableFilterComposer get planId {
    final $$MaintenancePlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableFilterComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InboxNotificationsTableOrderingComposer
    extends Composer<_$AppDatabase, $InboxNotificationsTable> {
  $$InboxNotificationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageCode => $composableBuilder(
    column: $table.messageCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageArgs => $composableBuilder(
    column: $table.messageArgs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dedupeKey => $composableBuilder(
    column: $table.dedupeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MaintenancePlansTableOrderingComposer get planId {
    final $$MaintenancePlansTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableOrderingComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InboxNotificationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InboxNotificationsTable> {
  $$InboxNotificationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get route =>
      $composableBuilder(column: $table.route, builder: (column) => column);

  GeneratedColumn<String> get messageCode => $composableBuilder(
    column: $table.messageCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get messageArgs => $composableBuilder(
    column: $table.messageArgs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get dedupeKey =>
      $composableBuilder(column: $table.dedupeKey, builder: (column) => column);

  GeneratedColumn<DateTime> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$MaintenancePlansTableAnnotationComposer get planId {
    final $$MaintenancePlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.planId,
      referencedTable: $db.maintenancePlans,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MaintenancePlansTableAnnotationComposer(
            $db: $db,
            $table: $db.maintenancePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InboxNotificationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InboxNotificationsTable,
          InboxNotificationRow,
          $$InboxNotificationsTableFilterComposer,
          $$InboxNotificationsTableOrderingComposer,
          $$InboxNotificationsTableAnnotationComposer,
          $$InboxNotificationsTableCreateCompanionBuilder,
          $$InboxNotificationsTableUpdateCompanionBuilder,
          (InboxNotificationRow, $$InboxNotificationsTableReferences),
          InboxNotificationRow,
          PrefetchHooks Function({bool planId})
        > {
  $$InboxNotificationsTableTableManager(
    _$AppDatabase db,
    $InboxNotificationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InboxNotificationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InboxNotificationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InboxNotificationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> route = const Value.absent(),
                Value<String?> planId = const Value.absent(),
                Value<String?> messageCode = const Value.absent(),
                Value<String> messageArgs = const Value.absent(),
                Value<String> dedupeKey = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InboxNotificationsCompanion(
                id: id,
                title: title,
                body: body,
                kind: kind,
                route: route,
                planId: planId,
                messageCode: messageCode,
                messageArgs: messageArgs,
                dedupeKey: dedupeKey,
                readAt: readAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String body,
                required String kind,
                Value<String?> route = const Value.absent(),
                Value<String?> planId = const Value.absent(),
                Value<String?> messageCode = const Value.absent(),
                Value<String> messageArgs = const Value.absent(),
                Value<String> dedupeKey = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InboxNotificationsCompanion.insert(
                id: id,
                title: title,
                body: body,
                kind: kind,
                route: route,
                planId: planId,
                messageCode: messageCode,
                messageArgs: messageArgs,
                dedupeKey: dedupeKey,
                readAt: readAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$InboxNotificationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({planId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (planId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.planId,
                        referencedTable: $$InboxNotificationsTableReferences
                            ._planIdTable(db),
                        referencedColumn: $$InboxNotificationsTableReferences
                            ._planIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$InboxNotificationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InboxNotificationsTable,
      InboxNotificationRow,
      $$InboxNotificationsTableFilterComposer,
      $$InboxNotificationsTableOrderingComposer,
      $$InboxNotificationsTableAnnotationComposer,
      $$InboxNotificationsTableCreateCompanionBuilder,
      $$InboxNotificationsTableUpdateCompanionBuilder,
      (InboxNotificationRow, $$InboxNotificationsTableReferences),
      InboxNotificationRow,
      PrefetchHooks Function({bool planId})
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$StreaksTableCreateCompanionBuilder = StreaksCompanion Function({
  required String id,
  Value<int> currentStreak,
  Value<int> bestStreak,
  Value<DateTime?> lastCompletedDate,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$StreaksTableUpdateCompanionBuilder = StreaksCompanion Function({
  Value<String> id,
  Value<int> currentStreak,
  Value<int> bestStreak,
  Value<DateTime?> lastCompletedDate,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$StreaksTableFilterComposer
    extends Composer<_$AppDatabase, $StreaksTable> {
  $$StreaksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentStreak => $composableBuilder(
    column: $table.currentStreak,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bestStreak => $composableBuilder(
    column: $table.bestStreak,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastCompletedDate => $composableBuilder(
    column: $table.lastCompletedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StreaksTableOrderingComposer
    extends Composer<_$AppDatabase, $StreaksTable> {
  $$StreaksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentStreak => $composableBuilder(
    column: $table.currentStreak,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bestStreak => $composableBuilder(
    column: $table.bestStreak,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastCompletedDate => $composableBuilder(
    column: $table.lastCompletedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StreaksTableAnnotationComposer
    extends Composer<_$AppDatabase, $StreaksTable> {
  $$StreaksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get currentStreak => $composableBuilder(
    column: $table.currentStreak,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bestStreak => $composableBuilder(
    column: $table.bestStreak,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastCompletedDate => $composableBuilder(
    column: $table.lastCompletedDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StreaksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StreaksTable,
          StreakRow,
          $$StreaksTableFilterComposer,
          $$StreaksTableOrderingComposer,
          $$StreaksTableAnnotationComposer,
          $$StreaksTableCreateCompanionBuilder,
          $$StreaksTableUpdateCompanionBuilder,
          (StreakRow, BaseReferences<_$AppDatabase, $StreaksTable, StreakRow>),
          StreakRow,
          PrefetchHooks Function()
        > {
  $$StreaksTableTableManager(_$AppDatabase db, $StreaksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StreaksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StreaksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StreaksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> currentStreak = const Value.absent(),
                Value<int> bestStreak = const Value.absent(),
                Value<DateTime?> lastCompletedDate = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StreaksCompanion(
                id: id,
                currentStreak: currentStreak,
                bestStreak: bestStreak,
                lastCompletedDate: lastCompletedDate,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int> currentStreak = const Value.absent(),
                Value<int> bestStreak = const Value.absent(),
                Value<DateTime?> lastCompletedDate = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StreaksCompanion.insert(
                id: id,
                currentStreak: currentStreak,
                bestStreak: bestStreak,
                lastCompletedDate: lastCompletedDate,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StreaksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StreaksTable,
      StreakRow,
      $$StreaksTableFilterComposer,
      $$StreaksTableOrderingComposer,
      $$StreaksTableAnnotationComposer,
      $$StreaksTableCreateCompanionBuilder,
      $$StreaksTableUpdateCompanionBuilder,
      (StreakRow, BaseReferences<_$AppDatabase, $StreaksTable, StreakRow>),
      StreakRow,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder = SyncOutboxCompanion Function({
  required String entity,
  required String recordKey,
  required String operation,
  Value<String?> payloadJson,
  Value<String?> userId,
  Value<DateTime> changedAt,
  Value<DateTime?> createdAt,
  Value<String> state,
  Value<int> attempts,
  Value<DateTime?> nextAttemptAt,
  Value<String?> lastErrorCode,
  Value<String?> lastError,
  Value<int> generation,
  Value<int> rowid,
});
typedef $$SyncOutboxTableUpdateCompanionBuilder = SyncOutboxCompanion Function({
  Value<String> entity,
  Value<String> recordKey,
  Value<String> operation,
  Value<String?> payloadJson,
  Value<String?> userId,
  Value<DateTime> changedAt,
  Value<DateTime?> createdAt,
  Value<String> state,
  Value<int> attempts,
  Value<DateTime?> nextAttemptAt,
  Value<String?> lastErrorCode,
  Value<String?> lastError,
  Value<int> generation,
  Value<int> rowid,
});

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get recordKey =>
      $composableBuilder(column: $table.recordKey, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          SyncOutboxData,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxData,
            BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
          ),
          SyncOutboxData,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entity = const Value.absent(),
                Value<String> recordKey = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String?> payloadJson = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<DateTime> changedAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion(
                entity: entity,
                recordKey: recordKey,
                operation: operation,
                payloadJson: payloadJson,
                userId: userId,
                changedAt: changedAt,
                createdAt: createdAt,
                state: state,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastError: lastError,
                generation: generation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entity,
                required String recordKey,
                required String operation,
                Value<String?> payloadJson = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<DateTime> changedAt = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                entity: entity,
                recordKey: recordKey,
                operation: operation,
                payloadJson: payloadJson,
                userId: userId,
                changedAt: changedAt,
                createdAt: createdAt,
                state: state,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastError: lastError,
                generation: generation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      SyncOutboxData,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxData,
        BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxData>,
      ),
      SyncOutboxData,
      PrefetchHooks Function()
    >;
typedef $$ReminderScheduleSnapshotsTableCreateCompanionBuilder =
    ReminderScheduleSnapshotsCompanion Function({
      required String identity,
      required int notificationId,
      required String planRevision,
      required DateTime scheduledAt,
      required String timezone,
      required String localComponents,
      required String scheduleMode,
      required String contentVersion,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ReminderScheduleSnapshotsTableUpdateCompanionBuilder =
    ReminderScheduleSnapshotsCompanion Function({
      Value<String> identity,
      Value<int> notificationId,
      Value<String> planRevision,
      Value<DateTime> scheduledAt,
      Value<String> timezone,
      Value<String> localComponents,
      Value<String> scheduleMode,
      Value<String> contentVersion,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ReminderScheduleSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $ReminderScheduleSnapshotsTable> {
  $$ReminderScheduleSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planRevision => $composableBuilder(
    column: $table.planRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localComponents => $composableBuilder(
    column: $table.localComponents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduleMode => $composableBuilder(
    column: $table.scheduleMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentVersion => $composableBuilder(
    column: $table.contentVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReminderScheduleSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReminderScheduleSnapshotsTable> {
  $$ReminderScheduleSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planRevision => $composableBuilder(
    column: $table.planRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timezone => $composableBuilder(
    column: $table.timezone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localComponents => $composableBuilder(
    column: $table.localComponents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduleMode => $composableBuilder(
    column: $table.scheduleMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentVersion => $composableBuilder(
    column: $table.contentVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReminderScheduleSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReminderScheduleSnapshotsTable> {
  $$ReminderScheduleSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get identity =>
      $composableBuilder(column: $table.identity, builder: (column) => column);

  GeneratedColumn<int> get notificationId => $composableBuilder(
    column: $table.notificationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get planRevision => $composableBuilder(
    column: $table.planRevision,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get timezone =>
      $composableBuilder(column: $table.timezone, builder: (column) => column);

  GeneratedColumn<String> get localComponents => $composableBuilder(
    column: $table.localComponents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scheduleMode => $composableBuilder(
    column: $table.scheduleMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentVersion => $composableBuilder(
    column: $table.contentVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReminderScheduleSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReminderScheduleSnapshotsTable,
          ReminderScheduleSnapshot,
          $$ReminderScheduleSnapshotsTableFilterComposer,
          $$ReminderScheduleSnapshotsTableOrderingComposer,
          $$ReminderScheduleSnapshotsTableAnnotationComposer,
          $$ReminderScheduleSnapshotsTableCreateCompanionBuilder,
          $$ReminderScheduleSnapshotsTableUpdateCompanionBuilder,
          (
            ReminderScheduleSnapshot,
            BaseReferences<
              _$AppDatabase,
              $ReminderScheduleSnapshotsTable,
              ReminderScheduleSnapshot
            >,
          ),
          ReminderScheduleSnapshot,
          PrefetchHooks Function()
        > {
  $$ReminderScheduleSnapshotsTableTableManager(
    _$AppDatabase db,
    $ReminderScheduleSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReminderScheduleSnapshotsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ReminderScheduleSnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReminderScheduleSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> identity = const Value.absent(),
                Value<int> notificationId = const Value.absent(),
                Value<String> planRevision = const Value.absent(),
                Value<DateTime> scheduledAt = const Value.absent(),
                Value<String> timezone = const Value.absent(),
                Value<String> localComponents = const Value.absent(),
                Value<String> scheduleMode = const Value.absent(),
                Value<String> contentVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReminderScheduleSnapshotsCompanion(
                identity: identity,
                notificationId: notificationId,
                planRevision: planRevision,
                scheduledAt: scheduledAt,
                timezone: timezone,
                localComponents: localComponents,
                scheduleMode: scheduleMode,
                contentVersion: contentVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String identity,
                required int notificationId,
                required String planRevision,
                required DateTime scheduledAt,
                required String timezone,
                required String localComponents,
                required String scheduleMode,
                required String contentVersion,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReminderScheduleSnapshotsCompanion.insert(
                identity: identity,
                notificationId: notificationId,
                planRevision: planRevision,
                scheduledAt: scheduledAt,
                timezone: timezone,
                localComponents: localComponents,
                scheduleMode: scheduleMode,
                contentVersion: contentVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReminderScheduleSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReminderScheduleSnapshotsTable,
      ReminderScheduleSnapshot,
      $$ReminderScheduleSnapshotsTableFilterComposer,
      $$ReminderScheduleSnapshotsTableOrderingComposer,
      $$ReminderScheduleSnapshotsTableAnnotationComposer,
      $$ReminderScheduleSnapshotsTableCreateCompanionBuilder,
      $$ReminderScheduleSnapshotsTableUpdateCompanionBuilder,
      (
        ReminderScheduleSnapshot,
        BaseReferences<
          _$AppDatabase,
          $ReminderScheduleSnapshotsTable,
          ReminderScheduleSnapshot
        >,
      ),
      ReminderScheduleSnapshot,
      PrefetchHooks Function()
    >;
typedef $$SyncCursorsTableCreateCompanionBuilder =
    SyncCursorsCompanion Function({
      required String entity,
      Value<int> lastSyncSeq,
      Value<String?> lastRecordKey,
      Value<int> rowid,
    });
typedef $$SyncCursorsTableUpdateCompanionBuilder =
    SyncCursorsCompanion Function({
      Value<String> entity,
      Value<int> lastSyncSeq,
      Value<String?> lastRecordKey,
      Value<int> rowid,
    });

class $$SyncCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSyncSeq => $composableBuilder(
    column: $table.lastSyncSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastRecordKey => $composableBuilder(
    column: $table.lastRecordKey,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSyncSeq => $composableBuilder(
    column: $table.lastSyncSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRecordKey => $composableBuilder(
    column: $table.lastRecordKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<int> get lastSyncSeq => $composableBuilder(
    column: $table.lastSyncSeq,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastRecordKey => $composableBuilder(
    column: $table.lastRecordKey,
    builder: (column) => column,
  );
}

class $$SyncCursorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCursorsTable,
          SyncCursor,
          $$SyncCursorsTableFilterComposer,
          $$SyncCursorsTableOrderingComposer,
          $$SyncCursorsTableAnnotationComposer,
          $$SyncCursorsTableCreateCompanionBuilder,
          $$SyncCursorsTableUpdateCompanionBuilder,
          (
            SyncCursor,
            BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>,
          ),
          SyncCursor,
          PrefetchHooks Function()
        > {
  $$SyncCursorsTableTableManager(_$AppDatabase db, $SyncCursorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entity = const Value.absent(),
                Value<int> lastSyncSeq = const Value.absent(),
                Value<String?> lastRecordKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion(
                entity: entity,
                lastSyncSeq: lastSyncSeq,
                lastRecordKey: lastRecordKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entity,
                Value<int> lastSyncSeq = const Value.absent(),
                Value<String?> lastRecordKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion.insert(
                entity: entity,
                lastSyncSeq: lastSyncSeq,
                lastRecordKey: lastRecordKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCursorsTable,
      SyncCursor,
      $$SyncCursorsTableFilterComposer,
      $$SyncCursorsTableOrderingComposer,
      $$SyncCursorsTableAnnotationComposer,
      $$SyncCursorsTableCreateCompanionBuilder,
      $$SyncCursorsTableUpdateCompanionBuilder,
      (
        SyncCursor,
        BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>,
      ),
      SyncCursor,
      PrefetchHooks Function()
    >;
typedef $$SyncShadowsTableCreateCompanionBuilder =
    SyncShadowsCompanion Function({
      required String entity,
      required String recordKey,
      required int remoteRevision,
      Value<DateTime?> remoteModifiedAt,
      Value<String?> payloadHash,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });
typedef $$SyncShadowsTableUpdateCompanionBuilder =
    SyncShadowsCompanion Function({
      Value<String> entity,
      Value<String> recordKey,
      Value<int> remoteRevision,
      Value<DateTime?> remoteModifiedAt,
      Value<String?> payloadHash,
      Value<DateTime> lastSyncedAt,
      Value<int> rowid,
    });

class $$SyncShadowsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncShadowsTable> {
  $$SyncShadowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteRevision => $composableBuilder(
    column: $table.remoteRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get remoteModifiedAt => $composableBuilder(
    column: $table.remoteModifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadHash => $composableBuilder(
    column: $table.payloadHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncShadowsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncShadowsTable> {
  $$SyncShadowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteRevision => $composableBuilder(
    column: $table.remoteRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get remoteModifiedAt => $composableBuilder(
    column: $table.remoteModifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadHash => $composableBuilder(
    column: $table.payloadHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncShadowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncShadowsTable> {
  $$SyncShadowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get recordKey =>
      $composableBuilder(column: $table.recordKey, builder: (column) => column);

  GeneratedColumn<int> get remoteRevision => $composableBuilder(
    column: $table.remoteRevision,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get remoteModifiedAt => $composableBuilder(
    column: $table.remoteModifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadHash => $composableBuilder(
    column: $table.payloadHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );
}

class $$SyncShadowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncShadowsTable,
          SyncShadow,
          $$SyncShadowsTableFilterComposer,
          $$SyncShadowsTableOrderingComposer,
          $$SyncShadowsTableAnnotationComposer,
          $$SyncShadowsTableCreateCompanionBuilder,
          $$SyncShadowsTableUpdateCompanionBuilder,
          (
            SyncShadow,
            BaseReferences<_$AppDatabase, $SyncShadowsTable, SyncShadow>,
          ),
          SyncShadow,
          PrefetchHooks Function()
        > {
  $$SyncShadowsTableTableManager(_$AppDatabase db, $SyncShadowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncShadowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncShadowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncShadowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entity = const Value.absent(),
                Value<String> recordKey = const Value.absent(),
                Value<int> remoteRevision = const Value.absent(),
                Value<DateTime?> remoteModifiedAt = const Value.absent(),
                Value<String?> payloadHash = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncShadowsCompanion(
                entity: entity,
                recordKey: recordKey,
                remoteRevision: remoteRevision,
                remoteModifiedAt: remoteModifiedAt,
                payloadHash: payloadHash,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entity,
                required String recordKey,
                required int remoteRevision,
                Value<DateTime?> remoteModifiedAt = const Value.absent(),
                Value<String?> payloadHash = const Value.absent(),
                Value<DateTime> lastSyncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncShadowsCompanion.insert(
                entity: entity,
                recordKey: recordKey,
                remoteRevision: remoteRevision,
                remoteModifiedAt: remoteModifiedAt,
                payloadHash: payloadHash,
                lastSyncedAt: lastSyncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncShadowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncShadowsTable,
      SyncShadow,
      $$SyncShadowsTableFilterComposer,
      $$SyncShadowsTableOrderingComposer,
      $$SyncShadowsTableAnnotationComposer,
      $$SyncShadowsTableCreateCompanionBuilder,
      $$SyncShadowsTableUpdateCompanionBuilder,
      (
        SyncShadow,
        BaseReferences<_$AppDatabase, $SyncShadowsTable, SyncShadow>,
      ),
      SyncShadow,
      PrefetchHooks Function()
    >;
typedef $$SyncRuntimeTableCreateCompanionBuilder =
    SyncRuntimeCompanion Function({
      Value<int> id,
      Value<bool> suppressOutbox,
      Value<String?> leaseOwner,
      Value<DateTime?> leaseExpiresAt,
    });
typedef $$SyncRuntimeTableUpdateCompanionBuilder =
    SyncRuntimeCompanion Function({
      Value<int> id,
      Value<bool> suppressOutbox,
      Value<String?> leaseOwner,
      Value<DateTime?> leaseExpiresAt,
    });

class $$SyncRuntimeTableFilterComposer
    extends Composer<_$AppDatabase, $SyncRuntimeTable> {
  $$SyncRuntimeTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get suppressOutbox => $composableBuilder(
    column: $table.suppressOutbox,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get leaseExpiresAt => $composableBuilder(
    column: $table.leaseExpiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncRuntimeTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncRuntimeTable> {
  $$SyncRuntimeTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get suppressOutbox => $composableBuilder(
    column: $table.suppressOutbox,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get leaseExpiresAt => $composableBuilder(
    column: $table.leaseExpiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncRuntimeTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncRuntimeTable> {
  $$SyncRuntimeTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get suppressOutbox => $composableBuilder(
    column: $table.suppressOutbox,
    builder: (column) => column,
  );

  GeneratedColumn<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get leaseExpiresAt => $composableBuilder(
    column: $table.leaseExpiresAt,
    builder: (column) => column,
  );
}

class $$SyncRuntimeTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncRuntimeTable,
          SyncRuntimeData,
          $$SyncRuntimeTableFilterComposer,
          $$SyncRuntimeTableOrderingComposer,
          $$SyncRuntimeTableAnnotationComposer,
          $$SyncRuntimeTableCreateCompanionBuilder,
          $$SyncRuntimeTableUpdateCompanionBuilder,
          (
            SyncRuntimeData,
            BaseReferences<_$AppDatabase, $SyncRuntimeTable, SyncRuntimeData>,
          ),
          SyncRuntimeData,
          PrefetchHooks Function()
        > {
  $$SyncRuntimeTableTableManager(_$AppDatabase db, $SyncRuntimeTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncRuntimeTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncRuntimeTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncRuntimeTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> suppressOutbox = const Value.absent(),
                Value<String?> leaseOwner = const Value.absent(),
                Value<DateTime?> leaseExpiresAt = const Value.absent(),
              }) => SyncRuntimeCompanion(
                id: id,
                suppressOutbox: suppressOutbox,
                leaseOwner: leaseOwner,
                leaseExpiresAt: leaseExpiresAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> suppressOutbox = const Value.absent(),
                Value<String?> leaseOwner = const Value.absent(),
                Value<DateTime?> leaseExpiresAt = const Value.absent(),
              }) => SyncRuntimeCompanion.insert(
                id: id,
                suppressOutbox: suppressOutbox,
                leaseOwner: leaseOwner,
                leaseExpiresAt: leaseExpiresAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncRuntimeTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncRuntimeTable,
      SyncRuntimeData,
      $$SyncRuntimeTableFilterComposer,
      $$SyncRuntimeTableOrderingComposer,
      $$SyncRuntimeTableAnnotationComposer,
      $$SyncRuntimeTableCreateCompanionBuilder,
      $$SyncRuntimeTableUpdateCompanionBuilder,
      (
        SyncRuntimeData,
        BaseReferences<_$AppDatabase, $SyncRuntimeTable, SyncRuntimeData>,
      ),
      SyncRuntimeData,
      PrefetchHooks Function()
    >;
typedef $$SyncMediaCleanupTableCreateCompanionBuilder =
    SyncMediaCleanupCompanion Function({
      required String objectPath,
      required String userId,
      required String entity,
      required String recordKey,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$SyncMediaCleanupTableUpdateCompanionBuilder =
    SyncMediaCleanupCompanion Function({
      Value<String> objectPath,
      Value<String> userId,
      Value<String> entity,
      Value<String> recordKey,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$SyncMediaCleanupTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMediaCleanupTable> {
  $$SyncMediaCleanupTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get objectPath => $composableBuilder(
    column: $table.objectPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMediaCleanupTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMediaCleanupTable> {
  $$SyncMediaCleanupTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get objectPath => $composableBuilder(
    column: $table.objectPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordKey => $composableBuilder(
    column: $table.recordKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMediaCleanupTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMediaCleanupTable> {
  $$SyncMediaCleanupTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get objectPath => $composableBuilder(
    column: $table.objectPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get recordKey =>
      $composableBuilder(column: $table.recordKey, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$SyncMediaCleanupTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMediaCleanupTable,
          SyncMediaCleanupData,
          $$SyncMediaCleanupTableFilterComposer,
          $$SyncMediaCleanupTableOrderingComposer,
          $$SyncMediaCleanupTableAnnotationComposer,
          $$SyncMediaCleanupTableCreateCompanionBuilder,
          $$SyncMediaCleanupTableUpdateCompanionBuilder,
          (
            SyncMediaCleanupData,
            BaseReferences<
              _$AppDatabase,
              $SyncMediaCleanupTable,
              SyncMediaCleanupData
            >,
          ),
          SyncMediaCleanupData,
          PrefetchHooks Function()
        > {
  $$SyncMediaCleanupTableTableManager(
    _$AppDatabase db,
    $SyncMediaCleanupTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMediaCleanupTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMediaCleanupTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMediaCleanupTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> objectPath = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> recordKey = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMediaCleanupCompanion(
                objectPath: objectPath,
                userId: userId,
                entity: entity,
                recordKey: recordKey,
                createdAt: createdAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String objectPath,
                required String userId,
                required String entity,
                required String recordKey,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMediaCleanupCompanion.insert(
                objectPath: objectPath,
                userId: userId,
                entity: entity,
                recordKey: recordKey,
                createdAt: createdAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMediaCleanupTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMediaCleanupTable,
      SyncMediaCleanupData,
      $$SyncMediaCleanupTableFilterComposer,
      $$SyncMediaCleanupTableOrderingComposer,
      $$SyncMediaCleanupTableAnnotationComposer,
      $$SyncMediaCleanupTableCreateCompanionBuilder,
      $$SyncMediaCleanupTableUpdateCompanionBuilder,
      (
        SyncMediaCleanupData,
        BaseReferences<
          _$AppDatabase,
          $SyncMediaCleanupTable,
          SyncMediaCleanupData
        >,
      ),
      SyncMediaCleanupData,
      PrefetchHooks Function()
    >;
typedef $$SyncAccountTableCreateCompanionBuilder =
    SyncAccountCompanion Function({
      Value<int> id,
      required String deviceId,
      Value<String?> boundUserId,
      Value<bool> enabled,
      Value<String> migrationState,
      Value<DateTime?> lastSyncedAt,
      Value<DateTime?> lastSyncAttemptAt,
      Value<DateTime?> lastSyncFailureAt,
      Value<DateTime?> lastIntegrityCheckAt,
      Value<String?> lastError,
      Value<String?> blockedReason,
      Value<bool> restorePending,
      Value<String?> backgroundResult,
      Value<String?> hydrationRunId,
      Value<String?> hydrationState,
      Value<String?> hydrationStage,
      Value<int> hydrationCompletedUnits,
      Value<int> hydrationTotalUnits,
      Value<DateTime?> hydrationStartedAt,
      Value<DateTime?> hydrationUpdatedAt,
      Value<String?> hydrationError,
      Value<bool> uploadProhibited,
      Value<String?> quarantineReason,
      Value<String?> legacyOwnerId,
      Value<DateTime> updatedAt,
    });
typedef $$SyncAccountTableUpdateCompanionBuilder =
    SyncAccountCompanion Function({
      Value<int> id,
      Value<String> deviceId,
      Value<String?> boundUserId,
      Value<bool> enabled,
      Value<String> migrationState,
      Value<DateTime?> lastSyncedAt,
      Value<DateTime?> lastSyncAttemptAt,
      Value<DateTime?> lastSyncFailureAt,
      Value<DateTime?> lastIntegrityCheckAt,
      Value<String?> lastError,
      Value<String?> blockedReason,
      Value<bool> restorePending,
      Value<String?> backgroundResult,
      Value<String?> hydrationRunId,
      Value<String?> hydrationState,
      Value<String?> hydrationStage,
      Value<int> hydrationCompletedUnits,
      Value<int> hydrationTotalUnits,
      Value<DateTime?> hydrationStartedAt,
      Value<DateTime?> hydrationUpdatedAt,
      Value<String?> hydrationError,
      Value<bool> uploadProhibited,
      Value<String?> quarantineReason,
      Value<String?> legacyOwnerId,
      Value<DateTime> updatedAt,
    });

class $$SyncAccountTableFilterComposer
    extends Composer<_$AppDatabase, $SyncAccountTable> {
  $$SyncAccountTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get boundUserId => $composableBuilder(
    column: $table.boundUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get migrationState => $composableBuilder(
    column: $table.migrationState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncAttemptAt => $composableBuilder(
    column: $table.lastSyncAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncFailureAt => $composableBuilder(
    column: $table.lastSyncFailureAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastIntegrityCheckAt => $composableBuilder(
    column: $table.lastIntegrityCheckAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blockedReason => $composableBuilder(
    column: $table.blockedReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get restorePending => $composableBuilder(
    column: $table.restorePending,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backgroundResult => $composableBuilder(
    column: $table.backgroundResult,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hydrationRunId => $composableBuilder(
    column: $table.hydrationRunId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hydrationState => $composableBuilder(
    column: $table.hydrationState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hydrationStage => $composableBuilder(
    column: $table.hydrationStage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hydrationCompletedUnits => $composableBuilder(
    column: $table.hydrationCompletedUnits,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hydrationTotalUnits => $composableBuilder(
    column: $table.hydrationTotalUnits,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get hydrationStartedAt => $composableBuilder(
    column: $table.hydrationStartedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get hydrationUpdatedAt => $composableBuilder(
    column: $table.hydrationUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hydrationError => $composableBuilder(
    column: $table.hydrationError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get uploadProhibited => $composableBuilder(
    column: $table.uploadProhibited,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quarantineReason => $composableBuilder(
    column: $table.quarantineReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get legacyOwnerId => $composableBuilder(
    column: $table.legacyOwnerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncAccountTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncAccountTable> {
  $$SyncAccountTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get boundUserId => $composableBuilder(
    column: $table.boundUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get migrationState => $composableBuilder(
    column: $table.migrationState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncAttemptAt => $composableBuilder(
    column: $table.lastSyncAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncFailureAt => $composableBuilder(
    column: $table.lastSyncFailureAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastIntegrityCheckAt => $composableBuilder(
    column: $table.lastIntegrityCheckAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blockedReason => $composableBuilder(
    column: $table.blockedReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get restorePending => $composableBuilder(
    column: $table.restorePending,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backgroundResult => $composableBuilder(
    column: $table.backgroundResult,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hydrationRunId => $composableBuilder(
    column: $table.hydrationRunId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hydrationState => $composableBuilder(
    column: $table.hydrationState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hydrationStage => $composableBuilder(
    column: $table.hydrationStage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hydrationCompletedUnits => $composableBuilder(
    column: $table.hydrationCompletedUnits,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hydrationTotalUnits => $composableBuilder(
    column: $table.hydrationTotalUnits,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get hydrationStartedAt => $composableBuilder(
    column: $table.hydrationStartedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get hydrationUpdatedAt => $composableBuilder(
    column: $table.hydrationUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hydrationError => $composableBuilder(
    column: $table.hydrationError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get uploadProhibited => $composableBuilder(
    column: $table.uploadProhibited,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quarantineReason => $composableBuilder(
    column: $table.quarantineReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get legacyOwnerId => $composableBuilder(
    column: $table.legacyOwnerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncAccountTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncAccountTable> {
  $$SyncAccountTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get boundUserId => $composableBuilder(
    column: $table.boundUserId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get migrationState => $composableBuilder(
    column: $table.migrationState,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncAttemptAt => $composableBuilder(
    column: $table.lastSyncAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncFailureAt => $composableBuilder(
    column: $table.lastSyncFailureAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastIntegrityCheckAt => $composableBuilder(
    column: $table.lastIntegrityCheckAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get blockedReason => $composableBuilder(
    column: $table.blockedReason,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get restorePending => $composableBuilder(
    column: $table.restorePending,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backgroundResult => $composableBuilder(
    column: $table.backgroundResult,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hydrationRunId => $composableBuilder(
    column: $table.hydrationRunId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hydrationState => $composableBuilder(
    column: $table.hydrationState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hydrationStage => $composableBuilder(
    column: $table.hydrationStage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hydrationCompletedUnits => $composableBuilder(
    column: $table.hydrationCompletedUnits,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hydrationTotalUnits => $composableBuilder(
    column: $table.hydrationTotalUnits,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get hydrationStartedAt => $composableBuilder(
    column: $table.hydrationStartedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get hydrationUpdatedAt => $composableBuilder(
    column: $table.hydrationUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hydrationError => $composableBuilder(
    column: $table.hydrationError,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get uploadProhibited => $composableBuilder(
    column: $table.uploadProhibited,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quarantineReason => $composableBuilder(
    column: $table.quarantineReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get legacyOwnerId => $composableBuilder(
    column: $table.legacyOwnerId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncAccountTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncAccountTable,
          SyncAccountData,
          $$SyncAccountTableFilterComposer,
          $$SyncAccountTableOrderingComposer,
          $$SyncAccountTableAnnotationComposer,
          $$SyncAccountTableCreateCompanionBuilder,
          $$SyncAccountTableUpdateCompanionBuilder,
          (
            SyncAccountData,
            BaseReferences<_$AppDatabase, $SyncAccountTable, SyncAccountData>,
          ),
          SyncAccountData,
          PrefetchHooks Function()
        > {
  $$SyncAccountTableTableManager(_$AppDatabase db, $SyncAccountTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncAccountTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncAccountTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncAccountTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String?> boundUserId = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> migrationState = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<DateTime?> lastSyncAttemptAt = const Value.absent(),
                Value<DateTime?> lastSyncFailureAt = const Value.absent(),
                Value<DateTime?> lastIntegrityCheckAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> blockedReason = const Value.absent(),
                Value<bool> restorePending = const Value.absent(),
                Value<String?> backgroundResult = const Value.absent(),
                Value<String?> hydrationRunId = const Value.absent(),
                Value<String?> hydrationState = const Value.absent(),
                Value<String?> hydrationStage = const Value.absent(),
                Value<int> hydrationCompletedUnits = const Value.absent(),
                Value<int> hydrationTotalUnits = const Value.absent(),
                Value<DateTime?> hydrationStartedAt = const Value.absent(),
                Value<DateTime?> hydrationUpdatedAt = const Value.absent(),
                Value<String?> hydrationError = const Value.absent(),
                Value<bool> uploadProhibited = const Value.absent(),
                Value<String?> quarantineReason = const Value.absent(),
                Value<String?> legacyOwnerId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => SyncAccountCompanion(
                id: id,
                deviceId: deviceId,
                boundUserId: boundUserId,
                enabled: enabled,
                migrationState: migrationState,
                lastSyncedAt: lastSyncedAt,
                lastSyncAttemptAt: lastSyncAttemptAt,
                lastSyncFailureAt: lastSyncFailureAt,
                lastIntegrityCheckAt: lastIntegrityCheckAt,
                lastError: lastError,
                blockedReason: blockedReason,
                restorePending: restorePending,
                backgroundResult: backgroundResult,
                hydrationRunId: hydrationRunId,
                hydrationState: hydrationState,
                hydrationStage: hydrationStage,
                hydrationCompletedUnits: hydrationCompletedUnits,
                hydrationTotalUnits: hydrationTotalUnits,
                hydrationStartedAt: hydrationStartedAt,
                hydrationUpdatedAt: hydrationUpdatedAt,
                hydrationError: hydrationError,
                uploadProhibited: uploadProhibited,
                quarantineReason: quarantineReason,
                legacyOwnerId: legacyOwnerId,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String deviceId,
                Value<String?> boundUserId = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> migrationState = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<DateTime?> lastSyncAttemptAt = const Value.absent(),
                Value<DateTime?> lastSyncFailureAt = const Value.absent(),
                Value<DateTime?> lastIntegrityCheckAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<String?> blockedReason = const Value.absent(),
                Value<bool> restorePending = const Value.absent(),
                Value<String?> backgroundResult = const Value.absent(),
                Value<String?> hydrationRunId = const Value.absent(),
                Value<String?> hydrationState = const Value.absent(),
                Value<String?> hydrationStage = const Value.absent(),
                Value<int> hydrationCompletedUnits = const Value.absent(),
                Value<int> hydrationTotalUnits = const Value.absent(),
                Value<DateTime?> hydrationStartedAt = const Value.absent(),
                Value<DateTime?> hydrationUpdatedAt = const Value.absent(),
                Value<String?> hydrationError = const Value.absent(),
                Value<bool> uploadProhibited = const Value.absent(),
                Value<String?> quarantineReason = const Value.absent(),
                Value<String?> legacyOwnerId = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => SyncAccountCompanion.insert(
                id: id,
                deviceId: deviceId,
                boundUserId: boundUserId,
                enabled: enabled,
                migrationState: migrationState,
                lastSyncedAt: lastSyncedAt,
                lastSyncAttemptAt: lastSyncAttemptAt,
                lastSyncFailureAt: lastSyncFailureAt,
                lastIntegrityCheckAt: lastIntegrityCheckAt,
                lastError: lastError,
                blockedReason: blockedReason,
                restorePending: restorePending,
                backgroundResult: backgroundResult,
                hydrationRunId: hydrationRunId,
                hydrationState: hydrationState,
                hydrationStage: hydrationStage,
                hydrationCompletedUnits: hydrationCompletedUnits,
                hydrationTotalUnits: hydrationTotalUnits,
                hydrationStartedAt: hydrationStartedAt,
                hydrationUpdatedAt: hydrationUpdatedAt,
                hydrationError: hydrationError,
                uploadProhibited: uploadProhibited,
                quarantineReason: quarantineReason,
                legacyOwnerId: legacyOwnerId,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncAccountTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncAccountTable,
      SyncAccountData,
      $$SyncAccountTableFilterComposer,
      $$SyncAccountTableOrderingComposer,
      $$SyncAccountTableAnnotationComposer,
      $$SyncAccountTableCreateCompanionBuilder,
      $$SyncAccountTableUpdateCompanionBuilder,
      (
        SyncAccountData,
        BaseReferences<_$AppDatabase, $SyncAccountTable, SyncAccountData>,
      ),
      SyncAccountData,
      PrefetchHooks Function()
    >;
typedef $$NotificationReconciliationRequestsTableCreateCompanionBuilder =
    NotificationReconciliationRequestsCompanion Function({
      required String scopeKey,
      Value<String?> planId,
      required String reason,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorMessage,
      Value<bool> requiresFullRebuild,
      Value<int> rowid,
    });
typedef $$NotificationReconciliationRequestsTableUpdateCompanionBuilder =
    NotificationReconciliationRequestsCompanion Function({
      Value<String> scopeKey,
      Value<String?> planId,
      Value<String> reason,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> attempts,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastErrorCode,
      Value<String?> lastErrorMessage,
      Value<bool> requiresFullRebuild,
      Value<int> rowid,
    });

class $$NotificationReconciliationRequestsTableFilterComposer
    extends Composer<_$AppDatabase, $NotificationReconciliationRequestsTable> {
  $$NotificationReconciliationRequestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scopeKey => $composableBuilder(
    column: $table.scopeKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorMessage => $composableBuilder(
    column: $table.lastErrorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get requiresFullRebuild => $composableBuilder(
    column: $table.requiresFullRebuild,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotificationReconciliationRequestsTableOrderingComposer
    extends Composer<_$AppDatabase, $NotificationReconciliationRequestsTable> {
  $$NotificationReconciliationRequestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scopeKey => $composableBuilder(
    column: $table.scopeKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorMessage => $composableBuilder(
    column: $table.lastErrorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get requiresFullRebuild => $composableBuilder(
    column: $table.requiresFullRebuild,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotificationReconciliationRequestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotificationReconciliationRequestsTable> {
  $$NotificationReconciliationRequestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scopeKey =>
      $composableBuilder(column: $table.scopeKey, builder: (column) => column);

  GeneratedColumn<String> get planId =>
      $composableBuilder(column: $table.planId, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorMessage => $composableBuilder(
    column: $table.lastErrorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get requiresFullRebuild => $composableBuilder(
    column: $table.requiresFullRebuild,
    builder: (column) => column,
  );
}

class $$NotificationReconciliationRequestsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotificationReconciliationRequestsTable,
          NotificationReconciliationRequestRow,
          $$NotificationReconciliationRequestsTableFilterComposer,
          $$NotificationReconciliationRequestsTableOrderingComposer,
          $$NotificationReconciliationRequestsTableAnnotationComposer,
          $$NotificationReconciliationRequestsTableCreateCompanionBuilder,
          $$NotificationReconciliationRequestsTableUpdateCompanionBuilder,
          (
            NotificationReconciliationRequestRow,
            BaseReferences<
              _$AppDatabase,
              $NotificationReconciliationRequestsTable,
              NotificationReconciliationRequestRow
            >,
          ),
          NotificationReconciliationRequestRow,
          PrefetchHooks Function()
        > {
  $$NotificationReconciliationRequestsTableTableManager(
    _$AppDatabase db,
    $NotificationReconciliationRequestsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotificationReconciliationRequestsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$NotificationReconciliationRequestsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NotificationReconciliationRequestsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> scopeKey = const Value.absent(),
                Value<String?> planId = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorMessage = const Value.absent(),
                Value<bool> requiresFullRebuild = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationReconciliationRequestsCompanion(
                scopeKey: scopeKey,
                planId: planId,
                reason: reason,
                createdAt: createdAt,
                updatedAt: updatedAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastErrorMessage: lastErrorMessage,
                requiresFullRebuild: requiresFullRebuild,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scopeKey,
                Value<String?> planId = const Value.absent(),
                required String reason,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorMessage = const Value.absent(),
                Value<bool> requiresFullRebuild = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationReconciliationRequestsCompanion.insert(
                scopeKey: scopeKey,
                planId: planId,
                reason: reason,
                createdAt: createdAt,
                updatedAt: updatedAt,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastErrorMessage: lastErrorMessage,
                requiresFullRebuild: requiresFullRebuild,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotificationReconciliationRequestsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotificationReconciliationRequestsTable,
      NotificationReconciliationRequestRow,
      $$NotificationReconciliationRequestsTableFilterComposer,
      $$NotificationReconciliationRequestsTableOrderingComposer,
      $$NotificationReconciliationRequestsTableAnnotationComposer,
      $$NotificationReconciliationRequestsTableCreateCompanionBuilder,
      $$NotificationReconciliationRequestsTableUpdateCompanionBuilder,
      (
        NotificationReconciliationRequestRow,
        BaseReferences<
          _$AppDatabase,
          $NotificationReconciliationRequestsTable,
          NotificationReconciliationRequestRow
        >,
      ),
      NotificationReconciliationRequestRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AreasTableTableManager get areas =>
      $$AreasTableTableManager(_db, _db.areas);
  $$RoomsTableTableManager get rooms =>
      $$RoomsTableTableManager(_db, _db.rooms);
  $$AssetsTableTableManager get assets =>
      $$AssetsTableTableManager(_db, _db.assets);
  $$DeviceDetailsTableTableTableManager get deviceDetailsTable =>
      $$DeviceDetailsTableTableTableManager(_db, _db.deviceDetailsTable);
  $$PetDetailsTableTableTableManager get petDetailsTable =>
      $$PetDetailsTableTableTableManager(_db, _db.petDetailsTable);
  $$PlantDetailsTableTableTableManager get plantDetailsTable =>
      $$PlantDetailsTableTableTableManager(_db, _db.plantDetailsTable);
  $$SafetyDetailsTableTableTableManager get safetyDetailsTable =>
      $$SafetyDetailsTableTableTableManager(_db, _db.safetyDetailsTable);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$AssetTagsTableTableManager get assetTags =>
      $$AssetTagsTableTableManager(_db, _db.assetTags);
  $$AssetPhotosTableTableManager get assetPhotos =>
      $$AssetPhotosTableTableManager(_db, _db.assetPhotos);
  $$MaintenancePlansTableTableManager get maintenancePlans =>
      $$MaintenancePlansTableTableManager(_db, _db.maintenancePlans);
  $$MaintenancePlanMetadataTableTableManager get maintenancePlanMetadata =>
      $$MaintenancePlanMetadataTableTableManager(
        _db,
        _db.maintenancePlanMetadata,
      );
  $$MaintenanceRecordsTableTableManager get maintenanceRecords =>
      $$MaintenanceRecordsTableTableManager(_db, _db.maintenanceRecords);
  $$AppNotificationsTableTableManager get appNotifications =>
      $$AppNotificationsTableTableManager(_db, _db.appNotifications);
  $$InboxNotificationsTableTableManager get inboxNotifications =>
      $$InboxNotificationsTableTableManager(_db, _db.inboxNotifications);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$StreaksTableTableManager get streaks =>
      $$StreaksTableTableManager(_db, _db.streaks);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$ReminderScheduleSnapshotsTableTableManager get reminderScheduleSnapshots =>
      $$ReminderScheduleSnapshotsTableTableManager(
        _db,
        _db.reminderScheduleSnapshots,
      );
  $$SyncCursorsTableTableManager get syncCursors =>
      $$SyncCursorsTableTableManager(_db, _db.syncCursors);
  $$SyncShadowsTableTableManager get syncShadows =>
      $$SyncShadowsTableTableManager(_db, _db.syncShadows);
  $$SyncRuntimeTableTableManager get syncRuntime =>
      $$SyncRuntimeTableTableManager(_db, _db.syncRuntime);
  $$SyncMediaCleanupTableTableManager get syncMediaCleanup =>
      $$SyncMediaCleanupTableTableManager(_db, _db.syncMediaCleanup);
  $$SyncAccountTableTableManager get syncAccount =>
      $$SyncAccountTableTableManager(_db, _db.syncAccount);
  $$NotificationReconciliationRequestsTableTableManager
  get notificationReconciliationRequests =>
      $$NotificationReconciliationRequestsTableTableManager(
        _db,
        _db.notificationReconciliationRequests,
      );
}
