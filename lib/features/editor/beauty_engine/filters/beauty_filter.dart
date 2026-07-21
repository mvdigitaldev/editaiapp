import '../models/filter_context.dart';

/// Filtro de beauty composável no pipeline.
abstract class BeautyFilter {
  String get id;

  void apply(FilterContext context);
}
