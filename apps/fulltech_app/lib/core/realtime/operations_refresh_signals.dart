import 'package:flutter_riverpod/flutter_riverpod.dart';

final catalogDataRefreshTickProvider = StateProvider<int>((ref) => 0);

final salesDataRefreshTickProvider = StateProvider<int>((ref) => 0);
final cashDataRefreshTickProvider = StateProvider<int>((ref) => 0);
