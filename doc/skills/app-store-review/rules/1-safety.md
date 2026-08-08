---
name: safety
description: App Store Review Guidelines Section 1 - Safety (objectionable content, UGC, Kids Category, physical harm, data security)
---

# 1. SAFETY

When people install an app from the App Store, they want to feel confident that it's safe to do so. Apps looking to shock and offend people don't belong on the App Store.

## Current Apple Emphasis

Apple's June 8, 2026 update revised kid and teen safety guidance. When reviewing an app that children or teens may use, do not rely only on platform parental controls:
- [ ] Confirm the in-app experience is age-appropriate for the audience actually using it
- [ ] Check onboarding, discovery, recommendations, messaging, ads, and UGC surfaces for age-inappropriate exposure
- [ ] Treat inaccurate age ratings or weak age gates as safety risks, not just metadata issues

## 1.1 Objectionable Content

Apps should not include content that is offensive, insensitive, upsetting, intended to disgust, in exceptionally poor taste, or just plain creepy.

### 1.1.1 Defamatory, Discriminatory, or Mean-Spirited Content

**REJECT if app contains:**
- [ ] Defamatory, discriminatory, or mean-spirited content — including references or commentary about religion, race, sexual orientation, gender, national/ethnic origin, or other targeted groups — particularly if the app is likely to humiliate, intimidate, or harm a targeted individual or group
- [ ] Discriminatory language in any text, assets, or user-facing content

**Note:** Merely mentioning religion, race, etc. is NOT a violation — the content must be defamatory, discriminatory, or mean-spirited.

**Exception:** Professional political satirists and humorists are generally exempt.

**Code patterns to flag:**

```swift
// Swift - FLAG: Review all hardcoded strings for discriminatory content
let strings = ["message", "alert", "notification"] // Audit for offensive language

// FLAG: User-facing text that targets groups
// Search for terms related to: religion, race, gender, nationality, orientation
```

```typescript
// React Native - FLAG: Review all hardcoded strings
const strings = {
  message: "...", // Audit for offensive language
  alert: "...",
};

// FLAG: Check i18n/localization files for discriminatory content
// en.json, es.json, etc.
```

### 1.1.2 Realistic Portrayals of Violence

**REJECT if app contains:**
- [ ] Realistic portrayals of people or animals being killed, maimed, tortured, or abused
- [ ] Content that encourages violence
- [ ] "Enemies" within the context of a game that solely target a specific race, culture, real government, corporation, or any other real entity

**Code patterns to flag:**

```swift
// Swift - FLAG: Violence-related asset names
"kill_", "death_", "blood_", "gore_", "torture_", "maim_"
```

```typescript
// React Native - FLAG: Violence-related assets
import killIcon from './assets/kill_enemy.png'; // REVIEW
import deathAnimation from './assets/death.json'; // REVIEW

// FLAG: Enemy targeting specific real groups
type EnemyType = 'specificNationality' | 'specificReligion'; // REJECTION RISK
```

### 1.1.3 Weapons and Dangerous Objects

**REJECT if app:**
- [ ] Depicts content encouraging illegal or reckless use of weapons and dangerous objects
- [ ] Facilitates the purchase of firearms or ammunition

**Code patterns to flag:**

```swift
// Swift - FLAG: Weapon purchase functionality
func purchaseFirearm()
func buyAmmunition()

// FLAG: Links to weapon retailers
"gunbroker.com", "ammo.com"
```

```typescript
// React Native - FLAG: Weapon purchase functionality
const purchaseFirearm = async () => { }; // REJECTION
const buyAmmunition = async () => { }; // REJECTION

// FLAG: Links to weapon retailers
Linking.openURL('https://gunbroker.com'); // REJECTION
```

### 1.1.4 Overtly Sexual or Pornographic Material

**REJECT if app contains:**
- [ ] Explicit descriptions or displays of sexual organs or activities intended to stimulate erotic rather than aesthetic or emotional feelings
- [ ] "Hookup" apps that may include pornography
- [ ] Content that could facilitate prostitution or human trafficking/exploitation

**Code patterns to flag:**

```swift
// Swift - FLAG: Adult content indicators
"nsfw", "adult_content", "explicit", "xxx"

// FLAG: Dating/hookup functionality without moderation
func matchUsers() // Ensure proper moderation exists
```

```typescript
// React Native - FLAG: Adult content indicators
const isNSFW = true; // REVIEW
const contentRating = 'explicit'; // REVIEW

// FLAG: Dating/hookup functionality without moderation
const matchUsers = async () => { }; // Ensure moderation exists
```

### 1.1.5 Inflammatory Religious Commentary

**REJECT if app contains:**
- [ ] Inflammatory religious commentary
- [ ] Inaccurate or misleading quotations of religious texts

### 1.1.6 False Information and Features

**REJECT if app:**
- [ ] Provides inaccurate device data
- [ ] Contains trick/joke functionality (e.g., fake location trackers)
- [ ] Enables anonymous or prank phone calls or SMS/MMS messaging

**Note:** Stating "for entertainment purposes" does NOT overcome this guideline.

**Code patterns to flag:**

```swift
// Swift - FLAG: Fake device data
func getFakeLocation() -> CLLocation // REJECTION
func spoofDeviceID() -> String // REJECTION

// FLAG: Prank call/SMS functionality
func makeAnonymousCall() // REJECTION
func sendPrankSMS() // REJECTION
```

```typescript
// React Native - FLAG: Fake device data
const getFakeLocation = (): Location => { }; // REJECTION
const spoofDeviceID = (): string => { }; // REJECTION

// FLAG: Using react-native-device-info to spoof
import DeviceInfo from 'react-native-device-info';
const fakeId = 'spoofed-id'; // Don't return fake data

// FLAG: Prank functionality
const makeAnonymousCall = () => { }; // REJECTION
const sendPrankSMS = () => { }; // REJECTION
```

### 1.1.7 Harmful Concepts Exploiting Current Events

**REJECT if app:**
- [ ] Capitalizes or seeks to profit on violent conflicts
- [ ] Exploits terrorist attacks
- [ ] Exploits epidemics
- [ ] Contains other harmful concepts capitalizing on recent or current events

---

## 1.2 User-Generated Content

Apps with user-generated content present particular challenges, ranging from intellectual property infringement to anonymous bullying. To prevent abuse, apps with UGC or social networking services MUST include:

### Required UGC Features (ALL MANDATORY)

- [ ] **Content Filtering:** A method for filtering objectionable material from being posted
- [ ] **Reporting Mechanism:** A way to report offensive content with timely responses
- [ ] **User Blocking:** The ability to block abusive users from the service
- [ ] **Contact Information:** Published contact information so users can easily reach you

**Swift implementation:**
```swift
// REQUIRED: Content filtering
protocol ContentFilter {
    func filterContent(_ content: String) -> FilterResult
    func moderateImage(_ image: UIImage) -> ModerationResult
}

// REQUIRED: Report mechanism
func reportContent(
    contentId: String,
    reason: ReportReason,
    additionalInfo: String?
) async throws

// REQUIRED: Block user
func blockUser(_ userId: String) async throws
func getBlockedUsers() -> [User]

// REQUIRED: Support contact
var supportEmail: String { get }
var supportURL: URL { get }
```

**React Native implementation:**
```typescript
// REQUIRED: Content filtering
interface ContentFilter {
  filterContent(content: string): Promise<FilterResult>;
  moderateImage(imageUri: string): Promise<ModerationResult>;
}

// Example using a moderation API
const filterContent = async (content: string): Promise<FilterResult> => {
  // Use a service like OpenAI Moderation, Perspective API, or custom ML
  const response = await fetch('https://api.example.com/moderate', {
    method: 'POST',
    body: JSON.stringify({ content }),
  });
  return response.json();
};

// REQUIRED: Report mechanism
const reportContent = async (
  contentId: string,
  reason: ReportReason,
  additionalInfo?: string
): Promise<void> => {
  await api.post('/reports', { contentId, reason, additionalInfo });
};

// REQUIRED: Block user
const blockUser = async (userId: string): Promise<void> => {
  await api.post(`/users/${userId}/block`);
};

const getBlockedUsers = async (): Promise<User[]> => {
  return api.get('/users/blocked');
};

// REQUIRED: Support contact - expose in app
const SUPPORT_EMAIL = 'support@example.com';
const SUPPORT_URL = 'https://example.com/support';
```

### Content That Results in Removal

Apps primarily used for the following will be removed WITHOUT notice:
- Pornographic content
- Chatroulette-style experiences
- Random or anonymous chat
- Objectification of real people (e.g., "hot-or-not" voting)
- Making physical threats
- Bullying

### Incidental Mature "NSFW" Content

If your app includes user-generated content from a web-based service:
- [ ] Mature content MUST be hidden by default
- [ ] Only displayed when user explicitly enables it via your website

```typescript
// React Native - REQUIRED: NSFW content hidden by default
const [showMatureContent, setShowMatureContent] = useState(false);

// Must be enabled via the developer's website, not an in-app toggle
// Check user preference from backend (set via website)
useEffect(() => {
  const checkMatureContentSetting = async () => {
    const setting = await api.get('/user/settings/mature-content');
    setShowMatureContent(setting.enabled); // Set via website only
  };
  checkMatureContentSetting();
}, []);
```

### Developer Responsibility for Violating UGC

Apple's current 1.2 language makes the developer responsible for removing content that violates the guideline, the app's terms of service, or community standards. If Apple finds violating content, expect to remove it and explain how compliance will improve.

- [ ] Violating content must be removable quickly when detected or reported
- [ ] App Review may require a concrete compliance improvement plan before the app can stay on the App Store
- [ ] Egregious or repeated UGC failures can trigger immediate app removal and Developer Program removal

**Review for:**
- [ ] Admin/moderator tooling that can remove posts, comments, profiles, messages, media, and creator content
- [ ] Abuse queues or dashboards with timestamps, severity, status, and reviewer actions
- [ ] Escalation paths for threats, bullying, sexual content, child safety issues, and repeat offenders
- [ ] Audit logs that can support an App Review response or remediation plan
- [ ] Clear terms/community standards surfaced to users and enforced consistently

```typescript
// React Native/backend contract - REQUIRED for UGC apps
type ModerationStatus = 'pending' | 'actioned' | 'dismissed' | 'escalated';

interface ModerationAction {
  reportId: string;
  contentId: string;
  action: 'remove_content' | 'suspend_user' | 'age_restrict' | 'dismiss';
  reason: string;
  status: ModerationStatus;
}

const removeViolatingContent = async (action: ModerationAction): Promise<void> => {
  await api.post('/moderation/actions', action);
};
```

### 1.2.1 Creator Content

Creator experiences are not native "apps" coded by developers — they are content within the app itself and are treated as user-generated content by App Review.

Apps featuring content from "creators" must:
- [ ] Properly moderate content per Guideline 1.2
- [ ] Follow payment guidelines per 3.1.1
- [ ] Communicate which content requires additional purchases
- [ ] Not change core features/functionality of native app

#### 1.2.1(a) Age Rating and Access Restrictions

- [ ] Provide way for users to identify content exceeding app's age rating
- [ ] Use age restriction mechanism based on verified or declared age
- [ ] Limit access by underage users to age-inappropriate content

---

## 1.3 Kids Category

If participating in Kids Category, you MUST follow these rules:

### Core Requirements

- [ ] No links out of app unless behind parental gate
- [ ] No purchasing opportunities unless behind parental gate
- [ ] No other distractions to kids unless behind parental gate
- [ ] Must continue meeting Kids Category requirements in all future updates — EVEN if you later deselect the category (once customers expect it, it sticks)

**Swift parental gate:**
```swift
// REQUIRED: Parental gate for Kids apps
class ParentalGate {
    // Must require adult verification - examples:
    // - Math problem (e.g., "What is 15 + 27?")
    // - Written instructions to have parent complete
    // NOTE: simple date-of-birth/age entry is trivially bypassable
    // and is a known rejection pattern — don't use it as the gate

    func presentGate(completion: @escaping (Bool) -> Void) {
        // Implementation must be non-trivial for children
    }
}

// REQUIRED: Gate before external links
func openExternalLink(_ url: URL) {
    parentalGate.presentGate { verified in
        if verified {
            UIApplication.shared.open(url)
        }
    }
}

// REQUIRED: Gate before purchases (StoreKit 2)
func initiatePurchase(_ product: Product) {
    parentalGate.presentGate { verified in
        if verified {
            Task { try await product.purchase() }
        }
    }
}
```

**React Native parental gate:**
```typescript
// REQUIRED: Parental gate for Kids apps
import { Linking } from 'react-native';

interface ParentalGateProps {
  onVerified: () => void;
  onCancelled: () => void;
}

const ParentalGate: React.FC<ParentalGateProps> = ({ onVerified, onCancelled }) => {
  const [answer, setAnswer] = useState('');

  // Must be non-trivial for children
  const correctAnswer = 15 + 27; // = 42

  const verify = () => {
    if (parseInt(answer) === correctAnswer) {
      onVerified();
    }
  };

  return (
    <Modal>
      <Text>For grown-ups only!</Text>
      <Text>What is 15 + 27?</Text>
      <TextInput
        keyboardType="numeric"
        value={answer}
        onChangeText={setAnswer}
      />
      <Button title="Submit" onPress={verify} />
      <Button title="Cancel" onPress={onCancelled} />
    </Modal>
  );
};

// REQUIRED: Gate before external links
const openExternalLink = async (url: string) => {
  const verified = await showParentalGate();
  if (verified) {
    Linking.openURL(url);
  }
};

// REQUIRED: Gate before purchases (using react-native-iap)
import * as IAP from 'react-native-iap';

const initiatePurchase = async (sku: string) => {
  const verified = await showParentalGate();
  if (verified) {
    await IAP.requestPurchase({ sku });
  }
};
```

### Privacy Requirements for Kids Category

- [ ] Comply with COPPA, GDPR, and all applicable children's privacy laws
- [ ] May NOT send personally identifiable information to third parties
- [ ] May NOT send device information to third parties
- [ ] Should NOT include third-party analytics (safer experience)
- [ ] Should NOT include third-party advertising (safer experience)

```typescript
// React Native - Kids Category: Remove these packages
// ❌ @react-native-firebase/analytics
// ❌ react-native-facebook-sdk
// ❌ @segment/analytics-react-native
// ❌ react-native-appsflyer
// ❌ Any advertising SDK

// ❌ BAD: Third-party analytics in Kids app
import analytics from '@react-native-firebase/analytics';
analytics().logEvent('screen_view'); // REJECTION for Kids Category

// ✅ GOOD: No third-party analytics, or use compliant ones only
// If analytics needed, must not collect IDFA, PII, location, or device info
```

### Limited Exceptions for Analytics/Advertising

Third-party analytics MAY be permitted if services:
- [ ] Do NOT collect or transmit IDFA
- [ ] Do NOT collect identifiable information (name, DOB, email)
- [ ] Do NOT use location
- [ ] Do NOT collect any device, network, or other information that could be used directly — or combined with other information — to identify users and their devices

Third-party contextual advertising MAY be permitted if services:
- [ ] Have publicly documented practices for Kids Category apps
- [ ] Include human review of ad creatives for age appropriateness

---

## 1.4 Physical Harm

### 1.4.1 Medical Apps

Medical apps providing data or information for diagnosis/treatment are reviewed with greater scrutiny.

**Requirements:**
- [ ] Clearly disclose data and methodology supporting accuracy claims
- [ ] If accuracy/methodology cannot be validated, app will be REJECTED
- [ ] Remind users to check with doctor before making medical decisions
- [ ] Submit regulatory clearance documentation if received

**Apps NOT permitted (claiming to use only device sensors for):**
- X-rays
- Blood pressure measurement
- Body temperature measurement
- Blood glucose measurement
- Blood oxygen measurement

**Code patterns to flag:**

```swift
// Swift - FLAG: Medical measurement claims
func measureBloodPressure() // REJECTION without proper hardware
func measureBloodGlucose()  // REJECTION without proper hardware
func measureBloodOxygen()   // REJECTION without proper hardware
func measureTemperature()   // REJECTION without proper hardware

// REQUIRED: Medical disclaimer
let medicalDisclaimer = """
This app is not intended to diagnose, treat, cure, or prevent any disease.
Always consult with a qualified healthcare provider before making medical decisions.
"""
```

```typescript
// React Native - FLAG: Medical measurement claims
const measureBloodPressure = async () => { }; // REJECTION without hardware
const measureBloodGlucose = async () => { };  // REJECTION without hardware
const measureBloodOxygen = async () => { };   // REJECTION without hardware
const measureTemperature = async () => { };   // REJECTION without hardware

// REQUIRED: Medical disclaimer
const MEDICAL_DISCLAIMER = `
This app is not intended to diagnose, treat, cure, or prevent any disease.
Always consult with a qualified healthcare provider before making medical decisions.
`;

// Display on first launch and in settings
const MedicalDisclaimer: React.FC = () => (
  <View>
    <Text>{MEDICAL_DISCLAIMER}</Text>
    <Button title="I Understand" onPress={acceptDisclaimer} />
  </View>
);
```

### 1.4.2 Drug Dosage Calculators

Drug dosage calculators MUST come from:
- [ ] The drug manufacturer, OR
- [ ] A hospital, OR
- [ ] A university, OR
- [ ] A health insurance company, OR
- [ ] A pharmacy, OR
- [ ] Another approved entity, OR
- [ ] Have FDA approval (or international equivalent)

Given the potential harm to patients, Apple needs to be sure the app will be supported and updated over the long term.

### 1.4.3 Substance Consumption

**NOT permitted:**
- [ ] Apps encouraging tobacco consumption
- [ ] Apps encouraging vape product consumption
- [ ] Apps encouraging illegal drug use
- [ ] Apps encouraging excessive alcohol consumption
- [ ] Apps encouraging minors to consume any of these substances
- [ ] Facilitating sale of controlled substances (except licensed pharmacies and licensed or otherwise legal cannabis dispensaries)
- [ ] Facilitating sale of tobacco

**Code patterns to flag:**

```swift
// Swift - FLAG: Substance promotion
"tobacco", "vaping", "drug_use", "alcohol_challenge"

// FLAG: Substance purchase (unless licensed pharmacy)
func purchaseControlledSubstance() // REJECTION unless licensed
```

```typescript
// React Native - FLAG: Substance promotion
const features = ['tobacco_tracker', 'vaping_counter']; // REJECTION
const alcoholChallenge = () => { }; // REJECTION

// FLAG: Substance purchase
const purchaseControlledSubstance = async () => { }; // REJECTION unless licensed
```

### 1.4.4 DUI Checkpoints

- [ ] May ONLY display DUI checkpoints published by law enforcement agencies
- [ ] Must NEVER encourage drunk driving or reckless behavior

### 1.4.5 Physical Harm Activities

- [ ] Must NOT urge customers to participate in activities risking physical harm (bets, challenges)
- [ ] Must NOT urge customers to use devices in ways risking physical harm

---

## 1.5 Developer Information

### Requirements

- [ ] App and Support URL must include easy way to contact you
- [ ] Failure to include accurate, up-to-date contact information may violate law
- [ ] Particularly important for apps used in classrooms

### Wallet Passes

- [ ] Must include valid contact information from issuer
- [ ] Must be signed with dedicated certificate assigned to brand/trademark owner

---

## 1.6 Data Security

- [ ] Implement appropriate security measures for handling user information collected pursuant to the Developer Program License Agreement and these Guidelines (see Guideline 5.1 / rules/5-legal.md)
- [ ] Prevent unauthorized use, disclosure, or access by third parties

**Swift implementation:**
```swift
// REQUIRED: Secure data storage
import Security

class SecureStorage {
    // Use Keychain for sensitive data
    func storeCredential(_ credential: String, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: credential.data(using: .utf8)!
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
}

// REQUIRED: HTTPS for network communications
let configuration = URLSessionConfiguration.default
configuration.tlsMinimumSupportedProtocolVersion = .TLSv12

// BAD: Hardcoded secrets
let apiKey = "sk_live_xxxxx" // NEVER DO THIS
let password = "admin123"    // NEVER DO THIS

// GOOD: Environment/secure storage
let apiKey = ProcessInfo.processInfo.environment["API_KEY"]
let apiKey = try SecureStorage.shared.retrieveCredential(for: "api_key")
```

**React Native implementation:**
```typescript
// REQUIRED: Secure data storage
import * as Keychain from 'react-native-keychain';
import EncryptedStorage from 'react-native-encrypted-storage';

// Use Keychain for credentials
const storeCredential = async (key: string, value: string) => {
  await Keychain.setGenericPassword(key, value);
};

const getCredential = async (key: string) => {
  const credentials = await Keychain.getGenericPassword();
  return credentials ? credentials.password : null;
};

// Use EncryptedStorage for other sensitive data
const storeSecureData = async (key: string, value: string) => {
  await EncryptedStorage.setItem(key, value);
};

// ❌ BAD: Hardcoded secrets
const API_KEY = 'sk_live_xxxxx'; // NEVER DO THIS
const PASSWORD = 'admin123';     // NEVER DO THIS

// ❌ BAD: Secrets in JavaScript bundle
// .env files get bundled into JS — and react-native-config also embeds
// values into the app where they are extractable; it is NOT a secret store

// ✅ GOOD: Fetch secrets from secure backend
const getApiKey = async () => {
  const response = await secureApi.get('/config/api-key');
  return response.data.key;
};

// REQUIRED: HTTPS for all network requests
// Ensure no HTTP endpoints in your app
// Check fetch() calls, axios baseURL, etc.
const api = axios.create({
  baseURL: 'https://api.example.com', // Must be HTTPS
});

// Enable SSL pinning for sensitive apps
import { fetch } from 'react-native-ssl-pinning';
```

---

## 1.7 Reporting Criminal Activity

- [ ] Apps for reporting alleged criminal activity MUST involve local law enforcement
- [ ] Can ONLY be offered in countries/regions where such involvement is active

---

## React Native Packages Reference

| Guideline | Expo Package | Bare RN Package |
|-----------|-------------|-----------------|
| UGC Moderation | Custom API integration | Custom API integration |
| Parental Gate | Custom implementation | Custom implementation |
| Kids Analytics | ❌ Remove all analytics | ❌ Remove all analytics |
| Secure Storage | `expo-secure-store` | `react-native-keychain` |
| SSL Pinning | - | `react-native-ssl-pinning` |
| Linking | `expo-linking` | `react-native` Linking |
| IAP (with parental gate) | `react-native-purchases` (RevenueCat, dev build) | `react-native-purchases` (RevenueCat) or `react-native-iap` |
