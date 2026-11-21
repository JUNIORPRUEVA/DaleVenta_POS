import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ServerConnection { unknown, reachable, unreachable }

final serverConnectionProvider = StateProvider<ServerConnection>(
  (ref) => ServerConnection.unknown,
);
