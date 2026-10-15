import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'core/database/spot_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final database = await SpotDatabase.open();
    runApp(SpotHubApp(database: database));
  } catch (error) {
    runApp(StartupErrorApp(error: error));
  }
}
