const OpenAI = require('openai');
require('dotenv').config();

// Initialize OpenAI client
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const chatCompletion = async (messages, model = 'gpt-4o-mini') => {
  try {
    if (!process.env.OPENAI_API_KEY || process.env.OPENAI_API_KEY === 'your-openai-api-key-here') {
      throw new Error('OpenAI API key not configured. Please add OPENAI_API_KEY to your .env file');
    }

    const completion = await openai.chat.completions.create({
      model,
      messages,
      temperature: 0.7,
      max_tokens: 1000,
    });

    return completion.choices[0].message;
  } catch (error) {
    console.error('OpenAI API error:', error);
    throw error;
  }
};

const chatCompletionStream = async function* (messages, model = 'gpt-4o-mini') {
  try {
    if (!process.env.OPENAI_API_KEY || process.env.OPENAI_API_KEY === 'your-openai-api-key-here') {
      throw new Error('OpenAI API key not configured. Please add OPENAI_API_KEY to your .env file');
    }

    const stream = await openai.chat.completions.create({
      model,
      messages,
      temperature: 0.7,
      max_tokens: 1000,
      stream: true,
    });

    for await (const chunk of stream) {
      const content = chunk.choices[0]?.delta?.content || '';
      if (content) {
        yield content;
      }
    }
  } catch (error) {
    console.error('OpenAI Stream API error:', error);
    throw error;
  }
};

const generateEmbedding = async (text) => {
  try {
    if (!process.env.OPENAI_API_KEY || process.env.OPENAI_API_KEY === 'your-openai-api-key-here') {
      throw new Error('OpenAI API key not configured');
    }

    const embedding = await openai.embeddings.create({
      model: 'text-embedding-3-small',
      input: text,
    });

    return embedding.data[0].embedding;
  } catch (error) {
    console.error('OpenAI Embedding error:', error);
    throw error;
  }
};

module.exports = {
  openai,
  chatCompletion,
  chatCompletionStream,
  generateEmbedding,
};