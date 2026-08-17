import 'package:flutter_riverpod/flutter_riverpod.dart';

final salesDataRefreshTickProvider = StateProvider<int>((ref) => 0);
final cashDataRefreshTickProvider = StateProvider<int>((ref) => 0);
