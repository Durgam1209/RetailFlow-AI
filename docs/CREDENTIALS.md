# Firebase and Generated Configuration

`murali_fruits_ml/lib/firebase_options.dart` and `murali_fruits_ml/android/app/google-services.json` contain Firebase client configuration: project/app identifiers and client API keys intended to be present in a distributed app. Those values are not Firebase Admin credentials and do not grant administrative access by themselves. Firebase and Supabase authorization must still be enforced by provider rules and Supabase RLS.

`GoogleService-Info.plist` is not currently present. If generated for iOS, it is also Firebase client configuration and should be treated like the Android file, not like an Admin SDK credential.

Never commit Firebase service-account JSON, Admin SDK private keys, private certificates, or local environment files. Keep those in GitHub Actions Secrets or the relevant secure secret store. `.gitignore` excludes common Firebase service-account credential filenames.

The app encrypts its Hive boxes with a key stored in `flutter_secure_storage`. The package's WebCrypto backend is currently documented as experimental and requires HTTPS or localhost; the app's hosted site meets the HTTPS requirement.
