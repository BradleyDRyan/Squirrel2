const { chatCompletion } = require('./openai');
const { Collection, Entry } = require('../models');

/**
 * Quick check if content is potentially worth saving
 * @param {string} content - The content to check
 * @param {Array} collectionNames - List of collection names
 * @returns {Promise<{isInteresting: boolean, reasoning: string}>}
 */
async function isContentInteresting(content, collectionNames) {
  try {
    const prompt = `Is this content potentially worth saving to one of these collections: ${collectionNames.join(', ')}?

Content: "${content}"

Criteria:
- Has educational, inspirational, or reference value
- Contains useful information, tips, or insights  
- Personal reflections or meaningful thoughts
- NOT routine activities or small talk

Return JSON only: { "isInteresting": boolean, "reasoning": "brief reason" }`;

    const messages = [
      {
        role: 'system',
        content: 'You are a quick content filter. Be liberal - when in doubt, mark as interesting. Return only valid JSON.'
      },
      {
        role: 'user',
        content: prompt
      }
    ];

    const response = await chatCompletion(messages, 'gpt-4o-mini', {
      temperature: 0.3,
      max_tokens: 50  // Just need { "isInteresting": true, "reasoning": "short reason" }
    });
    const responseText = response.content;
    
    try {
      return JSON.parse(responseText);
    } catch {
      // Default to interesting if parsing fails
      return { isInteresting: true, reasoning: 'Parse error - defaulting to interesting' };
    }
  } catch (error) {
    console.error('Error checking content interest:', error);
    // Default to interesting on error
    return { isInteresting: true, reasoning: 'Error - defaulting to interesting' };
  }
}

/**
 * Heavy classification - determine which collection and save
 * @param {string} userId - The user's ID
 * @param {string} content - The content to classify
 * @returns {Promise<{shouldSave: boolean, collectionId: string|null, confidence: number, reasoning: string}>}
 */
async function classifyAndRoute(userId, content) {
  try {
    // Get user's collections
    const collections = await Collection.findByUserId(userId);
    
    if (collections.length === 0) {
      // No collections exist, don't save
      return {
        shouldSave: false,
        collectionId: null,
        confidence: 0,
        reasoning: 'No collections exist for this user'
      };
    }
    
    // Build collection context for the AI
    const collectionContext = collections.map(col => {
      return `- ${col.name}: ${col.description || 'No description'}`;
    }).join('\n');
    
    const prompt = `You are a content classifier. Analyze the following content and determine:
1. Is it worth saving? (has lasting value, not mundane daily activities)
2. If yes, which collection fits best?

User's collections:
${collectionContext}

Content to analyze: "${content}"

Criteria for saving:
- Has educational, inspirational, or reference value
- Contains useful information, tips, or insights
- Personal reflections or meaningful thoughts
- NOT routine activities (had coffee, went to store, etc.)
- NOT simple acknowledgments or small talk

Return JSON only, no explanation:
{
  "shouldSave": boolean,
  "collectionId": "collection_id_or_null",
  "collectionName": "collection_name_or_null",
  "confidence": 0.0-1.0,
  "reasoning": "brief explanation"
}`;

    const messages = [
      {
        role: 'system',
        content: 'You are a precise content classifier. Return only valid JSON.'
      },
      {
        role: 'user',
        content: prompt
      }
    ];

    const response = await chatCompletion(messages, 'gpt-4o-mini', {
      temperature: 0.3,
      max_tokens: 50  // Just need { "isInteresting": true, "reasoning": "short reason" }
    });
    const responseText = response.content;
    
    // Parse the JSON response
    try {
      const classification = JSON.parse(responseText);
      
      // Validate and find the actual collection if one was suggested
      if (classification.shouldSave && classification.collectionName) {
        const matchedCollection = collections.find(col => 
          col.name.toLowerCase() === classification.collectionName.toLowerCase()
        );
        
        if (matchedCollection) {
          classification.collectionId = matchedCollection.id;
        } else {
          // Collection name didn't match, set to most likely based on confidence
          classification.shouldSave = false;
          classification.reasoning = 'Could not match to existing collection';
        }
      }
      
      return classification;
    } catch (parseError) {
      console.error('Failed to parse AI classification:', parseError);
      console.error('Response was:', responseText);
      
      // Default to not saving if parsing fails
      return {
        shouldSave: false,
        collectionId: null,
        confidence: 0,
        reasoning: 'Failed to parse classification'
      };
    }
  } catch (error) {
    console.error('Error classifying entry:', error);
    
    // Default to not saving on error
    return {
      shouldSave: false,
      collectionId: null,
      confidence: 0,
      reasoning: 'Classification error: ' + error.message
    };
  }
}

/**
 * Check if content is explicitly directed at a collection (e.g., "CollectionName: content")
 */
function checkExplicitCollection(content) {
  const colonMatch = content.match(/^([^:]+):\s*(.+)$/);
  if (colonMatch) {
    return {
      collectionName: colonMatch[1].trim(),
      cleanContent: colonMatch[2].trim()
    };
  }
  return null;
}

module.exports = {
  isContentInteresting,
  classifyAndRoute,
  checkExplicitCollection
};