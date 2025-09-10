/**
 * Convert Firestore timestamps to ISO8601 strings
 */
function formatFirestoreDate(date) {
  if (!date) return null;
  
  // Handle Firestore Timestamp objects
  if (date.toDate && typeof date.toDate === 'function') {
    return date.toDate().toISOString();
  }
  
  // Handle regular Date objects
  if (date instanceof Date) {
    return date.toISOString();
  }
  
  // Already a string, return as-is
  if (typeof date === 'string') {
    return date;
  }
  
  return null;
}

/**
 * Recursively format all dates in an object
 */
function formatDatesInObject(obj) {
  if (!obj || typeof obj !== 'object') return obj;
  
  const result = Array.isArray(obj) ? [] : {};
  
  for (const key in obj) {
    const value = obj[key];
    
    // Check if this looks like a date field
    if (key === 'createdAt' || key === 'updatedAt' || key === 'lastEntryAt' || key === 'completedAt' || key === 'dueDate') {
      result[key] = formatFirestoreDate(value);
    } else if (value && typeof value === 'object') {
      // Recursively format nested objects
      result[key] = formatDatesInObject(value);
    } else {
      result[key] = value;
    }
  }
  
  return result;
}

module.exports = {
  formatFirestoreDate,
  formatDatesInObject
};