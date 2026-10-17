import '../../../core/config/app_config.dart';

int toIntSafe(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

double? toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  return double.tryParse(v.toString());
}

// The API returns media as relative paths (e.g. `/public/uploads/x.jpg`),
// not absolute URLs — mirrors erp/desktop's LazyImage.tsx `resolveMediaUrl`
// and this app's own media_library_item.dart `_toAbsUrl`. Without this,
// Image.network gets a non-fetchable relative path and silently fails.
String _resolveMediaUrl(String url) {
  if (url.isEmpty) return url;
  if (url.startsWith('http') || url.startsWith('data:')) return url;
  return '${AppConfig.apiBase}${url.startsWith('/') ? '' : '/'}$url';
}

/// Mirrors erp/desktop's `stay_categories` rows (DbCategory in CreateStays.tsx).
class StayCategory {
  final int id;
  final String name;
  final String? icon;
  const StayCategory({required this.id, required this.name, this.icon});

  factory StayCategory.fromJson(Map<String, dynamic> json) => StayCategory(
        id: toIntSafe(json['id']),
        name: (json['name'] ?? '').toString(),
        icon: json['icon']?.toString(),
      );
}

/// Mirrors erp/desktop's `amenities` rows (DbAmenity in CreateStays.tsx).
class StayAmenity {
  final int id;
  final String key;
  final String label;
  final String icon;
  const StayAmenity({required this.id, required this.key, required this.label, required this.icon});

  factory StayAmenity.fromJson(Map<String, dynamic> json) => StayAmenity(
        id: toIntSafe(json['id']),
        key: (json['key'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        icon: (json['icon'] ?? '').toString(),
      );
}

/// One `stay_media` row — matches desktop's `DbMedia` / `SelectedMedia`.
class StayMedia {
  final String url;
  final String type; // 'image' | 'video'
  final String? name;
  final int position;
  const StayMedia({required this.url, this.type = 'image', this.name, this.position = 0});

  factory StayMedia.fromJson(Map<String, dynamic> json) => StayMedia(
        url: _resolveMediaUrl((json['url'] ?? '').toString()),
        type: (json['type'] ?? 'image').toString(),
        name: json['name']?.toString(),
        position: toIntSafe(json['position']),
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'type': type,
        if (name != null) 'name': name,
        'position': position,
      };
}

/// A `stays` row — mirrors erp/desktop's `DbStay` (StaysList.tsx) /
/// `StayInitialData` (CreateStays.tsx). Backend is the dedicated
/// `cloud/src/module/stays` controller (plain REST, not OData) — always
/// scoped to the calling user, so there's no `workplace_id` filtering here.
class Stay {
  final int id;
  final String title;
  final String? description;
  final String? propertyType;
  final int? categoryId;
  final StayCategory? category;
  final String? address;
  final String? city;
  final String? country;
  final int maxGuests;
  final int bedroomCount;
  final int bedCount;
  final double bathroomCount;
  final double? pricePerNight;
  final double cleaningFee;
  final String status; // 'draft' | 'active' | 'inactive'
  final List<int> amenityIds;
  final List<StayMedia> medias;
  final double? avgRating;
  final int reviewCount;

  const Stay({
    required this.id,
    required this.title,
    this.description,
    this.propertyType,
    this.categoryId,
    this.category,
    this.address,
    this.city,
    this.country,
    this.maxGuests = 2,
    this.bedroomCount = 1,
    this.bedCount = 1,
    this.bathroomCount = 1,
    this.pricePerNight,
    this.cleaningFee = 0,
    this.status = 'draft',
    this.amenityIds = const [],
    this.medias = const [],
    this.avgRating,
    this.reviewCount = 0,
  });

  String? get coverUrl => medias.isEmpty ? null : medias.first.url;

  factory Stay.fromJson(Map<String, dynamic> json) {
    final categoryJson = json['category'];
    final amenitiesRaw = (json['amenities'] as List?) ?? const [];
    final mediasRaw = (json['medias'] as List?) ?? const [];
    final reviewsRaw = (json['reviews'] as List?) ?? const [];

    final ratings = reviewsRaw.map((r) => toDoubleOrNull((r as Map)['rating']) ?? 0).toList();
    final avgRating = ratings.isEmpty ? null : ratings.reduce((a, b) => a + b) / ratings.length;

    final medias = mediasRaw.map((m) => StayMedia.fromJson((m as Map).cast<String, dynamic>())).toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    return Stay(
      id: toIntSafe(json['id']),
      title: (json['title'] ?? '').toString(),
      description: json['description']?.toString(),
      propertyType: json['property_type']?.toString(),
      categoryId: json['category_id'] != null
          ? toIntSafe(json['category_id'])
          : (categoryJson is Map ? toIntSafe(categoryJson['id']) : null),
      category: categoryJson is Map ? StayCategory.fromJson(categoryJson.cast<String, dynamic>()) : null,
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      country: json['country']?.toString(),
      maxGuests: json['max_guests'] != null ? toIntSafe(json['max_guests']) : 2,
      bedroomCount: json['bedroom_count'] != null ? toIntSafe(json['bedroom_count']) : 1,
      bedCount: json['bed_count'] != null ? toIntSafe(json['bed_count']) : 1,
      bathroomCount: toDoubleOrNull(json['bathroom_count']) ?? 1,
      pricePerNight: toDoubleOrNull(json['price_per_night']),
      cleaningFee: toDoubleOrNull(json['cleaning_fee']) ?? 0,
      status: (json['status'] ?? 'draft').toString(),
      amenityIds: amenitiesRaw
          .map((a) {
            final map = a as Map;
            final amenity = map['amenity'];
            return toIntSafe(map['amenity_id'] ?? (amenity is Map ? amenity['id'] : null));
          })
          .where((id) => id > 0)
          .toList(),
      medias: medias,
      avgRating: avgRating,
      reviewCount: reviewsRaw.length,
    );
  }
}
