const { firestore } = require('../config/firebase');

class Collection {
  constructor(data = {}) {
    this.id = data.id || null;
    this.userId = data.userId || null;
    this.name = data.name || '';
    this.description = data.description || '';
    this.icon = data.icon || '📝';
    this.color = data.color || '#6366f1';
    this.rules = data.rules || {
      // AI-generated rules for what should be saved to this collection
      keywords: [],
      patterns: [],
      examples: [],
      description: ''
    };
    this.entryFormat = data.entryFormat || null;  // New: Defines field structure for entries
    this.template = data.template || {
      // Legacy template structure - will phase out
      fields: [],
      prompts: []
    };
    this.settings = data.settings || {
      isPublic: false,
      allowComments: false,
      defaultTags: []
    };
    this.stats = data.stats || {
      entryCount: 0,
      lastEntryAt: null
    };
    this.createdAt = data.createdAt || new Date();
    this.updatedAt = data.updatedAt || new Date();
    this.metadata = data.metadata || {};
  }

  static collection() {
    return firestore.collection('collections');
  }

  static async create(data) {
    const collection = new Collection(data);
    const docRef = await this.collection().add({
      userId: collection.userId,
      name: collection.name,
      description: collection.description,
      icon: collection.icon,
      color: collection.color,
      rules: collection.rules,
      entryFormat: collection.entryFormat,
      template: collection.template,
      settings: collection.settings,
      stats: collection.stats,
      createdAt: collection.createdAt,
      updatedAt: collection.updatedAt,
      metadata: collection.metadata
    });
    collection.id = docRef.id;
    return collection;
  }

  static async findById(id) {
    const doc = await this.collection().doc(id).get();
    if (!doc.exists) {
      return null;
    }
    return new Collection({ id: doc.id, ...doc.data() });
  }

  static async findByUserId(userId) {
    try {
      const snapshot = await this.collection()
        .where('userId', '==', userId)
        .get();
      
      if (snapshot.empty) {
        return [];
      }
      
      // Sort in memory to avoid index requirement
      const collections = snapshot.docs.map(doc => {
        const data = doc.data();
        return new Collection({ id: doc.id, ...data });
      });
      
      collections.sort((a, b) => {
        // Handle Firestore timestamps
        const aTime = a.createdAt?.toDate ? a.createdAt.toDate() : new Date(a.createdAt);
        const bTime = b.createdAt?.toDate ? b.createdAt.toDate() : new Date(b.createdAt);
        return bTime - aTime;
      });
      
      return collections;
    } catch (error) {
      console.error('[Collection.findByUserId] Error:', error.message);
      throw error;
    }
  }

  static async findByName(userId, name) {
    // Case-insensitive search for collection by name
    const collections = await this.findByUserId(userId);
    return collections.find(col => 
      col.name.toLowerCase() === name.toLowerCase()
    );
  }

  static async findOrCreateByName(userId, name, description = '') {
    // Find existing collection or create new one
    let collection = await this.findByName(userId, name);
    
    if (!collection) {
      collection = await this.create({
        userId,
        name,
        description: description || `Collection for ${name}`,
        icon: this.getDefaultIcon(name),
        metadata: { source: 'auto_created' }
      });
    }
    
    return collection;
  }

  static async findBestMatch(userId, content) {
    // Find the best matching collection based on content and rules
    const collections = await this.findByUserId(userId);
    
    // Check for explicit collection reference (e.g., "words to live by: ...")
    const colonMatch = content.match(/^([^:]+):\s*(.+)$/);
    if (colonMatch) {
      const collectionName = colonMatch[1].trim();
      const matchedCollection = collections.find(col => 
        col.name.toLowerCase() === collectionName.toLowerCase()
      );
      if (matchedCollection) {
        return {
          collection: matchedCollection,
          content: colonMatch[2].trim(), // Return the content after the colon
          confidence: 1.0
        };
      }
    }
    
    // Check collections with rules
    for (const collection of collections) {
      if (collection.rules && collection.rules.keywords && collection.rules.keywords.length > 0) {
        const contentLower = content.toLowerCase();
        const matchedKeywords = collection.rules.keywords.filter(keyword => 
          contentLower.includes(keyword.toLowerCase())
        );
        
        if (matchedKeywords.length > 0) {
          return {
            collection,
            content, // Return original content
            confidence: matchedKeywords.length / collection.rules.keywords.length
          };
        }
      }
    }
    
    return null;
  }

  static getDefaultIcon(name) {
    // Return contextual emoji based on collection name
    const nameLower = name.toLowerCase();
    
    if (nameLower.includes('bak') || nameLower.includes('cook') || nameLower.includes('recipe')) return '🍞';
    if (nameLower.includes('travel') || nameLower.includes('trip')) return '✈️';
    if (nameLower.includes('book') || nameLower.includes('read')) return '📚';
    if (nameLower.includes('movie') || nameLower.includes('film')) return '🎬';
    if (nameLower.includes('music') || nameLower.includes('song')) return '🎵';
    if (nameLower.includes('workout') || nameLower.includes('exercise') || nameLower.includes('fitness')) return '💪';
    if (nameLower.includes('food') || nameLower.includes('restaurant')) return '🍽️';
    if (nameLower.includes('photo') || nameLower.includes('picture')) return '📷';
    if (nameLower.includes('idea') || nameLower.includes('thought')) return '💡';
    if (nameLower.includes('work') || nameLower.includes('project')) return '💼';
    if (nameLower.includes('garden') || nameLower.includes('plant')) return '🌱';
    if (nameLower.includes('pet') || nameLower.includes('dog') || nameLower.includes('cat')) return '🐾';
    
    return '📝'; // Default icon
  }

  async updateStats() {
    const entries = await firestore.collection('entries')
      .where('collectionId', '==', this.id)
      .get();
    
    this.stats.entryCount = entries.size;
    
    if (entries.size > 0) {
      // Get the most recent entry
      const sortedEntries = entries.docs
        .map(doc => doc.data())
        .sort((a, b) => b.createdAt - a.createdAt);
      
      this.stats.lastEntryAt = sortedEntries[0].createdAt;
    }
    
    await this.save();
    return this.stats;
  }

  async save() {
    this.updatedAt = new Date();
    if (this.id) {
      await Collection.collection().doc(this.id).update({
        name: this.name,
        description: this.description,
        icon: this.icon,
        color: this.color,
        rules: this.rules,
        template: this.template,
        settings: this.settings,
        stats: this.stats,
        updatedAt: this.updatedAt,
        metadata: this.metadata
      });
    } else {
      const created = await Collection.create(this);
      this.id = created.id;
    }
    return this;
  }

  async delete() {
    if (this.id) {
      // Check if collection has entries
      const entries = await firestore.collection('entries')
        .where('collectionId', '==', this.id)
        .limit(1)
        .get();
      
      if (!entries.empty) {
        throw new Error('Cannot delete collection with existing entries');
      }
      
      await Collection.collection().doc(this.id).delete();
    }
  }
}

module.exports = Collection;