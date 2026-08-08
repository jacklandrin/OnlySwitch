---
name: business
description: App Store Review Guidelines Section 3 - Business (in-app purchase, subscriptions, cryptocurrencies, other business models)
---

# 3. BUSINESS

**Section intro (enforcement-relevant):**
- [ ] If your business model isn't obvious, explain it in metadata and App Review notes — unclear monetization delays review and may trigger rejection
- [ ] No "rip-off" pricing: Apple rejects expensive apps that try to cheat users with irrationally high prices
- [ ] Manipulating reviews, inflating chart rankings with paid/incentivized/filtered/fake feedback, or hiring third-party services to do so can lead to expulsion from the Apple Developer Program

## 3.1 Payments

### 3.1.1 In-App Purchase

**MUST use In-App Purchase for unlocking:**
- [ ] Features or functionality
- [ ] Subscriptions
- [ ] In-game currencies
- [ ] Game levels
- [ ] Access to premium content
- [ ] Unlocking full version

**Apps may NOT use own mechanisms such as:**
- [ ] License keys
- [ ] Augmented reality markers
- [ ] QR codes
- [ ] Cryptocurrencies and cryptocurrency wallets

**Swift implementation:**
```swift
// REQUIRED: Use StoreKit for digital goods
import StoreKit

// Good: Using In-App Purchase
func purchasePremiumFeature() async throws {
    let product = try await Product.products(for: ["com.app.premium"]).first!
    let result = try await product.purchase()
    // Handle purchase result
}

// BAD: External payment for digital goods
func purchasePremiumFeature() {
    openStripeCheckout() // REJECTION for digital content
    openPayPalCheckout() // REJECTION for digital content
}
```

**React Native implementation (RevenueCat — recommended):**
```typescript
// RECOMMENDED: RevenueCat (react-native-purchases) — wraps StoreKit, so it
// satisfies the IAP requirement while handling receipts, entitlements, and
// cross-platform subscription state for you.
// Expo: requires a development build (not Expo Go).
import Purchases from 'react-native-purchases';

// Configure once at app start
Purchases.configure({ apiKey: REVENUECAT_APPLE_API_KEY });

// ✅ GOOD: Purchase digital goods through StoreKit via RevenueCat
const purchasePremiumFeature = async () => {
  const offerings = await Purchases.getOfferings();
  const pkg = offerings.current?.availablePackages[0];
  if (!pkg) return;
  const { customerInfo } = await Purchases.purchasePackage(pkg);
  if (customerInfo.entitlements.active['premium']) {
    unlockPremium();
  }
};

// ❌ BAD: External payment for digital goods
const purchasePremiumFeatureBad = () => {
  // REJECTION for digital content!
  Linking.openURL('https://stripe.com/checkout');
  Linking.openURL('https://paypal.com/checkout');
};

// ✅ OK: External payment for physical goods
const purchasePhysicalProduct = () => {
  // Physical goods CAN use external payment
  Linking.openURL('https://yourstore.com/checkout');
};
```

Lower-level alternative: `react-native-iap` (you manage receipt validation, restore, and transaction lifecycle yourself — see Best Practices below).

**Tips and Credits:**
- [ ] Apps may use IAP currencies to enable "tipping" developers or content providers

**Credits and Currency:**
- [ ] Credits/in-game currencies purchased via IAP may NOT expire
- [ ] Must have restore mechanism for restorable purchases

**Gifting:**
- [ ] Apps may enable gifting of IAP-eligible items
- [ ] Gifts may only be refunded to original purchaser
- [ ] Gifts may NOT be exchanged

**Mac App Store Exception:**
- [ ] Mac apps may host plug-ins enabled with mechanisms other than App Store

**Loot Boxes:**
- [ ] Apps offering randomized virtual items MUST disclose odds BEFORE purchase

**Swift implementation:**
```swift
// REQUIRED: Loot box odds disclosure
struct LootBox {
    let items: [(item: Item, probability: Double)]

    func displayOdds() -> String {
        return items.map { "\($0.item.name): \($0.probability * 100)%" }
            .joined(separator: "\n")
    }
}

// Must show this to user BEFORE purchase
let oddsView = LootBoxOddsView(lootBox: currentLootBox)
```

**React Native implementation:**
```typescript
// REQUIRED: Loot box odds disclosure
interface LootBoxItem {
  name: string;
  rarity: 'common' | 'rare' | 'epic' | 'legendary';
  probability: number; // 0-1
}

const lootBoxItems: LootBoxItem[] = [
  { name: 'Common Sword', rarity: 'common', probability: 0.60 },
  { name: 'Rare Shield', rarity: 'rare', probability: 0.25 },
  { name: 'Epic Armor', rarity: 'epic', probability: 0.12 },
  { name: 'Legendary Crown', rarity: 'legendary', probability: 0.03 },
];

// REQUIRED: Show odds BEFORE purchase
const LootBoxOddsModal: React.FC = () => (
  <Modal visible={showOdds}>
    <Text style={styles.title}>Drop Rates</Text>
    {lootBoxItems.map((item) => (
      <View key={item.name} style={styles.row}>
        <Text>{item.name}</Text>
        <Text>{(item.probability * 100).toFixed(1)}%</Text>
      </View>
    ))}
    <Button title="Purchase" onPress={purchaseLootBox} />
  </Modal>
);

// Must display odds before allowing purchase
const handleLootBoxPurchase = () => {
  setShowOdds(true); // Show odds first!
};
```

**Digital Gift Cards:**
- [ ] Digital gift cards redeemable for digital goods/services can ONLY be sold using IAP
- [ ] Physical gift cards mailed to customers may use other payment methods

**Free Trial Periods (Non-Subscription):**
- [ ] Use Non-Consumable IAP at Price Tier 0
- [ ] Naming convention: "XX-day Trial"
- [ ] Must clearly identify: duration, content no longer accessible after trial, downstream charges
- [ ] Manage content access and trial duration using Receipts and DeviceCheck

**NFTs:**
- [ ] May use IAP for minting, listing, transferring NFT services
- [ ] May allow users to view their own NFTs
- [ ] NFT ownership may NOT unlock features/functionality
- [ ] May allow browsing others' NFT collections
- [ ] Outside US: No external purchase links for NFTs

### 3.1.1(a) Link to Other Purchase Methods

**General:**
- [ ] Entitlements allow a link to a website the developer owns or maintains responsibility for, to purchase digital content or services
- [ ] US storefront: NO entitlement required — apps may include buttons, external links, or other calls to action freely

**StoreKit External Purchase Link Entitlements:**
- [ ] Available in specific regions only (iOS/iPadOS App Store)
- [ ] May include link to developer website informing users of other ways to purchase digital goods or services
- [ ] Link may state where and how to purchase, and that items may be available for a comparatively lower price
- [ ] All other storefronts (except US, where the prohibition does not apply): apps AND their metadata may NOT include buttons, external links, or other calls to action that direct customers to purchasing mechanisms other than IAP

**Music Streaming Services Entitlements:**
- [ ] May include link (or buy button) to developer website informing users of other ways to purchase digital music content or services
- [ ] May invite users to provide email for the express purpose of sending a purchase link
- [ ] Link may inform users where and how to purchase, and the price of items
- [ ] Limited to specific storefronts; in all other storefronts, streaming music apps AND their metadata may NOT include buttons, external links, or other calls to action to non-IAP purchasing

**Fraud and Misconduct:**
Misleading marketing, scams, or fraud results in removal from App Store and potentially Developer Program.

### 3.1.2 Subscriptions

**Core Requirements:**
- [ ] Auto-renewable subscriptions allowed regardless of App Store category
- [ ] Must provide ongoing value to customer
- [ ] Minimum 7-day subscription period
- [ ] Must be available across all user's devices

### 3.1.2(a) Permissible Uses

**Examples of appropriate subscriptions:**
- [ ] New game levels
- [ ] Episodic content
- [ ] Multiplayer support
- [ ] Consistent, substantive updates
- [ ] Access to large/continually updated media content
- [ ] Software as a service (SAAS)
- [ ] Cloud support

**Additional rules:**
- [ ] Subscriptions may be offered alongside à la carte offerings
- [ ] Gaming subscription services may share subscription across third-party apps
- [ ] Games must be downloaded from App Store
- [ ] Must avoid duplicate payment by subscriber
- [ ] Must not disadvantage non-subscriber customers
- [ ] Must work on all user's devices
- [ ] User should get value without additional tasks (posting to social media, uploading contacts, etc.)
- [ ] May include consumable credits, gems, currencies
- [ ] May offer subscriptions that include access to discounted consumable goods (e.g. platinum membership exposing gem-packs at reduced price)
- [ ] When changing to subscription model, don't remove functionality existing users paid for
- [ ] May offer free trial periods

**Scams:**
Apps attempting to scam users or use bait-and-switch tactics will be REMOVED.

**Cellular Carrier Bundling:**
- [ ] Carrier apps may bundle auto-renewable music and video subscriptions with NEW cellular data plans, with prior Apple approval
- [ ] Other subscription types may be bundled with new plans only if the carrier app also supports IAP for users (prior Apple approval required)
- [ ] Cannot include access to or discounts on consumable items
- [ ] Must terminate coincident with cellular data plan

### 3.1.2(b) Upgrades and Downgrades

- [ ] Users should have seamless upgrade/downgrade experience
- [ ] Users should NOT be able to inadvertently subscribe to multiple variations of same thing

### 3.1.2(c) Subscription Information

**Before asking customer to subscribe, clearly describe:**
- [ ] What user will get for the price
- [ ] How many issues per month? How much cloud storage? What access?
- [ ] Comply with Schedule 2 of Developer Program License Agreement

```swift
// REQUIRED: Clear subscription information
struct SubscriptionInfo {
    let price: String
    let period: String
    let features: [String]
    let renewalTerms: String
    let cancellationInstructions: String

    var displayText: String {
        """
        \(price) per \(period)

        Includes:
        \(features.map { "• \($0)" }.joined(separator: "\n"))

        \(renewalTerms)

        To cancel: \(cancellationInstructions)
        """
    }
}
```

### 3.1.3 Other Purchase Methods

The following may use purchase methods other than IAP. Important preamble rules:
- [ ] Apps in this section cannot, within the app, encourage users to use a purchasing method other than IAP — EXCEPT apps on the US storefront and as set forth in 3.1.1(a) and 3.1.3(a)
- [ ] Developers CAN send communications outside the app to their user base about non-IAP purchasing methods

#### 3.1.3(a) "Reader" Apps
- [ ] May allow access to previously purchased content (magazines, newspapers, books, audio, music, video)
- [ ] May offer free tier account creation
- [ ] May offer account management for existing customers
- [ ] May apply for External Link Account Entitlement: an informational link to a website the developer owns or maintains responsibility for, to create or manage an account
- [ ] US storefront: entitlement NOT required for buttons, external links, or other calls to action

#### 3.1.3(b) Multiplatform Services
- [ ] May allow access to content acquired on other platforms/web
- [ ] Includes consumable items in multi-platform games
- [ ] Must also be available as IAP within the app

#### 3.1.3(c) Enterprise Services
- [ ] Apps sold directly to organizations for employees/students
- [ ] Consumer/single user/family sales MUST use IAP

#### 3.1.3(d) Person-to-Person Services
- [ ] Real-time services between TWO individuals (tutoring, medical consultations, real estate tours, fitness training)
- [ ] One-to-few and one-to-many MUST use IAP

#### 3.1.3(e) Goods and Services Outside of the App
- [ ] Physical goods or services consumed outside app MUST use payment methods other than IAP (Apple Pay, credit card)

#### 3.1.3(f) Free Stand-alone Apps
- [ ] Free companions to paid web tools (VoIP, cloud storage, email, web hosting)
- [ ] No purchasing inside app
- [ ] No calls to action for purchase outside app

#### 3.1.3(g) Advertising Management Apps
- [ ] Apps for advertisers to manage campaigns across media types
- [ ] Don't display advertisements themselves
- [ ] Digital purchases for in-app content MUST use IAP

### 3.1.4 Hardware-Specific Content

- [ ] Features dependent on specific hardware may unlock without IAP
- [ ] Features working with optional physical products may unlock without IAP (if IAP option also available)
- [ ] May NOT require purchase of unrelated products
- [ ] May NOT require advertising/marketing activities to unlock

### 3.1.5 Cryptocurrencies

#### (i) Wallets
- [ ] May facilitate virtual currency storage
- [ ] Must be from developers enrolled as organization

#### (ii) Mining
- [ ] Apps may NOT mine on device
- [ ] Cloud-based mining is allowed

**Swift patterns to flag:**
```swift
// FLAG: On-device crypto mining
func mineBlock() { } // REJECTION
func calculateHash() { } // If for mining = REJECTION

// OK: Cloud-based mining reference
func checkCloudMiningStatus() { } // Allowed
```

**React Native patterns to flag:**
```typescript
// ❌ FLAG: On-device crypto mining
const mineBlock = () => { }; // REJECTION
const calculateHash = (data: string) => { }; // If for mining = REJECTION
import CryptoMiner from 'some-crypto-lib'; // REJECTION

// ❌ FLAG: Crypto rewards for tasks
const rewardCrypto = () => {
  // Cannot reward crypto for:
  // - Downloading other apps
  // - Social media posts
  // - Referrals
};

// ✅ OK: Cloud-based mining status
const checkCloudMiningStatus = async () => {
  const status = await api.get('/mining/status');
  return status;
};

// ✅ OK: Crypto wallet apps (must be organization account)
// Use established libraries like ethers.js for wallet functionality
import { ethers } from 'ethers';
```

#### (iii) Exchanges
- [ ] May facilitate transactions on approved exchange
- [ ] Only in countries with appropriate licensing/permissions

#### (iv) Initial Coin Offerings
- [ ] ICOs, futures trading, crypto-securities trading must come from:
  - Established banks
  - Securities firms
  - Futures commission merchants (FCM)
  - Other approved financial institutions
- [ ] Must comply with all applicable law

#### (v) Task Completion Restrictions
- [ ] May NOT offer cryptocurrency for completing tasks:
  - Downloading other apps
  - Encouraging others to download
  - Posting to social networks

---

## 3.2 Other Business Model Issues

### 3.2.1 Acceptable

#### (i) Self-Promotion
- [ ] May display own apps for purchase/promotion (if not merely a catalog)

#### (ii) Third-Party App Collections
- [ ] May display/recommend third-party apps for specific approved needs
- [ ] Must provide robust editorial content (not mere storefront)

#### (iii) Rental Content Expiration
- [ ] May disable access to rental content after rental period expires
- [ ] All other items/services may NOT expire

#### (iv) Wallet Passes
- [ ] May be used for: payments, offers, identification (movie tickets, coupons, VIP credentials)
- [ ] Other uses may result in rejection and credential revocation

#### (v) Insurance Apps
- [ ] Must be free
- [ ] Must be legally compliant in distributed regions
- [ ] Cannot use IAP

#### (vi) Approved Nonprofits
- [ ] Approved nonprofits may fundraise directly within their own apps or third-party apps
- [ ] Must offer Apple Pay support
- [ ] Must disclose fund usage
- [ ] Must abide by all laws
- [ ] Must ensure tax receipts available to donors
- [ ] Additional information must be provided to App Review upon request
- [ ] Nonprofit platforms must ensure all listed nonprofits are approved

#### (vii) Monetary Gifts
- [ ] May enable monetary gifts between individuals
- [ ] Must be completely optional
- [ ] 100% of funds must go to receiver
- [ ] Gifts connected to or associated at any point in time with receiving digital content or services MUST use IAP

#### (viii) Financial Services
- [ ] Trading, investing, money management apps must be from financial institution
- [ ] Must have necessary licensing/permissions

### 3.2.2 Unacceptable

#### (i) App Store-Like Interfaces
- [ ] Cannot create interface for displaying third-party apps, extensions, or plug-ins similar to the App Store or as a general-interest collection

#### (ii) Intentionally omitted

#### (iii) Ad Manipulation
- [ ] Cannot artificially increase ad impressions or click-throughs
- [ ] Apps predominantly for displaying ads will be REJECTED

#### (iv) Unauthorized Fundraising
- [ ] Cannot collect funds for charities unless approved nonprofit
- [ ] Charity apps must be free and collect funds outside app (Safari, SMS)

#### (v) Arbitrary User Restriction
- [ ] Cannot arbitrarily restrict users by location or carrier

#### (vi) Intentionally omitted

#### (vii) Artificial Status Manipulation
- [ ] Cannot artificially manipulate user visibility/status/rank on other services — UNLESS permitted by that service's Terms and Conditions

#### (viii) Derivatives Trading
- [ ] Binary options trading apps NOT permitted
- [ ] CFDs and other derivatives apps must be properly licensed in all jurisdictions where the service is available

#### (ix) Personal Loan Apps
**Must clearly disclose:**
- [ ] Equivalent maximum APR
- [ ] Payment due date
- [ ] May NOT charge APR higher than 36% (including costs/fees)
- [ ] May NOT require repayment in full in 60 days or less

#### (x) Forced Actions
**Apps must NOT force users to:**
- [ ] Rate the app
- [ ] Review the app
- [ ] Download other apps
- [ ] Other store-related actions

In order to access functionality, content, or use the app.

**Allowed:** Apps may otherwise incentivize users to take specific actions within apps (e.g. completing a level, watching an ad).

---

## React Native Packages Reference

| Guideline | Relevant Packages |
|-----------|------------------|
| In-App Purchase | `react-native-purchases` (RevenueCat, recommended), `react-native-iap` |
| Subscriptions | `react-native-purchases` + `react-native-purchases-ui` (paywalls), `react-native-iap` |
| Apple Pay | `@stripe/stripe-react-native` |
| Crypto Wallets | `ethers`, `web3` (organization accounts only) |

## React Native IAP Best Practices

**Recommended: RevenueCat (`react-native-purchases`).** It handles receipt validation, restore, entitlement state, and subscription lifecycle server-side, which removes most of the manual compliance surface below:

```typescript
import Purchases from 'react-native-purchases';

// 1. Configure once at app start (App.tsx)
Purchases.configure({ apiKey: REVENUECAT_APPLE_API_KEY });

// 2. Gate features on entitlements, not local flags
const isPremium = async () => {
  const info = await Purchases.getCustomerInfo();
  return info.entitlements.active['premium'] !== undefined;
};

// 3. REQUIRED by Apple: Restore purchases button
const RestorePurchasesButton = () => (
  <Button
    title="Restore Purchases"
    onPress={async () => {
      await Purchases.restorePurchases();
      Alert.alert('Restored', 'Your purchases have been restored.');
    }}
  />
);
```

**Lower-level alternative: `react-native-iap`** (API shown is v12/v13; v14+ renamed several methods, e.g. `getProducts` → `fetchProducts`):

```typescript
// Complete IAP setup for React Native
import * as IAP from 'react-native-iap';

const itemSkus = Platform.select({
  ios: ['com.app.premium', 'com.app.subscription_monthly'],
  android: ['premium', 'subscription_monthly'],
});

// 1. Initialize on app start
useEffect(() => {
  const init = async () => {
    try {
      await IAP.initConnection();
      // Get available products
      const products = await IAP.getProducts({ skus: itemSkus });
      setProducts(products);
    } catch (error) {
      console.error('IAP init failed:', error);
    }
  };

  // 2. Listen for purchase updates
  const purchaseListener = IAP.purchaseUpdatedListener(async (purchase) => {
    if (purchase.transactionReceipt) {
      // Validate on server
      await validatePurchase(purchase);
      // Deliver content
      await deliverContent(purchase.productId);
      // CRITICAL: Finish transaction
      await IAP.finishTransaction({ purchase, isConsumable: false });
    }
  });

  init();
  return () => {
    purchaseListener.remove();
    IAP.endConnection();
  };
}, []);

// 3. REQUIRED: Restore purchases button
const RestorePurchasesButton = () => (
  <Button
    title="Restore Purchases"
    onPress={async () => {
      const purchases = await IAP.getAvailablePurchases();
      for (const purchase of purchases) {
        await deliverContent(purchase.productId);
      }
      Alert.alert('Restored', 'Your purchases have been restored.');
    }}
  />
);
```

