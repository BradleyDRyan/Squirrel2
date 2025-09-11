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
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    private var entriesListener: ListenerRegistration?
    private let db = Firestore.firestore()
    private let collectionId: String
    
    init(collectionId: String) {
        self.collectionId = collectionId
    }
    
    func startListening(userId: String) {
        print("[CollectionDetailViewModel] Starting entries listener for collection: \(collectionId)")
        
        // Remove any existing listener
        stopListening()
        
        // Set up real-time listener for entries in this collection
        // Entries can belong to multiple collections (many-to-many)
        // Note: Removed orderBy to avoid composite index requirement with arrayContains
        entriesListener = db.collection("entries")
            .whereField("collectionIds", arrayContains: collectionId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("[CollectionDetailViewModel] Error listening to entries: \(error)")
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("[CollectionDetailViewModel] No documents in snapshot")
                    Task { @MainActor in
                        self.entries = []
                        self.isLoading = false
                    }
                    return
                }
                
                print("[CollectionDetailViewModel] Received \(documents.count) entries from snapshot")
                
                let newEntries = documents.compactMap { document -> Entry? in
                    let data = document.data()
                    
                    // Parse the entry data
                    guard let content = data["content"] as? String,
                          let userId = data["userId"] as? String else {
                        print("[CollectionDetailViewModel] Missing required fields in document: \(document.documentID)")
                        return nil
                    }
                    
                    // Create a dictionary for JSON decoding
                    let entryData: [String: Any] = [
                        "id": document.documentID,
                        "userId": userId,
                        "collectionIds": data["collectionIds"] as? [String] ?? [self.collectionId],
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
                    
                    // Convert to JSON and decode
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
                    // Sort entries by createdAt date descending (newest first)
                    self.entries = newEntries.sorted { $0.createdAt > $1.createdAt }
                    self.isLoading = false
                    self.errorMessage = nil
                    print("[CollectionDetailViewModel] Updated entries list with \(self.entries.count) items")
                }
            }
    }
    
    func stopListening() {
        entriesListener?.remove()
        entriesListener = nil
    }
    
    deinit {
        // Cleanup is handled by the listener itself when the object is deallocated
        entriesListener?.remove()
    }
}
