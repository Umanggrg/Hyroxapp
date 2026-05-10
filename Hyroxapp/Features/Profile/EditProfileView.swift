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

            // Handle gets its own row-group so the live-preview / validation
            // hint can live inline. `VStack(alignment: .leading, spacing: 4)`
            // keeps the helper text snug under the field.
            VStack(alignment: .leading, spacing: 6) {
                TextField("Handle", text: $handle)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                handleHelper
            }
            .listRowBackground(Color.surface)

            TextField("Location", text: $location)
                .listRowBackground(Color.surface)
        }
    }

    // Live preview of the saved handle + validation feedback. When empty,
    // nothing shows (the placeholder is self-explanatory). When non-empty:
    //   - valid   → green "Will save as @foo"
    //   - invalid → red explanation of which rule failed
    @ViewBuilder
    private var handleHelper: some View {
        let trimmed = handle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let normalized = Self.normalizedHandle(trimmed)
            if let error = Self.handleValidationError(for: normalized) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.warning)
            } else {
                Text("Will save as @\(normalized)")
                    .font(.caption)
                    .foregroundStyle(Color.success)
            }
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
        ZStack {
            // Coral spotlight halo behind the avatar — same visual
            // language as ProfileHero's hero treatment. Reads as
            // "this is the identity moment" rather than a flat
            // form-field. Kept low opacity so it doesn't compete
            // with the photo itself.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accent.opacity(0.22),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)
                .blur(radius: 8)

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
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.accent.opacity(0.7),
                            Color.accent.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
            )
            .shadow(color: Color.accent.opacity(0.25), radius: 12, y: 4)
        }
        .frame(height: 180)
        .padding(.vertical, 8)
    }

    // MARK: - Logic

    // Name has to be non-empty, handle has to normalize to something that
    // matches the allowed character set + length rules. Used to gate the
    // Save button so bad data never reaches the SwiftData model.
    private var isValid: Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }

        let normalized = Self.normalizedHandle(handle)
        return Self.handleValidationError(for: normalized) == nil
    }

    private func save() {
        profile.displayName = displayName.trimmingCharacters(in: .whitespaces)
        // Always write the normalized form — strips stray @, whitespace,
        // mixed casing. Ensures the DB-facing handle is a predictable shape
        // long before Supabase enforces uniqueness on it.
        profile.handle = Self.normalizedHandle(handle)
        profile.location = location.trimmingCharacters(in: .whitespaces)
        profile.bio = bio.trimmingCharacters(in: .whitespaces)
        profile.avatarData = avatarData
        profile.updatedAt = Date()
        try? modelContext.save()

        // Write-through to Supabase. Captured profile reference
        // survives the dismiss + Task suspension (it's a SwiftData
        // @Model class — reference type, persisted on the
        // capturedRun pattern we used for race rehydrate). Errors
        // are swallowed; the next bootstrap or save retries via
        // the syncOnSignIn last-write-wins path. UI doesn't block
        // on this — `dismiss` runs synchronously below.
        let snapshot = profile
        if let userID = profile.remoteUserID {
            Task { @MainActor in
                try? await ProfileSyncService.pushLocalProfile(
                    snapshot,
                    userID: userID
                )
            }
        }

        dismiss()
    }

    // MARK: - Handle helpers

    // Allowed handle alphabet: lowercase letters, digits, underscores. Max
    // length is 20, in line with what most social apps cap usernames at.
    // Min 3 because anything shorter is painful to disambiguate and makes
    // uniqueness collisions worse when the cloud lands.
    private static let handlePattern = /^[a-z0-9_]{3,20}$/
    private static let handleMaxLength = 20
    private static let handleMinLength = 3

    // Normalize a raw handle string:
    //   1. Trim whitespace
    //   2. Drop a single leading `@` if present (users often type it out
    //      of habit; the storage form doesn't carry the sigil)
    //   3. Lowercase
    // The result isn't guaranteed valid — it just gets us to the canonical
    // form we'll then validate against the pattern.
    static func normalizedHandle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("@") {
            s.removeFirst()
        }
        return s.lowercased()
    }

    // Returns a human-readable error message if the normalized handle is
    // invalid, or nil if it's clean. Kept deliberately short — this text
    // renders inline under the text field so brevity matters.
    static func handleValidationError(for normalized: String) -> String? {
        if normalized.isEmpty {
            return "Handle is required"
        }
        if normalized.count < handleMinLength {
            return "At least \(handleMinLength) characters"
        }
        if normalized.count > handleMaxLength {
            return "At most \(handleMaxLength) characters"
        }
        // Regex literal `/^[a-z0-9_]{3,20}$/` from Swift 5.7+ gives us
        // compile-checked matching. `.wholeMatch` returns nil when the
        // input fails the pattern.
        if (try? handlePattern.wholeMatch(in: normalized)) == nil {
            return "Letters, numbers, underscore only"
        }
        return nil
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
