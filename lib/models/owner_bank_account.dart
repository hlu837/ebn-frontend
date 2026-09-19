/// A property owner's registered receiving bank account — either their
/// own masked management view (GET /api/owner-bank-accounts/me) or the
/// full unmasked entry a tenant sees on the payment screen
/// (GET /api/rental-agreements/:id/bank-accounts). Same wire shape
/// either way; only whether [accountNumber] is masked differs, and
/// that's decided server-side, not here.
class OwnerBankAccount {
  final String id;
  final String ownerId;
  final String bankId;
  final String bankName;
  final String? bankShortCode;
  final String accountName;
  final String accountNumber;
  final bool isDefault;

  const OwnerBankAccount({
    required this.id,
    required this.ownerId,
    required this.bankId,
    required this.bankName,
    this.bankShortCode,
    required this.accountName,
    required this.accountNumber,
    required this.isDefault,
  });

  factory OwnerBankAccount.fromJson(Map<String, dynamic> json) {
    return OwnerBankAccount(
      id: json['id'] as String,
      ownerId: json['ownerId'] as String? ?? '',
      bankId: json['bankId'] as String? ?? '',
      bankName: json['bankName'] as String? ?? '',
      bankShortCode: json['bankShortCode'] as String?,
      accountName: json['accountName'] as String? ?? '',
      accountNumber: json['accountNumber'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}

/// One bank the platform currently accepts transfers on — from
/// GET /api/owner-bank-accounts/banks, used to populate the "add
/// account" dropdown on the owner side.
class PlatformBank {
  final String id;
  final String name;
  final String? shortCode;

  const PlatformBank({required this.id, required this.name, this.shortCode});

  factory PlatformBank.fromJson(Map<String, dynamic> json) {
    return PlatformBank(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      shortCode: json['shortCode'] as String?,
    );
  }
}
