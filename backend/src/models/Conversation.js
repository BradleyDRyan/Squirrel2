const { firestore } = require('../config/firebase');

class Conversation {
  constructor(data = {}) {
    this.id = data.id || null;
    this.userId = data.userId || null;
    this.spaceIds = data.spaceIds || [];
    this.title = data.title || 'New Conversation';
    this.lastMessage = data.lastMessage || null;
    this.createdAt = data.createdAt || new Date();
    this.updatedAt = data.updatedAt || new Date();
    this.metadata = data.metadata || {};
  }

  static collection() {
    return firestore.collection('conversations');
  }

  static async create(data) {
    const conversation = new Conversation(data);
    const docRef = await this.collection().add({
      userId: conversation.userId,
      spaceIds: conversation.spaceIds,
      title: conversation.title,
      lastMessage: conversation.lastMessage,
      createdAt: conversation.createdAt,
      updatedAt: conversation.updatedAt,
      metadata: conversation.metadata
    });
    conversation.id = docRef.id;
    return conversation;
  }

  static async findById(id) {
    const doc = await this.collection().doc(id).get();
    if (!doc.exists) {
      return null;
    }
    return new Conversation({ id: doc.id, ...doc.data() });
  }

  static async findByUserId(userId, spaceId = null) {
    let query = this.collection().where('userId', '==', userId);
    
    if (spaceId) {
      query = query.where('spaceIds', 'array-contains', spaceId);
    }
    
    const snapshot = await query.orderBy('updatedAt', 'desc').get();
    return snapshot.docs.map(doc => new Conversation({ id: doc.id, ...doc.data() }));
  }

  async save() {
    this.updatedAt = new Date();
    if (this.id) {
      await Conversation.collection().doc(this.id).update({
        title: this.title,
        spaceIds: this.spaceIds,
        lastMessage: this.lastMessage,
        updatedAt: this.updatedAt,
        metadata: this.metadata
      });
    } else {
      const created = await Conversation.create(this);
      this.id = created.id;
    }
    return this;
  }

  async delete() {
    if (this.id) {
      await Conversation.collection().doc(this.id).delete();
    }
  }
}

module.exports = Conversation;