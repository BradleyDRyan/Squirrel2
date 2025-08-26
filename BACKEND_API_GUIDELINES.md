# Backend API Guidelines for Squirrel2

## 🚨 IMPORTANT: Always Use Backend API

This document outlines the critical architectural principle for the Squirrel2 application.

## Core Principle

**NEVER access Firebase/Firestore directly from the iOS app for data operations.**
**ALWAYS use the Node.js backend API for all data operations.**

## Why Backend API?

1. **Security**: Backend validates and sanitizes all data
2. **Business Logic**: Centralized rules enforcement
3. **Authentication**: Proper token validation
4. **Rate Limiting**: Protection against abuse
5. **Data Consistency**: Single source of truth for data operations
6. **Logging & Monitoring**: Centralized tracking
7. **Future Flexibility**: Easy to switch databases or add features

## Backend API Base URL

Production: `https://backend-sigma-drab.vercel.app`

## Available API Endpoints

### Authentication Required (Bearer Token)
All endpoints require Firebase ID token in Authorization header:
```
Authorization: Bearer <firebase-id-token>
```

### Core Endpoints

#### Conversations
- `GET /api/conversations` - List user's conversations
- `GET /api/conversations/:id` - Get specific conversation
- `POST /api/conversations` - Create new conversation
- `PUT /api/conversations/:id` - Update conversation
- `DELETE /api/conversations/:id` - Delete conversation
- `GET /api/conversations/:id/messages` - Get messages in conversation

#### Messages
- `GET /api/messages/:id` - Get specific message
- `POST /api/messages` - Create new message
- `PUT /api/messages/:id` - Update message
- `DELETE /api/messages/:id` - Delete message

#### Tasks
- `GET /api/tasks` - List user's tasks
- `GET /api/tasks/:id` - Get specific task
- `POST /api/tasks` - Create new task
- `PUT /api/tasks/:id` - Update task
- `DELETE /api/tasks/:id` - Delete task

#### Spaces
- `GET /api/spaces` - List user's spaces
- `GET /api/spaces/:id` - Get specific space
- `POST /api/spaces` - Create new space
- `PUT /api/spaces/:id` - Update space
- `DELETE /api/spaces/:id` - Delete space

#### Entries
- `GET /api/entries` - List user's entries
- `POST /api/entries` - Create new entry
- `PUT /api/entries/:id` - Update entry
- `DELETE /api/entries/:id` - Delete entry

#### Thoughts
- `GET /api/thoughts` - List user's thoughts
- `POST /api/thoughts` - Create new thought
- `PUT /api/thoughts/:id` - Update thought
- `DELETE /api/thoughts/:id` - Delete thought

#### Config
- `GET /api/config/openai-key` - Get OpenAI API key

#### AI/Chat
- `POST /api/ai/chat/stream` - Stream AI chat responses

## iOS Implementation Pattern

### Correct Approach ✅
```swift
// Get auth token
let token = try await user.getIDToken()

// Call backend API
guard let url = URL(string: "\(AppConfig.apiBaseURL)/messages") else { return }
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

let jsonData = try JSONSerialization.data(withJSONObject: messageData)
request.httpBody = jsonData

let (_, response) = try await URLSession.shared.data(for: request)
```

### Incorrect Approach ❌
```swift
// NEVER DO THIS - Direct Firestore access
db.collection("messages").document(message.id).setData(messageData)
```

## When to Create New Backend Endpoints

Before implementing any new feature that requires data operations:

1. **Check if endpoint exists** in backend routes
2. **Create new endpoint** if needed in appropriate route file
3. **Test endpoint** with proper authentication
4. **Then implement** iOS client code to use the endpoint

## Backend Structure

```
backend/
├── src/
│   ├── routes/        # API endpoints
│   │   ├── conversations.js
│   │   ├── messages.js
│   │   ├── tasks.js
│   │   ├── spaces.js
│   │   ├── entries.js
│   │   └── thoughts.js
│   ├── models/        # Data models
│   └── middleware/    # Auth & validation
└── api/              # Vercel deployment
```

## Development Workflow

1. **Feature Request**: User needs new functionality
2. **Backend First**: Create/verify API endpoint exists
3. **Test Endpoint**: Ensure it works with auth
4. **iOS Implementation**: Call backend API from iOS app
5. **Never**: Access Firestore directly from iOS

## Exception

The ONLY acceptable direct Firebase access from iOS:
- **Authentication operations** (sign in/out)
- **Real-time listeners** for live updates (if absolutely necessary and backend doesn't provide WebSocket/SSE alternative)

Even for real-time features, prefer backend-provided solutions when available.

## Remember

> "If you're writing `db.collection()` in iOS code for data operations, you're doing it wrong!"

Always route through the backend API for:
- Better security
- Consistent business logic
- Proper validation
- Centralized control