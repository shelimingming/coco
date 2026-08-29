import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/daily_notes_api.dart';
import '../domain/models.dart';

final dailyNoteSettingsProvider =
    FutureProvider.autoDispose<DailyNoteSettings>((ref) async {
  return ref.watch(dailyNotesApiProvider).getSettings();
});

final dailyNotesListProvider =
    FutureProvider.autoDispose<List<DailyNote>>((ref) async {
  return ref.watch(dailyNotesApiProvider).list();
});

final dailyNoteDetailProvider =
    FutureProvider.autoDispose.family<DailyNote, String>((ref, id) async {
  return ref.watch(dailyNotesApiProvider).get(id);
});

final childDailyNoteTodayProvider =
    FutureProvider.autoDispose<DailyNote?>((ref) async {
  return ref.watch(dailyNotesApiProvider).childToday();
});

final dailyNoteImageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, urlPath) async {
  return ref.watch(dailyNotesApiProvider).loadImageBytes(urlPath);
});
