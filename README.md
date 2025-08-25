# Squirrel 2.0

A modern iOS application built with SwiftUI, Node.js backend, and Firebase integration.

## Project Structure

```
Squirrel2/
├── Squirrel2/           # iOS app (SwiftUI)
│   ├── Squirrel2.xcodeproj
│   └── Squirrel2/       # App source files
├── backend/             # Node.js backend
├── firebase.json        # Firebase configuration
└── firestore.rules      # Firestore security rules
```

## Features

- **iOS App**: Native SwiftUI application
- **Backend API**: Node.js/Express REST API
- **Firebase Integration**: Authentication, Firestore, and Storage
- **Real-time Updates**: Live data synchronization
- **Secure**: Firebase security rules and backend authentication

## Setup Instructions

### Prerequisites

- Xcode 14+ 
- Node.js 18+
- CocoaPods
- Firebase CLI
- Git

### iOS Setup

1. Open the Xcode project:
```bash
cd Squirrel2
open Squirrel2.xcodeproj
```

2. Add Firebase to your iOS app:
   - In Xcode, go to File → Add Package Dependencies
   - Add `https://github.com/firebase/firebase-ios-sdk`
   - Select the Firebase products you need (Auth, Firestore, Storage, etc.)

3. Add your `GoogleService-Info.plist` file:
   - Download from Firebase Console
   - Drag into Xcode project navigator
   - Ensure it's added to the Squirrel2 target

### Backend Setup

1. Navigate to backend directory:
```bash
cd backend
```

2. Install dependencies:
```bash
npm install
```

3. Create `.env` file from example:
```bash
cp .env.example .env
```

4. Add your Firebase service account credentials to `.env`

5. Start development server:
```bash
npm run dev
```

### Firebase Setup

1. Install Firebase CLI:
```bash
npm install -g firebase-tools
```

2. Login to Firebase:
```bash
firebase login
```

3. Initialize Firebase project:
```bash
firebase init
```

4. Deploy Firebase rules:
```bash
firebase deploy --only firestore:rules,storage:rules
```

## Development

### iOS Development
- Open `Squirrel2.xcodeproj` in Xcode
- Build and run on simulator or device (⌘+R)

### Backend Development
```bash
cd backend
npm run dev  # Start with nodemon for auto-reload
```

### Firebase Emulators
```bash
firebase emulators:start
```

## API Endpoints

- `GET /` - API status
- `GET /api/status` - API health check
- `POST /auth/verify` - Verify Firebase ID token
- `GET /api/user/:id` - Get user data (authenticated)
- `POST /api/data` - Submit data (authenticated)

## Technologies

- **Frontend**: SwiftUI, Firebase iOS SDK
- **Backend**: Node.js, Express, Firebase Admin SDK
- **Database**: Cloud Firestore
- **Authentication**: Firebase Auth
- **Storage**: Firebase Storage
- **Hosting**: Firebase Hosting

## License

MIT