const { firestore } = require('../config/firebase');

class Entry {
  constructor(data = {}) {
    this.id = data.id || null;
    this.userId = data.userId || null;
    this.spaceIds = data.spaceIds || [];
    this.conversationId = data.conversationId || null;
    this.title = data.title || '';
    this.content = data.content || '';
    this.type = data.type || 'journal';
    this.mood = data.mood || null;
    this.tags = data.tags || [];
    this.attachments = data.attachments || [];
    this.location = data.location || null;
    this.weather = data.weather || null;
    this.createdAt = data.createdAt || new Date();
    this.updatedAt = data.updatedAt || new Date();
    this.metadata = data.metadata || {};
  }

  static collection() {
    return firestore.collection('entries');
  }

  static async create(data) {
    const entry = new Entry(data);
    const docRef = await this.collection().add({
      userId: entry.userId,
      spaceIds: entry.spaceIds,
      conversationId: entry.conversationId,
      title: entry.title,
      content: entry.content,
      type: entry.type,
      mood: entry.mood,
      tags: entry.tags,
      attachments: entry.attachments,
      location: entry.location,
      weather: entry.weather,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
      metadata: entry.metadata
    });
    entry.id = docRef.id;
    return entry;
  }

  static async findById(id) {
    const doc = await this.collection().doc(id).get();
    if (!doc.exists) {
      return null;
    }
    return new Entry({ id: doc.id, ...doc.data() });
  }

  static async findByUserId(userId, filters = {}) {
    let query = this.collection().where('userId', '==', userId);
    
    if (filters.spaceId) {
      query = query.where('spaceIds', 'array-contains', filters.spaceId);
    }
    
    if (filters.type) {
      query = query.where('type', '==', filters.type);
    }
    
    if (filters.mood) {
      query = query.where('mood', '==', filters.mood);
    }
    
    if (filters.conversationId) {
      query = query.where('conversationId', '==', filters.conversationId);
    }
    
    if (filters.startDate && filters.endDate) {
      query = query
        .where('createdAt', '>=', filters.startDate)
        .where('createdAt', '<=', filters.endDate);
    }
    
    const snapshot = await query.orderBy('createdAt', 'desc').get();
    return snapshot.docs.map(doc => new Entry({ id: doc.id, ...doc.data() }));
  }

  static async findByTags(userId, tags) {
    const snapshot = await this.collection()
      .where('userId', '==', userId)
      .where('tags', 'array-contains-any', tags)
      .orderBy('createdAt', 'desc')
      .get();
    
    return snapshot.docs.map(doc => new Entry({ id: doc.id, ...doc.data() }));
  }

  static async searchContent(userId, searchText) {
    const entries = await this.findByUserId(userId);
    return entries.filter(entry => 
      entry.title.toLowerCase().includes(searchText.toLowerCase()) ||
      entry.content.toLowerCase().includes(searchText.toLowerCase())
    );
  }

  async save() {
    this.updatedAt = new Date();
    if (this.id) {
      await Entry.collection().doc(this.id).update({
        title: this.title,
        content: this.content,
        spaceIds: this.spaceIds,
        type: this.type,
        mood: this.mood,
        tags: this.tags,
        attachments: this.attachments,
        location: this.location,
        weather: this.weather,
        updatedAt: this.updatedAt,
        metadata: this.metadata
      });
    } else {
      const created = await Entry.create(this);
      this.id = created.id;
    }
    return this;
  }

  async delete() {
    if (this.id) {
      await Entry.collection().doc(this.id).delete();
    }
  }
}

module.exports = Entry;