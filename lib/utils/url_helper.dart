import 'constants.dart';

List<String> resolveMediaCandidates(String? url) {
  final raw = url?.trim() ?? '';
  if (raw.isEmpty) return const <String>[];
  if (raw.startsWith('data:') || raw.startsWith('blob:')) return [raw];

  if (raw.startsWith('channel-private:')) {
    return _candidateUrls(
      '/channel-media/${raw.substring('channel-private:'.length)}',
      preferredOrigin: Constants.baseUrl,
    );
  }

  final parsed = Uri.tryParse(raw);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    final host = parsed.host.toLowerCase();
    final trustedHosts = <String>{
      for (final server in Constants.mediaServers)
        Uri.tryParse(server)?.host.toLowerCase() ?? '',
      Uri.tryParse(Constants.baseUrl)?.host.toLowerCase() ?? '',
      'files.mcl0.dpdns.org',
    };
    if (!trustedHosts.contains(host)) return [raw];
    final path = parsed.path.isEmpty ? '/' : parsed.path;
    final query = parsed.hasQuery ? '?${parsed.query}' : '';
    return _candidateUrls(
      '$path$query',
      preferredOrigin: '${parsed.scheme}://${parsed.authority}',
      original: raw,
    );
  }

  final path = raw.startsWith('/') ? raw : '/$raw';
  return _candidateUrls(path, preferredOrigin: Constants.defaultBaseUrl);
}

List<String> _candidateUrls(
  String path, {
  required String preferredOrigin,
  String? original,
}) {
  final question = path.indexOf('?');
  final cleanPath = question < 0 ? path : path.substring(0, question);
  final query = question < 0 ? '' : path.substring(question);
  final appPath = _asAppUploadPath(cleanPath);
  final origins = <String>[
    preferredOrigin,
    Constants.defaultBaseUrl,
    ...Constants.mediaServers,
  ].map((value) => value.replaceFirst(RegExp(r'/+$'), '')).toSet();
  final candidates = <String>[];

  if (original != null) candidates.add(original);
  for (final origin in origins) {
    if (appPath != cleanPath) candidates.add('$origin$appPath$query');
    if (cleanPath.startsWith('/media/')) {
      final suffix = cleanPath.substring('/media'.length);
      candidates.add('$origin/uploads$suffix$query');
    }
    candidates.add('$origin$cleanPath$query');
  }
  return candidates.toSet().toList(growable: false);
}

String _asAppUploadPath(String path) {
  if (path.startsWith('/v1/uploads/')) return path;
  if (path.startsWith('/uploads/')) return '/v1$path';
  if (path.startsWith('/media/')) return '/v1/uploads$path';
  return path;
}

String resolveMediaUrl(String? url) {
  final candidates = resolveMediaCandidates(url);
  return candidates.isNotEmpty ? candidates.first : '';
}
