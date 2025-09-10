const { firestore } = require('../config/firebase');

class Collection {
  constructor(data = {}) {
    this.id = data.id || null;
    this.userId = data.userId || null;
    this.name = data.name || '';
    this.description = data.description || '';
    this.icon = data.icon || '📝';
    this.color = data.color || '#6366f1';
    this.template = data.template || {
      // Default template structure for entries in this collection
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
    const snapshot = await this.collection()
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .get();
    
    return snapshot.docs.map(doc => new Collection({ id: doc.id, ...doc.data() }));
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