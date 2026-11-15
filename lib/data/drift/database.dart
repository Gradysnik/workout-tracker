import 'package:drift/drift.dart';

part 'database.g.dart';

@DataClassName('JournalRecord')
class JournalRecords extends Table {
  TextColumn get id => text()();

  /// Дата тренировки в виде yyyy-MM-dd.
  TextColumn get date => text()();
  TextColumn get workout => text()();
  TextColumn get workoutKey => text()();
  TextColumn get exercise => text()();
  TextColumn get exKey => text()();
  IntColumn get setNo => integer()();
  IntColumn get partNo => integer()();
  RealColumn get weight => real().nullable()();
  IntColumn get reps => integer().nullable()();
  IntColumn get seconds => integer().nullable()();
  RealColumn get minutes => real().nullable()();
  IntColumn get kcal => integer().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get pending => boolean()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ProgramRecord')
class ProgramRecords extends Table {
  IntColumn get position => integer()();
  TextColumn get workout => text()();
  IntColumn get sortOrder => integer()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  IntColumn get sets => integer()();
  TextColumn get repsTarget => text()();
  BoolColumn get dropSet => boolean()();
  RealColumn get weightStep => real()();
  TextColumn get note => text()();

  @override
  Set<Column> get primaryKey => {position};
}

@DataClassName('ScheduleRecord')
class ScheduleRecords extends Table {
  IntColumn get position => integer()();
  IntColumn get weekday => integer()();
  TextColumn get workout => text()();

  @override
  Set<Column> get primaryKey => {position};
}

@DataClassName('MetaRecord')
class MetaRecords extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
    tables: [JournalRecords, ProgramRecords, ScheduleRecords, MetaRecords])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
