//
//  CollectionDetailViewModel.swift
//  Squirrel2
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class CollectionDetailViewModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var collectionEntries: [CollectionEntry] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    private var collectionEntriesListener: ListenerRegistration?
    private var entriesListener: ListenerRegistration?
    private let db = Firestore.firestore()
    private let collectionId: String
    
    init(collectionId: String) {
        self.collectionId = collectionId
    }
    
    func startListening(userId: String) {
        print("[CollectionDetailViewModel] Starting listeners for collection: \(collectionId)")
        
        // Remove any existing listeners
        stopListening()
        
        // Listen to CollectionEntries for this collection
        collectionEntriesListener = db.collection("collection_entries")
            .whereField("collectionId", isEqualTo: collectionId)
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("[CollectionDetailViewModel] Error listening to collection_entries: \(error)")
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("[CollectionDetailViewModel] No collection_entries documents")
                    Task { @MainActor in
                        self.collectionEntries = []
                        self.entries = []
                        self.isLoading = false
                    }
                    return
                }
                
                print("[CollectionDetailViewModel] Received \(documents.count) collection_entries")
                
                // Parse CollectionEntry documents
                let newCollectionEntries = documents.compactMap { document -> CollectionEntry? in
                    let data = document.data()
                    
                    guard let entryId = data["entryId"] as? String,
                          let collectionId = data["collectionId"] as? String,
                          let userId = data["userId"] as? String else {
                        print("[CollectionDetailViewModel] Missing required fields in collection_entry: \(document.documentID)")
                        return nil
                    }
                    
                    // Parse dates
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let lastProcessedAt = (data["lastProcessedAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    // Note: We're not fully parsing formattedData/userOverrides here
                    // since they have mixed types. They'll be empty for now.
                    var collectionEntry = CollectionEntry(
                        id: document.documentID,
                        entryId: entryId,
                        collectionId: collectionId,
                        userId: userId,
                        formattedData: data["formattedData"] as? [String: Any] ?? [:],
                        userOverrides: data["userOverrides"] as? [String: Any],
                        createdAt: createdAt,
                        lastProcessedAt: lastProcessedAt,
                        metadata: data["metadata"] as? [String: String]
                    )
                    
                    return collectionEntry
                }
                
                Task { @MainActor in
                    self.collectionEntries = newCollectionEntries.sorted { $0.createdAt > $1.createdAt }
                    
                    // Now fetch the actual Entry documents
                    self.fetchEntries(for: newCollectionEntries)
                }
            }
    }
    
    private func fetchEntries(for collectionEntries: [CollectionEntry]) {
        guard !collectionEntries.isEmpty else {
            self.entries = []
            self.isLoading = false
            return
        }
        
        let entryIds = collectionEntries.map { $0.entryId }
        
        // Listen to the actual Entry documents
        entriesListener = db.collection("entries")
            .whereField(FieldPath.documentID(), in: entryIds)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("[CollectionDetailViewModel] Error fetching entries: \(error)")
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    Task { @MainActor in
                        self.entries = []
                        self.isLoading = false
                    }
                    return
                }
                
                print("[CollectionDetailViewModel] Fetched \(documents.count) entries")
                
                let newEntries = documents.compactMap { document -> Entry? in
                    let data = document.data()
                    
                    guard let content = data["content"] as? String,
                          let userId = data["userId"] as? String else {
                        print("[CollectionDetailViewModel] Missing required fields in entry: \(document.documentID)")
                        return nil
                    }
                    
                    // Create Entry - note: no collectionIds field anymore
                    let entryData: [String: Any] = [
                        "id": document.documentID,
                        "userId": userId,
                        "spaceIds": data["spaceIds"] as? [String] ?? [],
                        "conversationId": data["conversationId"] as? String,
                        "title": data["title"] as? String ?? "",
                        "content": content,
                        "type": data["type"] as? String ?? "note",
                        "mood": data["mood"] as? String,
                        "tags": data["tags"] as? [String] ?? [],
                        "attachments": data["attachments"] as? [String] ?? [],
                        "location": data["location"],
                        "weather": data["weather"],
                        "createdAt": (data["createdAt"] as? Timestamp)?.dateValue().ISO8601Format() ?? Date().ISO8601Format(),
                        "updatedAt": (data["updatedAt"] as? Timestamp)?.dateValue().ISO8601Format() ?? Date().ISO8601Format(),
                        "metadata": data["metadata"]
                    ].compactMapValues { $0 }
                    
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: entryData)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        return try decoder.decode(Entry.self, from: jsonData)
                    } catch {
                        print("[CollectionDetailViewModel] Error decoding entry \(document.documentID): \(error)")
                        return nil
                    }
                }
                
                Task { @MainActor in
                    // Sort entries based on CollectionEntry order
                    let entryDict = Dictionary(uniqueKeysWithValues: newEntries.map { ($0.id, $0) })
                    self.entries = self.collectionEntries.compactMap { entryDict[$0.entryId] }
                    self.isLoading = false
                    self.errorMessage = nil
                    print("[CollectionDetailViewModel] Updated with \(self.entries.count) entries")
                }
            }
    }
    
    func stopListening() {
        collectionEntriesListener?.remove()
        collectionEntriesListener = nil
        entriesListener?.remove()
        entriesListener = nil
    }
    
    deinit {
        // Cleanup is handled by the listener itself when the object is deallocated
        collectionEntriesListener?.remove()
        entriesListener?.remove()
    }
}
