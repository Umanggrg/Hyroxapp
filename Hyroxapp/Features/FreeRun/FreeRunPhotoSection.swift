import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(Auth)
import Auth
#endif

// Editable photo attachment for a FreeRun — mirrors
// `RacePhotoSection` so both surfaces share the same compress +
// upload + URL-fallback flow. Shipped on `FreeRunSummaryView`
// (post-finish) and reusable on a future FreeRunDetailView.
//
// State machine (same as RacePhotoSection):
//   • Empty                       → "Add a photo" tile
//   • Local bytes present         → photo render + Change/Remove
//   • Remote URL only (synced)    → AsyncImage render + Change/Remove
//
// Compression: 1280pt longest edge, JPEG 0.7. Same as race
// photos so the upload payload, share-card scale, and bucket
// quota behave identically.
//
// Upload + sync: after a new photo is picked, the compressed
// bytes go straight to Supabase Storage via
// `PhotoStorageService.uploadFreeRunPhoto`. The returned URL
// gets stamped onto `run.photoURL`, then the run row is pushed
// via `FreeRunSyncService.pushFinishedRun` so paired devices
// pick up the new image on their next pull.
//
// Guarded `#if canImport(UIKit) && !os(watchOS)` for the same
// reason as RacePhotoSection — depends on PhotosPicker +
// UIImage + JPEG encoding.
#if canImport(UIKit) && !os(watchOS)
struct FreeRunPhotoSection: View {

    @Bindable var run: FreeRun

    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photo").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            if let data = run.photoData,
               let image = UIImage(data: data) {
                populatedView(image: image)
            } else if let urlString = run.photoURL,
                      let url = URL(string: urlString) {
                // Fresh-device case — run row synced down with a
                // photoURL but local photoData hasn't been
                // fetched. Show via AsyncImage so the user
                // doesn't see the empty tile and re-upload.
                populatedRemoteView(url: url)
            } else {
                emptyView
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            loadPhoto(newItem)
        }
    }

    // MARK: - States

    private var emptyView: some View {
        PhotosPicker(
            selection: $photoItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.accent.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a photo")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Sunset shot, sweaty selfie, anything")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
        .buttonStyle(.plain)
    }

    private func populatedView(image: UIImage) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))

                changePill
            }

            removeButton
        }
    }

    private func populatedRemoteView(url: URL) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        Color.surfaceElevated
                    @unknown default:
                        Color.surfaceElevated
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))

                changePill
            }

            removeButton
        }
    }

    // MARK: - Shared affordances

    private var changePill: some View {
        PhotosPicker(
            selection: $photoItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack(spacing: 4) {
                Image(systemName: "pencil")
                    .font(.caption2.weight(.bold))
                Text("Change")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.background.opacity(0.7))
            )
        }
        .buttonStyle(.plain)
        .padding(10)
    }

    private var removeButton: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                run.photoData = nil
                run.photoURL = nil
                photoItem = nil
                pushRunIfAuthenticated()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.caption2.weight(.bold))
                    Text("Remove")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.warning)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Loading + upload

    private func loadPhoto(_ item: PhotosPickerItem) {
        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                return
            }
            let compressed = compressedJPEG(from: data, maxDimension: 1280)
            run.photoData = compressed

            if let bytes = compressed {
                await uploadAndPersistURL(bytes: bytes)
            }
        }
    }

    private func uploadAndPersistURL(bytes: Data) async {
        #if canImport(Auth)
        guard let userID = AuthService.shared.user?.id.uuidString else {
            return
        }
        let runID = run.id.uuidString

        if let url = try? await PhotoStorageService.uploadFreeRunPhoto(
            data: bytes,
            userID: userID,
            runID: runID
        ) {
            run.photoURL = url
        }

        // Push the run row regardless of upload success so any
        // other edits in this session propagate. Failure to
        // upload leaves the prior URL in place and the next
        // edit retries.
        await FreeRunSyncService.pushFinishedRun(
            run,
            userID: userID
        )
        #endif
    }

    private func pushRunIfAuthenticated() {
        #if canImport(Auth)
        guard let userID = AuthService.shared.user?.id.uuidString else {
            return
        }
        let snapshot = run
        Task { @MainActor in
            await FreeRunSyncService.pushFinishedRun(
                snapshot,
                userID: userID
            )
        }
        #endif
    }

    // Scale to fit within 1280pt longest edge and re-encode as
    // JPEG at 0.7 quality. Same dimensions / quality as race
    // photos so share-card render passes look identical
    // regardless of which surface uploaded the photo.
    private func compressedJPEG(from data: Data, maxDimension: CGFloat) -> Data? {
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
