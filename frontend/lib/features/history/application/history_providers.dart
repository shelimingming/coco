import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/history_api.dart';
import '../domain/models.dart';

final conversationListProvider =
    FutureProvider.autoDispose<List<ConversationSummary>>((ref) async {
      return ref.watch(historyApiProvider).list();
    });

final conversationDetailProvider = FutureProvider.autoDispose
    .family<ConversationDetail, String>((ref, conversationId) async {
      return ref.watch(historyApiProvider).get(conversationId);
    });
