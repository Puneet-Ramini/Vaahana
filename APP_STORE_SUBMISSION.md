# Vaahana — App Store Submission Guide

Everything Apple will ask, answered for Vaahana. Fill this into App Store Connect exactly as written. Keep this file updated if anything in the app changes before submission.

---

## 1. App Information

| Field | Value |
|---|---|
| **App Name** | Vaahana |
| **Subtitle** | Rides between neighbors |
| **Bundle ID** | *(match Xcode — e.g. `com.vaahana.app`)* |
| **SKU** | `VAAHANA-IOS-V1` |
| **Primary Category** | Travel |
| **Secondary Category** | Lifestyle |
| **Copyright** | © 2026 Vaahana |

### Description (4,000 char max)

```
Vaahana is a community carpool for people who already trust each other — 
neighbors, classmates, and members of the South Asian diaspora going the same way.

HOW IT WORKS

For riders:
Post a ride request with your pickup location, destination, date and time. 
Nearby drivers see your request and can claim it instantly. You get a match 
without surge pricing, background checks handled within your community.

For drivers:
Browse ride requests near you on a live map. See pickup and drop-off before 
you commit. Claim a ride in one tap — no bidding, no waiting.

BUILT DIFFERENT

• No surge pricing. Ever.
• No strangers — rides stay within your community.
• Simple: post a request, get a match, coordinate directly by phone.
• Location used only while the app is open. Never in the background.
• Free to use for v1.

Vaahana started because every South Asian kid has begged their cousin for an 
airport drop. We turned that favor economy into an app. Built for the diaspora, 
open to everyone going the same way.

Active in campus communities across NJ, MA, TX and CA.
```

### Keywords (100 char max)

```
carpool,rideshare,community,diaspora,campus,rides,neighbors,driver,pickup,route
```

### Promotional Text (170 char max — can be updated without a new build)

```
Community carpooling for people who already trust each other. No surge pricing. No strangers. Just neighbors going the same way.
```

### Support URL

```
https://vaahana.app/contact
```

### Marketing URL

```
https://vaahana.app
```

### Privacy Policy URL

```
https://vaahana.app/contact  (update this to a dedicated /privacy page before launch)
```

---

## 2. Age Rating Questionnaire

Answer every question **exactly** as below. Vaahana is a carpool app with no violent, sexual, or mature content.

| Question | Answer |
|---|---|
| Alcohol, Tobacco, or Drug Use or References | **None** |
| Gambling and Contests | **None** |
| Sexual Content or Nudity | **None** |
| Violence | **None** |
| Realistic Violence | **None** |
| Horror/Fear Themes | **None** |
| Mature/Suggestive Themes | **None** |
| Medical/Treatment Information | **None** |
| User-Generated Content | **None** — riders post ride requests (pickup, destination, time). No freeform social content, no photos, no public messages |
| Unrestricted Web Access | **No** |
| In-App Purchases | **No** |
| Advertising | **No** |

**Expected rating: 4+**

> **Note:** Although riders and drivers communicate directly by phone after matching, that contact happens outside the app (Phone/WhatsApp). There is no in-app chat. Do not check "chat" or "social networking" — the app does not have those features.

---

## 3. Privacy Nutrition Labels

Go to **App Privacy → Data Types** in App Store Connect. Declare each type below.

### Data collected and linked to identity

| Data Type | Category | Linked to Identity | Used for Tracking | Purpose |
|---|---|---|---|---|
| Email Address | Contact Info | ✅ Yes | ❌ No | App Functionality |
| Phone Number | Contact Info | ✅ Yes | ❌ No | App Functionality |
| Name | Contact Info | ✅ Yes | ❌ No | App Functionality |
| Device ID | Identifiers | ✅ Yes | ❌ No | App Functionality (Firebase) |

### Data collected but NOT linked to identity

| Data Type | Category | Linked to Identity | Used for Tracking | Purpose |
|---|---|---|---|---|
| Precise Location | Location | ❌ No | ❌ No | App Functionality (show nearby rides) |

### Data NOT collected (leave unchecked)

Health & Fitness, Financial Info, Sensitive Info, Contacts, User Content, Browsing History, Search History, Purchases, Usage Data, Diagnostics, Other Data.

### Privacy Tracking

**"Do you track users?"** → **No**

**Tracking domains:** None

---

## 4. Export Compliance (Encryption)

| Question | Answer |
|---|---|
| Does your app use encryption? | **Yes** |
| Is the encryption solely for the purpose of protecting the integrity of app data or is it used for authentication? | **Yes — standard HTTPS/TLS only** |
| Does your app qualify for an exemption? | **Yes** |
| Exemption reason | App uses only standard encryption built into the OS (HTTPS via Firebase SDK, Firebase Auth). No proprietary or non-standard encryption algorithms are implemented. |

**Recommended:** Add to `Info.plist` to skip the question on every future build:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

> This is correct because all encryption is via Apple's built-in TLS/HTTPS stack through Firebase SDKs — no custom crypto.

---

## 5. App Review Information

### Demo Account

Apple reviewers **must** be able to log in and see the full app. Create a dedicated reviewer account before submission:

| Field | Value |
|---|---|
| **Email** | `reviewer@vaahana.app` *(create this account in the app before submitting)* |
| **Password** | *(set a strong password, enter it here)* |

### Notes for Reviewer

```
Vaahana is a community carpool app. Here's how to review it:

SIGN IN
Use the demo credentials above. The account is pre-configured as a rider.

RIDER FLOW
1. Open the app — you'll land on the Rides tab showing community ride requests.
2. Tap "Post a Ride Request" (blue button at the bottom) to post a new request.
3. Fill in From, To, pickup date/time, your name and phone number.
4. Tap Submit — your request will appear in the feed.

DRIVER FLOW
1. Tap the Map tab to see ride pins near a location.
2. Tap any ride card to see details and the "Accept Ride" button.
   (Note: you cannot accept your own ride — use a second account or 
    tap any other ride in the feed to see the full driver UI.)

SETTINGS
Tap the Settings tab to see and edit your profile.
Tap "About & Contact" at the bottom of Settings to see the contact/info page.

FEATURE FLAGS
WhatsApp integration and post-ride ratings are intentionally disabled 
in this version (v1 feature flags). These features exist in the codebase 
and will be enabled in a future update.

LOCATION
The app requests location permission on first use to show nearby rides.
Please allow location access when prompted to see the full experience.

No third-party accounts, hardware, or special setup required.
```

### Contact Information

| Field | Value |
|---|---|
| **First Name** | *(your name)* |
| **Last Name** | *(your name)* |
| **Phone** | *(your phone number — Apple may call)* |
| **Email** | hello@vaahana.app |

---

## 6. Pricing & Availability

| Field | Value |
|---|---|
| **Price** | Free |
| **Availability** | United States (start here; expand to Canada/UK/India after v1 is stable) |
| **Release** | Manually release after approval (do not auto-release) |
| **In-App Purchases** | None |

---

## 7. Screenshots Required

Apple requires screenshots for every device size you support. Minimum required sets:

| Device | Dimensions |
|---|---|
| iPhone 6.9" (iPhone 16 Pro Max) | 1320 × 2868 px |
| iPhone 6.5" (iPhone 14 Plus / 15 Plus) | 1242 × 2688 px |
| iPad Pro 13" (if supporting iPad) | 2048 × 2732 px |

**Screens to capture:**

1. **Rides tab** — community feed with a few ride cards visible
2. **Post a Ride** sheet — form filled out with example data
3. **Ride Detail** — tapped into a ride, driver action buttons visible
4. **Map tab** — map with ride pins
5. **Settings tab** — profile screen

> Tip: Use the iOS Simulator at the correct device size and take screenshots with ⌘+S. Do not use placeholder images or marketing mockups — Apple wants real app screens.

---

## 8. Pre-Submission Checklist

Before you hit Submit for Review, confirm every item below:

### Technical
- [ ] `PrivacyInfo.xcprivacy` is in the app bundle (✅ already added)
- [ ] `NSLocationWhenInUseUsageDescription` is in Info.plist (✅ already added)
- [ ] `ITSAppUsesNonExemptEncryption = false` added to Info.plist
- [ ] Build is archived in Xcode with **Release** configuration
- [ ] Version number and build number are set correctly (e.g. 1.0, build 1)
- [ ] Build uploaded via Xcode → Product → Archive → Distribute

### Content
- [ ] Demo reviewer account created and tested (can log in, post ride, see feed)
- [ ] Privacy Policy URL is live and reachable
- [ ] Support URL (`vaahana.app/contact`) is live (✅ already deployed)
- [ ] All screenshots captured at correct resolutions
- [ ] App description spell-checked

### Legal
- [ ] Privacy Nutrition Labels filled in exactly as in Section 3 above
- [ ] Age rating answered as in Section 2 above (should resolve to 4+)
- [ ] Encryption compliance answered (Section 4)

---

## 9. Common Rejection Reasons to Pre-empt

| Risk | How Vaahana is covered |
|---|---|
| **2.1 — App Completeness** | All flows work end-to-end. Demo account provided. |
| **5.1.1 — Data Collection** | PrivacyInfo.xcprivacy present; nutrition labels match actual collection |
| **5.1.2 — Data Use** | Location used only while app is open; no background location |
| **4.0 — Design** | No placeholder screens, no "coming soon" features surfaced to users (WhatsApp/ratings gated by feature flags, not shown as broken) |
| **2.5.4 — Background Services** | No background location, no background modes declared |
| **3.1.1 — Payments** | No payments, no in-app purchases — no mention of money in UI |
| **1.2 — User-generated Content** | Ride posts (pickup/destination/time) are functional data, not social content. No moderation requirement applies. |

---

*Last updated: June 2026. Update this document if app features change before the next submission.*
