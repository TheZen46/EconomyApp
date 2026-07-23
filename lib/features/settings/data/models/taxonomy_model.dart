// ignore_for_file: deprecated_member_use, deprecated_member_use_from_same_package, unused_local_variable, unnecessary_underscores, invalid_annotation_target, unused_element, non_constant_identifier_names, use_build_context_synchronously
import 'package:hive/hive.dart';
import '../../../../core/constants/taxonomy_constants.dart';

part 'taxonomy_model.g.dart';

@HiveType(typeId: 4)
class TaxonomyItemModel {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final String defaultNecessity;

  TaxonomyItemModel({required this.name, required this.defaultNecessity});

  factory TaxonomyItemModel.fromEntity(TaxonomyItem item) {
    return TaxonomyItemModel(name: item.name, defaultNecessity: item.defaultNecessity);
  }

  TaxonomyItem toEntity() {
    return TaxonomyItem(name, defaultNecessity);
  }
}

@HiveType(typeId: 5)
class TaxonomyConfigModel {
  @HiveField(0)
  final Map<String, Map<String, List<TaxonomyItemModel>>> hierarchy;

  TaxonomyConfigModel({required this.hierarchy});
}
