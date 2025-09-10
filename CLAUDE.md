# Claude Instructions for Squirrel2 Development

## 🚨 CRITICAL: Architecture Rules

### ALWAYS Use Backend API
- **NEVER** access Firebase/Firestore directly from iOS for data operations
- **ALWAYS** use the Node.js backend API at `https://backend-sigma-drab.vercel.app`
- **CHECK** if a backend endpoint exists before implementing any feature
- **CREATE** new backend endpoints when needed rather than direct database access

### Backend-First Development
When implementing any feature that involves data:
1. First check `/backend/src/routes/` for existing endpoints
2. If endpoint doesn't exist, create it in the backend
3. Test the endpoint with proper authentication
4. Only then implement the iOS client code

### Correct Pattern
```swift
// ✅ CORRECT - Use backend API
// ⚠️ IMPORTANT: AppConfig.apiBaseURL already includes "/api" prefix!
let token = try await user.getIDToken()
guard let url = URL(string: "\(AppConfig.apiBaseURL)/collections") else { return }
// This creates: https://backend-sigma-drab.vercel.app/api/collections
var request = URLRequest(url: url)
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
// ... make request
```

### Common Mistakes to Avoid
```swift
// ❌ WRONG - This creates /api/api/collections (double /api)
URL(string: "\(AppConfig.apiBaseURL)/api/collections")

// ✅ CORRECT - apiBaseURL already has /api
URL(string: "\(AppConfig.apiBaseURL)/collections")

// ❌ NEVER DO THIS - Direct Firestore access
db.collection("anything").document(id).setData(data)
```

## Project Structure

```
Squirrel2/
├── backend/                 # Node.js backend (Vercel)
│   ├── src/
│   │   ├── routes/         # API endpoints - CHECK HERE FIRST
│   │   ├── models/         # Data models
│   │   └── middleware/     # Auth & validation
│   └── api/               # Vercel deployment
├── Squirrel2/             # iOS app
│   ├── Models/
│   ├── Views/
│   ├── Services/
│   └── Config/
└── docs/
```

## Available Backend Endpoints

See `BACKEND_API_GUIDELINES.md` for full list. Key endpoints:
- `/api/conversations` - Conversation management
- `/api/messages` - Message operations
- `/api/tasks` - Task management
- `/api/spaces` - Space operations
- `/api/config/openai-key` - Configuration

## Testing & Building

**IMPORTANT**: Do NOT attempt to build the iOS app yourself. The user will handle building and will report any build errors that need to be fixed.

For backend changes:
```bash
# IMPORTANT: Commit and push changes first so Vercel deploys the latest code!
git add .
git commit -m "Backend updates"
git push

# Then deploy to Vercel
cd backend && vercel --prod
```

⚠️ **CRITICAL**: Vercel deploys from the Git repository, not local files. Always commit and push before running `vercel --prod` or your changes won't be deployed!

## Key Principles

1. **Security First**: All data operations go through authenticated backend
2. **Single Source of Truth**: Backend handles all business logic
3. **Consistency**: Use existing patterns from the codebase
4. **API Documentation**: Check backend route files for endpoint details

## When Working on Features

1. **Read** `BACKEND_API_GUIDELINES.md` first
2. **Check** backend routes for existing endpoints
3. **Create** backend endpoints if needed
4. **Implement** iOS code using backend API
5. **Never** write direct Firestore operations in iOS

## Remember

> "The backend is the brain, iOS is just the UI"

All data operations, validation, and business logic belong in the backend.