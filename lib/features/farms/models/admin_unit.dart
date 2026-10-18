/// One unit in the downloaded location tree (county, sub-county, ward, ...).
class AdminUnit {
  const AdminUnit({required this.id, this.parentId, required this.level, required this.name});

  factory AdminUnit.fromRow(Map<String, Object?> r) => AdminUnit(
        id: r['unit_id'] as int,
        parentId: r['parent_id'] as int?,
        level: r['level'] as String? ?? '',
        name: r['name'] as String? ?? '',
      );

  final int id;
  final int? parentId;
  final String level;
  final String name;

  static const levelLabels = {
    'COUNTY': 'County',
    'SUB_COUNTY': 'Sub-county',
    'WARD': 'Ward',
    'LOCATION': 'Location',
    'SUB_LOCATION': 'Sub-location',
  };

  String get levelLabel => levelLabels[level] ?? 'Area';
}
