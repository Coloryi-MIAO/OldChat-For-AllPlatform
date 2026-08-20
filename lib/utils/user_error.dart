String safeErrorMessage(Object error) {
  var message = error.toString();
  message = message.replaceAll(RegExp(r"file ['\"]?[^'\"]+['\"]?"), 'file');
  message = message.replaceAll(RegExp(r"/(?:home|Users|storage|private)/[^\s'\"]+"), 'local file');
  message = message.replaceAll(RegExp(r"[A-Za-z]:\\[^\s'\"]+"), 'local file');
  return message.length > 240 ? '${message.substring(0, 240)}…' : message;
}
