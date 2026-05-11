import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(Auth)
import Auth
#endif

// Editable photo attachment for a Race — used on RaceSummaryView
// (right after finishing) and RaceDetailView (retroactively).
//
// Two states:
//   • Empty — a tappable "Add photo" tile with a camera icon. Tap
//     opens the system PhotosPicker.
//   • Populated — a 16:9 hero preview of the chosen photo with an
//     overlaid "Change" button + a "Remove" pill below.
//
// Compression: photos are scaled to 1280pt longest edge and
// re-encoded as JPEG at 0.7 quality. That's a comfortable
// resolution for the share-card hero (1080px wide × 3 scale = 1080
// effective px) while keeping each race's row well under ~300KB.
// `@Attribute(.externalStorage)` on Race.photoData means SwiftData
// stores the bytes outside the main SQLite row anyway, so the size
// is more about cloud-sync and Photos round-trip than DB bloat.
//
// `@Bindable` on Race lets the picker write directly into the
// persisted model — same no-save-button autosave pattern used by
// `NotesSection` / `TitleSection`.
//
// Guarded `#if canImport(UIKit)` because PhotosPicker, UIImage,
// jpegData, and the renderer all live in UIKit. macOS / watchOS
// builds get a stub that does nothing — those surfaces don't show
// the section anyway, but the guard keeps the file compilable
// across targets.
#if canImport(UIKit) && !os(watchOS)
struct RacePhotoSection: View {

    @Bindable var race: Race

    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photo").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            if let data = race.photoData,
               let image = UIImage(data: data) {
                populatedView(image: image)
            } else if let urlString = race.photoURL,
                      let url = URL(string: urlString) {
                // Fresh-device case — race row synced down with a
                // photo URL but the bytes haven't been fetched.
                // Show the photo via AsyncImage so the user
                // doesn't see the "Add a photo" tile and try to
                // re-upload the same image.
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
                    Text("Gym selfie, finish-line shot, anything")
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
            // 16:9 preview. `.aspectRatio(16/9, .fill)` + .clipped()
            // gives a clean fixed-height banner regardless of the
            // source photo's aspect — landscape, portrait, square
            // all crop sensibly to the same panel size.
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))

                // Floating "Change" pill over the top-right of the
                // photo. Re-uses the PhotosPicker so tapping opens
                // the same picker in replace mode.
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

            HStack {
                Spacer()
                Button(role: .destructive) {
                    race.photoData = nil
                    race.photoURL = nil
                    photoItem = nil
                    pushRaceIfAuthenticated()
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
    }

    // Same shape as `populatedView` but driven by a remote URL.
    // Used on fresh-device installs where the race row synced
    // down with a photoURL but local photoData hasn't been
    // fetched. Identical Change/Remove affordances — picking a
    // new photo overwrites both the bytes and the URL on save;
    // tapping Remove clears both.
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

            HStack {
                Spacer()
                Button(role: .destructive) {
                    race.photoData = nil
                    race.photoURL = nil
                    photoItem = nil
                    pushRaceIfAuthenticated()
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
    }

    // MARK: - Loading + compression

    // Off-main load + compression so the UI stays smooth while a
    // multi-MB camera-roll image is processed. Picker hands us raw
    // transferable Data; we re-encode at a sensible size for the
    // race-card hero / share card.
    private func loadPhoto(_ item: PhotosPickerItem) {
        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                return
            }
            let compressed = compressedJPEG(from: data, maxDimension: 1280)
            race.photoData = compressed

            // Upload the freshly compressed bytes to Supabase
            // Storage and stamp the returned URL on the race row.
            // This runs after the local bytes are already
            // displayed (zero-latency) so the upload latency
            // doesn't block the UI. If upload fails, the local
            // bytes are still saved + visible; only cloud
            // propagation is delayed, and a follow-up edit or
            // the next pullAndReconcile retries the URL stamp.
            if let bytes = compressed {
                await uploadAndPersistURL(bytes: bytes)
            }
        }
    }

    // MARK: - Cloud sync

    // Upload race photo to Supabase Storage, then push the race
    // row so partner devices pick up the new URL. Bails silently
    // if the user isn't authenticated (cloud sync is opt-in via
    // Sign in with Apple).
    private func uploadAndPersistURL(bytes: Data) async {
        #if canImport(Auth)
        guard let userID = AuthService.shared.user?.id.uuidString else {
            return
        }
        let raceID = race.id.uuidString

        if let url = try? await PhotoStorageService.uploadRacePhoto(
            data: bytes,
            userID: userID,
            raceID: raceID
        ) {
            race.photoURL = url
        }

        // Push the race row regardless of upload success so any
        // other field changes propagate. If the URL upload
        // failed, we push with the prior URL (or nil) — next
        // edit retries.
        await RaceSyncService.pushFinishedRace(
            race,
            userID: userID
        )
        #endif
    }

    // Push the race row up after a photo removal. Same auth
    // gate as the upload path. Used by the destructive Remove
    // button to propagate the URL clear immediately rather than
    // waiting for the next field edit.
    private func pushRaceIfAuthenticated() {
        #if canImport(Auth)
        guard let userID = AuthService.shared.user?.id.uuidString else {
            return
        }
        let snapshot = race
        Task { @MainActor in
            await RaceSyncService.pushFinishedRace(
                snapshot,
                userID: userID
            )
        }
        #endif
    }

    // Scale to fit within a 1280pt square and re-encode as JPEG at
    // 0.7 quality. 1280 is enough for the share card (1080px wide
    // × 3 scale → 1080 effective px on the rendered image) without
    // wasting storage on detail nobody can see at card size.
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
