---
name: app-store-review
description: Evaluates code against Apple's App Store Review Guidelines. Use this skill when reviewing iOS, macOS, tvOS, watchOS, or visionOS app code (Swift, Objective-C, React Native, or Expo) to identify potential App Store rejection issues before submission. Triggers on tasks involving app review preparation, compliance checking, or App Store submission readiness.
license: MIT
metadata:
  author: safaiyeh
  version: "1.1.0"
---

# App Store Review Guidelines Checker

Comprehensive guide for evaluating iOS, macOS, tvOS, watchOS, and visionOS app code against Apple's App Store Review Guidelines. This skill covers EVERY guideline point to identify potential rejection issues before submission.

**Supports:** Swift, Objective-C, React Native, and Expo apps

**Guidelines current through:** Apple's June 8, 2026 App Review Guidelines update.

## When to Apply

Use this skill when:
- Preparing an app for App Store submission
- Reviewing code for compliance issues
- Implementing features that may trigger review concerns
- Auditing existing apps for guideline violations
- Building features involving payments, user data, or sensitive content

## Guideline Sections

Read individual rule files for detailed explanations, checklists, and code examples:

| Section | File | Key Topics |
|---------|------|------------|
| **1. Safety** | [rules/1-safety.md](rules/1-safety.md) | Objectionable content, UGC moderation, Kids Category, physical harm, data security |
| **2. Performance** | [rules/2-performance.md](rules/2-performance.md) | App completeness, metadata accuracy, hardware compatibility, software requirements |
| **3. Business** | [rules/3-business.md](rules/3-business.md) | In-app purchase, subscriptions, cryptocurrencies, other business models |
| **4. Design** | [rules/4-design.md](rules/4-design.md) | Copycats, minimum functionality, spam, extensions, Apple services, login |
| **5. Legal** | [rules/5-legal.md](rules/5-legal.md) | Privacy, data collection, intellectual property, gambling, VPN, MDM, developer code of conduct |

## Risk Levels by Category

| Risk Level | Category | Section | Common Rejection Reasons |
|------------|----------|---------|--------------------------|
| CRITICAL | Privacy & Data | 5.1 | Missing privacy policy, unauthorized data collection |
| CRITICAL | Payments | 3.1 | Bypassing in-app purchase, unclear pricing |
| HIGH | Safety | 1.x | Objectionable content, inadequate UGC moderation |
| HIGH | Performance | 2.x | Crashes, incomplete features, deprecated APIs |
| MEDIUM | Design | 4.x | Copycat apps, minimum functionality issues |
| MEDIUM | Legal | 5.x | IP violations, gambling without license |

---

## Quick Reference: High-Risk Rejection Patterns

### Critical Issues (Immediate Rejection)

**Swift:**
```swift
// 🔴 Private API usage
let selector = NSSelectorFromString("_privateMethod")

// 🔴 Hardcoded secrets
let apiKey = "sk_live_xxxxx"

// 🔴 External payment for digital goods
func purchaseDigitalContent() {
    openStripeCheckout() // Use StoreKit instead
}
```

**React Native / Expo:**
```typescript
// 🔴 Hardcoded secrets in JS bundle
const API_KEY = 'sk_live_xxxxx'; // REJECTION

// 🔴 External payment for digital goods
Linking.openURL('https://stripe.com/checkout'); // Use react-native-iap

// 🔴 Dynamic code execution
eval(downloadedCode); // REJECTION

// 🔴 Major feature changes via CodePush/expo-updates
// OTA updates for bug fixes only, not new features!
```

### High-Risk Issues

**Swift:**
```swift
// 🟡 Missing ATT when using ad SDKs
import FacebookAds // Without ATTrackingManager

// 🟡 Account creation without deletion
func createAccount() { } // But no deleteAccount()
```

**React Native / Expo:**
```typescript
// 🟡 Missing ATT (use expo-tracking-transparency)
import analytics from '@react-native-firebase/analytics';
analytics().logEvent('event'); // Without ATT prompt = REJECTION

// 🟡 Account deletion via website only
Linking.openURL('https://example.com/delete'); // Must be in-app!

// 🟡 Social login without a privacy-preserving alternative (4.8)
<GoogleSigninButton /> // Also offer a login meeting 4.8 criteria
                       // (Sign in with Apple is the simplest option)

// 🟡 Custom review prompts (5.6.1)
showCustomAlert('Rate us 5 stars!'); // Use StoreReview.requestReview()
```

### Medium-Risk Issues

```typescript
// 🟠 Vague purpose strings in Info.plist
"This app needs camera access" // Be specific!

// 🟠 WebView-only app (insufficient native functionality)
const App = () => <WebView source={{ uri: 'https://site.com' }} />;

// 🟠 References to Android in iOS app
const text = "Also available on Android"; // REJECTION

// 🟠 console.log in production
console.log('debug'); // Remove or wrap in __DEV__
```

---

## Pre-Submission Checklist

### Privacy (Section 5.1)
- [ ] Privacy policy link in App Store Connect
- [ ] Privacy policy link accessible within app
- [ ] All purpose strings are specific and accurate
- [ ] App Privacy details completed in App Store Connect
- [ ] ATT implemented if tracking users
- [ ] Account deletion available if accounts exist
- [ ] Data minimization - only requesting necessary permissions
- [ ] User consent obtained before data collection

### Payments (Section 3.1)
- [ ] StoreKit used for all digital purchases
- [ ] Restore purchases implemented
- [ ] Subscription terms clearly displayed
- [ ] Loot box odds disclosed if applicable
- [ ] No external payment for digital goods (unless entitled)
- [ ] Credits/currencies don't expire

### Safety (Section 1.x)
- [ ] No objectionable content
- [ ] UGC moderation implemented (filter, report, block, contact)
- [ ] UGC violations can be removed quickly and backed by a remediation plan
- [ ] Kids and teens receive age-appropriate experiences inside the app
- [ ] Parental gates for Kids Category apps
- [ ] No false information or prank features
- [ ] Medical disclaimers if applicable
- [ ] No substance promotion

### Performance (Section 2.x)
- [ ] No crashes or bugs
- [ ] All features complete and functional
- [ ] No placeholder content
- [ ] IPv6 tested and functional
- [ ] Demo account provided if needed
- [ ] Using only public APIs
- [ ] No deprecated APIs
- [ ] Proper background mode usage

### Design (Section 4.x)
- [ ] Sufficient native functionality (not just web wrapper)
- [ ] No copycat concerns
- [ ] Original app name and branding
- [ ] No duplicate Bundle ID spam or low-effort saturated-category clones
- [ ] Live Activities, push notifications, and Game Center are not used for spam, phishing, or unsolicited messages
- [ ] Extensions comply with guidelines
- [ ] Login alternatives if using social login
- [ ] Not monetizing built-in capabilities

### Legal (Section 5.x)
- [ ] No unlicensed third-party content
- [ ] Proper Apple trademark usage
- [ ] Gambling license if applicable (with real location-based geo-restriction)
- [ ] VPN uses NEVPNManager API
- [ ] COPPA/GDPR compliance for kids
- [ ] Review prompts use the system API only (no custom prompts)
- [ ] No review, chart, search, or referral manipulation (5.6)

---

## References

- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
- [June 8, 2026 App Review Guidelines update](https://developer.apple.com/news/?id=a233fmpw)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [App Store Connect Help](https://developer.apple.com/help/app-store-connect/)
- [Apple Developer Documentation](https://developer.apple.com/documentation/)
