/// Builds labels for map-backed select controls without dropping duplicate
/// options that share the same display name.
Map<String, V> buildUniqueSelectOptions<T, V>(
  Iterable<T> values, {
  required String Function(T value) labelOf,
  required V Function(T value) valueOf,
  String Function(T value)? disambiguatorOf,
  String Function(T value)? idOf,
  Set<String> reservedLabels = const {},
}) {
  final items = values.toList(growable: false);
  final labelCounts = <String, int>{};
  for (final item in items) {
    final label = labelOf(item).trim();
    labelCounts.update(label, (count) => count + 1, ifAbsent: () => 1);
  }
  final contextualLabelCounts = <String, int>{};
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final label = labelOf(item).trim();
    if (labelCounts[label]! > 1 || reservedLabels.contains(label)) {
      final context = disambiguatorOf?.call(item).trim() ?? '';
      final id = idOf?.call(item).trim() ?? '';
      final fallback = id.isEmpty ? '${index + 1}' : id;
      final contextualLabel =
          '$label · ${context.isEmpty ? fallback : context}';
      contextualLabelCounts.update(
        contextualLabel,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
  }

  final options = <String, V>{};
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final label = labelOf(item).trim();
    var optionLabel = label;
    if (labelCounts[label]! > 1 || reservedLabels.contains(label)) {
      final context = disambiguatorOf?.call(item).trim() ?? '';
      final id = idOf?.call(item).trim() ?? '';
      final fallback = id.isEmpty ? '${index + 1}' : id;
      optionLabel = '$label · ${context.isEmpty ? fallback : context}';
      if (contextualLabelCounts[optionLabel]! > 1) {
        optionLabel = '$optionLabel · $fallback';
      }
    }

    if (reservedLabels.contains(optionLabel) ||
        options.containsKey(optionLabel)) {
      final id = idOf?.call(item).trim() ?? '';
      optionLabel = '$optionLabel · ${id.isEmpty ? index + 1 : id}';
    }
    var suffix = index + 1;
    while (reservedLabels.contains(optionLabel) ||
        options.containsKey(optionLabel)) {
      optionLabel = '$optionLabel · ${suffix++}';
    }
    options[optionLabel] = valueOf(item);
  }
  return options;
}
