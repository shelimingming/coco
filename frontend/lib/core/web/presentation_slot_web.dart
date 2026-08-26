import 'package:web/web.dart' as web;

/// Web：从 URL `?presentation_slot=` 读取演示槽位（parent / child）。
String? readPresentationSlot() {
  final search = web.window.location.search;
  final query = search.startsWith('?') ? search.substring(1) : search;
  final fromWindow = Uri.splitQueryString(query)['presentation_slot'];
  final raw =
      (fromWindow ?? Uri.base.queryParameters['presentation_slot'])
          ?.trim()
          .toLowerCase();
  if (raw == null || raw.isEmpty) return null;
  if (!RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(raw)) return null;
  return raw;
}
