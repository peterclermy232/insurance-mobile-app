import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/auth/auth_controller.dart';
import 'core/auth/token_store.dart';
import 'core/db/app_database.dart';
import 'core/db/syncable.dart';
import 'core/location/location_service.dart';
import 'core/media/media_repository.dart';
import 'core/media/photo_service.dart';
import 'core/network/api_client.dart';
import 'core/network/connectivity_service.dart';
import 'core/sync/sync_controller.dart';
import 'core/sync/sync_engine.dart';
import 'core/sync/sync_transport.dart';
import 'features/claims/data/claim_repository.dart';
import 'features/farmers/data/farmer_repository.dart';
import 'features/farms/data/admin_unit_repository.dart';
import 'features/farms/data/farm_repository.dart';
import 'features/inspections/data/inspection_repository.dart';
import 'features/quotations/data/quotation_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await AppDatabase.open();
  final changes = DataChanges();
  final tokens = SecureTokenStore();
  final api = ApiClient(tokens: tokens);
  final auth = AuthController(api: api, tokens: tokens, db: db);
  final connectivity = ConnectivityService();
  final engine = SyncEngine(db: db, transport: ApiSyncTransport(api));
  final sync = SyncController(
    engine: engine,
    db: db,
    auth: auth,
    connectivity: connectivity,
    changes: changes,
  );

  await auth.init();
  await connectivity.start();
  sync.start();

  runApp(MultiProvider(
    providers: [
      Provider.value(value: db),
      ChangeNotifierProvider.value(value: changes),
      Provider.value(value: api),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: connectivity),
      ChangeNotifierProvider.value(value: sync),
      Provider(create: (_) => const LocationService()),
      Provider(create: (_) => PhotoService()),
      Provider(create: (_) => MediaRepository(db, changes)),
      Provider(create: (_) => FarmerRepository(db, changes)),
      Provider(create: (_) => FarmRepository(db, changes)),
      Provider(create: (_) => AdminUnitRepository(db)),
      Provider(create: (_) => QuotationRepository(db, changes)),
      Provider(create: (_) => ClaimRepository(db, changes)),
      Provider(create: (_) => InspectionRepository(db, changes)),
    ],
    child: const CropInsuranceApp(),
  ));
}
