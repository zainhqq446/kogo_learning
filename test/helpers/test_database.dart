import 'package:kogo_voice_learning/data/db/kogo_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Memakai SQLite in-memory per isolate test sehingga file test yang berjalan
/// paralel tidak saling mengunci satu file database.
Future<void> useFreshTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  await KogoDatabase.instance.close();
  KogoDatabase.overridePath = inMemoryDatabasePath;
}
