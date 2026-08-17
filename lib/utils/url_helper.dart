import 'constants.dart';

List<String> resolveMediaCandidates(String? url) {
  if (url == null || url.trim().isEmpty) return const <String>[];
  final raw = url.trim();
  if (raw.startsWith('data:') || raw.startsWith('blob:')) return [raw];
  final uri = Uri.tryParse(raw);
  final isAbsolute = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  if (isAbsolute && !_isTrustedMediaHost(uri.host)) return [raw];
  final path = raw.startsWith('http://') || raw.startsWith('https://')
      ? (uri?.path ?? raw)
      : (raw.startsWith('/') ? raw : '/$raw');
  final isUpload = path.startsWith('/v1/uploads/') || path.startsWith('/uploads/');
  if (!isUpload && (raw.startsWith('http://') || raw.startsWith('https://'))) return [raw];
  final uploadPath = path.startsWith('/uploads/') ? '/v1$path' : path;
  final suffix = uploadPath.substring('/v1/uploads/'.length);
  final candidates = <String>[
    '${Constants.resourceBaseUrl}/$suffix',
    '${Constants.backupServer}/v1/uploads/$suffix',
    '${Constants.baseUrl}/v1/uploads/$suffix',
  ];
  return candidates.toSet().toList();
}

bool _isTrustedMediaHost(String host) {
  final lower = host.toLowerCase();
  return lower == 'files.mcl0.dpdns.org' ||
      lower == '60.205.94.101' ||
      lower == '154.9.24.232' ||
      lower == 'data.mcl0.dpdns.org' ||
      lower == Uri.tryParse(Constants.baseUrl)?.host.toLowerCase();
}

String resolveMediaUrl(String? url) {
  final candidates = resolveMediaCandidates(url);
  if (candidates.isNotEmpty) return candidates.first;
  return '';
}
