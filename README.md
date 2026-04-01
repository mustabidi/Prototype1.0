# Community Support Platform

A fast, resilient, and safe hyper-local community platform built for production scale. The app empowers users to seek local help, share community updates, and discover verified local businesses—all prioritized by geography and real-time community engagement.

## 🚀 Key Features

*   **Geolocated Real-time Feeds:** Browse posts specific to your immediate dynamic radius (Local), your wider city (City), or nationwide (India).
*   **Intelligent Ranking Algorithms:** Posts aren't just chronological. They are ranked based on a composite score of author trust (+0.2 boosts per upvote), urgency level, and rapid decay algorithms.
*   **Fully-Automated Moderation System:** Built-in community safety. Any post receiving 5 unique user reports is instantly hidden from all feeds via Cloud Functions, protecting the platform 24/7.
*   **Trust Scoring:** Users hold an internal `trustScore` [0.0 - 10.0]. Spammers are penalized automatically, preventing systemic abuse from malicious actors.
*   **Native "Block User" Controls:** Fully compliant with Apple App Store UGC guidelines (Guideline 1.2), allowing users to curate their feeds instantly.
*   **Topic-Based Push Notifications:** Intelligent background notification routing via Firebase Cloud Messaging. If an urgent 'Help' request drops in a user's 5km geohash radius or city, they are alerted—with built-in anti-spam throttling maxing out at 3/hour.
*   **Curated Business Directory:** A zero-friction place to list and discover vital local services (Pharmacies, Plumbers, Medical) segmented tightly by specific areas. 

## 🛠 Tech Stack

*   **Frontend:** Flutter SDK
*   **State Management & Routing:** Riverpod (`flutter_riverpod`), GoRouter (`go_router`)
*   **Backend as a Service:** Firebase (Auth, Cloud Firestore, Cloud Storage, Crashlytics)
*   **Location Services:** `geolocator`, `geoflutterfire2`
*   **Cloud Run / Backend Logic:** Firebase Cloud Functions (Node.js)
*   **CI/CD:** GitHub Actions (Automated release Android APK builds)

## 🛡 Security Highlights
We follow strict "Zero Trust" client architectures:
*   Users can *never* edit their own `trustScore` directly.
*   Community votes, scores, and global stats collections are locked strictly behind Server-Side logic (`functions/index.js`).
*   Client feeds process strict conditional reads backed by exact multidimensional composite indexes (`firestore.indexes.json`).

## 📦 Setting up the project locally
1. Clone the repository.
2. Ensure you have the Flutter SDK initialized. 
3. Run `flutter pub get`
4. Deploy the mandatory Firestore Indexes and rules to your Firebase environment:
   ```bash
   firebase deploy --only firestore,functions
   ```
5. Build and run the app:
   ```bash
   flutter run
   ```
