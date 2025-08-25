const { firestore } = require('../config/firebase');

class Space {
  constructor(data = {}) {
    this.id = data.id || null;
    this.userId = data.userId || null;
    this.name = data.name || '';
    this.description = data.description || '';
    this.color = data.color || '#000000';
    this.icon = data.icon || null;
    this.isDefault = data.isDefault || false;
    this.isArchived = data.isArchived || false;
    this.settings = data.settings || {};
    this.stats = data.stats || {
      conversationCount: 0,
      taskCount: 0,
      entryCount: 0,
      thoughtCount: 0
    };
    this.createdAt = data.createdAt || new Date();
    this.updatedAt = data.updatedAt || new Date();
    this.metadata = data.metadata || {};
  }

  static collection() {
    return firestore.collection('spaces');
  }

  static async create(data) {
    const space = new Space(data);
    const docRef = await this.collection().add({
      userId: space.userId,
      name: space.name,
      description: space.description,
      color: space.color,
      icon: space.icon,
      isDefault: space.isDefault,
      isArchived: space.isArchived,
      settings: space.settings,
      stats: space.stats,
      createdAt: space.createdAt,
      updatedAt: space.updatedAt,
      metadata: space.metadata
    });
    space.id = docRef.id;
    return space;
  }

  static async findById(id) {
    const doc = await this.collection().doc(id).get();
    if (!doc.exists) {
      return null;
    }
    return new Space({ id: doc.id, ...doc.data() });
  }

  static async findByUserId(userId, includeArchived = false) {
    let query = this.collection().where('userId', '==', userId);
    
    if (!includeArchived) {
      query = query.where('isArchived', '==', false);
    }
    
    const snapshot = await query.orderBy('createdAt', 'asc').get();
    return snapshot.docs.map(doc => new Space({ id: doc.id, ...doc.data() }));
  }

  static async findDefaultSpace(userId) {
    const snapshot = await this.collection()
      .where('userId', '==', userId)
      .where('isDefault', '==', true)
      .limit(1)
      .get();
    
    if (snapshot.empty) {
      return null;
    }
    
    const doc = snapshot.docs[0];
    return new Space({ id: doc.id, ...doc.data() });
  }

  static async createDefaultSpace(userId) {
    const existingDefault = await this.findDefaultSpace(userId);
    if (existingDefault) {
      return existingDefault;
    }
    
    return this.create({
      userId,
      name: 'Personal',
      description: 'Your personal space',
      color: '#6366f1',
      isDefault: true
    });
  }

  async updateStats() {
    const batch = firestore.batch();
    
    const conversations = await firestore.collection('conversations')
      .where('spaceIds', 'array-contains', this.id)
      .get();
    
    const tasks = await firestore.collection('tasks')
      .where('spaceIds', 'array-contains', this.id)
      .get();
    
    const entries = await firestore.collection('entries')
      .where('spaceIds', 'array-contains', this.id)
      .get();
    
    const thoughts = await firestore.collection('thoughts')
      .where('spaceIds', 'array-contains', this.id)
      .get();
    
    this.stats = {
      conversationCount: conversations.size,
      taskCount: tasks.size,
      entryCount: entries.size,
      thoughtCount: thoughts.size
    };
    
    await this.save();
    return this.stats;
  }

  async save() {
    this.updatedAt = new Date();
    if (this.id) {
      await Space.collection().doc(this.id).update({
        name: this.name,
        description: this.description,
        color: this.color,
        icon: this.icon,
        isDefault: this.isDefault,
        isArchived: this.isArchived,
        settings: this.settings,
        stats: this.stats,
        updatedAt: this.updatedAt,
        metadata: this.metadata
      });
    } else {
      const created = await Space.create(this);
      this.id = created.id;
    }
    return this;
  }

  async archive() {
    this.isArchived = true;
    return this.save();
  }

  async unarchive() {
    this.isArchived = false;
    return this.save();
  }

  async delete() {
    if (this.id) {
      const hasContent = Object.values(this.stats).some(count => count > 0);
      if (hasContent) {
        throw new Error('Cannot delete space with existing content. Archive it instead.');
      }
      
      await Space.collection().doc(this.id).delete();
    }
  }
}

module.exports = Space;