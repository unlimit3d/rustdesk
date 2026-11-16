import 'dart:convert';

List<dynamic> parseLoginOptions(String body) {
  final options = jsonDecode(body);
  if (options == null) return [];
  if (options is! List || options.any((item) => item is! String)) {
    throw const FormatException('Invalid login options');
  }
  for (final item in options.cast<String>()) {
    if (item.startsWith('common-oidc/')) {
      final providers = jsonDecode(item.substring('common-oidc/'.length));
      if (providers == null) return [];
      if (providers is! List ||
          providers.any((item) => item is! Map || item['name'] is! String)) {
        throw const FormatException('Invalid login providers');
      }
      return providers;
    }
  }
  return options
      .cast<String>()
      .where((item) => item.startsWith('oidc/'))
      .map((item) => {'name': item.substring('oidc/'.length)})
      .toList();
}
