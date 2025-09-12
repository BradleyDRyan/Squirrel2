const { firestore } = require('../config/firebase');

class Message {
  constructor(data = {}) {
    this.id = data.id || null;
    this.conversationId = data.conversationId || null;
    this.userId = data.userId || null;
    this.content = data.content || '';
    this.type = data.type || 'text';
    this.photoId = data.photoId || null; // Reference to Photo object
    this.attachments = data.attachments || []; // Backward compatibility
    this.createdAt = data.createdAt || new Date();
    this.editedAt = data.editedAt || null;
    this.metadata = data.metadata || {};
  }

  static collection() {
    return firestore.collection('messages');
  }

  static async create(data) {
    const message = new Message(data);
    const docRef = await this.collection().add({
      conversationId: message.conversationId,
      userId: message.userId,
      content: message.content,
      type: message.type,
      photoId: message.photoId,
      attachments: message.attachments,
      createdAt: message.createdAt,
      editedAt: message.editedAt,
      metadata: message.metadata
    });
    message.id = docRef.id;
    
    // Update the document with its ID
    await docRef.update({ id: docRef.id });
    
    return message;
  }

  static async findById(id) {
    const doc = await this.collection().doc(id).get();
    if (!doc.exists) {
      return null;
    }
    return new Message({ id: doc.id, ...doc.data() });
  }

  static async findByConversationId(conversationId, limit = 50) {
    const snapshot = await this.collection()
      .where('conversationId', '==', conversationId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();
    
    return snapshot.docs.map(doc => new Message({ id: doc.id, ...doc.data() })).reverse();
  }

  async save() {
    if (this.id) {
      this.editedAt = new Date();
      await Message.collection().doc(this.id).update({
        content: this.content,
        photoId: this.photoId,
        attachments: this.attachments,
        editedAt: this.editedAt,
        metadata: this.metadata
      });
    } else {
      const created = await Message.create(this);
      this.id = created.id;
    }
    return this;
  }

  async delete() {
    if (this.id) {
      await Message.collection().doc(this.id).delete();
    }
  }
}

module.exports = Message;