class TextNormalizer {
  const TextNormalizer._();

  static String normalize(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}