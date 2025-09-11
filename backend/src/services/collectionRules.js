const { chatCompletion } = require('./openai');

async function generateCollectionRules(collectionName, description = '') {
  try {
    if (!process.env.OPENAI_API_KEY) {
      // Return basic rules if OpenAI is not configured
      return {
        keywords: [collectionName.toLowerCase()],
        patterns: [],
        examples: [],
        description: description || `Entries related to ${collectionName}`
      };
    }

    const prompt = `Generate smart rules for a collection called "${collectionName}".
${description ? `Description: ${description}` : ''}

Generate a JSON object with:
- keywords: array of keywords that indicate content belongs in this collection
- patterns: array of phrase patterns that match this collection
- examples: 2-3 example entries that would belong here
- description: a brief description of what belongs in this collection

Be creative and thorough. For example, for "Words to Live By", include keywords like "wisdom", "advice", "principle", "motto", etc.

Return ONLY valid JSON, no markdown or explanation.`;

    const messages = [
      {
        role: 'system',
        content: 'You are a helpful assistant that generates collection rules. Return only valid JSON.'
      },
      {
        role: 'user',
        content: prompt
      }
    ];

    const response = await chatCompletion(messages, 'gpt-4o-mini', {
      temperature: 0.3,
      max_tokens: 200  // Rules object with keywords, patterns, examples
    });
    const rulesText = response.content;
    
    // Parse the JSON response
    try {
      const rules = JSON.parse(rulesText);
      return rules;
    } catch (parseError) {
      console.error('Failed to parse AI rules:', parseError);
      // Fallback to basic rules
      return {
        keywords: [collectionName.toLowerCase()],
        patterns: [],
        examples: [],
        description: description || `Entries related to ${collectionName}`
      };
    }
  } catch (error) {
    console.error('Error generating collection rules:', error);
    // Fallback to basic rules
    return {
      keywords: [collectionName.toLowerCase()],
      patterns: [],
      examples: [],
      description: description || `Entries related to ${collectionName}`
    };
  }
}

module.exports = {
  generateCollectionRules
};