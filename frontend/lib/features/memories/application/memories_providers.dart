import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/memories_api.dart';
import '../domain/models.dart';

final memoriesListProvider = FutureProvider.autoDispose<List<Memory>>((
  ref,
) async {
  return ref.watch(memoriesApiProvider).list();
});
