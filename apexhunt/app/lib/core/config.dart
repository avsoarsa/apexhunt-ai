/// Build-time configuration, injected with `--dart-define-from-file=env/prod.json`.
///
/// Every value is optional so the app still runs in development: without a
/// gateway/Supabase the app works in Bring-Your-Own-Key mode only, and without a
/// RevenueCat key purchases are hidden and Pro features are unlocked for testing.
class AppConfig {
  static const appName = 'ApexHunt AI';

  static const gatewayUrl = String.fromEnvironment('GATEWAY_URL');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const revenueCatAndroidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'sk.wedmist@gmail.com');
  static bool get hasSupportEmail => supportEmail.isNotEmpty;

  /// RevenueCat entitlement + product identifiers (must match Play Console + RevenueCat).
  static const proEntitlement = String.fromEnvironment('RC_ENTITLEMENT', defaultValue: 'pro');
  static const creditProductIds = ['apex_credits_5', 'apex_credits_10', 'apex_credits_25'];

  static bool get hasGateway => gatewayUrl.isNotEmpty;
  static bool get hasAuth => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get hasManagedAi => hasGateway && hasAuth;
  static bool get hasBilling => revenueCatAndroidKey.isNotEmpty;

  /// Public legal pages (Play Console requires a privacy policy + account-deletion URL).
  /// Override with --dart-define once you have your own domain or the gateway is live.
  static const _legalBase = 'https://github.com/avsoarsa/apexhunt-ai/blob/main/apexhunt/docs/legal';
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL', defaultValue: '$_legalBase/privacy.md');
  static const termsUrl = String.fromEnvironment('TERMS_URL', defaultValue: '$_legalBase/terms.md');
  static const deleteAccountUrl = String.fromEnvironment('DELETE_ACCOUNT_URL', defaultValue: '$_legalBase/delete-account.md');
}
