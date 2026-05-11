import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(Auth)
import Auth
#endif

// Comment thread for one race. Modal sheet presented from a
// feed card's "💬 N" pill (or its detail sheet). Three areas:
//   1. Scrollable comment list, oldest first (same chronological
//      shape Strava / Instagram use)
//   2. Composer at the bottom — text field + Post button,
//      pinned via .safeAreaInset so the keyboard doesn't
//      cover it
//   3. Swipe-to-delete on rows the local user owns
//
// v1 is intentionally minimal — no threading, no edits, no
// mentions. The composer enforces the same 1–500 char range
// the Postgres CHECK uses; Post is disabled when out-of-range
// or empty.
struct CommentsSheet: View {

    let raceID: String

    @Environment(\.dismiss) private var dismiss

    @State private var comments: [RemoteComment] = []
    @State private var isLoading = true
    @State private var draft: String = ""
    @State private var isPosting = false
    @State private var postError: String?
    @State private var selectedCommenterID: String?

    private var localUserID: String? {
        #if canImport(Auth)
        return AuthService.shared.user?.id.uuidString
        #else
        return nil
        #endif
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                if isLoading {
                    loadingIndicator
                } else if comments.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Comments")
            .hyroxNavigationBar(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                composer
            }
            .task { await load() }
            .sheet(item: Binding(
                get: { selectedCommenterID.map(IDWrapper.init) },
                set: { selectedCommenterID = $0?.id }
            )) { wrapper in
                PublicProfileSheet(userID: wrapper.id)
            }
        }
    }

    private struct IDWrapper: Identifiable {
        let id: String
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        comments = await CommentService.comments(forRaceID: raceID)
        isLoading = false
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(comments) { comment in
                    row(comment: comment)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, Layout.screenMargin)
            .padding(.top, 16)
        }
    }

    private func row(comment: RemoteComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(urlString: comment.commenterAvatarUrl)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.divider, lineWidth: 1))
                .onTapGesture {
                    selectedCommenterID = comment.userId
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        selectedCommenterID = comment.userId
                    } label: {
                        Text(comment.commenterDisplayName)
                            .font(.callout.weight(.heavy))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .buttonStyle(.plain)

                    Text(relativeDateLabel(from: comment.createdAt))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)

                    Spacer()

                    if comment.userId == localUserID {
                        Button(role: .destructive) {
                            deleteComment(comment)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption2)
                                .foregroundStyle(Color.warning)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(comment.body)
                    .font(.callout)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    @ViewBuilder
    private func avatar(urlString: String?) -> some View {
        #if canImport(UIKit)
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    defaultAvatarSymbol
                @unknown default:
                    defaultAvatarSymbol
                }
            }
        } else {
            defaultAvatarSymbol
        }
        #else
        defaultAvatarSymbol
        #endif
    }

    private var defaultAvatarSymbol: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.textTertiary, Color.surfaceElevated)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().background(Color.divider)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.surface)
                    )

                Button {
                    Task { await postComment() }
                } label: {
                    if isPosting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.onAccent)
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Color.onAccent)
                            .frame(width: 36, height: 36)
                    }
                }
                .background(
                    Circle().fill(canPost ? Color.accent : Color.accent.opacity(0.4))
                )
                .clipShape(Circle())
                .disabled(!canPost || isPosting)
            }
            .padding(.horizontal, Layout.screenMargin)
            .padding(.vertical, 8)
            .background(Color.background)

            if let postError {
                Text(postError)
                    .font(.caption2)
                    .foregroundStyle(Color.warning)
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.bottom, 4)
            }
        }
    }

    private var canPost: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= CommentService.minBodyLength
            && trimmed.count <= CommentService.maxBodyLength
            && !isPosting
            && localUserID != nil
    }

    // MARK: - Actions

    private func postComment() async {
        isPosting = true
        postError = nil
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await CommentService.post(raceID: raceID, body: trimmed)
            draft = ""
            // Reload to pick up the new row + its server-
            // assigned id + commenter identity from the JOIN.
            await load()
        } catch CommentService.CommentServiceError.bodyEmpty {
            postError = "Comment can't be empty."
        } catch CommentService.CommentServiceError.bodyTooLong {
            postError = "Comments are capped at \(CommentService.maxBodyLength) characters."
        } catch CommentService.CommentServiceError.notAuthenticated {
            postError = "Sign in to comment."
        } catch {
            postError = "Couldn't post. Try again."
        }
        isPosting = false
    }

    private func deleteComment(_ comment: RemoteComment) {
        // Optimistic local removal so the tap feels instant.
        let index = comments.firstIndex(where: { $0.id == comment.id })
        let snapshot = comments
        if let index {
            comments.remove(at: index)
        }

        Task { @MainActor in
            do {
                try await CommentService.delete(commentID: comment.id)
            } catch {
                // Revert on failure.
                comments = snapshot
            }
        }
    }

    // MARK: - States

    private var loadingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(Color.accent)
            Text("Loading comments…")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text("No comments yet")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("Be the first to say something.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // Strava-style abbreviated relative date.
    private func relativeDateLabel(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
