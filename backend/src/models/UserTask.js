const { firestore } = require('../config/firebase');

class UserTask {
  constructor(data = {}) {
    this.id = data.id || null;
    this.userId = data.userId || null;
    this.spaceIds = data.spaceIds || [];
    this.conversationId = data.conversationId || null;
    this.title = data.title || '';
    this.description = data.description || '';
    this.status = data.status || 'pending';
    this.priority = data.priority || 'medium';
    this.dueDate = data.dueDate || null;
    this.completedAt = data.completedAt || null;
    this.tags = data.tags || [];
    this.createdAt = data.createdAt || new Date();
    this.updatedAt = data.updatedAt || new Date();
    this.metadata = data.metadata || {};
  }

  static collection() {
    return firestore.collection('tasks');
  }

  static async create(data) {
    const task = new UserTask(data);
    const docRef = await this.collection().add({
      userId: task.userId,
      spaceIds: task.spaceIds,
      conversationId: task.conversationId,
      title: task.title,
      description: task.description,
      status: task.status,
      priority: task.priority,
      dueDate: task.dueDate,
      completedAt: task.completedAt,
      tags: task.tags,
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      metadata: task.metadata
    });
    task.id = docRef.id;
    return task;
  }

  static async findById(id) {
    const doc = await this.collection().doc(id).get();
    if (!doc.exists) {
      return null;
    }
    return new UserTask({ id: doc.id, ...doc.data() });
  }

  static async findByUserId(userId, filters = {}) {
    let query = this.collection().where('userId', '==', userId);
    
    if (filters.spaceId) {
      query = query.where('spaceIds', 'array-contains', filters.spaceId);
    }
    
    if (filters.status) {
      query = query.where('status', '==', filters.status);
    }
    
    if (filters.priority) {
      query = query.where('priority', '==', filters.priority);
    }
    
    if (filters.conversationId) {
      query = query.where('conversationId', '==', filters.conversationId);
    }
    
    const snapshot = await query.orderBy('createdAt', 'desc').get();
    return snapshot.docs.map(doc => new UserTask({ id: doc.id, ...doc.data() }));
  }

  static async findPending(userId) {
    return this.findByUserId(userId, { status: 'pending' });
  }

  static async findCompleted(userId) {
    return this.findByUserId(userId, { status: 'completed' });
  }

  async save() {
    this.updatedAt = new Date();
    if (this.id) {
      await UserTask.collection().doc(this.id).update({
        title: this.title,
        description: this.description,
        spaceIds: this.spaceIds,
        status: this.status,
        priority: this.priority,
        dueDate: this.dueDate,
        completedAt: this.completedAt,
        tags: this.tags,
        updatedAt: this.updatedAt,
        metadata: this.metadata
      });
    } else {
      const created = await UserTask.create(this);
      this.id = created.id;
    }
    return this;
  }

  async markComplete() {
    this.status = 'completed';
    this.completedAt = new Date();
    return this.save();
  }

  async delete() {
    if (this.id) {
      await UserTask.collection().doc(this.id).delete();
    }
  }
}

module.exports = UserTask;