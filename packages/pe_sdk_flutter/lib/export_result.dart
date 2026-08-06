/// Represents data exported with Photo Editor SDK. Contains a exported photo file.

class ExportResult {
  String photoSource;

  ExportResult(
      {required this.photoSource});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ExportResult &&
              runtimeType == other.runtimeType &&
              photoSource == other.photoSource;


  @override
  int get hashCode => photoSource.hashCode;

  @override
  String toString() {
    return 'ExportResult{photoSource: $photoSource}';
  }
}