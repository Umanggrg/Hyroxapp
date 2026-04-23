import SwiftUI
import SwiftData
import PhotosUI

#if canImport(UIKit)
import UIKit
#endif

// Sheet for editing the user's profile. Takes the existing `UserProfile`
// model, shadows its fields into `@State` drafts so edits don't leak into
// the Header view behind the sheet until the user explicitly taps Save.
//
// iOS-only for now: the file guards on `canImport(UIKit)` because the
// avatar preview and image compression depend on `UIImage`. The whole
// edit-profile flow doesn't apply to a hypothetical macOS build until we
// replace that with a cross-platform image type.
#if canImport(UIKit)
struct EditProfileView: View {
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Draft state. These shadow the model's fields so the sheet can cancel
    // cleanly. @State initializers in an init are fine here — `@State`
    // respects first-run seeding and ignores subsequent init calls.
    @State private var displayName: String
    @State private var handle: String
    @State private var location: String
    @State private var bio: String
    @State private var avatarData: Data?

    @State private var photoItem: PhotosPickerItem?

    init(profile: UserProfile) {
        self.profile = profile
        _displayName = State(initialValue: profile.displayName)
        _handle = State(initialValue: profile.handle)
        _location = State(initialValue: profile.location)
        _bio = State(initialValue: profile.bio)
        _avatarData = State(initialValue: profile.avatarData)
    }

    var body: some View {
        NavigationStack {
            Form {
                avatarSection
                detailsSection
                bioSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.background)
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                loadPhoto(newItem)
            }
        }
    }

    // MARK: - Sections

    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                avatarPreview
                Spacer()
            }
            .listRowBackground(Color.surface)

            PhotosPicker(
                selection: $photoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(avatarData == nil ? "Add Photo" : "Change Photo",
                      systemImage: "camera")
            }
            .listRowBackground(Color.surface)

            if avatarData != nil {
                Button(role: .destructive) {
                    avatarData = nil
                    photoItem = nil
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
                .listRowBackground(Color.surface)
            }
        }
    }

    private var detailsSection: some View {
        Section("Profile") {
            TextField("Name", text: $displayName)
                .listRowBackground(Color.surface)
            TextField("Handle", text: $handle)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .listRowBackground(Color.surface)
            TextField("Location", text: $location)
                .listRowBackground(Color.surface)
        }
    }

    private var bioSection: some View {
        Section("Bio") {
            TextField("Say something", text: $bio, axis: .vertical)
                .lineLimit(3...6)
                .listRowBackground(Color.surface)
        }
    }

    private var avatarPreview: some View {
        Group {
            if let data = avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Color.textTertiary, Color.surfaceElevated)
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.divider, lineWidth: 1)
        )
        .padding(.vertical, 8)
    }

    // MARK: - Logic

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !handle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        profile.displayName = displayName.trimmingCharacters(in: .whitespaces)
        profile.handle = handle.trimmingCharacters(in: .whitespaces)
        profile.location = location.trimmingCharacters(in: .whitespaces)
        profile.bio = bio.trimmingCharacters(in: .whitespaces)
        profile.avatarData = avatarData
        profile.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        // Off-main image loading + compression. The picker gives us raw
        // transferable data; we downscale to a reasonable avatar size so
        // the SwiftData row stays small (and cloud-sync-friendly later).
        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                return
            }
            avatarData = compressedAvatarJPEG(from: data, maxDimension: 512)
        }
    }

    // Resize to fit within a 512pt square and re-encode as JPEG at 0.7.
    // An avatar at 120pt on screen doesn't need anything bigger; this
    // keeps profile rows well under 100KB even for camera-roll originals.
    private func compressedAvatarJPEG(from data: Data, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let size = image.size
        let longest = max(size.width, size.height)
        let scaled: UIImage = {
            guard longest > maxDimension else { return image }
            let factor = maxDimension / longest
            let newSize = CGSize(width: size.width * factor, height: size.height * factor)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }()

        return scaled.jpegData(compressionQuality: 0.7)
    }
}
#endif
