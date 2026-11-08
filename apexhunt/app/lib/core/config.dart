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
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
  static bool get hasSupportEmail => supportEmail.isNotEmpty;

  /// RevenueCat entitlement + product identifiers (must match Play Console + RevenueCat).
  static const proEntitlement = String.fromEnvironment('RC_ENTITLEMENT', defaultValue: 'pro');
  static const creditProductIds = ['apex_credits_5', 'apex_credits_10', 'apex_credits_25'];

  static bool get hasGateway => gatewayUrl.isNotEmpty;
  static bool get hasAuth => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get hasManagedAi => hasGateway && hasAuth;
  static bool get hasBilling => revenueCatAndroidKey.isNotEmpty;

  static String get privacyUrl => hasGateway ? '$gatewayUrl/privacy' : 'https://example.com/privacy';
  static String get termsUrl => hasGateway ? '$gatewayUrl/terms' : 'https://example.com/terms';
  static String get deleteAccountUrl => hasGateway ? '$gatewayUrl/delete-account' : 'https://example.com/delete-account';
}
