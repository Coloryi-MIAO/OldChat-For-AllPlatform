import 'constants.dart';

List<String> resolveMediaCandidates(String? url) {
  final raw = url?.trim() ?? '';
  if (raw.isEmpty) return const <String>[];
  if (raw.startsWith('data:') || raw.startsWith('blob:')) return [raw];
  if (raw.startsWith('channel-private:')) {
    return [Constants.resolveMediaUrl(raw)];
  }
  final parsed = Uri.tryParse(raw);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    if (parsed.path.contains('/channel-media/')) return [raw];
    final trustedHosts = <String>{
      Uri.tryParse(Constants.defaultBaseUrl)?.host ?? '',
      Uri.tryParse(Constants.hiddenFallbackServer)?.host ?? '',
      Uri.tryParse(Constants.baseUrl)?.host ?? '',
    };
    final isKnownMediaPath = parsed.path == '/media' ||
        parsed.path.startsWith('/media/') ||
        parsed.path == '/uploads' ||
        parsed.path.startsWith('/uploads/') ||
        parsed.path.startsWith('/v1/uploads/');
    if (!trustedHosts.contains(parsed.host) && !isKnownMediaPath) return [raw];
    final normalized = _normalizeMediaPath(parsed.path, parsed.query);
    final origin = '${parsed.scheme}://${parsed.authority}';
    return _candidatesForPath(origin, normalized);
  }
  final path = _normalizeMediaPath(raw.startsWith('/') ? raw : '/$raw', '');
  return _candidatesForPath(Constants.defaultBaseUrl, path);
}

List<String> _candidatesForPath(String preferredOrigin, String path) {
  final origins = <String>[
    preferredOrigin,
    ...Constants.mediaServers,
  ].map((value) => value.replaceFirst(RegExp(r'/+$'), '')).toSet();
  return origins.map((origin) => '$origin$path').toList();
}

String _normalizeMediaPath(String path, String query) {
  var normalized = path;
  if (normalized == '/media' || normalized.startsWith('/media/')) {
    normalized = '/uploads/media${normalized.substring('/media'.length)}';
  } else if (normalized.startsWith('/uploads/media/') &&
      !normalized.startsWith('/v1/')) {
    normalized = '/v1$normalized';
  } else if (normalized.startsWith('/uploads/') &&
      !normalized.startsWith('/v1/')) {
    normalized = '/v1$normalized';
  }
  return query.isEmpty ? normalized : '$normalized?$query';
}

String resolveMediaUrl(String? url) {
  final candidates = resolveMediaCandidates(url);
  return candidates.isNotEmpty ? candidates.first : '';
}
