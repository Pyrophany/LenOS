/// The Headspaces and Traits offered by the Headspace Manager's dropdowns.
///
/// PLACEHOLDER: these are meant to come from the LenOS documentation on Read
/// the Docs, which has not been written yet. Until then there are no preset
/// options, only Custom (which the Headspace Manager always adds).
/// When the docs exist, load the lists here and keep [defaults] as the
/// offline fallback.
class HeadspaceCatalog {
  const HeadspaceCatalog({required this.headspaces, required this.traits});

  final List<String> headspaces;
  final List<String> traits;

  static const defaults = HeadspaceCatalog(headspaces: [], traits: []);

  /// The current catalog. Will fetch from the docs once they are written.
  static Future<HeadspaceCatalog> load() async => defaults;
}
