/// Advisor domain model — mirrors backend AdvisorPublicResponse
/// (see backend/app/schemas/user.py).
class AdvisorAddress {
  final String? line1;
  final String? line2;
  final String? city;
  final String? state;
  final String? pincode;

  const AdvisorAddress({
    this.line1,
    this.line2,
    this.city,
    this.state,
    this.pincode,
  });

  factory AdvisorAddress.fromJson(Map<String, dynamic> json) {
    return AdvisorAddress(
      line1: json['line1'] as String?,
      line2: json['line2'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      pincode: json['pincode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (line1 != null) 'line1': line1,
        if (line2 != null) 'line2': line2,
        if (city != null) 'city': city,
        if (state != null) 'state': state,
        if (pincode != null) 'pincode': pincode,
      };

  String get displayLine {
    final parts = [city, state, pincode].where((p) => p != null && p.isNotEmpty);
    return parts.join(', ');
  }
}

/// GST verification lifecycle — mirrors User.gst_verification_status.
enum GstVerificationStatus { unverified, pending, verified, failed }

GstVerificationStatus gstStatusFromString(String? value) {
  switch (value) {
    case 'pending':
      return GstVerificationStatus.pending;
    case 'verified':
      return GstVerificationStatus.verified;
    case 'failed':
      return GstVerificationStatus.failed;
    default:
      return GstVerificationStatus.unverified;
  }
}

class Advisor {
  final String id;
  final String name;
  final String email;
  final String? phoneNumberMasked;
  final String? profileImageUrl;
  final AdvisorAddress? address;
  final String? panMasked;

  /// AMFI ARN — used for mutual fund execution/distribution.
  final String? arnNumber;
  final bool arnVerified;

  /// SEBI RIA registration number — used for fee-only advice.
  /// `inaNumber` is the same value as `sebiRegistrationNumber`, surfaced
  /// under its SEBI-facing name for UI clarity.
  final String? sebiRegistrationNumber;
  String? get inaNumber => sebiRegistrationNumber;

  final String? gstNumber;
  final bool gstVerified;
  final GstVerificationStatus gstVerificationStatus;

  final double? consultationFeeMonthly;
  final String? bio;
  final List<String> specializations;
  final int? experienceYears;
  final double rating;
  final String? charges;

  const Advisor({
    required this.id,
    required this.name,
    required this.email,
    this.phoneNumberMasked,
    this.profileImageUrl,
    this.address,
    this.panMasked,
    this.arnNumber,
    this.arnVerified = false,
    this.sebiRegistrationNumber,
    this.gstNumber,
    this.gstVerified = false,
    this.gstVerificationStatus = GstVerificationStatus.unverified,
    this.consultationFeeMonthly,
    this.bio,
    this.specializations = const [],
    this.experienceYears,
    this.rating = 5.0,
    this.charges,
  });

  bool get hasIna => sebiRegistrationNumber != null && sebiRegistrationNumber!.isNotEmpty;
  bool get hasConsultationFee => consultationFeeMonthly != null && consultationFeeMonthly! > 0;

  factory Advisor.fromJson(Map<String, dynamic> json) {
    return Advisor(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Advisor',
      email: json['email'] as String? ?? '',
      phoneNumberMasked: json['phone_number'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      address: json['address'] != null
          ? AdvisorAddress.fromJson(json['address'] as Map<String, dynamic>)
          : null,
      panMasked: json['pan_masked'] as String?,
      arnNumber: json['arn_number'] as String?,
      arnVerified: json['arn_verified'] as bool? ?? false,
      sebiRegistrationNumber: (json['ina_number'] ?? json['sebi_registration_number']) as String?,
      gstNumber: json['gst_number'] as String?,
      gstVerified: json['gst_verified'] as bool? ?? false,
      gstVerificationStatus: gstStatusFromString(json['gst_verification_status'] as String?),
      consultationFeeMonthly: (json['consultation_fee_monthly'] as num?)?.toDouble(),
      bio: json['bio'] as String?,
      specializations: (json['specializations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      experienceYears: json['experience_years'] as int?,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      charges: json['charges'] as String?,
    );
  }
}
