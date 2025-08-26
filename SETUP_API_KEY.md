# Setting Up Your OpenAI API Key

## Quick Setup

1. **Get an OpenAI API Key**
   - Go to https://platform.openai.com/api-keys
   - Sign in or create an account
   - Click "Create new secret key"
   - Copy the key (it starts with `sk-` or `sk-proj-`)

2. **Add the Key to Your App**
   - Open `Squirrel2/Squirrel2/Config/APIConfig.swift`
   - Find line 14: `private static let OPENAI_API_KEY = "YOUR_OPENAI_API_KEY_HERE"`
   - Replace `YOUR_OPENAI_API_KEY_HERE` with your actual key
   - Save the file

3. **Run the App**
   - Build and run the app in Xcode
   - The voice mode should now work!

## Important Notes

- **Keep your key secret**: Never commit your actual API key to git
- **Add to .gitignore**: The key is stored in the code, so be careful
- **Costs**: The Realtime API has usage costs - check OpenAI's pricing
- **Alternative**: You can also set the key programmatically via `APIConfig.saveOpenAIKey("your-key")`

## Troubleshooting

If you see "OpenAI API key not configured":
1. Make sure you replaced the placeholder in APIConfig.swift
2. Check that your key starts with `sk-` or `sk-proj-`
3. Verify the key is valid on OpenAI's platform

## Security Best Practice

For production apps, consider:
1. Using a backend service to proxy API calls
2. Storing keys in environment variables
3. Using iOS Keychain for secure storage
4. Never hardcoding keys in the source code

But for development and testing, the local key approach works fine!