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
