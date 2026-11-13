//
//  RecordingSettingsView.swift
//  EasyDemo
//
//  Created by Daniel Oquelis on 30.10.25.
//

import SwiftUI

/// View for configuring recording quality settings (resolution and codec)
struct RecordingSettingsView: View {
    @Binding var selectedResolution: RecordingConfiguration.Resolution
    @Binding var selectedCodec: RecordingConfiguration.VideoCodec
    @Binding var frameRate: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Resolution Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Resolution", selection: $selectedResolution) {
                    ForEach(RecordingConfiguration.Resolution.allCases) { resolution in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(resolution.rawValue)
                                .font(.body)
                            Text(resolutionDescription(for: resolution))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(resolution)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Description for selected resolution
                Text(resolutionDetailedDescription(for: selectedResolution))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
            }

            Divider()

            // Codec Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Video Codec")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Codec", selection: $selectedCodec) {
                    ForEach(RecordingConfiguration.VideoCodec.allCases) { codec in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(codec.rawValue)
                                .font(.body)
                            Text(codecDescription(for: codec))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(codec)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Description for selected codec
                Text(codecDetailedDescription(for: selectedCodec))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
            }

            Divider()

            // Frame Rate Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Frame Rate")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Frame Rate", selection: $frameRate) {
                    Text("30 fps - Smooth").tag(30)
                    Text("60 fps - Cinematic").tag(60)
                }
                .pickerStyle(.segmented)

                Text(frameRate == 60
                     ? "Buttery smooth motion, best for demos and gameplay. Larger file sizes."
                     : "Standard video quality, great for presentations. Smaller file sizes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
            }

            // Quality tip
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                    .frame(width: 12, height: 12)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pro Tip")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(getQualityTip())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(nil)
                }
            }
            .padding(8)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
    }

    // MARK: - Helper Functions

    private func resolutionDescription(for resolution: RecordingConfiguration.Resolution) -> String {
        switch resolution {
        case .original:
            return "Capture-size canvas, up to 4K"
        case .hd1080:
            return "Full HD, standard quality"
        case .hd1440:
            return "2K, high quality"
        case .uhd4k:
            return "4K Ultra HD, maximum quality"
        }
    }

    private func resolutionDetailedDescription(for resolution: RecordingConfiguration.Resolution) -> String {
        switch resolution {
        case .original:
            return "Uses the captured source dimensions, up to 4K, with your chosen background and screen framing."
        case .hd1080:
            return "🎬 1920×1080 - Standard for YouTube and web. Universal compatibility, smaller files."
        case .hd1440:
            return "🎯 2560×1440 - Higher quality for professional presentations. Good balance of quality and size."
        case .uhd4k:
            return "💎 3840×2160 - Maximum quality for professional demos and large displays. Large files (~100-150 MB/min with HEVC)."
        }
    }

    private func codecDescription(for codec: RecordingConfiguration.VideoCodec) -> String {
        switch codec {
        case .h264:
            return "Universal, widely supported"
        case .hevc:
            return "Modern, 40% smaller files"
        case .prores:
            return "Professional, lossless quality"
        }
    }

    private func codecDetailedDescription(for codec: RecordingConfiguration.VideoCodec) -> String {
        switch codec {
        case .h264:
            return "🌐 H.264 (AVC) - Works everywhere: YouTube, social media, all players. Best for sharing. Larger file sizes."
        case .hevc:
            return "⚡ HEVC (H.265) - 40% smaller files with same quality. Perfect for 4K. Requires macOS 10.13+, iOS 11+."
        case .prores:
            return "🎨 ProRes 422 - Lossless quality for video editing. Huge files (~500+ MB/min). Use only if editing in Final Cut/Premiere."
        }
    }

    private func getQualityTip() -> String {
        if selectedResolution == .uhd4k && selectedCodec == .h264 {
            return "For 4K recordings, HEVC codec is recommended for better compression and smaller file sizes."
        } else if selectedResolution == .original && selectedCodec == .prores {
            return "ProRes is overkill for native resolution. Consider H.264 or HEVC for smaller files."
        } else if selectedCodec == .hevc && selectedResolution != .original {
            return "Great choice! HEVC provides excellent quality with smaller file sizes, perfect for your resolution."
        } else {
            return "Your current settings provide a good balance of quality and file size."
        }
    }
}

#Preview {
    RecordingSettingsView(
        selectedResolution: .constant(.original),
        selectedCodec: .constant(.h264),
        frameRate: .constant(60)
    )
    .padding()
    .frame(width: 350)
}
