---
name: design
description: App Store Review Guidelines Section 4 - Design (copycats, minimum functionality, spam, extensions, Apple services, login)
---

# 4. DESIGN

**Section intro (enforcement-relevant):**
- [ ] These are minimum standards for approval — even after approval, keep the app functional and engaging
- [ ] Apps that stop working or offer a degraded experience may be REMOVED from the App Store at any time

## 4.1 Copycats

### 4.1(a) Original Ideas
- [ ] Create your own ideas
- [ ] Don't copy popular apps with minor changes
- [ ] Risk of IP infringement claims

### 4.1(b) Impersonation
- [ ] Submitting apps impersonating other apps/services violates Developer Code of Conduct
- [ ] May result in removal from Developer Program

### 4.1(c) Trademark and Brand Usage
- [ ] Cannot use another developer's icon, brand, or product name without approval

---

## 4.2 Minimum Functionality

Apps should include features, content, and UI elevating it beyond a repackaged website.

- [ ] App must be useful, unique, or "app-like" — otherwise it doesn't belong on the App Store
- [ ] Must provide lasting entertainment value or adequate utility
- [ ] Apps that are simply a song or movie belong on the iTunes Store; simply a book or game guide belongs on Apple Books

**React Native - WebView-only apps will be REJECTED:**
```typescript
// ❌ BAD: Pure WebView wrapper (REJECTION)
const App = () => (
  <WebView source={{ uri: 'https://mywebsite.com' }} />
);

// ❌ BAD: WebView with minimal native chrome
const App = () => (
  <SafeAreaView>
    <WebView source={{ uri: 'https://mywebsite.com' }} />
  </SafeAreaView>
);

// ✅ GOOD: Hybrid app with native features
const App = () => (
  <NavigationContainer>
    <Tab.Navigator>
      <Tab.Screen name="Home" component={NativeHomeScreen} />
      <Tab.Screen name="Profile" component={NativeProfileScreen} />
      <Tab.Screen name="WebContent" component={WebViewScreen} />
    </Tab.Navigator>
  </NavigationContainer>
);

// ✅ GOOD: WebView with significant native functionality
const App = () => {
  // Native features that justify the app
  const { pushToken } = usePushNotifications();
  const { biometricAuth } = useBiometrics();
  const { offlineData } = useOfflineStorage();

  return (
    <View>
      <NativeHeader />
      <WebView source={{ uri: 'https://mywebsite.com' }} />
      <NativeTabBar />
    </View>
  );
};
```

### 4.2.1 ARKit Requirements
- [ ] Must provide rich, integrated AR experiences
- [ ] Merely dropping model into AR view is NOT enough

### 4.2.2 Marketing Content Restrictions
- [ ] Other than catalogs, apps shouldn't primarily be marketing materials
- [ ] Not advertisements, web clippings, content aggregators, or link collections

### 4.2.3 App Independence and Resource Downloads

#### 4.2.3(i) Standalone Functionality
- [ ] App should work without requiring installation of another app

#### 4.2.3(ii) Download Disclosure
- [ ] If additional resources needed for initial launch, disclose download size
- [ ] Prompt users before downloading

### 4.2.4 / 4.2.5 Intentionally omitted

### 4.2.6 Template and App Generation Services
- [ ] Template apps must be submitted by content provider, not service
- [ ] Services should offer tools for clients to create customized apps
- [ ] Apps should provide unique customer experiences
- [ ] Alternative: Single binary hosting all client content (picker model)

### 4.2.7 Remote Desktop Clients

If mirroring specific software/services (not generic host device):

#### 4.2.7(a) Connection Requirements
- [ ] Only connect to user-owned host device (PC or game console)
- [ ] Must be on local AND LAN-based network

#### 4.2.7(b) Software Execution
- [ ] All software/services fully executed on host device
- [ ] Rendered on host device screen
- [ ] May not use APIs beyond what's required to stream

#### 4.2.7(c) Account Management
- [ ] All account creation/management from host device

#### 4.2.7(d) UI Requirements
- [ ] UI must NOT resemble iOS or App Store
- [ ] No store-like interface
- [ ] No ability to browse/select/purchase software not already owned
- [ ] Clarification: transactions inside mirrored software do NOT need IAP, provided they are processed on the host device

#### 4.2.7(e) Cloud-Based Limitations
- [ ] Thin clients for cloud-based apps NOT appropriate

---

## 4.3 Spam

### 4.3(a) Bundle ID Restrictions
- [ ] Don't create multiple Bundle IDs for the same app
- [ ] Do not submit separate variants for each city, sports team, university, location, customer, or minor content change
- [ ] Use one app with search, configuration, downloadable content, or in-app purchase for legitimate variations
- [ ] Flag app-generator workflows that mint many near-identical apps from the same template

### 4.3(b) Category Saturation
- [ ] Do not submit apps that are indistinguishable from what is already widely available
- [ ] Opportunistic variants of existing categories or popular apps degrade App Store discovery and overall quality
- [ ] Saturated examples include dating, flashlight, sound effects, wallpaper, simple timers, and fortune telling apps
- [ ] New submissions in saturated categories need a meaningfully different or improved experience
- [ ] Existing apps in these categories may be removed if they are not updated, improved, or attracting customers
- [ ] Low-quality or low-effort examples include drinking games, Kama Sutra, fart, and burp apps
- [ ] Repeated submissions of mediocre, low-quality, or low-effort apps may lead to Developer Program removal

**Code and repository patterns to flag:**
```typescript
// FLAG: white-label spam with only metadata or asset swaps
const APP_VARIANT = 'city_042'; // Review whether this should be one searchable app
const ENABLED_TEAM = 'team_red'; // Review if separate Bundle IDs exist per team
```

---

## 4.4 Extensions

- [ ] Comply with App Extension Programming Guide, Safari app extensions documentation, or Safari web extensions documentation
- [ ] Include functionality (help screens, settings)
- [ ] Clearly disclose extensions in marketing text
- [ ] Extensions may NOT include marketing, advertising, or IAP

### 4.4.1 Keyboard Extensions

**Must:**
- [ ] Provide keyboard input functionality
- [ ] Follow Sticker guidelines for images/emoji
- [ ] Provide method to progress to next keyboard
- [ ] Remain functional without full network access AND without requiring Full Access
- [ ] Only collect user activity to enhance keyboard functionality

**Must NOT:**
- [ ] Launch other apps (besides Settings)
- [ ] Repurpose keyboard buttons for other behaviors

### 4.4.2 Safari Extensions
- [ ] Must run on current Safari version
- [ ] May not interfere with System or Safari UI
- [ ] Must never include malicious or misleading content/code — violating this leads to removal from the Developer Program
- [ ] Should not claim access to more websites than necessary

### 4.4.3 Intentionally omitted

---

## 4.5 Apple Sites and Services

### 4.5.1 Approved RSS Feeds and Scraping
- [ ] May use approved Apple RSS feeds
- [ ] May NOT scrape Apple sites (apple.com, iTunes, App Store, App Store Connect, developer portal)
- [ ] May NOT create rankings using Apple information

### 4.5.2 Apple Music

#### 4.5.2(i) MusicKit on iOS
- [ ] Users must initiate playback
- [ ] Must provide standard media controls (play, pause, skip)
- [ ] May NOT require payment or monetize access to Apple Music
- [ ] Do NOT download/upload/share music files except as permitted

#### 4.5.2(ii) Additional Licenses
- [ ] MusicKit is not replacement for synchronization/adaptation rights
- [ ] Cover art/metadata only for playback/playlists
- [ ] Not for marketing without rights-holder authorization
- [ ] Follow Apple Music Identity Guidelines

#### 4.5.2(iii) Apple Music User Data
- [ ] Clearly disclose data access in purpose string
- [ ] Only share data to support/improve app experience
- [ ] NOT for user identification or ad targeting

### 4.5.3 Do Not Spam, Phish, or Send Unsolicited Messages via Apple Services
- [ ] Do NOT spam via Game Center, Push Notifications, Live Activities, or other Apple services
- [ ] Do NOT phish customers through Apple services
- [ ] Do NOT send unsolicited messages through Apple services
- [ ] Do NOT exploit Player IDs, aliases, or other information obtained through Game Center
- [ ] Violations result in removal from the Apple Developer Program

**Live Activities review points:**
- [ ] Live Activities are tied to a user-initiated, time-bound activity
- [ ] Activity updates are factual and directly related to the active event
- [ ] ActivityKit push updates are not used as an extra marketing or messaging channel
- [ ] Users can end or control the Live Activity where appropriate

```swift
// FLAG: Live Activity used for unsolicited promotion instead of active event state
try await activity.update(ActivityContent(
    state: PromotionState(message: "Limited time offer"),
    staleDate: nil
))
```

### 4.5.4 Push Notifications
- [ ] NOT required for app to function
- [ ] NOT for sensitive personal/confidential information
- [ ] NOT for promotions/marketing UNLESS opt-in
- [ ] Opt-in must be via consent language in app UI
- [ ] Must provide opt-out method
- [ ] Abuse of these services may result in revocation of privileges

### 4.5.5 Game Center Player IDs
- [ ] Only use as approved by Game Center terms
- [ ] Do NOT display or share with third parties

### 4.5.6 Apple Emoji
- [ ] May use Unicode characters rendering as Apple emoji
- [ ] Apple emoji may NOT be used on other platforms
- [ ] May NOT embed directly in app binary

---

## 4.6 Intentionally omitted

---

## 4.7 Mini Apps, Mini Games, Streaming Games, Chatbots, Plug-ins, Game Emulators

**Scope and responsibility:**
- [ ] Applies to software NOT embedded in the binary: HTML5/JavaScript mini apps and mini games, streaming games, chatbots, and plug-ins
- [ ] Retro game console and PC emulator apps may offer game downloads
- [ ] Developer is responsible for ALL such software offered in the app — it must comply with these Guidelines and all applicable laws
- [ ] Hosted software violating any guideline leads to rejection of the app

### 4.7.1 Software Requirements
- [ ] Follow all privacy guidelines (5.1)
- [ ] Include content filtering method
- [ ] Include content reporting mechanism
- [ ] Provide timely responses to concerns
- [ ] Include user blocking capability
- [ ] Follow payment guidelines (3.1)

### 4.7.2 Platform APIs and Technologies
- [ ] May NOT extend/expose native platform APIs without Apple permission

### 4.7.3 Data and Privacy Permissions
- [ ] May NOT share data/permissions to software without explicit user consent each instance

### 4.7.4 Software Index and Metadata
- [ ] Must provide index of software and metadata
- [ ] Must include universal links to all software

### 4.7.5 Age Rating and Age Restrictions
- [ ] Must provide way to identify content exceeding age rating
- [ ] Must use age restriction mechanism (verified or declared age)
- [ ] Must limit underage user access

---

## 4.8 Login Services

If using a third-party or social login service (e.g. Facebook Login, Google Sign-In, Log in with X, Sign In with LinkedIn, Login with Amazon, WeChat Login) to set up or authenticate the user's **primary account**, must ALSO offer as an equivalent option another login service with ALL of:
- [ ] Only collects name and email
- [ ] Allows keeping email private
- [ ] Does NOT collect interactions with the app for advertising without consent

Sign in with Apple meets all three criteria and is the simplest way to comply, but any login service meeting them is acceptable.

**Primary account** = the account the user establishes with your app to identify themselves, sign in, and access features and services. Secondary or linked logins are out of scope.

**Exceptions (alternative NOT required if):**
- [ ] Exclusively using company's own account system
- [ ] Alternative marketplace with marketplace-specific login
- [ ] Education/enterprise app requiring existing accounts
- [ ] Government/industry citizen identification system
- [ ] Client for specific third-party service requiring direct sign-in

**Swift implementation:**
```swift
// REQUIRED: If using social login, also offer alternative
class LoginViewController {
    @IBAction func signInWithApple() {
        // Sign in with Apple (recommended alternative)
    }

    @IBAction func signInWithGoogle() {
        // Third-party login
    }

    @IBAction func signInWithEmail() {
        // Email-only alternative (name + email only)
    }
}
```

**React Native implementation:**
```typescript
// REQUIRED: If social login sets up the primary account, also offer an
// equivalent privacy-preserving login. Sign in with Apple is the simplest
// compliant option (not the only one).
import { appleAuth } from '@invertase/react-native-apple-authentication';
import { GoogleSignin } from '@react-native-google-signin/google-signin';

const LoginScreen = () => {
  // ✅ Sign in with Apple — meets all three 4.8 criteria
  const signInWithApple = async () => {
    const credential = await appleAuth.performRequest({
      requestedOperation: appleAuth.Operation.LOGIN,
      requestedScopes: [appleAuth.Scope.EMAIL, appleAuth.Scope.FULL_NAME],
    });
    // User can hide their email - respect this!
    const { email, fullName } = credential;
    await authenticateWithBackend(credential);
  };

  // Third-party login
  const signInWithGoogle = async () => {
    await GoogleSignin.hasPlayServices();
    const userInfo = await GoogleSignin.signIn();
    await authenticateWithBackend(userInfo);
  };

  // Email-only alternative (collects only name + email)
  const signInWithEmail = async (email: string, name: string) => {
    await authenticateWithBackend({ email, name });
  };

  return (
    <View>
      {/* Google login alone isn't compliant — pair it with a login
          meeting 4.8's criteria (e.g. Sign in with Apple) */}
      <AppleButton onPress={signInWithApple} />
      <GoogleSigninButton onPress={signInWithGoogle} />
      <Button title="Continue with Email" onPress={showEmailForm} />
    </View>
  );
};

// Packages needed:
// - @invertase/react-native-apple-authentication
// - @react-native-google-signin/google-signin
```

---

## 4.9 Apple Pay

- [ ] Provide all material purchase information PRIOR to sale
- [ ] Use Apple Pay branding and UI as described in the Apple Pay Marketing Guidelines and Human Interface Guidelines

**Recurring payments must disclose:**
- [ ] Length of renewal term and auto-continuation
- [ ] What's provided each period
- [ ] Actual charges
- [ ] How to cancel

---

## 4.10 Monetizing Built-In Capabilities

**May NOT monetize:**
- [ ] Push Notifications
- [ ] Camera
- [ ] Gyroscope
- [ ] Other built-in hardware capabilities
- [ ] Apple Music access
- [ ] iCloud storage
- [ ] Screen Time APIs
- [ ] Other Apple services and technologies

---

## React Native Packages Reference

| Guideline | Expo Package | Bare RN Package |
|-----------|-------------|-----------------|
| Sign in with Apple | `expo-apple-authentication` | `@invertase/react-native-apple-authentication` |
| Google Sign-In | `expo-auth-session` | `@react-native-google-signin/google-signin` |
| Facebook Login | `expo-auth-session` | `react-native-fbsdk-next` |
| WebView | - | `react-native-webview` |
| Push Notifications | `expo-notifications` | `@react-native-firebase/messaging` |
| Linking | `expo-linking` | `react-native` Linking |

## React Native Design Checklist

- [ ] If using social login (Google, Facebook, etc.) for the primary account, also offer a login meeting 4.8's privacy criteria (Sign in with Apple is the simplest compliant option)
- [ ] App has meaningful native functionality beyond WebView
- [ ] No App Store-like interfaces for third-party content
- [ ] Extensions/widgets don't contain ads or IAP
- [ ] Push notifications are optional and have opt-out
- [ ] App is responsive and functional on iPad (reviewers test on iPads)

---

## Practical Review Considerations (Unofficial)

> **Note:** The following are not official App Store Review Guidelines but are important practical considerations based on how Apple reviews apps.

### iPad Responsiveness

Apple reviewers frequently test apps on iPads, even for iPhone-only apps. Your app must be responsive and functional on iPad to avoid rejection.

- [ ] Test your app on iPad simulator before submission
- [ ] Ensure layouts don't break on larger screens
- [ ] UI elements should be appropriately sized and positioned
- [ ] Navigation should work correctly on iPad
- [ ] Modal presentations should display properly

**React Native implementation:**
```typescript
import { useWindowDimensions, Platform } from 'react-native';

// ✅ GOOD: Responsive design that works on iPad
const ResponsiveComponent = () => {
  const { width, height } = useWindowDimensions();
  const isTablet = width >= 768;

  return (
    <View style={[
      styles.container,
      isTablet && styles.tabletContainer
    ]}>
      {/* Adapt layout based on screen size */}
    </View>
  );
};

// ✅ GOOD: Check if running on iPad
const isIPad = Platform.OS === 'ios' && Platform.isPad;

// ✅ GOOD: Use flex layouts that adapt to screen size
const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 16,
  },
  tabletContainer: {
    paddingHorizontal: 48,
    maxWidth: 800,
    alignSelf: 'center',
  },
});
```

**Expo considerations:**
```typescript
import { useWindowDimensions } from 'react-native';
import Constants from 'expo-constants';

// Check device type in Expo
const deviceType = Constants.deviceType;
// 1 = Phone, 2 = Tablet, 3 = Desktop
```

**Swift implementation:**
```swift
import UIKit

// ✅ GOOD: Check if running on iPad
let isIPad = UIDevice.current.userInterfaceIdiom == .pad

// ✅ GOOD: Adaptive layouts using size classes
class ResponsiveViewController: UIViewController {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateLayoutForCurrentTraitCollection()
    }

    private func updateLayoutForCurrentTraitCollection() {
        if traitCollection.horizontalSizeClass == .regular {
            // iPad or large screen layout
            configureTabletLayout()
        } else {
            // iPhone or compact layout
            configurePhoneLayout()
        }
    }

    private func configureTabletLayout() {
        // Wider margins, larger touch targets, split views
    }

    private func configurePhoneLayout() {
        // Standard phone layout
    }
}

// ✅ GOOD: Using Auto Layout constraints that adapt
class AdaptiveView: UIView {
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Use readable content guide for text on iPad
            contentView.leadingAnchor.constraint(equalTo: readableContentGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: readableContentGuide.trailingAnchor),
        ])
    }
}

// ✅ GOOD: SwiftUI adaptive layout
import SwiftUI

struct ResponsiveView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            // iPad layout
            HStack {
                SidebarView()
                ContentView()
            }
        } else {
            // iPhone layout
            NavigationStack {
                ContentView()
            }
        }
    }
}
```
