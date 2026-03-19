import SwiftUI

struct DayDetailView: View {
    let record: DailyRecord
    @Environment(\.dismiss) private var dismiss
    @State private var isExportingVideo = false
    @State private var shareItems: [Any] = []
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DailyCardView(record: record)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    // Share buttons
                    HStack(spacing: 12) {
                        Button {
                            if let image = CardExporter.exportImage(for: record) {
                                shareItems = [image]
                                showingShareSheet = true
                            }
                        } label: {
                            Label("Image", systemImage: "photo")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            isExportingVideo = true
                            Task {
                                do {
                                    let url = try await CardExporter.exportVideo(for: record)
                                    shareItems = [url]
                                    showingShareSheet = true
                                } catch {
                                    // Video export failed silently — image sharing still works
                                }
                                isExportingVideo = false
                            }
                        } label: {
                            Group {
                                if isExportingVideo {
                                    ProgressView()
                                } else {
                                    Label("Video", systemImage: "video")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isExportingVideo)
                    }
                    .padding(.horizontal, 16)

                    // Session breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sessions")
                            .font(.headline)
                            .padding(.horizontal, 16)

                        ForEach(record.sessions.sorted(by: { $0.startTime < $1.startTime })) { session in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(session.startTime, style: .time)
                                        .font(.headline)
                                    Text("\(session.count) pushups")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let score = session.formScore {
                                    Text("\(Int(score))% form")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                let duration = session.endTime.timeIntervalSince(session.startTime)
                                Text(Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds])))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("Day Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: shareItems)
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
