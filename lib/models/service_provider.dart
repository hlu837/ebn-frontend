/// Mirrors the JSON shape returned by `/api/service-providers/*` on the
/// real backend (`backend/src/models/serviceProviders.js` → `toPublic`).
/// Phase 3 of the maintenance-request workflow: the admin-managed
/// directory of local service professionals a tenant can browse — either
/// after an owner rejects a maintenance request, or independently.
library;

enum ServiceProviderCategory { electrician, plumber, carpenter, mechanic, applianceTechnician, other }

extension ServiceProviderCategoryX on ServiceProviderCategory {
  static ServiceProviderCategory fromWire(String? value) {
    switch (value) {
      case 'electrician':
        return ServiceProviderCategory.electrician;
      case 'plumber':
        return ServiceProviderCategory.plumber;
      case 'carpenter':
        return ServiceProviderCategory.carpenter;
      case 'mechanic':
        return ServiceProviderCategory.mechanic;
      case 'appliance_technician':
        return ServiceProviderCategory.applianceTechnician;
      case 'other':
      default:
        return ServiceProviderCategory.other;
    }
  }

  String get wireValue {
    switch (this) {
      case ServiceProviderCategory.electrician:
        return 'electrician';
      case ServiceProviderCategory.plumber:
        return 'plumber';
      case ServiceProviderCategory.carpenter:
        return 'carpenter';
      case ServiceProviderCategory.mechanic:
        return 'mechanic';
      case ServiceProviderCategory.applianceTechnician:
        return 'appliance_technician';
      case ServiceProviderCategory.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case ServiceProviderCategory.electrician:
        return 'Electrician';
      case ServiceProviderCategory.plumber:
        return 'Plumber';
      case ServiceProviderCategory.carpenter:
        return 'Carpenter';
      case ServiceProviderCategory.mechanic:
        return 'Mechanic';
      case ServiceProviderCategory.applianceTechnician:
        return 'Appliance Technician';
      case ServiceProviderCategory.other:
        return 'Other';
    }
  }
}

class ServiceProvider {
  final String id;
  final String name;
  final ServiceProviderCategory category;
  final String phone;
  final String city;
  final double? latitude;
  final double? longitude;
  final int rateCents;
  final double? rating;
  final String? photoUrl;
  final bool isActive;
  final String? userId;

  const ServiceProvider({
    required this.id,
    required this.name,
    required this.category,
    required this.phone,
    required this.city,
    this.latitude,
    this.longitude,
    this.rateCents = 0,
    this.rating,
    this.photoUrl,
    this.isActive = true,
    this.userId,
  });

  double get rateBirr => rateCents / 100;

  factory ServiceProvider.fromJson(Map<String, dynamic> json) {
    return ServiceProvider(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      category: ServiceProviderCategoryX.fromWire(json['category'] as String?),
      phone: json['phone'] as String? ?? '',
      city: json['city'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      rateCents: (json['rateCents'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble(),
      photoUrl: json['photoUrl'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      userId: json['userId'] as String?,
    );
  }
}
