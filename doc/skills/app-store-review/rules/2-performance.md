---
name: performance
description: App Store Review Guidelines Section 2 - Performance (app completeness, metadata, hardware compatibility, software requirements)
---

# 2. PERFORMANCE

## 2.1 App Completeness

### 2.1(a) Final Version Requirements

**ALL submissions (including apps made available for pre-order) must be final versions with:**
- [ ] All necessary metadata complete
- [ ] Fully functional URLs (no broken links)
- [ ] No placeholder text ("Lorem ipsum", "Coming soon", "TBD")
- [ ] No empty websites
- [ ] No temporary content
- [ ] Tested on-device for bugs and stability
- [ ] Incomplete app bundles and binaries that crash or exhibit obvious technical problems will be REJECTED

**Swift code patterns to flag:**
```swift
// FLAG: Placeholder content
"Lorem ipsum"
"Coming soon"
"TBD"
"TODO"
"FIXME" // In user-facing strings
"placeholder"
"test_image"
"sample_data"

// FLAG: Debug code in production
#if DEBUG
    // Ensure debug-only code doesn't affect production
#endif

print("Debug:") // Remove debug prints
NSLog("Test") // Remove test logs
```

**React Native code patterns to flag:**
```typescript
// FLAG: Placeholder content in components
<Text>Lorem ipsum dolor sit amet</Text> // REJECTION
<Text>Coming soon!</Text> // REJECTION
<Text>TBD</Text> // REJECTION
<Image source={require('./placeholder.png')} /> // REJECTION

// FLAG: Placeholder in localization files (en.json, etc.)
{
  "welcome": "Lorem ipsum", // REJECTION
  "feature": "Coming soon" // REJECTION
}

// FLAG: Debug code in production
console.log('Debug:', data); // Remove before submission
console.warn('Test warning'); // Remove before submission
__DEV__ && console.log('Dev only'); // OK - but verify

// FLAG: Check for leftover TODO/FIXME in user-facing code
// TODO: implement this feature // Not in user-facing strings!

// ✅ GOOD: Use __DEV__ for debug-only code
if (__DEV__) {
  // This won't run in production builds
  console.log('Debug info');
}
```

**Demo Account Requirements:**
- [ ] If app includes login, provide demo account credentials
- [ ] Enable backend services before submission
- [ ] If demo account not possible due to legal/security, may include built-in demo mode (with prior Apple approval)
- [ ] Demo mode must exhibit app's full features and functionality

### 2.1(b) In-App Purchase Requirements

- [ ] All in-app purchases must be complete and up-to-date
- [ ] All IAPs must be visible to reviewer
- [ ] All IAPs must be functional
- [ ] If any IAP cannot be reviewed, explain in review notes

---

## 2.2 Beta Testing

- [ ] Demos, betas, and trial versions do NOT belong on App Store
- [ ] Use TestFlight for beta distribution
- [ ] TestFlight apps must be intended for public distribution
- [ ] TestFlight apps must comply with App Review Guidelines
- [ ] Cannot distribute TestFlight apps for compensation (including crowdfunding rewards)
- [ ] Significant updates to beta builds require TestFlight App Review

---

## 2.3 Accurate Metadata

All metadata — including privacy information, app description, screenshots, and previews — must accurately reflect the core app experience and remain up-to-date.

### 2.3.1 Hidden/Undocumented Features and Misleading Marketing

#### 2.3.1(a) Feature Disclosure

- [ ] Do NOT include hidden, dormant, or undocumented features
- [ ] App functionality must be clear to end users and App Review
- [ ] All new features must be described with specificity in Notes for Review
- [ ] Generic descriptions will be REJECTED
- [ ] All new features must be accessible for review

**Misleading marketing — whether within or outside the App Store — is grounds for removal from the App Store, a block from installing via alternative distribution, and termination of the developer account:**
- Promoting content/services app doesn't offer
- iOS virus/malware scanners (not actually possible)
- Promoting false prices

#### 2.3.1(b) Egregious Behavior

Egregious or repeated behavior results in removal from Apple Developer Program.

### 2.3.2 In-App Purchase Disclosure

- [ ] Description, screenshots, and previews must clearly indicate items requiring additional purchases
- [ ] If promoting IAPs on the App Store: IAP Display Name, Screenshot, and Description must be appropriate for public audience, follow the "Promoting Your In-App Purchases" guidance, and the app must properly handle `SKPaymentTransactionObserver` so customers can seamlessly complete the purchase at launch

**Swift implementation:**
```swift
// REQUIRED (when promoting IAPs on the App Store): handle pending
// transactions at launch. StoreKit 1 shown to match the guideline text;
// with StoreKit 2, listen to Transaction.updates instead.
class PaymentObserver: NSObject, SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue,
                      updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                // Deliver content
                completeTransaction(transaction)
            case .failed:
                // Handle failure
                failTransaction(transaction)
            case .restored:
                // Restore content
                restoreTransaction(transaction)
            case .deferred, .purchasing:
                break
            @unknown default:
                break
            }
        }
    }
}
```

**React Native implementation (react-native-iap):**
```typescript
// REQUIRED: Proper IAP handling with react-native-iap
import * as IAP from 'react-native-iap';

// Initialize on app start
useEffect(() => {
  const initIAP = async () => {
    await IAP.initConnection();
  };

  const purchaseUpdateSubscription = IAP.purchaseUpdatedListener(
    async (purchase) => {
      const receipt = purchase.transactionReceipt;
      if (receipt) {
        // Validate receipt on your server
        await validateReceipt(receipt);
        // Deliver content
        await deliverContent(purchase.productId);
        // Finish transaction - CRITICAL!
        await IAP.finishTransaction({ purchase });
      }
    }
  );

  const purchaseErrorSubscription = IAP.purchaseErrorListener((error) => {
    console.warn('Purchase error:', error);
    // Handle error appropriately
  });

  initIAP();

  return () => {
    purchaseUpdateSubscription.remove();
    purchaseErrorSubscription.remove();
    IAP.endConnection();
  };
}, []);

// REQUIRED: Restore purchases functionality
const restorePurchases = async () => {
  try {
    const purchases = await IAP.getAvailablePurchases();
    for (const purchase of purchases) {
      await deliverContent(purchase.productId);
    }
  } catch (error) {
    console.error('Restore failed:', error);
  }
};
```

### 2.3.3 Screenshots

- [ ] Must show app in use
- [ ] Must NOT be merely title art, login page, or splash screen
- [ ] May include text/image overlays demonstrating input mechanisms
- [ ] May show extended functionality (Touch Bar, etc.)

### 2.3.4 Previews

- [ ] May ONLY use video screen captures of app itself
- [ ] Stickers/iMessage extensions may show Messages app experience
- [ ] May add narration and overlays to explain unclear functionality

### 2.3.5 Category Selection

- [ ] Select most appropriate category
- [ ] Apple may change category if significantly off-base

### 2.3.6 Age Rating

- [ ] Answer age rating questions honestly
- [ ] Rating must align with parental controls
- [ ] Mis-rating may trigger government regulator inquiry
- [ ] Responsible for complying with local content rating requirements

### 2.3.7 App Name, Keywords, and Metadata Integrity

**Requirements:**
- [ ] App name must be unique (max 30 characters)
- [ ] Keywords must accurately describe app

**Do NOT include in metadata:**
- [ ] Trademarked terms you don't own
- [ ] Popular app names
- [ ] Pricing information
- [ ] Irrelevant phrases to game the system

**App subtitles must:**
- [ ] Follow standard metadata rules
- [ ] Not include inappropriate content
- [ ] Not reference other apps
- [ ] Not make unverifiable product claims

**Additional rules:**
- [ ] Metadata (names, subtitles, screenshots, previews) must not include prices, terms, or descriptions that are not specific to that metadata type
- [ ] Apple may modify inappropriate keywords at any time or take other steps to prevent abuse

### 2.3.8 Age-Appropriate Metadata

- [ ] Metadata must be appropriate for ALL audiences
- [ ] Icons, screenshots, previews must adhere to 4+ rating (even if app is rated higher)
- [ ] For games with violence: select images that don't depict a gruesome death or a gun pointed at a specific character
- [ ] Terms "For Kids" and "For Children" reserved for Kids Category
- [ ] Ensure all icon variants (small, large, Watch, alternates) are similar

### 2.3.9 Rights and Fictional Information

- [ ] Secure rights to all materials in icons, screenshots, previews
- [ ] Display fictional account information instead of real person data

### 2.3.10 Platform Focus and Metadata Relevance

- [ ] App should focus on Apple platforms it supports
- [ ] Do NOT include names, icons, or imagery of other platforms (Android, Windows) — UNLESS there is specific, approved interactive functionality
- [ ] Do NOT include alternative app marketplace references
- [ ] App metadata must focus on app itself

**Code patterns to flag:**

```swift
// Swift - FLAG: References to other platforms in user-facing content
"Android"
"Google Play"
"Windows"
"Download on Play Store"
```

```typescript
// React Native - FLAG: References to other platforms
// Check all user-facing strings!
const strings = {
  download: "Also available on Android", // REJECTION
  share: "Share on Google Play", // REJECTION
};

// FLAG: Platform-specific code leaking to iOS
import { Platform } from 'react-native';
const message = Platform.OS === 'ios'
  ? "Welcome to our app"
  : "Welcome to Android"; // Make sure iOS doesn't see Android text!

// FLAG: Check assets for other platform logos
import googlePlayBadge from './assets/google-play-badge.png'; // Remove from iOS
```

### 2.3.11 Pre-Order Accuracy

- [ ] Pre-order apps must be complete and deliverable as submitted
- [ ] Released app must NOT be materially different from advertised
- [ ] Material changes (e.g., business model) require restarting pre-order sales

### 2.3.12 "What's New" Text

- [ ] Clearly describe new features and product changes
- [ ] Bug fixes, security updates, performance improvements may use generic description
- [ ] Significant changes must be specifically listed

### 2.3.13 In-App Events

- [ ] Events must fall within event type in App Store Connect
- [ ] Event metadata must be accurate and pertain to event (not app generally)
- [ ] Events must happen at selected times/dates across storefronts
- [ ] Event deep link must direct to proper destination
- [ ] Events may be monetized, following the Section 3 Business rules

---

## 2.4 Hardware Compatibility

### 2.4.1 Multi-Device Support

- [ ] iPhone apps should run on iPad whenever possible
- [ ] Encouraged to build apps for all devices

```swift
// Swift - REQUIRED: Check device support
// In Info.plist - only include truly required capabilities
<key>UIRequiredDeviceCapabilities</key>
<array>
    <!-- Only include what's actually required -->
</array>
```

```typescript
// React Native - iPad support
// Ensure your app works on iPad - test thoroughly!
// In Xcode: Check "iPad" under Deployment Info

// Check for tablet-specific layouts
import { useWindowDimensions } from 'react-native';

const App = () => {
  const { width } = useWindowDimensions();
  const isTablet = width >= 768;

  return isTablet ? <TabletLayout /> : <PhoneLayout />;
};
```

### 2.4.2 Power Efficiency and Device Strain

**Apps must NOT:**
- [ ] Rapidly drain battery
- [ ] Generate excessive heat
- [ ] Put unnecessary strain on device resources
- [ ] Encourage placing device under mattress/pillow while charging
- [ ] Perform excessive write cycles to SSD
- [ ] Run unrelated background processes (e.g., cryptocurrency mining) — this includes any third-party advertisements displayed within the app

**Swift code patterns to flag:**
```swift
// FLAG: Aggressive polling
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    // REJECTION RISK: Too frequent
}

// FLAG: Continuous location updates without need
locationManager.startUpdatingLocation() // Use significant changes if possible

// FLAG: Crypto mining
"bitcoin", "mining", "hash_rate", "proof_of_work" // On-device = REJECTION

// FLAG: Excessive disk writes
for i in 0..<1000000 {
    try data.write(to: url) // REJECTION RISK
}
```

**React Native code patterns to flag:**
```typescript
// FLAG: Aggressive polling
useEffect(() => {
  const interval = setInterval(() => {
    fetchData(); // Every 100ms = REJECTION RISK
  }, 100);
  return () => clearInterval(interval);
}, []);

// ✅ GOOD: Reasonable polling interval
const interval = setInterval(fetchData, 30000); // 30 seconds

// FLAG: Continuous location updates
import Geolocation from '@react-native-community/geolocation';
Geolocation.watchPosition(callback, error, {
  enableHighAccuracy: true,
  distanceFilter: 0, // Updates on ANY movement = battery drain
});

// ✅ GOOD: Use distance filter
Geolocation.watchPosition(callback, error, {
  distanceFilter: 100, // Only update every 100 meters
});

// FLAG: Crypto mining
const mineBlock = () => { }; // REJECTION
const calculateHash = () => { }; // If for mining = REJECTION

// FLAG: Excessive AsyncStorage writes
for (let i = 0; i < 1000000; i++) {
  await AsyncStorage.setItem(`key_${i}`, data); // REJECTION RISK
}
```

### 2.4.3 Apple TV Hardware Input Requirements

- [ ] App must be usable without hardware beyond Siri remote or game controllers
- [ ] May provide enhanced functionality with other peripherals
- [ ] If requiring game controller, clearly explain in metadata

### 2.4.4 Device Restart and System Settings

**Apps must NEVER:**
- [ ] Suggest or require device restart unrelated to core functionality
- [ ] Encourage turning off Wi-Fi
- [ ] Encourage disabling security features
- [ ] Require system setting modifications unrelated to app

### 2.4.5 Mac App Store Additional Requirements

#### 2.4.5(i) Sandboxing and File System
- [ ] Must be appropriately sandboxed
- [ ] Must follow macOS File System Documentation
- [ ] Only use appropriate macOS APIs for modifying user data stored by OTHER apps (e.g. bookmarks, Address Book, Calendar entries)

#### 2.4.5(ii) Packaging and Installation
- [ ] Must be packaged using Xcode technologies
- [ ] No third-party installers
- [ ] Must be self-contained, single app installation bundles
- [ ] Cannot install code/resources in shared locations

#### 2.4.5(iii) Auto-Launch and Startup Code
- [ ] May NOT auto-launch or have other code run automatically at startup or login without consent
- [ ] May NOT spawn processes that continue running after user quits, without consent
- [ ] Should NOT automatically add Dock icons or desktop shortcuts

#### 2.4.5(iv) Code and Resource Installation
- [ ] May NOT download or install standalone apps, kexts, additional code
- [ ] Cannot add functionality significantly changing from reviewed version

#### 2.4.5(v) Privilege Escalation
- [ ] May NOT request escalation to root privileges
- [ ] May NOT use setuid attributes

#### 2.4.5(vi) Licensing and Copy Protection
- [ ] May NOT present license screen at launch
- [ ] May NOT require license keys
- [ ] May NOT implement own copy protection

#### 2.4.5(vii) App Store Update Distribution
- [ ] Must use Mac App Store to distribute updates

#### 2.4.5(viii) Operating System Compatibility
- [ ] Must run on currently shipping OS
- [ ] May NOT use deprecated or optionally installed technologies (Java, etc.)

#### 2.4.5(ix) Language and Localization
- [ ] Must contain all language/localization support in single app bundle

---

## 2.5 Software Requirements

### 2.5.1 Public APIs and Current OS

- [ ] Apps may ONLY use public APIs
- [ ] Must run on currently shipping OS
- [ ] Keep apps up-to-date
- [ ] Phase out deprecated features, frameworks, technologies
- [ ] Use APIs/frameworks for intended purposes
- [ ] Indicate framework integration in app description

**Swift code patterns to flag:**
```swift
// FLAG: Private API usage
let selector = NSSelectorFromString("_privateMethod") // REJECTION
perform(selector)

// FLAG: Accessing private frameworks
@import PrivateFramework; // REJECTION

// FLAG: Using undocumented methods
objc_msgSend(self, sel_registerName("_hiddenMethod")) // REJECTION

// REQUIRED: Only use documented public APIs
import UIKit
import SwiftUI
import StoreKit // All public frameworks
```

**React Native code patterns to flag:**
```typescript
// FLAG: Accessing private native APIs via native modules
// In your native module (iOS)
// Don't call private Objective-C methods!

// FLAG: Using deprecated React Native APIs
import { NativeModules } from 'react-native';
NativeModules.SomeDeprecatedModule; // Check if deprecated

// ✅ GOOD: Use maintained, public packages
import { Camera } from 'expo-camera'; // Public API
import * as IAP from 'react-native-iap'; // Public StoreKit wrapper
```

### 2.5.2 Self-Contained Bundles

- [ ] Apps should be self-contained in bundles
- [ ] May NOT read/write data outside designated container area
- [ ] May NOT download, install, or execute code that changes app features/functionality

**Exception for Educational Code:**
- [ ] Educational apps teaching executable code may download code if:
  - Code not used for other purposes
  - Source code completely viewable and editable by user

**Swift code patterns to flag:**
```swift
// FLAG: Dynamic code execution
let script = downloadScript()
JSContext().evaluateScript(script) // REJECTION unless educational

// FLAG: Code injection
dlopen("downloaded_library.dylib", RTLD_NOW) // REJECTION

// FLAG: Writing outside container
FileManager.default.createFile(atPath: "/usr/local/bin/app") // REJECTION
```

**React Native code patterns to flag:**
```typescript
// ⚠️ CRITICAL: OTA JS updates (expo-updates, self-hosted CodePush)
// OTA updates ARE allowed but with restrictions!
// Note: Microsoft's hosted CodePush service (App Center) was retired in
// March 2025 — react-native-code-push now requires a self-hosted server.
// expo-updates is the maintained mainstream path.

// ✅ ALLOWED: Bug fixes and minor changes via OTA update
import * as Updates from 'expo-updates';
await Updates.fetchUpdateAsync(); // OK for bug fixes

// ❌ NOT ALLOWED: Significant feature changes via OTA update
// - Adding new screens/features
// - Changing app's primary purpose
// - Bypassing App Review for major updates

// FLAG: Executing downloaded JavaScript
const downloadedCode = await fetch('https://example.com/code.js');
eval(downloadedCode); // REJECTION

// FLAG: Dynamic requires
const module = require(dynamicPath); // REJECTION RISK

// ✅ GOOD: Static imports only
import { MyComponent } from './MyComponent';
```

### 2.5.3 Malicious Code

**Apps will be REJECTED for:**
- [ ] Transmitting viruses
- [ ] Transmitting files, code, programs harming/disrupting OS or hardware
- [ ] Disrupting Push Notifications or Game Center

Egregious violations result in removal from Apple Developer Program.

### 2.5.4 Multitasking Background Services

Background services may ONLY be used for intended purposes (non-exhaustive list):
- [ ] VoIP
- [ ] Audio playback
- [ ] Location
- [ ] Task completion
- [ ] Local notifications
- [ ] etc. — other legitimate background purposes exist; the test is that the mode matches its intended purpose

**Swift configuration:**
```swift
// REQUIRED: Proper background mode usage
// In Info.plist
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>           <!-- Only if playing audio -->
    <string>location</string>        <!-- Only if tracking location -->
    <string>voip</string>            <!-- Only if VoIP app -->
    <string>fetch</string>           <!-- Only if fetching content -->
</array>

// FLAG: Misusing background modes
// Using audio background mode just to keep app alive = REJECTION
```

**React Native background handling:**
```typescript
// FLAG: Misusing background modes
// Don't add background modes you don't actually need!

// Check ios/[AppName]/Info.plist for UIBackgroundModes
// Only include modes you legitimately use

// ✅ GOOD: Proper background audio (react-native-track-player)
import TrackPlayer from 'react-native-track-player';
// Requires audio background mode - legitimate use

// ✅ GOOD: Proper background location
import Geolocation from 'react-native-geolocation-service';
// Requires location background mode - only for navigation/fitness apps

// ❌ BAD: Playing silent audio to keep app alive
TrackPlayer.play(silentAudio); // REJECTION

// For background tasks, use proper APIs:
import BackgroundFetch from 'react-native-background-fetch';
// Configure in Info.plist with 'fetch' background mode
```

### 2.5.5 IPv6-Only Networks

- [ ] Apps MUST be fully functional on IPv6-only networks

**Swift implementation:**
```swift
// REQUIRED: IPv6 compatibility
// Test with Network Link Conditioner: "100% Loss" for IPv4

// BAD: Hardcoded IPv4 addresses
let server = "192.168.1.1" // REJECTION RISK

// GOOD: Use hostnames
let server = "api.example.com"
```

**React Native implementation:**
```typescript
// REQUIRED: IPv6 compatibility
// Test your app with Network Link Conditioner!

// ❌ BAD: Hardcoded IPv4 addresses
const API_URL = 'http://192.168.1.1:3000'; // REJECTION RISK

// ✅ GOOD: Use hostnames
const API_URL = 'https://api.example.com';

// Check all fetch() calls and API configurations
const api = axios.create({
  baseURL: 'https://api.example.com', // Hostname, not IP
});

// Also check: WebSocket connections, native module configs
const socket = new WebSocket('wss://api.example.com/ws'); // Good
```

### 2.5.6 Web Browser Requirements

- [ ] Apps browsing web MUST use appropriate WebKit framework and WebKit JavaScript
- [ ] May apply for entitlement to use alternative web browser engine (available for the EU and Japan)

**Swift implementation:**
```swift
// REQUIRED: Use WebKit
import WebKit

let webView = WKWebView(frame: .zero)

// FLAG: Custom browser engines without entitlement
// JavaScriptCore for full browser functionality = REJECTION
```

**React Native implementation:**
```typescript
// REQUIRED: Use react-native-webview (uses WKWebView on iOS)
import { WebView } from 'react-native-webview';

const MyWebView = () => (
  <WebView
    source={{ uri: 'https://example.com' }}
    // Uses WKWebView on iOS - compliant!
  />
);

// ✅ react-native-webview uses WKWebView internally
// No additional configuration needed for compliance
```

### 2.5.8 Alternate Desktop/Home Screen Environments

- [ ] Apps creating alternate desktop/home screen environments will be REJECTED

### 2.5.9 Standard UI Element Alterations

**Apps will be REJECTED for:**
- [ ] Altering or disabling Volume Up/Down switches
- [ ] Altering or disabling Ring/Silent switch
- [ ] Altering other native UI elements/behaviors
- [ ] Blocking links users expect to work

### 2.5.11 SiriKit and Shortcuts

#### 2.5.11(i) Appropriate Intent Registration
- [ ] Only register intents app can handle without additional support
- [ ] Only register intents users would expect from stated functionality

#### 2.5.11(ii) Vocabulary and Aliases
- [ ] Vocabulary and phrases must pertain to app and Siri functionality
- [ ] Aliases must relate directly to app or company name
- [ ] No generic terms
- [ ] No third-party app names/services

#### 2.5.11(iii) Direct Request Resolution
- [ ] Resolve Siri requests in most direct way possible
- [ ] Do NOT insert ads or marketing between request and fulfillment
- [ ] Only request disambiguation when required

### 2.5.12 CallKit, SMS Blocking, and Spam Identification

- [ ] Only block phone numbers confirmed as spam
- [ ] Clearly identify features in marketing text
- [ ] Explain criteria for blocked/spam lists
- [ ] May NOT use data for tracking, user profiles, or selling

### 2.5.13 Facial Recognition

- [ ] Apps using facial recognition for authentication MUST use LocalAuthentication where possible
- [ ] Do NOT use ARKit or other facial recognition for this purpose
- [ ] Must use alternate authentication for users under 13

**Swift implementation:**
```swift
// REQUIRED: Use LocalAuthentication for face auth
import LocalAuthentication

let context = LAContext()
context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                       localizedReason: "Authenticate to access account") { success, error in
    // Handle result
}

// FLAG: Using ARKit for authentication
ARFaceTrackingConfiguration() // For authentication = REJECTION
```

**React Native implementation:**
```typescript
// REQUIRED: Use react-native-biometrics or expo-local-authentication
import ReactNativeBiometrics from 'react-native-biometrics';

const rnBiometrics = new ReactNativeBiometrics();

const authenticate = async () => {
  const { success } = await rnBiometrics.simplePrompt({
    promptMessage: 'Authenticate to access account',
  });
  return success;
};

// Or with Expo:
import * as LocalAuthentication from 'expo-local-authentication';

const authenticate = async () => {
  const result = await LocalAuthentication.authenticateAsync({
    promptMessage: 'Authenticate to access account',
  });
  return result.success;
};

// FLAG: Using vision/ML for face auth
// (e.g. react-native-vision-camera frame processors + a face model)
// Don't use camera-based face recognition for auth!
// Must use device biometrics (Face ID/Touch ID)
```

### 2.5.14 Recording and User Activity Logging

- [ ] Must request explicit user consent when recording/logging user activity
- [ ] Must provide clear visual and/or audible indication when recording
- [ ] Applies to: camera, microphone, screen recordings, other user inputs

### 2.5.15 File Selection and Display

- [ ] Apps enabling file viewing/selection should include items from Files app and iCloud documents

### 2.5.16 Widgets, Extensions, and Notifications

- [ ] Must be related to app content and functionality

#### 2.5.16(a) App Clips
- [ ] All App Clip features must be in main app binary
- [ ] App Clips cannot contain advertising

### 2.5.17 Matter Support

- [ ] Apps supporting Matter must use Apple's support framework for pairing
- [ ] Other Matter software components must be CSA certified

### 2.5.18 Display Advertising

**Ads limited to main app binary only. NOT allowed in:**
- [ ] Extensions
- [ ] App Clips
- [ ] Widgets
- [ ] Notifications
- [ ] Keyboards
- [ ] watchOS apps

**Ad requirements:**
- [ ] Appropriate for app's age rating
- [ ] Allow user to see all targeting information without leaving app
- [ ] No targeted/behavioral advertising based on:
  - Health/medical data (HealthKit)
  - School/classroom data (ClassKit)
  - Kids data (Kids Category apps)

**Interstitial/blocking ads must:**
- [ ] Clearly indicate they are ads
- [ ] Not manipulate/trick users into tapping
- [ ] Provide easily accessible close/skip buttons (large enough for easy dismissal)
- [ ] Apps must include ability to report any inappropriate or age-inappropriate ads

---

## React Native Packages Reference

| Guideline | Expo Package | Bare RN Package |
|-----------|-------------|-----------------|
| In-App Purchase | `react-native-purchases` (RevenueCat, dev build) | `react-native-purchases` (RevenueCat) or `react-native-iap` |
| Biometric Auth | `expo-local-authentication` | `react-native-biometrics` |
| WebView | - | `react-native-webview` |
| Background Tasks | `expo-background-task`, `expo-task-manager` | `react-native-background-fetch` |
| Location | `expo-location` | `react-native-geolocation-service` |
| OTA Updates | `expo-updates` | `react-native-code-push` (self-hosted server required) |
| Secure Storage | `expo-secure-store` | `react-native-keychain` |
| Device Info | `expo-device` | `react-native-device-info` |

## React Native Pre-Submission Checklist

- [ ] Remove all `console.log` statements (or wrap in `__DEV__`)
- [ ] Remove placeholder content from all screens
- [ ] Test on real iOS device (not just simulator)
- [ ] Test IAP flow end-to-end including restore
- [ ] Verify no hardcoded IP addresses
- [ ] Check all background modes are legitimately used
- [ ] Ensure OTA updates (expo-updates/CodePush) only deliver bug fixes, not features
- [ ] Test on IPv6-only network
- [ ] Verify biometrics use LocalAuthentication APIs
