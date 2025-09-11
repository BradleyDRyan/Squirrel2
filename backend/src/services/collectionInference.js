const { chatCompletion } = require('./openai');

/**
 * Infers collection details from user content, including:
 * - Collection name
 * - Rules (keywords, patterns)
 * - Entry format (structured fields)
 * 
 * Example: "boy smells ash candle is 8/10" 
 * -> Collection: "Candle Ratings"
 * -> Format: { name: text, brand: text, rating: number }
 */
async function inferCollectionFromContent(content) {
  try {
    if (!process.env.OPENAI_API_KEY) {
      console.log('[INFERENCE] No OpenAI API key configured');
      // Return null if OpenAI is not configured
      return null;
    }
    
    console.log('[INFERENCE] Starting inference for content:', content);

    const prompt = `Analyze this user input and determine if it should belong to a collection:
"${content}"

If this content suggests a collection pattern (like ratings, reviews, lists, etc.), generate:
1. A collection name (e.g., "Candle Ratings", "Book Reviews", "Workout Log")
2. Rules for what belongs in this collection
3. A structured entry format with fields

Return a JSON object with this structure:
{
  "shouldCreateCollection": true/false,
  "collectionName": "Name of Collection",
  "description": "Brief description of what this collection captures",
  "rules": {
    "keywords": ["array", "of", "keywords"],
    "patterns": ["phrase patterns like 'I rated'", "watched {movie}"],
    "description": "When to add entries to this collection"
  },
  "entryFormat": {
    "fields": [
      {
        "key": "fieldKey",
        "label": "Field Label",
        "type": "text|number|date|select|boolean",
        "required": true/false,
        "options": ["for", "select", "fields"],
        "min": null,
        "max": null,
        "multiline": false,
        "multiple": false
      }
    ]
  },
  "extractedData": {
    "fieldKey": "extracted value from the content"
  }
}

For example, for "boy smells ash candle is 8/10":
- Collection: "Candle Ratings"
- Fields: brand (text), scent (text), rating (number)
- Extracted: { brand: "Boy Smells", scent: "Ash", rating: 8 }

Return ONLY valid JSON, no markdown or explanation.`;

    const messages = [
      {
        role: 'system',
        content: 'You are an AI that analyzes user input to determine collection patterns and structure. Return only valid JSON.'
      },
      {
        role: 'user',
        content: prompt
      }
    ];

    const response = await chatCompletion(messages, 'gpt-4o-mini');
    console.log('[INFERENCE] AI response received:', response.content);
    
    const result = JSON.parse(response.content);
    console.log('[INFERENCE] Parsed result:', JSON.stringify(result, null, 2));
    
    return result;
  } catch (error) {
    console.error('[INFERENCE] Error inferring collection from content:', error);
    console.error('[INFERENCE] Error details:', error.message, error.stack);
    return null;
  }
}

/**
 * Generates comprehensive collection details including rules and entry format
 * This is called when explicitly creating a collection (not from content inference)
 */
async function generateCollectionDetails(collectionName, description = '', sampleContent = '') {
  try {
    if (!process.env.OPENAI_API_KEY) {
      // Return basic structure if OpenAI is not configured
      return {
        name: collectionName,
        description: description || `Collection for ${collectionName}`,
        rules: {
          keywords: [collectionName.toLowerCase()],
          patterns: [],
          examples: [],
          description: `Capture entries related to ${collectionName}`
        },
        entryFormat: null
      };
    }

    const prompt = `Generate comprehensive details for a collection called "${collectionName}".
${description ? `Description: ${description}` : ''}
${sampleContent ? `Sample content: "${sampleContent}"` : ''}

Generate a JSON object with:
1. Enhanced description (brief, clear)
2. Rules for what belongs in this collection
3. A structured entry format with appropriate fields

Think about what kind of data someone would want to capture for "${collectionName}".
For ratings: include item name, rating, notes
For reviews: include title, rating, review text, date
For logs: include relevant fields for tracking

Return a JSON object with this structure:
{
  "name": "${collectionName}",
  "description": "Enhanced description",
  "icon": "emoji that fits",
  "color": "#hexcolor",
  "rules": {
    "keywords": ["keywords"],
    "patterns": ["patterns like 'I rated'"],
    "examples": [{"content": "example 1"}, {"content": "example 2"}],
    "description": "When to add entries"
  },
  "entryFormat": {
    "fields": [
      {
        "key": "fieldKey",
        "label": "Field Label",
        "type": "text|number|date|select|boolean",
        "required": true/false,
        "options": null,
        "min": null,
        "max": null,
        "multiline": false,
        "multiple": false
      }
    ],
    "version": 1
  }
}

Return ONLY valid JSON, no markdown or explanation.`;

    const messages = [
      {
        role: 'system',
        content: 'You are an AI that generates collection structures. Be creative but practical. Return only valid JSON.'
      },
      {
        role: 'user',
        content: prompt
      }
    ];

    const response = await chatCompletion(messages, 'gpt-4o-mini');
    const result = JSON.parse(response.content);
    
    return result;
  } catch (error) {
    console.error('Error generating collection details:', error);
    // Fallback to basic structure
    return {
      name: collectionName,
      description: description || `Collection for ${collectionName}`,
      rules: {
        keywords: [collectionName.toLowerCase()],
        patterns: [],
        examples: [],
        description: `Capture entries related to ${collectionName}`
      },
      entryFormat: null
    };
  }
}

module.exports = {
  inferCollectionFromContent,
  generateCollectionDetails
};