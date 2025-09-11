//
//  CollectionSettingsView.swift
//  Squirrel2
//
//  View for editing collection rules and entry format
//

import SwiftUI
import FirebaseAuth

struct CollectionSettingsView: View {
    let collection: Collection
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var firebaseManager: FirebaseManager
    
    // Instructions editing
    @State private var instructions: String = ""
    
    // Entry format editing
    @State private var entryFields: [EntryField] = []
    @State private var showingAddField = false
    
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    
    var body: some View {
        NavigationView {
            Form {
                // Collection Info Section
                Section("Collection Info") {
                    HStack {
                        Text("Icon")
                        Spacer()
                        Text(collection.icon)
                            .font(.title2)
                    }
                    
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(collection.name)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Instructions")
                        Spacer()
                        Text(collection.instructions.isEmpty ? "No instructions" : collection.instructions)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                // Instructions Section
                Section("Collection Instructions") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AI Instructions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $instructions)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .font(.caption)
                        
                        Text("Provide guidance to the AI about what type of content belongs in this collection")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Entry Format Section
                Section("Entry Format") {
                    if entryFields.isEmpty {
                        VStack(spacing: 12) {
                            Text("No custom fields defined")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            
                            Text("Add fields to structure how entries are formatted in this collection")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else {
                        ForEach(entryFields.indices, id: \.self) { index in
                            EntryFieldRow(field: entryFields[index], onDelete: {
                                entryFields.remove(at: index)
                            })
                        }
                    }
                    
                    Button(action: { showingAddField = true }) {
                        Label("Add Field", systemImage: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                
                // Stats Section
                Section("Statistics") {
                    HStack {
                        Text("Total Entries")
                        Spacer()
                        Text("\(collection.stats.entryCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastEntry = collection.stats.lastEntryAt {
                        HStack {
                            Text("Last Entry")
                            Spacer()
                            Text(lastEntry.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                
                // Delete Section
                Section {
                    Button(action: { showingDeleteConfirmation = true }) {
                        HStack {
                            Spacer()
                            Text("Delete Collection")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("This will permanently delete the collection. Entries will be preserved but no longer associated with this collection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Collection Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showingAddField) {
                AddFieldView { field in
                    entryFields.append(field)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog("Delete Collection", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteCollection()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete \"\(collection.name)\"? This action cannot be undone.")
            }
            .onAppear {
                loadCurrentSettings()
            }
        }
    }
    
    private func loadCurrentSettings() {
        // Load current instructions
        instructions = collection.instructions
        
        // Load current entry format
        if let format = collection.entryFormat {
            entryFields = format.fields
        }
    }
    
    private func saveChanges() {
        guard let user = firebaseManager.currentUser else {
            errorMessage = "Not authenticated"
            showingError = true
            return
        }
        
        isSaving = true
        
        // No rules anymore - just instructions
        
        // Prepare updated entry format
        let updatedFormat = entryFields.isEmpty ? nil : EntryFormat(
            fields: entryFields,
            version: collection.entryFormat?.version ?? 1
        )
        
        // Update collection via API
        Task {
            do {
                let token = try await user.getIDToken()
                guard let url = URL(string: "\(AppConfig.apiBaseURL)/collections/\(collection.id)") else { return }
                
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let updateData: [String: Any] = [
                    "instructions": instructions,
                    "entryFormat": updatedFormat != nil ? [
                        "fields": entryFields.map { field in
                            [
                                "key": field.key,
                                "label": field.label,
                                "type": field.type.rawValue,
                                "required": field.required,
                                "options": field.options as Any,
                                "min": field.min as Any,
                                "max": field.max as Any,
                                "multiline": field.multiline as Any,
                                "multiple": field.multiple as Any
                            ]
                        },
                        "version": updatedFormat?.version ?? 1
                    ] : nil
                ].compactMapValues { $0 }
                
                request.httpBody = try JSONSerialization.data(withJSONObject: updateData)
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    // Successfully updated - dismiss the view
                    // The parent view will refresh with the updated data from Firestore
                    await MainActor.run {
                        dismiss()
                    }
                } else {
                    throw NSError(domain: "CollectionUpdate", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to update collection"])
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }
        }
    }
    
    private func deleteCollection() {
        guard let user = firebaseManager.currentUser else {
            errorMessage = "Not authenticated"
            showingError = true
            return
        }
        
        isDeleting = true
        
        Task {
            do {
                let token = try await user.getIDToken()
                guard let url = URL(string: "\(AppConfig.apiBaseURL)/collections/\(collection.id)") else { return }
                
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 204 {
                    // Successfully deleted - dismiss the view
                    await MainActor.run {
                        dismiss()
                    }
                } else if let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 500 {
                    // Collection has entries - show error
                    throw NSError(domain: "CollectionDelete", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot delete collection with existing entries"])
                } else {
                    throw NSError(domain: "CollectionDelete", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to delete collection"])
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isDeleting = false
                }
            }
        }
    }
}

struct EntryFieldRow: View {
    let field: EntryField
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label)
                    .font(.body)
                
                HStack(spacing: 8) {
                    Text(field.type.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                    
                    if field.required {
                        Text("Required")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddFieldView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (EntryField) -> Void
    
    @State private var key = ""
    @State private var label = ""
    @State private var fieldType: EntryField.FieldType = .text
    @State private var isRequired = false
    @State private var options = ""
    @State private var min = ""
    @State private var max = ""
    @State private var isMultiline = false
    @State private var isMultiple = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Field Details") {
                    TextField("Key (e.g., title)", text: $key)
                        .textInputAutocapitalization(.never)
                    
                    TextField("Label (e.g., Movie Title)", text: $label)
                    
                    Picker("Type", selection: $fieldType) {
                        ForEach([EntryField.FieldType.text, .number, .date, .select, .boolean], id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    
                    Toggle("Required", isOn: $isRequired)
                }
                
                // Type-specific options
                if fieldType == .text {
                    Section("Text Options") {
                        Toggle("Multiline", isOn: $isMultiline)
                    }
                }
                
                if fieldType == .number {
                    Section("Number Options") {
                        TextField("Minimum Value", text: $min)
                            .keyboardType(.decimalPad)
                        
                        TextField("Maximum Value", text: $max)
                            .keyboardType(.decimalPad)
                    }
                }
                
                if fieldType == .select {
                    Section("Select Options") {
                        TextEditor(text: $options)
                            .frame(minHeight: 80)
                        
                        Text("Enter options separated by commas")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Toggle("Allow Multiple", isOn: $isMultiple)
                    }
                }
            }
            .navigationTitle("Add Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addField()
                    }
                    .disabled(key.isEmpty || label.isEmpty)
                }
            }
        }
    }
    
    private func addField() {
        let field: EntryField
        
        switch fieldType {
        case .text:
            field = EntryField(
                key: key,
                label: label,
                type: .text,
                required: isRequired,
                options: nil,
                min: nil,
                max: nil,
                multiline: isMultiline,
                multiple: nil
            )
        case .number:
            field = EntryField(
                key: key,
                label: label,
                type: .number,
                required: isRequired,
                options: nil,
                min: Double(min),
                max: Double(max),
                multiline: nil,
                multiple: nil
            )
        case .select:
            let optionsList = options.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            field = EntryField(
                key: key,
                label: label,
                type: .select,
                required: isRequired,
                options: optionsList.isEmpty ? nil : optionsList,
                min: nil,
                max: nil,
                multiline: nil,
                multiple: isMultiple
            )
        case .date:
            field = EntryField(
                key: key,
                label: label,
                type: .date,
                required: isRequired,
                options: nil,
                min: nil,
                max: nil,
                multiline: nil,
                multiple: nil
            )
        case .boolean:
            field = EntryField(
                key: key,
                label: label,
                type: .boolean,
                required: isRequired,
                options: nil,
                min: nil,
                max: nil,
                multiline: nil,
                multiple: nil
            )
        }
        
        onAdd(field)
        dismiss()
    }
}
