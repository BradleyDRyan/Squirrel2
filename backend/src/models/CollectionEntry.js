const { firestore } = require('../config/firebase');

class CollectionEntry {
  constructor(data = {}) {
    this.id = data.id || null;
    this.entryId = data.entryId || null;  // Reference to Entry
    this.collectionId = data.collectionId || null;  // Reference to Collection
    this.userId = data.userId || null;
    this.formattedData = data.formattedData || {};  // Extracted/formatted fields
    this.userOverrides = data.userOverrides || null;  // Manual edits
    this.createdAt = data.createdAt || new Date();
    this.lastProcessedAt = data.lastProcessedAt || new Date();
    this.metadata = data.metadata || {};
  }

  static collection() {
    return firestore.collection('collection_entries');
  }

  static async create(data) {
    const collectionEntry = new CollectionEntry(data);
    const docRef = await this.collection().add({
      entryId: collectionEntry.entryId,
      collectionId: collectionEntry.collectionId,
      userId: collectionEntry.userId,
      formattedData: collectionEntry.formattedData,
      userOverrides: collectionEntry.userOverrides,
      createdAt: collectionEntry.createdAt,
      lastProcessedAt: collectionEntry.lastProcessedAt,
      metadata: collectionEntry.metadata
    });
    collectionEntry.id = docRef.id;
    return collectionEntry;
  }

  static async findById(id) {
    const doc = await this.collection().doc(id).get();
    if (!doc.exists) return null;
    
    return new CollectionEntry({
      id: doc.id,
      ...doc.data()
    });
  }

  static async findByEntry(entryId) {
    const snapshot = await this.collection()
      .where('entryId', '==', entryId)
      .get();
    
    return snapshot.docs.map(doc => new CollectionEntry({
      id: doc.id,
      ...doc.data()
    }));
  }

  static async findByCollection(collectionId) {
    const snapshot = await this.collection()
      .where('collectionId', '==', collectionId)
      .orderBy('createdAt', 'desc')
      .get();
    
    return snapshot.docs.map(doc => new CollectionEntry({
      id: doc.id,
      ...doc.data()
    }));
  }

  static async findByCollectionAndUser(collectionId, userId) {
    const snapshot = await this.collection()
      .where('collectionId', '==', collectionId)
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .get();
    
    return snapshot.docs.map(doc => new CollectionEntry({
      id: doc.id,
      ...doc.data()
    }));
  }

  static async findExisting(entryId, collectionId) {
    const snapshot = await this.collection()
      .where('entryId', '==', entryId)
      .where('collectionId', '==', collectionId)
      .limit(1)
      .get();
    
    if (snapshot.empty) return null;
    
    const doc = snapshot.docs[0];
    return new CollectionEntry({
      id: doc.id,
      ...doc.data()
    });
  }

  // Alias for findExisting for clarity
  static async findByEntryAndCollection(entryId, collectionId) {
    return this.findExisting(entryId, collectionId);
  }

  async save() {
    if (!this.id) {
      throw new Error('Cannot save CollectionEntry without ID');
    }
    
    await CollectionEntry.collection().doc(this.id).update({
      formattedData: this.formattedData,
      userOverrides: this.userOverrides,
      lastProcessedAt: new Date(),
      metadata: this.metadata
    });
    
    return this;
  }

  async reprocess(entryContent, collectionFormat) {
    // This will be implemented with AI extraction service
    // For now, just update the timestamp
    this.lastProcessedAt = new Date();
    return this.save();
  }

  async delete() {
    if (!this.id) {
      throw new Error('Cannot delete CollectionEntry without ID');
    }
    
    await CollectionEntry.collection().doc(this.id).delete();
  }

  // Get display data (formatted + overrides)
  getDisplayData() {
    if (!this.userOverrides) {
      return this.formattedData;
    }
    
    // Merge overrides on top of formatted data
    return {
      ...this.formattedData,
      ...this.userOverrides
    };
  }
}

module.exports = CollectionEntry;