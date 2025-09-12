const { db, admin } = require('../config/firebase');

class Photo {
  constructor(data) {
    this.id = data.id || '';
    this.userId = data.userId || '';
    
    // Storage URLs for different sizes
    this.urls = {
      original: data.urls?.original || '',
      thumbnail: data.urls?.thumbnail || null, // 150x150
      small: data.urls?.small || null,         // 400x400
      medium: data.urls?.medium || null,       // 800x800
      large: data.urls?.large || null          // 1600x1600
    };
    
    // Storage paths for management
    this.storagePaths = {
      original: data.storagePaths?.original || '',
      thumbnail: data.storagePaths?.thumbnail || null,
      small: data.storagePaths?.small || null,
      medium: data.storagePaths?.medium || null,
      large: data.storagePaths?.large || null
    };
    
    // Image metadata
    this.mimeType = data.mimeType || 'image/jpeg';
    this.originalSize = data.originalSize || 0;
    this.dimensions = {
      width: data.dimensions?.width || null,
      height: data.dimensions?.height || null
    };
    
    // AI Analysis results
    this.analysis = {
      description: data.analysis?.description || '',
      collectionName: data.analysis?.collectionName || '',
      suggestedTitle: data.analysis?.suggestedTitle || '',
      tags: data.analysis?.tags || []
    };
    
    // Timestamps
    this.createdAt = data.createdAt || new Date();
    this.updatedAt = data.updatedAt || new Date();
    
    // Additional metadata
    this.metadata = data.metadata || {};
  }

  // Convert to Firestore document format
  toFirestore() {
    return {
      userId: this.userId,
      urls: this.urls,
      storagePaths: this.storagePaths,
      mimeType: this.mimeType,
      originalSize: this.originalSize,
      dimensions: this.dimensions,
      analysis: this.analysis,
      createdAt: admin.firestore.Timestamp.fromDate(this.createdAt),
      updatedAt: admin.firestore.Timestamp.fromDate(this.updatedAt),
      metadata: this.metadata
    };
  }

  // Create a new photo document
  static async create(photoData) {
    const photo = new Photo(photoData);
    const docRef = await db.collection('photos').add(photo.toFirestore());
    photo.id = docRef.id;
    
    // Update the document with its ID
    await docRef.update({ id: docRef.id });
    
    console.log('✅ [Photo] Created with ID:', photo.id);
    return photo;
  }

  // Find photo by ID
  static async findById(photoId) {
    const doc = await db.collection('photos').doc(photoId).get();
    if (!doc.exists) {
      return null;
    }
    
    const data = doc.data();
    return new Photo({
      id: doc.id,
      ...data,
      createdAt: data.createdAt?.toDate() || new Date(),
      updatedAt: data.updatedAt?.toDate() || new Date()
    });
  }

  // Find photos by user
  static async findByUserId(userId, limit = 100) {
    const snapshot = await db.collection('photos')
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();
    
    return snapshot.docs.map(doc => {
      const data = doc.data();
      return new Photo({
        id: doc.id,
        ...data,
        createdAt: data.createdAt?.toDate() || new Date(),
        updatedAt: data.updatedAt?.toDate() || new Date()
      });
    });
  }

  // Update photo sizes (after processing)
  async updateSizes(sizes) {
    if (sizes.thumbnail) {
      this.urls.thumbnail = sizes.thumbnail.url;
      this.storagePaths.thumbnail = sizes.thumbnail.path;
    }
    if (sizes.small) {
      this.urls.small = sizes.small.url;
      this.storagePaths.small = sizes.small.path;
    }
    if (sizes.medium) {
      this.urls.medium = sizes.medium.url;
      this.storagePaths.medium = sizes.medium.path;
    }
    if (sizes.large) {
      this.urls.large = sizes.large.url;
      this.storagePaths.large = sizes.large.path;
    }
    
    this.updatedAt = new Date();
    
    await db.collection('photos').doc(this.id).update({
      urls: this.urls,
      storagePaths: this.storagePaths,
      updatedAt: admin.firestore.Timestamp.fromDate(this.updatedAt)
    });
    
    console.log('✅ [Photo] Updated sizes for:', this.id);
  }

  // Delete photo and all its sizes from storage
  async delete() {
    const { getStorage } = require('firebase-admin/storage');
    const storage = getStorage();
    const bucket = storage.bucket();
    
    // Delete all sizes from storage
    const deletePromises = [];
    for (const [size, path] of Object.entries(this.storagePaths)) {
      if (path) {
        deletePromises.push(
          bucket.file(path).delete()
            .then(() => console.log(`✅ [Photo] Deleted ${size} from storage:`, path))
            .catch(err => console.error(`❌ [Photo] Error deleting ${size}:`, err))
        );
      }
    }
    
    await Promise.all(deletePromises);
    
    // Delete from Firestore
    await db.collection('photos').doc(this.id).delete();
    console.log('✅ [Photo] Deleted from database:', this.id);
  }

  // Get the best available URL for a given size preference
  getBestUrl(preferredSize = 'medium') {
    const sizeOrder = ['medium', 'small', 'large', 'original', 'thumbnail'];
    
    // Start with preferred size
    if (this.urls[preferredSize]) {
      return this.urls[preferredSize];
    }
    
    // Fall back to other sizes
    for (const size of sizeOrder) {
      if (this.urls[size]) {
        return this.urls[size];
      }
    }
    
    // Last resort - original
    return this.urls.original;
  }
}

module.exports = Photo;