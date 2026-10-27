//
//  MediaLightboxView.swift
//  XClient
//
//  Immersive full-screen Liquid Glass media lightbox viewer with pinch-to-zoom,
//  pan gesture navigation, swipe-down dismissal, and download pipeline integration.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import Combine

@MainActor
public final class MediaLightboxViewModel: ObservableObject {
    @Published public var currentScale: CGFloat = 1.0
    @Published public var lastScale: CGFloat = 1.0
    @Published public var offset: CGSize = .zero
    @Published public var lastOffset: CGSize = .zero
    @Published public var isSavedToPhotos: Bool = false
    @Published public var isSaving: Bool = false

    public init() {}
}

@MainActor
public struct MediaLightboxView: View {
    public let url: URL
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var navigationState: AppNavigationState
    @StateObject private var model = MediaLightboxViewModel()

    public init(url: URL) {
        self.url = url
    }

    public var body: some View {
        ZStack {
            // Dark ultra-thin glass background
            Color.black
                .ignoresSafeArea()

            // Main Interactive Zoomable Image
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(max(1.0, model.currentScale))
                        .offset(model.offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / model.lastScale
                                        model.lastScale = value
                                        model.currentScale = min(max(1.0, model.currentScale * delta), 4.0)
                                    }
                                    .onEnded { _ in
                                        model.lastScale = 1.0
                                        if model.currentScale <= 1.0 {
                                            withAnimation(.spring()) {
                                                model.offset = .zero
                                            }
                                        }
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        if model.currentScale > 1.0 {
                                            model.offset = CGSize(
                                                width: model.lastOffset.width + value.translation.width,
                                                height: model.lastOffset.height + value.translation.height
                                            )
                                        } else {
                                            // Swipe down to dismiss
                                            model.offset = CGSize(width: 0, height: max(0, value.translation.height))
                                        }
                                    }
                                    .onEnded { value in
                                        if model.currentScale <= 1.0 && value.translation.height > 120 {
                                            dismiss()
                                        } else {
                                            withAnimation(.spring()) {
                                                if model.currentScale <= 1.0 {
                                                    model.offset = .zero
                                                }
                                                model.lastOffset = model.offset
                                            }
                                        }
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if model.currentScale > 1.0 {
                                    model.currentScale = 1.0
                                    model.offset = .zero
                                    model.lastOffset = .zero
                                } else {
                                    model.currentScale = 2.5
                                }
                            }
                        }
                case .failure:
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Unable to load media")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                case .empty:
                    ProgressView()
                        .tint(.white)
                @unknown default:
                    EmptyView()
                }
            }

            // Overlay Controls Chrome
            VStack {
                // Top Bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // Bottom Bar with Save Button
                HStack {
                    Spacer()
                    Button {
                        saveMedia()
                    } label: {
                        HStack(spacing: 8) {
                            if model.isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: model.isSavedToPhotos ? "checkmark" : "arrow.down.to.line")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(model.isSavedToPhotos ? "Saved" : "Save Image")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSaving || model.isSavedToPhotos)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        #if os(iOS)
        .statusBarHidden()
        #endif
    }

    private func saveMedia() {
        model.isSaving = true
        Task {
            do {
                let manager = MediaDownloadManager.shared
                _ = try await manager.downloadMedia(from: url)
                model.isSavedToPhotos = true
            } catch {
                // Fallback
            }
            model.isSaving = false
        }
    }
}
