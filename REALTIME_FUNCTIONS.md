# OpenAI Realtime API Function Calling Implementation

## Overview
This document outlines the implementation of function calling capabilities for the Squirrel2 iOS app using OpenAI's Realtime API. The system allows users to create and manage tasks through voice commands, with the tasks being stored in Firebase Firestore.

## Current Implementation Status

### ✅ Completed Components

1. **RealtimeFunctions.swift** (`/Squirrel2/Squirrel2/Models/RealtimeFunctions.swift`)
   - Defines available functions for task management
   - Contains the `VoiceTask` model for Firebase storage
   - Implements `RealtimeFunctionHandler` for executing functions

2. **VoiceAIManager Updates** (`/Squirrel2/Squirrel2/Models/VoiceAIManager.swift`)
   - Added `functionHandler` property to handle function calls
   - Created `configureSession()` method to set up tools/functions
   - Added `observeFunctionCalls()` placeholder for monitoring function call events

3. **Firebase Integration**
   - Tasks are stored in Firestore under the `tasks` collection
   - Each task is associated with the authenticated user's ID
   - Task model includes: id, title, dueDate, priority, completed status, createdAt, userId

### 🔧 Available Functions

1. **create_task**
   - Creates a new task/reminder in Firebase
   - Parameters: title (required), dueDate (optional), priority (optional: low/medium/high)
   - Example: "Create a reminder to pick up the kids at 3 PM"

2. **list_tasks**
   - Lists all tasks with optional filters
   - Parameters: filter (optional: all/pending/completed/today)
   - Example: "Show me my tasks for today"

3. **complete_task**
   - Marks a task as completed
   - Parameters: taskId or taskTitle
   - Example: "Mark the grocery shopping task as complete"

4. **delete_task**
   - Deletes a task from Firebase
   - Parameters: taskId or taskTitle
   - Example: "Delete the dentist appointment reminder"

## ⚠️ Pending Integration Points

The following areas need to be connected based on the specific OpenAI Realtime Swift library API:

### 1. Session Configuration
```swift
// In VoiceAIManager.configureSession()
// Need to send the session configuration with tools to the WebSocket
conversation.send(jsonString) // <- Actual method depends on library
```

### 2. Function Call Event Handling
The OpenAI Realtime API sends function calls through WebSocket events:
- `response.function_call_arguments.delta` - Streaming function arguments
- `response.function_call_arguments.done` - Complete function call
- Need to implement parsing of these events in `observeFunctionCalls()`

### 3. Function Response Handling
After executing a function, need to send the result back:
```swift
// Need to send function result back to conversation
let functionResult = await functionHandler.handleFunctionCall(name: functionName, arguments: args)
// Send result back using conversation.item.create or similar
```

## 📝 Example Voice Interactions

### Creating Tasks
- User: "Create a reminder to buy milk"
- AI: Calls `create_task` with title="buy milk"
- System: Creates task in Firebase
- AI: "I've created a reminder to buy milk for you."

### Managing Tasks
- User: "What tasks do I have for today?"
- AI: Calls `list_tasks` with filter="today"
- System: Queries Firebase for today's tasks
- AI: "You have 3 tasks today: pick up dry cleaning, team meeting at 2 PM, and buy groceries."

## 🚀 Next Steps

1. **Test OpenAI Realtime Library API**
   - Determine exact methods for sending session configuration
   - Identify how function call events are received
   - Find method to send function results back

2. **Complete WebSocket Event Handling**
   - Parse incoming function call events
   - Execute functions through RealtimeFunctionHandler
   - Send results back to the conversation

3. **Add UI Components**
   - Create a tasks list view to display stored tasks
   - Add visual feedback when functions are executed
   - Show function execution status in the voice mode UI

4. **Error Handling**
   - Add retry logic for failed function calls
   - Implement proper error messages for users
   - Handle edge cases (duplicate tasks, invalid dates, etc.)

## 🔐 Security Considerations

- API key is securely fetched from backend (not stored in app)
- Tasks are user-scoped using Firebase Authentication
- Anonymous authentication is currently used (can be upgraded to phone auth)
- Firestore rules should be configured to only allow users to access their own tasks

## 📱 Testing Instructions

1. Build and run the app on iOS device/simulator
2. App will automatically sign in anonymously
3. Open voice mode
4. Try voice commands like:
   - "Create a task to call mom tomorrow"
   - "Add a reminder to feed the cat"
   - "Show me all my pending tasks"
   - "Complete the task about feeding the cat"

## 🔗 Resources

- [OpenAI Realtime API Documentation](https://platform.openai.com/docs/guides/realtime)
- [Swift OpenAI Realtime Library](https://github.com/m1guelpf/swift-realtime-openai)
- [Firebase Firestore iOS SDK](https://firebase.google.com/docs/firestore/quickstart#ios)

## 📊 Current Project Structure

```
squirrel2/
├── backend/                 # Node.js backend (deployed to Vercel)
│   ├── src/
│   │   ├── routes/
│   │   │   └── realtime.js  # API key endpoint
│   │   └── config/
│   │       └── firebase.js  # Firebase Admin SDK
│   └── vercel.json          # Vercel deployment config
│
└── Squirrel2/               # iOS SwiftUI app
    └── Squirrel2/
        ├── Models/
        │   ├── VoiceAIManager.swift      # Realtime API connection
        │   ├── RealtimeFunctions.swift   # Function definitions
        │   └── ChatAIManager.swift       # Chat completions
        ├── Config/
        │   ├── APIConfig.swift           # API key fetching
        │   └── AppConfig.swift           # Backend URL config
        └── Views/
            └── RealtimeVoiceModeView.swift # Voice UI

```

## 🔄 Deployment Info

- **Backend URL**: https://backend-sigma-drab.vercel.app
- **Vercel Project**: squirrel2-backend
- **Firebase Project**: squirrel-2
- **iOS Bundle ID**: bradley.Squirrel2

---

*Last Updated: August 25, 2025*