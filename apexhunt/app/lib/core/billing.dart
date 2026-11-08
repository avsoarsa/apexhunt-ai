import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'config.dart';

class CreditPack {
  CreditPack({required this.id, required this.usd, required this.priceString, this.product});
  final String id;
  final double usd;
  final String priceString;
  final StoreProduct? product;
}

class BillingSnapshot {
  BillingSnapshot({this.isPro = false, this.monthly, this.annual, this.credits = const [], this.ready = false});
  final bool isPro, ready;
  final Package? monthly, annual;
  final List<CreditPack> credits;
}

class PurchaseCancelled implements Exception {}

/// Google Play Billing through RevenueCat: the $3.99/mo Pro subscription and
/// consumable Apex credit packs. RevenueCat forwards events to the gateway webhook.
class BillingService {
  bool _configured = false;
  bool get enabled => AppConfig.hasBilling && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!enabled || _configured) return;
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
    await Purchases.configure(PurchasesConfiguration(AppConfig.revenueCatAndroidKey));
    _configured = true;
  }

  /// Links purchases to the signed-in account so the gateway can credit the right wallet.
  Future<void> identify(String? userId) async {
    if (!_configured) return;
    try {
      if (userId == null) {
        if (!(await Purchases.isAnonymous)) await Purchases.logOut();
      } else {
        await Purchases.logIn(userId);
      }
    } catch (e) {
      debugPrint('RevenueCat identify failed: $e');
    }
  }

  bool _proFrom(CustomerInfo info) => info.entitlements.active.containsKey(AppConfig.proEntitlement);

  Future<BillingSnapshot> load() async {
    if (!_configured) return BillingSnapshot(ready: false);
    try {
      final info = await Purchases.getCustomerInfo();
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      final products = await Purchases.getProducts(AppConfig.creditProductIds, productCategory: ProductCategory.nonSubscription);
      final packs = <CreditPack>[];
      for (final id in AppConfig.creditProductIds) {
        final p = products.where((p) => p.identifier == id).firstOrNull;
        if (p == null) continue;
        packs.add(CreditPack(id: id, usd: double.tryParse(id.split('_').last) ?? 0, priceString: p.priceString, product: p));
      }
      return BillingSnapshot(isPro: _proFrom(info), monthly: current?.monthly, annual: current?.annual, credits: packs, ready: true);
    } catch (e) {
      debugPrint('RevenueCat load failed: $e');
      return BillingSnapshot(ready: false);
    }
  }

  Future<bool> buyPackage(Package package) async {
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return _proFrom(result.customerInfo);
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) throw PurchaseCancelled();
      rethrow;
    }
  }

  Future<void> buyCredits(CreditPack pack) async {
    if (pack.product == null) throw StateError('Product unavailable');
    try {
      await Purchases.purchase(PurchaseParams.storeProduct(pack.product!));
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) throw PurchaseCancelled();
      rethrow;
    }
  }

  Future<bool> restore() async {
    if (!_configured) return false;
    return _proFrom(await Purchases.restorePurchases());
  }
}
