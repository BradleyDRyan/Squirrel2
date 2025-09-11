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
async function inferCollectionFromContent(content, existingCollections = []) {
  try {
    if (!process.env.OPENAI_API_KEY) {
      console.log('[INFERENCE] No OpenAI API key configured');
      // Return null if OpenAI is not configured
      return null;
    }
    
    console.log('[INFERENCE] Starting inference for content:', content.substring(0, 100));
    console.log('[INFERENCE] Existing collections:', existingCollections);

    const existingCollectionsContext = existingCollections.length > 0 
      ? `Existing collections: ${existingCollections.join(', ')}. Use exact name if matches.`
      : 'No existing collections.';

    const prompt = `Content: "${content}"
${existingCollectionsContext}

Return JSON:
{
  "collectionName": "collection name",
  "shouldCreateCollection": true/false,
  "extractedData": {"key": "value"},
  "entryFormat": [{"key": "field", "type": "text|number|date", "label": "Field Name"}] // only if creating new
}`;

    const messages = [
      {
        role: 'system',
        content: 'Quickly categorize content into collections. Be decisive. Return only JSON.'
      },
      {
        role: 'user',
        content: prompt
      }
    ];

    const response = await chatCompletion(messages, 'gpt-4o-mini', {
      temperature: 0.3,  // Lower temperature for faster, more deterministic responses
      max_tokens: 250    // Need room for entryFormat when creating new collections
    });
    console.log('[INFERENCE] AI response received (truncated):', response.content.substring(0, 200));
    
    const result = JSON.parse(response.content);
    console.log('[INFERENCE] Parsed result:', JSON.stringify(result, null, 2));
    
    // Add description for new collections
    if (result.shouldCreateCollection && !result.description) {
      result.description = `A collection for ${result.collectionName}`;
    }
    
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

    const prompt = `Collection: "${collectionName}"

Return JSON with icon and color:
{"name": "${collectionName}", "icon": "emoji", "color": "#hex"}`;

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

    const response = await chatCompletion(messages, 'gpt-4o-mini', {
      temperature: 0.3,  // Faster, more deterministic
      max_tokens: 50     // Just need {"name": "...", "icon": "📚", "color": "#123456"}
    });
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