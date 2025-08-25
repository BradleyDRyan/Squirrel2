const { firestore } = require('../config/firebase');

class Thought {
  constructor(data = {}) {
    this.id = data.id || null;
    this.userId = data.userId || null;
    this.spaceIds = data.spaceIds || [];
    this.conversationId = data.conversationId || null;
    this.content = data.content || '';
    this.type = data.type || 'reflection';
    this.category = data.category || 'general';
    this.tags = data.tags || [];
    this.insights = data.insights || [];
    this.linkedThoughts = data.linkedThoughts || [];
    this.isPrivate = data.isPrivate !== undefined ? data.isPrivate : true;
    this.createdAt = data.createdAt || new Date();
    this.updatedAt = data.updatedAt || new Date();
    this.metadata = data.metadata || {};
  }

  static collection() {
    return firestore.collection('thoughts');
  }

  static async create(data) {
    const thought = new Thought(data);
    const docRef = await this.collection().add({
      userId: thought.userId,
      spaceIds: thought.spaceIds,
      conversationId: thought.conversationId,
      content: thought.content,
      type: thought.type,
      category: thought.category,
      tags: thought.tags,
      insights: thought.insights,
      linkedThoughts: thought.linkedThoughts,
      isPrivate: thought.isPrivate,
      createdAt: thought.createdAt,
      updatedAt: thought.updatedAt,
      metadata: thought.metadata
    });
    thought.id = docRef.id;
    return thought;
  }

  static async findById(id) {
    const doc = await this.collection().doc(id).get();
    if (!doc.exists) {
      return null;
    }
    return new Thought({ id: doc.id, ...doc.data() });
  }

  static async findByUserId(userId, filters = {}) {
    let query = this.collection().where('userId', '==', userId);
    
    if (filters.spaceId) {
      query = query.where('spaceIds', 'array-contains', filters.spaceId);
    }
    
    if (filters.type) {
      query = query.where('type', '==', filters.type);
    }
    
    if (filters.category) {
      query = query.where('category', '==', filters.category);
    }
    
    if (filters.conversationId) {
      query = query.where('conversationId', '==', filters.conversationId);
    }
    
    if (filters.isPrivate !== undefined) {
      query = query.where('isPrivate', '==', filters.isPrivate);
    }
    
    const snapshot = await query.orderBy('createdAt', 'desc').get();
    return snapshot.docs.map(doc => new Thought({ id: doc.id, ...doc.data() }));
  }

  static async findByTags(userId, tags) {
    const snapshot = await this.collection()
      .where('userId', '==', userId)
      .where('tags', 'array-contains-any', tags)
      .orderBy('createdAt', 'desc')
      .get();
    
    return snapshot.docs.map(doc => new Thought({ id: doc.id, ...doc.data() }));
  }

  static async findLinkedThoughts(thoughtId) {
    const snapshot = await this.collection()
      .where('linkedThoughts', 'array-contains', thoughtId)
      .get();
    
    return snapshot.docs.map(doc => new Thought({ id: doc.id, ...doc.data() }));
  }

  static async searchContent(userId, searchText) {
    const thoughts = await this.findByUserId(userId);
    return thoughts.filter(thought => 
      thought.content.toLowerCase().includes(searchText.toLowerCase()) ||
      thought.insights.some(insight => 
        insight.toLowerCase().includes(searchText.toLowerCase())
      )
    );
  }

  async linkTo(thoughtId) {
    if (!this.linkedThoughts.includes(thoughtId)) {
      this.linkedThoughts.push(thoughtId);
      await this.save();
    }
  }

  async addInsight(insight) {
    this.insights.push(insight);
    await this.save();
  }

  async save() {
    this.updatedAt = new Date();
    if (this.id) {
      await Thought.collection().doc(this.id).update({
        content: this.content,
        spaceIds: this.spaceIds,
        type: this.type,
        category: this.category,
        tags: this.tags,
        insights: this.insights,
        linkedThoughts: this.linkedThoughts,
        isPrivate: this.isPrivate,
        updatedAt: this.updatedAt,
        metadata: this.metadata
      });
    } else {
      const created = await Thought.create(this);
      this.id = created.id;
    }
    return this;
  }

  async delete() {
    if (this.id) {
      await Thought.collection().doc(this.id).delete();
    }
  }
}

module.exports = Thought;