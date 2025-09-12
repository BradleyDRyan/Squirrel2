const { firestore } = require('../config/firebase');

class Collection {
  constructor(data = {}) {
    this.id = data.id || null;
    this.userId = data.userId || null;
    this.name = data.name || '';
    this.instructions = data.instructions || '';  // AI guidance for what belongs in this collection
    this.icon = data.icon || 'doc.text';
    this.color = data.color || '#6366f1';
    this.entryFormat = data.entryFormat || null;  // Defines field structure for entries
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
      instructions: collection.instructions,
      icon: collection.icon,
      color: collection.color,
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

  static async findOrCreateByName(userId, name, instructions = '') {
    // Find existing collection or create new one
    let collection = await this.findByName(userId, name);
    
    if (!collection) {
      collection = await this.create({
        userId,
        name,
        instructions: instructions || `Add entries related to ${name}`,
        icon: this.getDefaultIcon(name),
        metadata: { source: 'auto_created' }
      });
    }
    
    return collection;
  }

  static async findBestMatch(userId, content) {
    // Find the best matching collection based on explicit reference
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
    
    // No keyword matching - let AI handle all inference
    return null;
  }

  static getDefaultIcon(name) {
    // Return contextual SF Symbol based on collection name
    const nameLower = name.toLowerCase();
    
    // Media & Entertainment
    if (nameLower.includes('book') || nameLower.includes('read')) return 'book';
    if (nameLower.includes('movie') || nameLower.includes('film')) return 'film';
    if (nameLower.includes('tv') || nameLower.includes('show')) return 'tv';
    if (nameLower.includes('music') || nameLower.includes('song') || nameLower.includes('album')) return 'music.note';
    if (nameLower.includes('podcast')) return 'mic';
    if (nameLower.includes('game') || nameLower.includes('gaming')) return 'gamecontroller';
    
    // Food & Dining
    if (nameLower.includes('recipe')) return 'fork.knife';
    if (nameLower.includes('restaurant') || nameLower.includes('dining')) return 'fork.knife.circle';
    if (nameLower.includes('cook') || nameLower.includes('bak')) return 'flame';
    if (nameLower.includes('wine') || nameLower.includes('drink')) return 'wineglass';
    if (nameLower.includes('coffee')) return 'cup.and.saucer';
    
    // Activities & Lifestyle
    if (nameLower.includes('travel') || nameLower.includes('trip')) return 'airplane';
    if (nameLower.includes('workout') || nameLower.includes('exercise') || nameLower.includes('fitness')) return 'figure.walk';
    if (nameLower.includes('sport')) return 'sportscourt';
    if (nameLower.includes('yoga') || nameLower.includes('meditation')) return 'figure.mind.and.body';
    if (nameLower.includes('run')) return 'figure.run';
    
    // Shopping & Products
    if (nameLower.includes('product') || nameLower.includes('review')) return 'star';
    if (nameLower.includes('shop') || nameLower.includes('buy')) return 'cart';
    if (nameLower.includes('candle')) return 'flame.circle';
    if (nameLower.includes('clothes') || nameLower.includes('fashion')) return 'tshirt';
    
    // Personal & Life
    if (nameLower.includes('idea') || nameLower.includes('thought')) return 'lightbulb';
    if (nameLower.includes('advice') || nameLower.includes('tip')) return 'quote.bubble';
    if (nameLower.includes('goal') || nameLower.includes('plan')) return 'target';
    if (nameLower.includes('dream')) return 'moon.stars';
    if (nameLower.includes('memory') || nameLower.includes('memories')) return 'heart';
    
    // Work & Productivity
    if (nameLower.includes('work') || nameLower.includes('job')) return 'briefcase';
    if (nameLower.includes('project')) return 'folder';
    if (nameLower.includes('meeting')) return 'person.2';
    if (nameLower.includes('task') || nameLower.includes('todo')) return 'checklist';
    
    // Home & Nature
    if (nameLower.includes('home') || nameLower.includes('house')) return 'house';
    if (nameLower.includes('garden') || nameLower.includes('plant')) return 'leaf';
    if (nameLower.includes('pet') || nameLower.includes('dog') || nameLower.includes('cat')) return 'pawprint';
    if (nameLower.includes('weather')) return 'cloud.sun';
    
    // Media Creation
    if (nameLower.includes('photo') || nameLower.includes('picture')) return 'camera';
    if (nameLower.includes('video')) return 'video';
    if (nameLower.includes('art') || nameLower.includes('draw')) return 'paintbrush';
    if (nameLower.includes('write') || nameLower.includes('journal')) return 'pencil';
    
    // Health & Wellness
    if (nameLower.includes('health')) return 'heart.circle';
    if (nameLower.includes('medical') || nameLower.includes('doctor')) return 'stethoscope';
    if (nameLower.includes('sleep')) return 'bed.double';
    
    // Learning & Education
    if (nameLower.includes('learn') || nameLower.includes('study')) return 'graduationcap';
    if (nameLower.includes('language')) return 'globe';
    if (nameLower.includes('math') || nameLower.includes('number')) return 'number';
    
    // Finance
    if (nameLower.includes('money') || nameLower.includes('finance') || nameLower.includes('budget')) return 'dollarsign.circle';
    if (nameLower.includes('invest')) return 'chart.line.uptrend.xyaxis';
    
    return 'doc.text'; // Default icon
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
        instructions: this.instructions,
        icon: this.icon,
        color: this.color,
        entryFormat: this.entryFormat,
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