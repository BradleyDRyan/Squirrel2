const OpenAI = require('openai');
require('dotenv').config();

// Initialize OpenAI client
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const chatCompletion = async (messages, model = 'gpt-4o-mini', options = {}) => {
  try {
    if (!process.env.OPENAI_API_KEY || process.env.OPENAI_API_KEY === 'your-openai-api-key-here') {
      throw new Error('OpenAI API key not configured. Please add OPENAI_API_KEY to your .env file');
    }

    const completion = await openai.chat.completions.create({
      model,
      messages,
      temperature: options.temperature || 0.7,
      max_tokens: options.max_tokens || 1000,
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

const classifyIntent = async (text) => {
  try {
    if (!process.env.OPENAI_API_KEY || process.env.OPENAI_API_KEY === 'your-openai-api-key-here') {
      throw new Error('OpenAI API key not configured');
    }

    const messages = [
      {
        role: 'system',
        content: `You are a voice intent classifier. Classify user input as either COMMAND (0) or CONVERSATION (1).

Commands are one-way actions that just need execution:
- Create/add/make a task/reminder/note
- Set a timer/alarm
- Mark something as done/complete
- Delete/remove a task
- Add to shopping list

Everything else is a conversation (questions, chat, unclear intent, multi-turn interactions).

Reply with ONLY a single digit: 0 for COMMAND or 1 for CONVERSATION.`
      },
      {
        role: 'user',
        content: text
      }
    ];

    const completion = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages,
      temperature: 0,
      max_tokens: 1,
    });

    const result = completion.choices[0].message.content?.trim();
    return result === '0' ? 'command' : 'conversation';
  } catch (error) {
    console.error('OpenAI Classification error:', error);
    // Default to conversation on error
    return 'conversation';
  }
};

module.exports = {
  openai,
  chatCompletion,
  chatCompletionStream,
  generateEmbedding,
  classifyIntent,
};