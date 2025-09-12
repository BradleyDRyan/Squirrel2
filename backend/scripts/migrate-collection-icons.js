#!/usr/bin/env node

/**
 * Migration script to update collection icons from emojis to SF Symbols
 */

// Load environment variables
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

// Use the existing Firebase configuration
const { firestore } = require('../src/config/firebase');
const db = firestore;

// Mapping of emojis to SF Symbol names
const iconMapping = {
  '📝': 'doc.text',
  '🍞': 'fork.knife',
  '✈️': 'airplane',
  '📚': 'book',
  '🎬': 'film',
  '🎵': 'music.note',
  '💪': 'figure.walk',
  '🍽️': 'fork.knife',
  '📷': 'camera',
  '💡': 'lightbulb',
  '💼': 'briefcase',
  '🌱': 'leaf',
  '🐾': 'pawprint',
  '📂': 'folder',
  '⭐': 'star',
  '❤️': 'heart',
  '📖': 'book',
  '🎯': 'target',
  '🏠': 'house',
  '🚗': 'car',
  '⚡': 'bolt',
  '🔥': 'flame',
  '💰': 'dollarsign.circle',
  '📊': 'chart.bar',
  '🎨': 'paintpalette',
  '🎮': 'gamecontroller',
  '⚽': 'sportscourt',
  '🏃': 'figure.run',
  '🍔': 'fork.knife',
  '☕': 'cup.and.saucer',
  '🌍': 'globe',
  '📱': 'iphone',
  '💻': 'laptopcomputer',
  '🔧': 'wrench',
  '🔨': 'hammer',
  '📦': 'shippingbox',
  '🎁': 'gift',
  '🔔': 'bell',
  '📅': 'calendar',
  '⏰': 'alarm',
  '🔒': 'lock',
  '🔑': 'key',
  '📍': 'mappin',
  '🗺️': 'map',
  '💭': 'bubble.left',
  '💬': 'message',
  '📢': 'megaphone',
  '🔍': 'magnifyingglass',
  '📈': 'chart.line.uptrend.xyaxis',
  '📉': 'chart.line.downtrend.xyaxis',
  '✉️': 'envelope',
  '📮': 'envelope.open',
  '📎': 'paperclip',
  '✏️': 'pencil',
  '✒️': 'pencil.tip',
  '📐': 'ruler',
  '📏': 'ruler',
  '🔗': 'link',
  '📌': 'pin',
  '✂️': 'scissors',
  '🗂️': 'folder',
  '🗄️': 'archivebox',
  '🗑️': 'trash',
  '⚙️': 'gearshape',
  '🔮': 'sparkles',
  '🎪': 'theatermasks',
  '🎭': 'theatermasks',
  '🎪': 'tent',
  '🏆': 'trophy',
  '🥇': 'medal',
  '🎖️': 'medal',
  '🏅': 'medal',
  '⚽': 'soccer',
  '🏀': 'basketball',
  '🏈': 'football',
  '⚾': 'baseball',
  '🎾': 'tennis.racket',
  '🏐': 'volleyball',
  '🎳': 'figure.bowling',
  '🏋️': 'figure.strengthtraining.traditional',
  '🚴': 'figure.outdoor.cycle',
  '🏊': 'figure.pool.swim',
  '🧘': 'figure.yoga',
  '🛒': 'cart',
  '🎤': 'mic',
  '🎧': 'headphones',
  '🎸': 'guitars',
  '🎹': 'piano',
  '🥁': 'music.note',
  '📻': 'radio',
  '📺': 'tv',
  '📹': 'video',
  '📸': 'camera',
  '🔊': 'speaker.wave.3',
  '🔇': 'speaker.slash',
  '🔈': 'speaker',
  '📣': 'megaphone',
  '📯': 'megaphone',
  '🔕': 'bell.slash',
  '🎼': 'music.note.list',
  '🎶': 'music.note',
  '🎙️': 'mic',
  '🎚️': 'slider.horizontal.3',
  '🎛️': 'dial.min',
  '📲': 'iphone.radiowaves.left.and.right',
  '📞': 'phone',
  '☎️': 'phone',
  '📟': 'flipphone',
  '📠': 'faxmachine',
  '🔌': 'powerplug',
  '💡': 'lightbulb',
  '🔦': 'flashlight.off.fill',
  '🕯️': 'flame',
  '💎': 'diamond',
  '🧲': 'cpu',
  '🧪': 'testtube.2',
  '🧬': 'atom',
  '🔬': 'microscope',
  '🔭': 'binoculars',
  '📡': 'antenna.radiowaves.left.and.right',
  '💊': 'pills',
  '💉': 'syringe',
  '🩺': 'stethoscope',
  '🌡️': 'thermometer',
  '🧹': 'trash',
  '🧺': 'basket',
  '🧻': 'toilet.paper',
  '🚿': 'shower',
  '🛁': 'bathtub',
  '🛏️': 'bed.double',
  '🚪': 'door.left.hand.open',
  '🪟': 'window.vertical.open',
  '🪑': 'chair',
  '🚽': 'toilet',
  '🧼': 'hands.and.sparkles',
  '🧽': 'hands.and.sparkles',
  '🧴': 'hands.and.sparkles',
  '🏠': 'house',
  '🏡': 'house',
  '🏢': 'building.2',
  '🏬': 'building.2',
  '🏭': 'building.2',
  '🏗️': 'building.2',
  '🏘️': 'building.2',
  '🏚️': 'house',
  '🛖': 'house',
  '⛺': 'tent',
  '🏕️': 'tent',
  '🏞️': 'photo',
  '🏜️': 'sun.max',
  '🏖️': 'beach.umbrella',
  '🏝️': 'island',
  '🌋': 'mountain.2',
  '⛰️': 'mountain.2',
  '🏔️': 'mountain.2',
  '🗻': 'mountain.2',
  '🏛️': 'building.columns',
  '🕌': 'building',
  '🕍': 'building',
  '⛪': 'building',
  '🕋': 'building',
  '⛩️': 'building',
  '🛤️': 'road.lanes',
  '🛣️': 'road.lanes',
  '🗾': 'map',
  '🎌': 'flag',
  '🏴': 'flag',
  '🏳️': 'flag',
  '🚩': 'flag',
  '🚁': 'airplane',
  '🛸': 'airplane',
  '🚀': 'airplane.departure',
  '🛰️': 'antenna.radiowaves.left.and.right'
};

async function migrateCollections() {
  try {
    console.log('Starting collection icon migration...');
    
    // Get all collections
    const collectionsSnapshot = await db.collection('collections').get();
    
    if (collectionsSnapshot.empty) {
      console.log('No collections found.');
      return;
    }
    
    console.log(`Found ${collectionsSnapshot.size} collections to check.`);
    
    let updatedCount = 0;
    let skippedCount = 0;
    
    // Process each collection
    for (const doc of collectionsSnapshot.docs) {
      const collection = doc.data();
      const currentIcon = collection.icon;
      
      // Check if icon needs migration
      if (currentIcon && iconMapping[currentIcon]) {
        const newIcon = iconMapping[currentIcon];
        
        console.log(`Updating collection "${collection.name}" (${doc.id}): ${currentIcon} → ${newIcon}`);
        
        await doc.ref.update({
          icon: newIcon,
          updatedAt: new Date()
        });
        
        updatedCount++;
      } else if (currentIcon && !currentIcon.includes('.')) {
        // If it's not in our mapping and doesn't look like an SF Symbol, set default
        console.log(`Setting default icon for collection "${collection.name}" (${doc.id}): ${currentIcon} → doc.text`);
        
        await doc.ref.update({
          icon: 'doc.text',
          updatedAt: new Date()
        });
        
        updatedCount++;
      } else {
        console.log(`Skipping collection "${collection.name}" (${doc.id}): already using SF Symbol "${currentIcon}"`);
        skippedCount++;
      }
    }
    
    console.log('\nMigration complete!');
    console.log(`Updated: ${updatedCount} collections`);
    console.log(`Skipped: ${skippedCount} collections`);
    
  } catch (error) {
    console.error('Error during migration:', error);
    process.exit(1);
  }
  
  process.exit(0);
}

// Run the migration
migrateCollections();