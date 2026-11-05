//
//  DiagnosticsView.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 11/4/26.
//

import SwiftUI
import BaseColors
import LoggingKit
import StatusOverlayKit

struct DiagnosticsView: View {
    @Bindable private var logRecorder = AppLogRecorder.shared
    @State private var searchText: String = ""
    @State private var showClearConfirmation: Bool = false

    private var filteredRecords: [LogRecord] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return logRecorder.records
        }
        return logRecorder.records.filter { record in
            record.message.localizedCaseInsensitiveContains(searchText) ||
            record.level.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            Color.bg
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // MARK: - Search and Action Bar
                HStack(spacing: 10) {
                    searchField

                    // Copy Button
                    Button {
                        copyLogsToClipboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.mainOpp)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(logRecorder.records.isEmpty)
                    .opacity(logRecorder.records.isEmpty ? 0.45 : 1.0)

                    // Delete Button
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.red)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(logRecorder.records.isEmpty)
                    .opacity(logRecorder.records.isEmpty ? 0.45 : 1.0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // MARK: - Log Console Container
                VStack(spacing: 0) {
                    if filteredRecords.isEmpty {
                        EmptyStateView(
                            icon: "doc.text.magnifyingglass",
                            title: searchText.isEmpty ? "No Logs Recorded" : "No Matching Logs",
                            message: searchText.isEmpty ? "System events, playback diagnostics, and network outputs will stream here." : "Try adjusting your search query."
                        )
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(filteredRecords) { record in
                                        logRow(record)
                                            .id(record.id)
                                    }
                                }
                                .padding(12)
                            }
                            .onChange(of: logRecorder.records.count) { _, _ in
                                if let last = filteredRecords.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.sub)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Diagnostics & Logs")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear Recorded Logs?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Logs", role: .destructive) {
                withAnimation(.smooth(duration: 0.2)) {
                    logRecorder.clear()
                }
                TransientStatusSignal.shared.pending = StatusMessage(
                    title: "Logs Cleared",
                    subtitle: "Diagnostics buffer emptied",
                    icon: "trash",
                    tint: .red
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all logs from memory.")
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.mainOpp.opacity(0.5))

            TextField("Filter logs…", text: $searchText)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.mainOpp)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mainOpp.opacity(0.4))
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .animation(.smooth(duration: 0.2), value: searchText.isEmpty)
    }

    // MARK: - Log Entry Row

    private func logRow(_ record: LogRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.level.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(record.level.badgeColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(record.level.badgeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                Spacer()

                Text(record.timestamp, style: .time)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.mainOpp.opacity(0.4))
            }

            Text(record.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.mainOpp.opacity(0.85))
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Actions

    private func copyLogsToClipboard() {
        let text = logRecorder.exportLogText()
        UIPasteboard.general.string = text
        TransientStatusSignal.shared.pending = StatusMessage(
            title: "Logs Copied",
            subtitle: "\(logRecorder.records.count) entries copied to clipboard",
            icon: "doc.on.doc",
            tint: .blue
        )
    }
}
