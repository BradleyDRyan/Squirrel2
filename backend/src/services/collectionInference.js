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
async function inferCollectionFromContent(content, existingCollections = [], collectionInstructions = {}) {
  try {
    if (!process.env.OPENAI_API_KEY) {
      console.log('[INFERENCE] No OpenAI API key configured');
      // Return null if OpenAI is not configured
      return null;
    }
    
    console.log('[INFERENCE] Starting inference for content:', content.substring(0, 100));
    console.log('[INFERENCE] Existing collections:', existingCollections);

    // Build context with collection names and their instructions
    let existingCollectionsContext = '';
    if (existingCollections.length > 0) {
      const collectionsWithInstructions = existingCollections.map(name => {
        const instructions = collectionInstructions[name];
        if (instructions) {
          return `- ${name}: ${instructions}`;
        }
        return `- ${name}`;
      }).join('\n');
      
      existingCollectionsContext = `Existing collections with instructions:\n${collectionsWithInstructions}\n\nUse exact name if content matches the instructions.`;
    } else {
      existingCollectionsContext = 'No existing collections.';
    }

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
    
    return result;
  } catch (error) {
    console.error('[INFERENCE] Error inferring collection from content:', error);
    console.error('[INFERENCE] Error details:', error.message, error.stack);
    return null;
  }
}

/**
 * Generates collection details including icon, color, and instructions
 * This is called when explicitly creating a collection (not from content inference)
 */
async function generateCollectionDetails(collectionName, unused = '', sampleContent = '') {
  try {
    if (!process.env.OPENAI_API_KEY) {
      // Return basic structure if OpenAI is not configured
      return {
        name: collectionName,
        instructions: `Add entries related to ${collectionName}`,
        icon: '📝',
        color: '#6366f1'
      };
    }

    const prompt = `Collection: "${collectionName}"

Return JSON with icon, color, and instructions:
{"name": "${collectionName}", "icon": "emoji", "color": "#hex", "instructions": "brief guidance on what belongs in this collection"}`;

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
      max_tokens: 100     // Need room for instructions field
    });
    const result = JSON.parse(response.content);
    
    return result;
  } catch (error) {
    console.error('Error generating collection details:', error);
    // Fallback to basic structure
    return {
      name: collectionName,
      instructions: `Add entries related to ${collectionName}`,
      icon: '📝',
      color: '#6366f1'
    };
  }
}

module.exports = {
  inferCollectionFromContent,
  generateCollectionDetails
};