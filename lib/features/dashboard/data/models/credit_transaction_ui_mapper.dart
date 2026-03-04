enum CreditTransactionUiType {
  usage,
  subscriptionCredit,
  extraPurchase,
  creditExpiration,
  bonus,
  referralBonus,
  unknown,
}

class CreditTransactionUiMapper {
  const CreditTransactionUiMapper._();

  static CreditTransactionUiType fromDbType(String rawType) {
    switch (rawType) {
      case 'usage':
        return CreditTransactionUiType.usage;
      case 'subscription_credit':
        return CreditTransactionUiType.subscriptionCredit;
      case 'extra_purchase':
        return CreditTransactionUiType.extraPurchase;
      case 'credit_expiration':
        return CreditTransactionUiType.creditExpiration;
      case 'bonus':
        return CreditTransactionUiType.bonus;
      case 'referral_bonus':
        return CreditTransactionUiType.referralBonus;
      default:
        return CreditTransactionUiType.unknown;
    }
  }

  static String typeLabelPtBr(
      CreditTransactionUiType type, String fallbackRaw) {
    switch (type) {
      case CreditTransactionUiType.usage:
        return 'Uso em edicao';
      case CreditTransactionUiType.subscriptionCredit:
        return 'Credito de assinatura';
      case CreditTransactionUiType.extraPurchase:
        return 'Compra extra de creditos';
      case CreditTransactionUiType.creditExpiration:
        return 'Expiracao de creditos';
      case CreditTransactionUiType.bonus:
        return 'Bonus de creditos';
      case CreditTransactionUiType.referralBonus:
        return 'Bonus por indicacao';
      case CreditTransactionUiType.unknown:
        return fallbackRaw;
    }
  }

  static String? descriptionPtBr(String? rawDescription) {
    final trimmed = rawDescription?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final normalized = trimmed.toLowerCase();
    if (normalized == 'usage') {
      return 'Uso em edicao';
    }
    if (normalized.startsWith('expired unused credits')) {
      return 'Creditos expirados nao utilizados';
    }
    return trimmed;
  }
}
