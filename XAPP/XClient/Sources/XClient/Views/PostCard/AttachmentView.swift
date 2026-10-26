//
//  AttachmentView.swift
//  XClient
//
//  Adaptive aspect-ratio multi-image grid (1-4 images) and video thumbnail
//  with Liquid Glass play overlay, duration badge, and download context menus.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Responsive media presentation subview displaying 1, 2, 3, or 4 images/videos in balanced HIG grids.
public struct AttachmentView: View {
    @Environment(\.colorPalette) private var palette

    public let attachments: [MediaAttachment]
    public var onMediaTap: ((MediaAttachment) -> Void)?
    public var onSaveMedia: ((MediaAttachment) -> Void)?
    public var onCopyMediaLink: ((MediaAttachment) -> Void)?
    public var onShareMedia: ((MediaAttachment) -> Void)?

    public init(
        attachments: [MediaAttachment],
        onMediaTap: ((MediaAttachment) -> Void)? = nil,
        onSaveMedia: ((MediaAttachment) -> Void)? = nil,
        onCopyMediaLink: ((MediaAttachment) -> Void)? = nil,
        onShareMedia: ((MediaAttachment) -> Void)? = nil
    ) {
        self.attachments = attachments
        self.onMediaTap = onMediaTap
        self.onSaveMedia = onSaveMedia
        self.onCopyMediaLink = onCopyMediaLink
        self.onShareMedia = onShareMedia
    }

    public var body: some View {
        Group {
            switch attachments.count {
            case 1:
                singleAttachment(attachments[0])
            case 2:
                twoAttachmentsGrid(attachments[0], attachments[1])
            case 3:
                threeAttachmentsGrid(attachments[0], attachments[1], attachments[2])
            case 4:
                fourAttachmentsGrid(attachments)
            default:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - 1 Media Item
    private func singleAttachment(_ item: MediaAttachment) -> some View {
        let ratio = max(0.75, min(1.78, item.aspectRatio))
        return mediaTile(item: item)
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 360)
    }

    // MARK: - 2 Media Items
    private func twoAttachmentsGrid(_ first: MediaAttachment, _ second: MediaAttachment) -> some View {
        HStack(spacing: 4) {
            mediaTile(item: first)
            mediaTile(item: second)
        }
        .frame(height: 200)
    }

    // MARK: - 3 Media Items
    private func threeAttachmentsGrid(_ first: MediaAttachment, _ second: MediaAttachment, _ third: MediaAttachment) -> some View {
        HStack(spacing: 4) {
            mediaTile(item: first)
                .frame(maxWidth: .infinity)
            VStack(spacing: 4) {
                mediaTile(item: second)
                mediaTile(item: third)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 260)
    }

    // MARK: - 4 Media Items
    private func fourAttachmentsGrid(_ items: [MediaAttachment]) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                mediaTile(item: items[0])
                mediaTile(item: items[1])
            }
            HStack(spacing: 4) {
                mediaTile(item: items[2])
                mediaTile(item: items[3])
            }
        }
        .frame(height: 260)
    }

    // MARK: - Atomic Media Tile
    private func mediaTile(item: MediaAttachment) -> some View {
        ZStack {
            let displayUrl = item.previewUrl ?? item.url
            AsyncImage(url: displayUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    ZStack {
                        palette.tertiaryBackground
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(palette.textTertiary)
                    }
                case .empty:
                    ZStack {
                        palette.tertiaryBackground
                        ProgressView()
                    }
                @unknown default:
                    palette.tertiaryBackground
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Video Play Overlay
            if item.type == .video || item.type == .animatedGif {
                LiquidGlassPlayButton()

                // Duration Pill
                if let duration = item.durationSeconds {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(formatDuration(duration))
                                .font(Typography.characterCount)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.75))
                                .clipShape(Capsule())
                                .padding(8)
                        }
                    }
                }
            }

            // ALT Text Badge
            if let alt = item.altText, !alt.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Text("ALT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                        Spacer()
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onMediaTap?(item)
        }
        .contextMenu {
            #if os(macOS)
            Button {
                if let onSave = onSaveMedia {
                    onSave(item)
                } else {
                    Task {
                        _ = try? await MediaDownloadManager.shared.saveMediaToLocalDevice(from: item.url)
                    }
                }
            } label: {
                Label("Save to Downloads", systemImage: "arrow.down.circle")
            }
            #else
            Button {
                if let onSave = onSaveMedia {
                    onSave(item)
                } else {
                    Task {
                        _ = try? await MediaDownloadManager.shared.saveMediaToLocalDevice(from: item.url)
                    }
                }
            } label: {
                Label("Save to Photos", systemImage: "photo.on.rectangle")
            }
            #endif

            Button {
                if let onCopy = onCopyMediaLink {
                    onCopy(item)
                } else {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
                    #else
                    UIPasteboard.general.string = item.url.absoluteString
                    #endif
                }
            } label: {
                Label("Copy Media Link", systemImage: "link")
            }

            Button {
                onShareMedia?(item)
            } label: {
                Label("Share Media…", systemImage: "square.and.arrow.up")
            }
        }
        .accessibilityLabel(item.altText ?? "Attached media")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Liquid Glass Play Button Overlay
public struct LiquidGlassPlayButton: View {
    public init() {}

    public var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 52, height: 52)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)

            Image(systemName: "play.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 2) // Optical center correction
        }
    }
}
